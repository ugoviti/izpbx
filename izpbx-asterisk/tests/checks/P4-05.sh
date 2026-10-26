#!/usr/bin/env bash
# P4-05: snapshot M4 of the migration (izpbx-migrate snapshot), on the
# 20.16.22 fixture with ~100 MB of recordings added to the spool:
# - the dumps of the config and CDR databases import into a test database
#   with the same row count for every table;
# - the checksum list of every moved directory (var/www, var/lib/asterisk,
#   etc/asterisk, home/asterisk, usr/local/fop2, var/spool/cron, freepbx.conf,
#   amportal.conf) matches the one before, and they are gone from /data;
# - the spool stays in place, its snapshot (hardlinks) takes less than 1% of
#   its size;
# - a second run changes nothing (state "snapshot=done");
# - negative check: with the database unreachable the snapshot fails and
#   nothing is moved.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-05
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
mariadb_up() { # name -> a MariaDB on the network (alias = name)
  local d
  d=$(t_run "$1" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$1" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || die "MariaDB did not start"
  printf '%s\n' "$d"
}
sqlroot() { docker exec -i -e MYSQL_PWD=rootpw "$1" mariadb -uroot -N "${@:2}"; }
rowcounts() { # container -> "db.table count" for the two databases
  local s t
  for s in asterisk asteriskcdrdb; do
    echo "SELECT table_name FROM information_schema.tables WHERE table_schema='$s' AND table_type='BASE TABLE' ORDER BY 1" | sqlroot "$1" |
      while read -r t; do echo "$s.$t $(echo "SELECT COUNT(*) FROM \`$s\`.\`$t\`" | sqlroot "$1")"; done
  done
}
db=$(mariadb_up db)
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | sqlroot "$db" || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" | sqlroot "$db"

v=$(t_volume data)
inv() { docker run --rm --entrypoint "" -v "$v:/data" "$image" "$@"; }
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
# ~100 MB of recordings in the spool: the hardlinked snapshot must cost only its directories
inv sh -c 'd=/data/var/spool/asterisk/monitor/2026/10/25; mkdir -p $d && for i in $(seq 1 50); do
  head -c 2097152 /dev/urandom > $d/rec-$i.wav; done && chown -R 1000:1000 /data/var/spool/asterisk/monitor'
# checksum list of a tree: entries (type, mode, owner, symlink target) and file contents, relative paths
list() { # dir (inside the volume)
  inv sh -c "cd '/data/$1' 2>/dev/null || exit 0
    find . -printf '%y %m %U:%G %p %l\n' | LC_ALL=C sort; find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum"
}
filesum() { inv sh -c "[ -e '/data/$1' ] && { stat -c '%a %u:%g' '/data/$1'; sha256sum < '/data/$1'; } || true"; }
moved_dirs="var/www var/lib/asterisk etc/asterisk home/asterisk usr/local/fop2 var/spool/cron"
moved_files="etc/freepbx.conf etc/amportal.conf"
declare -A before
for d in $moved_dirs; do before[$d]=$(list "$d" | sha256sum); done
for f in $moved_files; do before[$f]=$(filesum "$f"); done
spool_before=$(list var/spool/asterisk | sha256sum)
migrate() { # [env...] -> izpbx-migrate snapshot
  docker run --rm --entrypoint "" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
    -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw "$@" "$image" izpbx-migrate snapshot 2>&1
}

# --- negative check: database unreachable -> fails, nothing moved
out=$(migrate -e MYSQL_SERVER=nodb -e MYSQL_ROOT_PASSWORD=) && rc=0 || rc=$?
assert_ne 0 "$rc" "control: with the database unreachable the snapshot fails"
assert_contains "$out" "dump of 'asterisk' failed" "control: the failed dump is reported"
assert_eq "${before[var/www]}" "$(list var/www | sha256sum)" "control: nothing moved after the failed snapshot"

# --- snapshot
out=$(migrate) && rc=0 || rc=$?
log "snapshot:"; sed 's/^/    | /' <<< "$out" | tail -n 20 >&2
assert_eq 0 "$rc" "izpbx-migrate snapshot succeeds"
snap=$(inv sh -c 'sed -n "s/^snapshot_dir=//p" /data/.izpbx-migration/state | tail -n 1')
snap=${snap#/data/}
assert_contains "$snap" ".izpbx-migration/" "snapshot directory recorded in the state ($snap)"
assert_eq "done" "$(inv sh -c 'sed -n "s/^snapshot=//p" /data/.izpbx-migration/state | tail -n 1')" "state: snapshot=done"

for d in $moved_dirs; do
  assert_eq "${before[$d]}" "$(list "$snap/fs/$d" | sha256sum)" "$d: same checksum list in the snapshot"
  assert_eq "" "$(inv sh -c "[ -e '/data/$d' ] && echo present || true")" "$d: moved, no longer in /data"
done
for f in $moved_files; do
  assert_eq "${before[$f]}" "$(filesum "$snap/fs/$f")" "$f: same content in the snapshot"
done
assert_eq "$spool_before" "$(list var/spool/asterisk | sha256sum)" "spool: unchanged in place"
assert_eq "$spool_before" "$(list "$snap/fs/var/spool/asterisk" | sha256sum)" "spool: same checksum list in the snapshot"
read -r spool_kb snap_kb <<< "$(inv sh -c "du -sk /data/var/spool/asterisk '/data/$snap/fs/var/spool/asterisk' | cut -f1 | tr '\n' ' '")"
log "spool ${spool_kb} KB, its snapshot ${snap_kb} KB more"
assert_cmd "spool snapshot under 1% of the spool size" -- test "$(( ${snap_kb:-999999999} * 100 ))" -lt "${spool_kb:-0}"

# --- the dumps import with the same row counts
sums=$(inv sh -c "cd '/data/$snap/db' && sha256sum -c SHA256SUMS")
assert_contains "$sums" "asterisk.sql.gz: OK" "config dump matches SHA256SUMS"
assert_contains "$sums" "asteriskcdrdb.sql.gz: OK" "CDR dump matches SHA256SUMS"
t=$(mariadb_up dbtest)
for f in asterisk asteriskcdrdb; do
  docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" gzip -dc "/data/$snap/db/$f.sql.gz" | sqlroot "$t" || fail "cannot import the $f dump"
done
src_counts=$(rowcounts "$db") dst_counts=$(rowcounts "$t")
assert_ne "" "$src_counts" "row counts read"
assert_eq "$src_counts" "$dst_counts" "the dumps import with the same row count for every table ($(wc -l <<< "$src_counts") tables)"

# --- a second run changes nothing
state_before=$(inv cat /data/.izpbx-migration/state)
out=$(migrate) && rc=0 || rc=$?
assert_eq 0 "$rc" "second run succeeds"
assert_contains "$out" "snapshot already done" "second run: snapshot already done"
assert_eq "$state_before" "$(inv cat /data/.izpbx-migration/state)" "second run: state unchanged"
finish
