#!/usr/bin/env bash
# P4-21 (T6): izpbx-rollback (M9). The 20.16.22 fixture migrated to FreePBX 17
# in a real start, the container stopped, izpbx-rollback run in a one-off
# container on the same volume and database:
# - the config database equals the fixture one, table by table (CHECKSUM
#   TABLE against a reference MariaDB loaded with the fixture dump);
#   control: after the migration, before the rollback, it does differ;
# - the directories moved by the snapshot (var/www, var/lib/asterisk,
#   etc/asterisk, home/asterisk, usr/local/fop2, var/spool/cron) and
#   freepbx.conf, amportal.conf, .initialized equal the fixture;
# - the FreePBX 17 data is kept aside (rollback-<ts>: database dump, state);
# - the izPBX 20.16.22 image of the fixture starts on the volume, and the
#   inventory (izpbx-inventory, DB + files) equals the one of the fixture,
#   but the DUNDi secret of the astdb (Asterisk renews it at the start).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-21
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
img16=$(sed -n 's/^image=//p' "$fx/manifest.txt")
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
fixture_db() { # name
  local d
  d=$(t_run "$1" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$1" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || die "MariaDB did not start"
  for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot || die "cannot load $f"; done
  echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
    docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot
  printf '%s\n' "$d"
}
tables() { # db container -> "table checksum" of every table of asterisk
  docker exec -e MYSQL_PWD=rootpw "$1" sh -c 'mariadb -uroot -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema=\"asterisk\" ORDER BY 1" |
    while read -r t; do mariadb -uroot -N -e "CHECKSUM TABLE asterisk.\`$t\`"; done'
}
fixture_data() { docker run --rm --entrypoint "" -v "$1:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null; }
tree() { # volume path -> entries and contents of a tree or a file
  docker run --rm --entrypoint "" -v "$1:/data:ro" "$image" sh -c "cd /data && [ -e '$2' ] || exit 0
    find '$2' -printf '%y %m %U:%G %p %l\n' | LC_ALL=C sort; find '$2' -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum" | sha256sum
}
env22=(-e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw)

ref=$(fixture_db dbref)
vref=$(t_volume ref); fixture_data "$vref"
db=$(fixture_db db)
v=$(t_volume data); fixture_data "$v"
ref_tables=$(tables "$ref")
docker run --rm --entrypoint "" --network "$net" -v "$vref:/data:ro" -e APP_DATA=/data -e MYSQL_SERVER=dbref \
  -e MYSQL_PASSWORD=fixture-pw "$image" izpbx-inventory > "$work/inv-fixture.json"

# --- migration, then the container stopped
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" "${env22[@]}" -e IZPBX_MIGRATE_FREEPBX=true)
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 2400
docker stop -t 60 "$c" >/dev/null
assert_ne "$ref_tables" "$(tables "$db")" "control: after the migration the config database differs from the fixture"

# --- rollback
out=$(docker run --rm --entrypoint "" --network "$net" -v "$v:/data" "${env22[@]}" "$image" izpbx-rollback 2>&1) && rc=0 || rc=$?
sed 's/^/    | /' <<< "$out" >&2
assert_eq 0 "$rc" "izpbx-rollback succeeds"
assert_eq "$ref_tables" "$(tables "$db")" "config database equal to the fixture, table by table ($(wc -l <<< "$ref_tables") tables)"
for p in var/www var/lib/asterisk etc/asterisk home/asterisk usr/local/fop2 var/spool/cron etc/freepbx.conf etc/amportal.conf .initialized; do
  assert_eq "$(tree "$vref" "$p")" "$(tree "$v" "$p")" "$p equal to the fixture"
done
aside=$(docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" sh -c 'ls -d /data/.izpbx-migration/rollback-* 2>/dev/null | head -n 1')
assert_cmd "FreePBX 17 data kept aside: database dump and state" -- \
  docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" sh -c "test -s '$aside/db/asterisk.sql.gz' && grep -qx 'migration=rolled-back' '$aside/state' && test ! -e /data/.izpbx-migration/state"

# --- izPBX 20.16.22 on the volume
c16=$(t_run pbx16 "$img16" --network "$net" --hostname izpbx-fixture -v "$v:/data" --env-file "$TESTS_DIR/fixtures/fixture.env" \
  -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw)
up16() { docker logs "$c16" 2>&1 | grep 'supervisord started' >/dev/null &&
  docker exec "$c16" sh -c 'asterisk -rx "core show version" | grep -q "Asterisk 20"'; }
assert_cmd "izPBX 20.16.22 starts on the volume (Asterisk 20 up)" -- t_wait_for 900 -- up16
assert_cmd_fails "izPBX 20.16.22 does not install FreePBX again" -- \
  sh -c "docker logs '$c16' 2>&1 | grep -i 'new installation\|installing freepbx' >/dev/null"
docker stop -t 60 "$c16" >/dev/null
docker run --rm --entrypoint "" --network "$net" -v "$v:/data:ro" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_PASSWORD=fixture-pw "$image" izpbx-inventory > "$work/inv-after.json"
printf 'astdb\t^key=/dundi/secret\t\n' > "$work/map"
diff=$(docker run --rm --entrypoint "" -v "$work:/w:ro" "$image" izpbx-inventory --diff /w/inv-fixture.json /w/inv-after.json --mapping /w/map) && rc=0 || rc=$?
log "inventory after 20.16.22: $(tail -n 1 <<< "$diff")"
[ "$rc" == 0 ] || sed 's/^/    | /' <<< "$diff" | head -n 30 >&2
assert_eq 0 "$rc" "the inventory after izPBX 20.16.22 equals the one of the fixture (DUNDi secret apart)"
finish
