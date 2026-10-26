#!/usr/bin/env bash
# P4-22 (T4): migration from the 20.16.18 and 20.16.21 fixtures (older
# FreePBX 16 frameworks: 16.0.40.11 and 16.0.50), in a real start each, at
# the same time. Both frameworks are above the minimum of the checks M2
# (16.0.26), so the migration must complete:
# - nothing blocks in the checks M2;
# - the verification M7 passes (verify=done: inventory after = before with
#   the product mapping) and the state has migration=done;
# - the container becomes healthy on FreePBX 17;
# - the diff of the inventories with the product mapping, run again on the
#   saved inventories, is empty.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-22
versions="20.16.18 20.16.21"
assert_cmd "image builds" -- t_build_image "$image"
for ver in $versions; do
  assert_cmd "$ver fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v "$ver" ${TEST_REUSE_FIXTURES:+--reuse}
done

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
migrate() { # version -> the migrating container
  local ver=$1 n=${1//./-} fx="$TESTS_DIR/fixtures/out/$1" d v
  d=$(t_run "db-$n" docker.io/mariadb:10.11.19 --network "$net" --network-alias "db-$n" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || return 1
  for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot || return 1; done
  echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
    docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot
  v=$(t_volume "data-$n")
  docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
  t_run "pbx-$n" "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER="db-$n" \
    -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true
}
declare -A pbx
for ver in $versions; do pbx[$ver]=$(migrate "$ver") || die "cannot start the migration of $ver"; done

for ver in $versions; do
  c=${pbx[$ver]}
  # healthy, or stopped in maintenance mode by the verification
  ok=0
  t_wait_for 2400 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)' >/dev/null"
  t_wait_healthy "$c" 300 && ok=1
  docker logs "$c" 2>&1 | grep -E 'framework|preflight: (BLOCK|RESULT)|VERIFICATION|error:   |verification passed|completed' | sed 's/^/    | /' >&2
  assert_eq 1 "$ok" "$ver: migrated, healthy"
  assert_cmd "$ver: nothing blocks in the checks M2" -- \
    sh -c "docker logs '$c' 2>&1 | grep 'preflight: RESULT: nothing blocks the migration' >/dev/null"
  state=$(docker exec "$c" cat /data/.izpbx-migration/state 2>/dev/null)
  assert_cmd "$ver: verification M7 passed (verify=done)" -- grep -qx 'verify=done' <<< "$state"
  assert_cmd "$ver: migration=done" -- grep -qx 'migration=done' <<< "$state"
  assert_contains "$(docker exec -u asterisk "$c" fwconsole -V 2>/dev/null)" "17." "$ver: FreePBX 17 running"
  diff=$(docker exec "$c" izpbx-inventory --diff /data/.izpbx-migration/inventory-before.json /data/.izpbx-migration/inventory-after.json \
    --mapping /usr/local/share/izpbx/migration-mapping.tsv 2>&1) && rc=0 || rc=$?
  log "$ver: $(tail -n 1 <<< "$diff")"
  assert_eq 0 "$rc" "$ver: inventory diff empty with the product mapping"
done
finish
