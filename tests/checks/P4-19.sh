#!/usr/bin/env bash
# P4-19: verification M7 blocks a migration with differences. The 20.16.22
# fixture migrated in a real start, with a discrepancy injected after the
# restore (IZPBX_TEST_AFTER_RESTORE_SQL: extension 1003 deleted):
# - the inventory before (M3) is in .izpbx-migration/inventory-before.json;
# - the verification reports the difference (extension 1003) in the log and
#   in .izpbx-migration/verify-<ts>.txt;
# - the migration is not completed: no verify=done in the state, maintenance
#   mode, the container stays up, unhealthy, Asterisk not running;
# - control: the same migration without the injection passes the
#   verification (verify=done, healthy) with the product mapping
#   (/usr/local/share/izpbx/migration-mapping.tsv).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-19
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
migrated() { # name [env...] -> a migrating container on its own database and volume
  local n=$1 d v; shift
  d=$(t_run "db-$n" docker.io/mariadb:10.11.19 --network "$net" --network-alias "db-$n" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || return 1
  for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot || return 1; done
  echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
    docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot
  v=$(t_volume "data-$n")
  docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
  t_run "pbx-$n" "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER="db-$n" \
    -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true \
    --health-start-period 1s --health-interval 10s --health-retries 2 "$@"
}
bad=$(migrated bad -e IZPBX_TEST_AFTER_RESTORE_SQL="DELETE FROM devices WHERE id = '1003'; DELETE FROM users WHERE extension = '1003'")
good=$(migrated good)

# --- discrepancy injected
assert_cmd "with a discrepancy: the init completes" -- \
  t_wait_for 2400 -- sh -c "docker logs $bad 2>&1 | grep 'izpbx-init: done\|maintenance mode, the remaining steps' >/dev/null"
docker logs "$bad" 2>&1 | grep -E 'VERIFICATION|  extensions|MAINTENANCE' | sed 's/^/    | /' >&2
assert_cmd "inventory before saved (M3)" -- docker exec "$bad" test -s /data/.izpbx-migration/inventory-before.json
assert_cmd "the log reports the failed verification" -- \
  sh -c "docker logs '$bad' 2>&1 | grep 'migration: VERIFICATION FAILED' >/dev/null"
report=$(docker exec "$bad" sh -c 'cat /data/.izpbx-migration/verify-*.txt' 2>/dev/null)
assert_contains "$report" "extensions: - extension=1003" "the report lists extension 1003"
assert_cmd_fails "no verify=done in the state" -- docker exec "$bad" grep -qx 'verify=done' /data/.izpbx-migration/state
assert_cmd "maintenance mode" -- docker exec "$bad" test -e /run/izpbx/maintenance
assert_cmd "unhealthy" -- t_wait_for 90 -- sh -c "[ \"\$(docker inspect -f '{{.State.Health.Status}}' $bad)\" = unhealthy ]"
assert_eq true "$(docker inspect -f '{{.State.Running}}' "$bad")" "the container stays up"
assert_cmd_fails "Asterisk not running" -- docker exec "$bad" pgrep -f '^asterisk -f'

# --- control: the same migration without the injection
assert_cmd "control: without the discrepancy the migration completes (healthy)" -- t_wait_healthy "$good" 2400
assert_cmd "control: verify=done" -- docker exec "$good" grep -qx 'verify=done' /data/.izpbx-migration/state
assert_cmd "control: the verification passed" -- \
  sh -c "docker logs '$good' 2>&1 | grep 'migration: verification passed' >/dev/null"
finish
