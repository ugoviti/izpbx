#!/usr/bin/env bash
# P4-24: commercial modules in the migration, migrated with a warning (D24).
# The commercial fixture variant (20.16.22 with queuestats 16.0.3, a
# commercial module, installed without license) migrated in a real start:
# - the checks M2 list it as informative (nothing blocks);
# - the migration completes: verification M7 passed (verify=done),
#   migration=done, healthy;
# - the log and the final report (.izpbx-migration/report.txt) name the
#   commercial module to reactivate with its license;
# - the inventories before and after, with the product mapping, differ at
#   most in the commercial module (its state depends on the license).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-24
base="$TESTS_DIR/fixtures/out/20.16.22"
fx="$TESTS_DIR/fixtures/out/20.16.22-commercial"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
assert_cmd "commercial variant derives" -- "$TESTS_DIR/fixtures/derive-variant.sh" "$base" commercial

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
logs=$(docker logs "$c" 2>&1)
grep -E 'preflight: (INFO commercial|RESULT)|queuestats|commercial' <<< "$logs" | sed 's/^/    | /' >&2
assert_cmd "M2: the commercial module is informative" -- grep -q 'preflight: INFO commercial: .*queuestats' <<< "$logs"
assert_cmd "M2: nothing blocks" -- grep -q 'preflight: RESULT: nothing blocks the migration' <<< "$logs"
state=$(docker exec "$c" cat /data/.izpbx-migration/state)
assert_cmd "verification M7 passed (verify=done)" -- grep -qx 'verify=done' <<< "$state"
assert_cmd "migration=done" -- grep -qx 'migration=done' <<< "$state"
assert_cmd "the log names the commercial module to reactivate" -- \
  grep -q 'migration: commercial modules migrated, reactivate them with their license: queuestats' <<< "$logs"
report=$(docker exec "$c" cat /data/.izpbx-migration/report.txt 2>/dev/null)
log "report:"; sed 's/^/    | /' <<< "$report" >&2
assert_contains "$report" "commercial modules to reactivate with their license: queuestats" "the final report names it"
log "fwconsole ma list: $(docker exec -u asterisk "$c" fwconsole ma list 2>/dev/null | grep -E '^\| queuestats ' || echo 'queuestats not installed')"
diff=$(docker exec "$c" izpbx-inventory --diff /data/.izpbx-migration/inventory-before.json /data/.izpbx-migration/inventory-after.json \
  --mapping /usr/local/share/izpbx/migration-mapping.tsv 2>&1 || true)
log "diff with the product mapping only: $(tail -n 1 <<< "$diff")"
assert_eq "" "$(grep -E '^[a-z_]+: [-+]' <<< "$diff" | grep -v 'queuestats' || true)" \
  "inventory: no difference but the commercial module"
finish
