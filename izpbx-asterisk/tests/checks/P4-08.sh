#!/usr/bin/env bash
# P4-08: clean FreePBX 17 install + restore (M5.2-M5.4) in a real start: the
# 20.16.22 fixture with IZPBX_MIGRATE_FREEPBX=true.
# - the container becomes healthy; the restore ran with exit 0 ("Restore
#   completed successfully" in <snapshot>/restore.log, state restore=done);
# - izpbx-inventory --diff of the fixture before (DB + files) and of the
#   running PBX after (--live) is empty with the mapping of this check:
#   chan_sip -> PJSIP, phonebook removed on purpose (D28); ignored: the
#   categories of the M6 items still to come (files P4-14 and dongle.conf),
#   astdb (generated keys such as pbx/UUID, P4-11 checks it key by key),
#   advanced_settings (P4-19), pjsip_endpoints (only in the --live inventory);
# - the CDR database: same checksum of every table as before;
# - control: the same diff with one extension removed from the "after"
#   inventory reports it (exit 1).
# P4_08_AFTER_RESTORE_SQL (CI, P6-03): passed to the migration as
# IZPBX_TEST_AFTER_RESTORE_SQL, a discrepancy after the restore: the check
# must then fail.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-08
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
sqlroot() { docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot -N; }
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | sqlroot || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" | sqlroot
cdrsum() {
  echo "SELECT table_name FROM information_schema.tables WHERE table_schema='asteriskcdrdb' ORDER BY 1" | sqlroot |
    while read -r t; do echo "CHECKSUM TABLE asteriskcdrdb.\`$t\`" | sqlroot; done
}
cdr_before=$(cdrsum)

v=$(t_volume data)
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
env=(-e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw)
# inventory before: the fixture DB and files, as the migration finds them
docker run --rm --entrypoint "" --network "$net" -v "$v:/data:ro" "${env[@]}" "$image" izpbx-inventory > "$work/before.json"
assert_cmd "inventory before" -- jq -e '.categories.extensions | length > 0' "$work/before.json"

inject=()
[ -z "${P4_08_AFTER_RESTORE_SQL:-}" ] || inject=(-e IZPBX_TEST_AFTER_RESTORE_SQL="$P4_08_AFTER_RESTORE_SQL")
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" "${env[@]}" -e IZPBX_MIGRATE_FREEPBX=true "${inject[@]}")
# the end of the migration first: a failed verification (break_migration in CI)
# is known at once, not after the timeout of healthy
t_wait_for 2400 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)|MAINTENANCE MODE|rc.init: fatal' >/dev/null"
migrated() { docker logs "$c" 2>&1 | grep -E 'migration: FreePBX 16 -> .* completed' >/dev/null && t_wait_healthy "$c" 300; }
assert_cmd "migrated: healthy" -- migrated
docker logs "$c" 2>&1 | grep -E 'migration:|preflight: (BLOCK|RESULT)|freepbx: (migration|FreePBX)' | sed 's/^/    | /' | tail -n 40 >&2
state=$(docker exec "$c" cat /data/.izpbx-migration/state 2>/dev/null)
assert_contains "$state" "restore=done" "state: restore=done"
snap=$(sed -n 's/^snapshot_dir=//p' <<< "$state" | tail -n 1)
assert_cmd "restore log: Restore completed successfully" -- docker exec "$c" grep -q 'Restore completed successfully' "$snap/restore.log"
assert_contains "$(docker exec -u asterisk "$c" fwconsole -V 2>/dev/null)" "17." "FreePBX 17 running"

# inventory after, on the running PBX
docker exec "$c" izpbx-inventory --live > "$work/after.json"
# a removed module becomes a record present after, so it is no difference
printf '%s\n' \
  "extensions	tech=sip	tech=pjsip" \
  "trunks	tech=sip	tech=pjsip" \
  "modules	^module=phonebook enabled=1$	module=framework enabled=1" \
  "astdb	ignore" "files	ignore" \
  "advanced_settings	ignore" "pjsip_endpoints	ignore" > "$work/map"
docker cp "$work/before.json" "$c:/tmp/before.json" >/dev/null
docker cp "$work/after.json" "$c:/tmp/after.json" >/dev/null
docker cp "$work/map" "$c:/tmp/map" >/dev/null
diff=$(docker exec "$c" izpbx-inventory --diff /tmp/before.json /tmp/after.json --mapping /tmp/map) && rc=0 || rc=$?
log "inventory diff:"; sed 's/^/    | /' <<< "$diff" | head -n 80 >&2
assert_eq 0 "$rc" "inventory diff empty with the mapping"
assert_eq "$cdr_before" "$(cdrsum)" "CDR database unchanged (checksum of every table)"

# control: an extension missing after the migration is reported
jq '.categories.extensions |= .[1:]' "$work/after.json" > "$work/after-1.json"
docker cp "$work/after-1.json" "$c:/tmp/after-1.json" >/dev/null
docker exec "$c" izpbx-inventory --diff /tmp/before.json /tmp/after-1.json --mapping /tmp/map >/dev/null && rc=0 || rc=$?
assert_eq 1 "$rc" "control: a missing extension is a difference"
finish
