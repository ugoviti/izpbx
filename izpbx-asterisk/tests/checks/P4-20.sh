#!/usr/bin/env bash
# P4-20: completion M8 of the migration: the 20.16.22 fixture migrated in a
# real start, then restarted twice.
# - after the migration: state "migration=done", .initialized with the
#   FreePBX 17 version, the log reports the snapshot and its size;
# - each restart is a normal start: FreePBX 17 found, no migration phase
#   (no resume, no snapshot, no restore), the state file unchanged, healthy,
#   and the snapshot notice again with its size.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-20
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

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
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 2400
state=$(docker exec "$c" cat /data/.izpbx-migration/state)
assert_cmd "state: migration=done" -- grep -qx 'migration=done' <<< "$state"
assert_contains "$(docker exec "$c" cat /data/.initialized)" "17." ".initialized has the FreePBX 17 version"
notice='migration: the snapshot of FreePBX 16 is still in /data/.izpbx-migration/[0-9TZ]+ and takes [0-9]+ MB'
assert_cmd "the migration log reports the snapshot and its size" -- sh -c "docker logs '$c' 2>&1 | grep -E '$notice' >/dev/null"
log "$(docker logs "$c" 2>&1 | grep -E 'snapshot of FreePBX 16' | tail -n 1)"

for n in 1 2; do
  since=$(date -u +%Y-%m-%dT%H:%M:%SZ); sleep 1
  docker restart "$c" >/dev/null
  assert_cmd "restart $n: healthy" -- t_wait_healthy "$c" 600
  out=$(docker logs --since "$since" "$c" 2>&1)
  assert_contains "$out" "found: normal start" "restart $n: a normal start (FreePBX 17 found)"
  assert_cmd_fails "restart $n: no migration phase runs" -- \
    grep -E 'resuming|migration: (snapshot in|restoring|database .* recreated|inventory of FreePBX 16)' <<< "$out"
  assert_cmd "restart $n: the snapshot notice with its size" -- grep -E "$notice" <<< "$out"
  assert_eq "$state" "$(docker exec "$c" cat /data/.izpbx-migration/state)" "restart $n: the migration state is unchanged"
done
finish
