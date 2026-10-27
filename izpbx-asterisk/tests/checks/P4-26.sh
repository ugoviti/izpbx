#!/usr/bin/env bash
# P4-26: migration of an installation born on FreePBX 15 (fixture P0-08b,
# 20.16.22-fp15: created on 18.15.24, upgraded via 18.16.14 to 20.16.22), in
# a real start. It still has speeddial, a module with no FreePBX 17 release,
# a known exception like phonebook (D30, its data: P4-32):
# - the checks M2 list speeddial as removed and nothing blocks, without
#   IZPBX_MIGRATE_IGNORE_MODULES;
# - the migration completes, verification M7 passed (verify=done, inventory
#   diff empty with the mapping of the migration), healthy on FreePBX 17, the
#   final report names speeddial left out;
# - no residue of FreePBX 15 breaks the restore ("Restore completed
#   successfully") and "fwconsole ma list" has no module in state Broken.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-26
fx="$TESTS_DIR/fixtures/out/20.16.22-fp15"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "fp15 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 --variant fp15 ${TEST_REUSE_FIXTURES:+--reuse}

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
env=(-e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)

c=$(t_run pbx "$image" --network "$net" -v "$v:/data" "${env[@]}")
t_wait_for 2400 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)|izpbx-init: done' >/dev/null"
logs=$(docker logs "$c" 2>&1)
grep -E -e 'preflight: (BLOCK|INFO|REMOVED|RESULT)|VERIFICATION|not installed|completed' -e "$T_LOG_DETAIL_RE" <<< "$logs" | sed 's/^/    | /' >&2
assert_cmd "M2: speeddial removed on purpose (D30)" -- grep -q 'preflight: REMOVED modules: speeddial has no FreePBX 17 release' <<< "$logs"
assert_cmd "M2: nothing blocks" -- grep -q 'preflight: RESULT: nothing blocks the migration' <<< "$logs"
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 300
state=$(docker exec "$c" cat /data/.izpbx-migration/state 2>/dev/null)
assert_cmd "verification M7 passed (verify=done)" -- grep -qx 'verify=done' <<< "$state"
assert_cmd "migration=done" -- grep -qx 'migration=done' <<< "$state"
snap=$(sed -n 's/^snapshot_dir=//p' <<< "$state" | tail -n 1)
assert_cmd "the restore completed (no FreePBX 15 residue breaks it)" -- \
  docker exec "$c" grep -q 'Restore completed successfully' "$snap/restore.log"
ma=$(docker exec -u asterisk "$c" fwconsole ma list 2>/dev/null)
log "modules not Enabled: $(grep -E '^\| ' <<< "$ma" | grep -vE '\| Enabled ' | awk -F'|' 'NR > 1 {gsub(/ /, "", $2); gsub(/^ +| +$/, "", $4); print $2 "=" $4}' | tr '\n' ' ')"
assert_eq "" "$(grep -iE '^\| [^|]+\| [^|]+\| Broken' <<< "$ma" || true)" "fwconsole ma list: no module Broken"
assert_contains "$(docker exec "$c" cat /data/.izpbx-migration/report.txt 2>/dev/null)" "modules left out (no FreePBX 17 release): phonebook speeddial" \
  "the final report names speeddial left out"
diff=$(docker exec "$c" izpbx-inventory --diff /data/.izpbx-migration/inventory-before.json /data/.izpbx-migration/inventory-after.json \
  --mapping /data/.izpbx-migration/mapping.tsv 2>&1) && rc=0 || rc=$?
log "inventory: $(tail -n 1 <<< "$diff")"
assert_eq 0 "$rc" "inventory diff empty with the mapping of the migration"
finish
