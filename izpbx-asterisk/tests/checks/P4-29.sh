#!/usr/bin/env bash
# P4-29: migration of a large volume (fixture P0-08e, 20.16.22-large: 500
# extensions, 2 million CDR rows, 1000 x 5 MiB recordings).
# - the space check of M2: with a /data volume holding 10% less free space
#   than the check needs it blocks on space only; control: with 10% more it
#   does not (tmpfs volumes sized from the need the check reports on the
#   real volume; a tmpfs takes memory only for the files in it);
# - the migration completes: verification M7 passed (inventory diff empty),
#   healthy; s6 does not interrupt the long initialization (no timeout);
# - its duration (container start -> "completed") is at most 30 minutes
#   (D26) and is recorded in izpbx-asterisk/tests/expected/migration-time.txt;
# - the spool snapshot is hardlinked: less than 1% of the spool size more.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-29
fx="$TESTS_DIR/fixtures/out/20.16.22-large"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "large fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 --variant large ${TEST_REUSE_FIXTURES:+--reuse}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
  docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot
v=$(t_volume data)
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
env=(-e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw)

# --- the space check: need on the real volume, then 90% and 110% of it
out=$(docker run --rm --entrypoint "" --network "$net" -v "$v:/data" "${env[@]}" "$image" izpbx-preflight 2>&1 || true)
need=$(sed -nE 's/^OK space: .* ([0-9]+) MB needed.*/\1/p' <<< "$out")
used=$(docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" sh -c 'du -sm /data | cut -f1')
log "real volume: $(grep '^OK space' <<< "$out"); data $used MB"
assert_ne "" "$need" "the space check reports the space needed"
space_check() { # free MB -> the preflight report, on a tmpfs /data with the data and that free space
  local vol="$TEST_PROJECT-tmp$1"
  docker volume create --label "izpbx.test=$TEST_PROJECT" --driver local --opt type=tmpfs --opt device=tmpfs \
    --opt "o=size=$(( used + $1 + 64 ))m" "$vol" >/dev/null
  docker run --rm --entrypoint "" --network "$net" -v "$vol:/data" -v "$fx:/fx:ro" "${env[@]}" "$image" sh -c '
    tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
    # the extra 64 MB of the volume size covers the filesystem: free space exactly as asked
    free=$(df -Pm /data | awk "NR == 2 {print \$4}"); fill=$(( free - '"$1"' ))
    [ "$fill" -le 0 ] || head -c "$((fill * 1048576))" /dev/zero > /data/.fill
    izpbx-preflight' 2>&1 || true
  docker volume rm "$vol" >/dev/null 2>&1 || true
}
low=$(space_check $(( need * 9 / 10 )))
log "90%: $(grep -E '^(OK|BLOCK) space' <<< "$low")"
assert_eq "BLOCK space" "$(grep -oE '^BLOCK [a-z]+' <<< "$low" | tr '\n' ' ' | sed 's/ $//')" "with 10% less free space: only the space check blocks"
high=$(space_check $(( need * 11 / 10 )))
log "110%: $(grep -E '^(OK|BLOCK) space' <<< "$high")"
assert_cmd "control: with 10% more free space the space check passes" -- grep -q '^OK space' <<< "$high"

# --- the migration, timed
start=$SECONDS
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" "${env[@]}" -e IZPBX_MIGRATE_FREEPBX=true)
t_wait_for 3600 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)|izpbx-init: maintenance' >/dev/null"
duration=$((SECONDS - start))
docker logs "$c" 2>&1 | grep -E -e 'migration: (database|spool|snapshot done|archive|FreePBX 16 ->)|VERIFICATION' -e "$T_LOG_DETAIL_RE" | sed 's/^/    | /' >&2
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 600
state=$(docker exec "$c" cat /data/.izpbx-migration/state 2>/dev/null)
assert_cmd "verification M7 passed (verify=done, inventory diff empty)" -- grep -qx 'verify=done' <<< "$state"
assert_cmd_fails "s6 does not interrupt the initialization (no timeout)" -- sh -c "docker logs '$c' 2>&1 | grep -iE 's6.*(timed out|timeout)' >/dev/null"
log "migration time: ${duration} s"
assert_cmd "migration time at most 30 minutes (D26): ${duration} s" -- test "$duration" -le 1800
printf '%s\t%s\t%ss\t%s\n' "$(date -u +%Y-%m-%d)" "20.16.22-large (500 ext, 2M CDR, 5 GB recordings)" "$duration" \
  "$(nproc) cpu" >> "$REPO_DIR/izpbx-asterisk/tests/expected/migration-time.txt"
snap=$(sed -n 's/^snapshot_dir=//p' <<< "$state" | tail -n 1)
read -r spool_kb extra_kb <<< "$(docker exec "$c" sh -c "du -sk /var/spool/asterisk/ '$snap/fs/var/spool/asterisk' | cut -f1 | tr '\n' ' '")"
log "spool ${spool_kb} KB, its snapshot ${extra_kb} KB more"
assert_cmd "spool snapshot under 1% of the spool size" -- test "$(( ${extra_kb:-999999999} * 100 ))" -lt "${spool_kb:-0}"
finish
