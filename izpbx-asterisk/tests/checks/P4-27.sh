#!/usr/bin/env bash
# P4-27: migration without MYSQL_ROOT_PASSWORD (fixture P0-08c,
# 20.16.22-noroot: database and user made by hand, grants on the two
# databases only). The user starts without DROP/CREATE on the config database:
# - the checks M2 block with the exact GRANT to run (for the account of the
#   connection), maintenance mode, the databases and /data unchanged;
# - that GRANT, read from the log, is run by an administrator and the
#   container started again (still without MYSQL_ROOT_PASSWORD): the migration
#   completes with the user's privileges, verification M7 passed, inventory
#   diff empty, healthy.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-27
fx="$TESTS_DIR/fixtures/out/20.16.22-noroot"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "noroot fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 --variant noroot ${TEST_REUSE_FIXTURES:+--reuse}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
sqlroot() { docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot -N; }
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | sqlroot || die "cannot load $f"; done
# no DROP/CREATE on the config database
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT SELECT, INSERT, UPDATE, DELETE ON asterisk.* TO asterisk@'%';
      GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" | sqlroot
dbsum() {
  for s in asterisk asteriskcdrdb; do
    echo "SELECT table_name FROM information_schema.tables WHERE table_schema='$s' ORDER BY 1" | sqlroot |
      while read -r t; do echo "CHECKSUM TABLE $s.\`$t\`" | sqlroot; done
  done | md5sum
}
v=$(t_volume data)
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
datasum() {
  docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" sh -c 'cd /data && {
    find . -path ./.izpbx-migration -prune -o -printf "%y %m %U:%G %p %l\n" | LC_ALL=C sort
    find . -path ./.izpbx-migration -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum; } | sha256sum'
}
env=(-e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw -e IZPBX_MIGRATE_FREEPBX=true)
db_before=$(dbsum) data_before=$(datasum)

# --- without DROP/CREATE: blocked with the exact GRANT
c0=$(t_run pbx0 "$image" --network "$net" -v "$v:/data" "${env[@]}")
t_wait_for 300 -- sh -c "docker logs '$c0' 2>&1 | grep 'izpbx-init: maintenance mode' >/dev/null"
block=$(docker logs "$c0" 2>&1 | grep 'preflight: BLOCK' || true)
log "$block"
assert_contains "$block" "BLOCK database" "M2 blocks on the database privileges"
grant=$(grep -oE "GRANT ALL PRIVILEGES ON \`asterisk\`\.\* TO '[^']+'@'[^']+';" <<< "$block" | head -n 1)
assert_eq "GRANT ALL PRIVILEGES ON \`asterisk\`.* TO 'asterisk'@'%';" "$grant" "the exact GRANT for the account of the connection"
assert_eq 1 "$(grep -c 'BLOCK' <<< "$block")" "only the database check blocks"
docker rm -f "$c0" >/dev/null
assert_eq "$db_before" "$(dbsum)" "blocked: the databases are unchanged"
assert_eq "$data_before" "$(datasum)" "blocked: /data is unchanged outside .izpbx-migration"

# --- the GRANT run by an administrator, start again (no root password)
echo "$grant" | sqlroot
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" "${env[@]}")
t_wait_for 2400 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)|izpbx-init: maintenance' >/dev/null"
docker logs "$c" 2>&1 | grep -E -e 'preflight: (BLOCK|RESULT|OK database)|VERIFICATION|completed' -e "$T_LOG_DETAIL_RE" | sed 's/^/    | /' >&2
assert_cmd "with the GRANT: migrated, healthy" -- t_wait_healthy "$c" 300
state=$(docker exec "$c" cat /data/.izpbx-migration/state 2>/dev/null)
assert_cmd "verification M7 passed (verify=done)" -- grep -qx 'verify=done' <<< "$state"
assert_cmd "migration=done" -- grep -qx 'migration=done' <<< "$state"
diff=$(docker exec "$c" izpbx-inventory --diff /data/.izpbx-migration/inventory-before.json /data/.izpbx-migration/inventory-after.json \
  --mapping /data/.izpbx-migration/mapping.tsv 2>&1) && rc=0 || rc=$?
log "inventory: $(tail -n 1 <<< "$diff")"
assert_eq 0 "$rc" "inventory diff empty"
finish
