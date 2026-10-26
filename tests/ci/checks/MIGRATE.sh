#!/usr/bin/env bash
# MIGRATE (CI, P6-08): migration of one izPBX 20.16.x version to 22.17, for the
# weekly job "migration from every 20.16.x" (.gitea/workflows/migration-matrix.yml).
#   MIGRATE_VERSION=20.16.5 TEST_CHECKS_DIR=tests/ci/checks tests/run.sh MIGRATE
# The fixture of that version (tests/fixtures/make-fixture.sh, P0-04) migrated
# in a real start with the opt-in. Result line "VERSION<TAB>RESULT<TAB>DETAIL"
# in MIGRATE_RESULT (default tests/.logs/migrate-<version>.txt), RESULT one of:
#   ok       migrated, verification M7 passed, healthy
#   blocked  stopped by the checks M2 with their instructions (maintenance mode);
#            a space block is "failed" instead: the fixtures are small, it is the
#            disk of the CI runner
#   failed   anything else
# The check passes for ok and blocked, fails for failed. MIGRATE_BREAK=1 breaks
# the version on purpose (extension 1003 removed after the restore: the
# verification M7 finds it), the negative check of the job.
source "$(dirname "$0")/../../lib.sh"
ver=${MIGRATE_VERSION:?MIGRATE_VERSION not set}
result_file=${MIGRATE_RESULT:-$TESTS_DIR/.logs/migrate-$ver.txt}
image=izpbx-asterisk:migrate
fx="$TESTS_DIR/fixtures/out/$ver"
mkdir -p "$(dirname "$result_file")"
record() { printf '%s\t%s\t%s\n' "$ver" "$1" "$2" > "$result_file"; log "result: $ver $1 $2"; }
record failed "did not run to the end"

assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "$ver fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v "$ver" --reuse
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
broken=()
[ "${MIGRATE_BREAK:-}" != 1 ] || broken=(-e IZPBX_TEST_AFTER_RESTORE_SQL="DELETE FROM devices WHERE id = '1003'; DELETE FROM users WHERE extension = '1003'")
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw \
  -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true "${broken[@]}")
t_wait_for 2700 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)|MAINTENANCE MODE|rc.init: fatal' >/dev/null"
logs=$(docker logs "$c" 2>&1)
grep -E 'preflight: (BLOCK|RESULT)|migration: (FreePBX 16 ->|VERIFICATION)|MAINTENANCE|error:' <<< "$logs" | sed 's/^/    | /' | head -n 20 >&2
if grep -qE 'migration: FreePBX 16 -> .* completed' <<< "$logs" && t_wait_healthy "$c" 300; then
  record ok "$(grep -oE 'FreePBX 16 -> [0-9.]+' <<< "$logs" | head -n 1)"
elif grep -q 'preflight: BLOCK space' <<< "$logs"; then
  # the fixtures are small: a space block is the disk of the CI runner, not a
  # result of the migration (seen with 4 Docker-in-Docker jobs at a time)
  record failed "not enough disk space on the CI runner: $(grep -m1 -oE 'preflight: BLOCK space: .*' <<< "$logs" | cut -c 25-140)"
elif grep -q 'preflight: BLOCK' <<< "$logs" && grep -q 'MAINTENANCE MODE' <<< "$logs"; then
  record blocked "$(grep -m1 -oE 'preflight: BLOCK .*' <<< "$logs" | cut -c 18-200)"
elif grep -q 'cannot reload the migrated configuration' <<< "$logs"; then
  record failed "reload of FreePBX 17: $(grep -A4 'cannot reload the migrated configuration' <<< "$logs" | sed -E 's/^izpbx: error: +//' | grep -m1 -iE 'error|understand|exception' | cut -c 1-150)"
elif grep -q 'VERIFICATION FAILED' <<< "$logs"; then
  # the first difference of the report, after "VERIFICATION FAILED" (lines "izpbx: error:   <category>: - <record>")
  record failed "verification M7: $(grep -A8 'VERIFICATION FAILED' <<< "$logs" | sed -E 's/^izpbx: (error|warning|info): +//' |
    grep -m1 -E '^[a-z_]+: [-+] ' | cut -c 1-150)"
else
  record failed "$(grep -m1 -E 'error:' <<< "$logs" | sed 's/^izpbx: error: //' | cut -c 1-150)"
fi
assert_cmd_fails "$ver: migrated or blocked with instructions (not failed)" -- grep -qP '\tfailed\t' "$result_file"
finish
