#!/usr/bin/env bash
# P7-01: README section "Upgrade from 20.16 to 22.17".
# - every variable new or removed in the release notes (§13 of the design:
#   the list below, and the names in backticks of §13 when .specs is there)
#   is named in the README; negative check: a README without one is reported;
# - the code blocks marked "<!-- test:run -->" are run, in order, as written,
#   in a docker CLI container (sh, docker compose) on a deploy made of the
#   compose.yml and default.env of the repository, with the 20.16.22 fixture
#   in data/: image switched, checks green, backup files written, migration
#   started and healthy, final report shown, rollback back to FreePBX 16;
#   negative check: a failing block makes the runner fail.
# The deploy differs from the repository files only where a test must:
# compose.test.yml gives the containers names and labels of the test, the
# bridge network instead of the host one, no published port, and the image
# under test; .env the database host and passwords of the fixture.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p7-01
cli=docker.io/library/docker:27.5.1-cli
readme="$REPO_DIR/README.md"
fx="$TESTS_DIR/fixtures/out/20.16.22"
work=$(mktemp -d)

# --- the variables of the release notes
vars="IZPBX_MIGRATE_FREEPBX IZPBX_MIGRATE_IGNORE_MODULES IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN FREEPBX_AUTOUPGRADE_CORE
  ASTERISK_VER FREEPBX_VER FOP2_VER ZABBIX_VER FOP2_SHA256 ZABBIX_REL FREEPBX_MODULES_EXTRA APP_RUNAS MULTISERVICE
  CMD_OVERRIDE ENTRYPOINT_TINI UMASK PMA_CONFIG APP_PORT_SIP APP_CUSTOM_SCRIPTS"
spec="$REPO_DIR/.specs/2026-10-23-release-22.17.0-freepbx17.md"
if [ -f "$spec" ]; then
  vars+=" $(sed -n '/^## 13\./,/^## 14\./p' "$spec" | grep -oE '`[A-Z][A-Z0-9_]{2,}`' | tr -d '`' | sort -u | tr '\n' ' ')"
fi
vars=$(tr ' \n' '\n\n' <<< "$vars" | grep . | sort -u)
missing_vars() { # readme -> the variables it does not name
  local v; for v in $vars; do grep -qw "$v" "$1" || printf '%s ' "$v"; done
}
assert_eq "" "$(missing_vars "$readme")" "the README names every variable of the release notes"
grep -vw IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN "$readme" > "$work/readme-without"
assert_eq "IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN " "$(missing_vars "$work/readme-without")" "negative: a README without one is reported"

# --- the marked blocks
awk -v dir="$work" '
  /^<!-- test:run -->$/ {m = 1; next}
  m && /^```sh$/ {n++; f = sprintf("%s/block-%d.sh", dir, n); b = 1; m = 0; next}
  b && /^```$/ {b = 0; close(f); next}
  b {print > f}
  {m = 0}' "$readme"
blocks=$(find "$work" -maxdepth 1 -name 'block-*.sh' | wc -l)
assert_eq 7 "$blocks" "7 marked blocks: switch, checks, backup, start, wait, report, rollback"

assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

# --- the deploy: compose.yml and default.env of the repository
cp "$REPO_DIR/compose.yml" "$work/compose.yml"
sed -e 's/^MYSQL_SERVER=.*/MYSQL_SERVER=db/' -e 's/^MYSQL_PASSWORD=.*/MYSQL_PASSWORD=fixture-pw/' \
  -e 's/^MYSQL_ROOT_PASSWORD=.*/MYSQL_ROOT_PASSWORD=rootpw/' "$REPO_DIR/default.env" > "$work/.env"
cat > "$work/compose.test.yml" <<EOF
services:
  db:
    container_name: $TEST_PROJECT-db
    labels:
      izpbx.test: $TEST_PROJECT
    ports: !reset []
  izpbx:
    container_name: $TEST_PROJECT-izpbx
    image: $image
    labels:
      izpbx.test: $TEST_PROJECT
    network_mode: !reset null
    networks:
      - izpbx
EOF
# the blocks run here: a docker CLI container, the work directory at the same path
runner() { # [timeout] < script
  docker run --rm -i -v /var/run/docker.sock:/var/run/docker.sock -v "$work:$work" -w "$work" \
    -e COMPOSE_PROJECT_NAME="$TEST_PROJECT" -e COMPOSE_FILE=compose.yml:compose.test.yml \
    "$cli" timeout "${1:-600}" sh -eu
}
# root owned files of the containers (data/, the backup): removed as root, after the deploy
t_on_cleanup "echo 'docker compose down -v --timeout 10 >/dev/null 2>&1; rm -rf data izpbx-20.16-*' | runner 120"
t_on_cleanup "t_rmtree '$work'"

echo 'docker compose up -d db' | runner >/dev/null 2>&1
db_ping() { echo 'docker compose exec -T db mariadb-admin ping -uroot -prootpw' | runner 30 >/dev/null 2>&1; }
t_wait_for 120 -- db_ping
dbsql() { echo "docker compose exec -T db mariadb -uroot -prootpw -N $*" | runner; }
for f in asterisk asteriskcdrdb; do
  gzip -dc "$fx/$f.sql.gz" > "$work/$f.sql"
  dbsql "< $f.sql" || die "cannot load $f"
  rm -f "$work/$f.sql"
done
echo "GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" > "$work/grant.sql"; dbsql "< grant.sql"
docker run --rm --entrypoint "" -v "$work:/w" -v "$fx:/fx:ro" "$image" sh -c 'mkdir -p /w/data/izpbx && tar -C /w/data/izpbx -xzf /fx/data.tar.gz' 2>/dev/null

run_block() { # n timeout -> output of the block in $work/out-n
  log "block $1: $(head -n 1 "$work/block-$1.sh")"
  runner "$2" < "$work/block-$1.sh" > "$work/out-$1" 2>&1
}
assert_cmd "block 1 (image switch) runs" -- run_block 1 60
assert_cmd "compose.yml: image 22.17.0" -- grep -q 'image: docker.io/izdock/izpbx-asterisk:22.17.0' "$work/compose.yml"
assert_cmd "block 2 (checks) runs: nothing blocks" -- run_block 2 600
grep -E '^(BLOCK|RESULT)' "$work/out-2" | sed 's/^/    | /' >&2
assert_cmd "checks: OK framework" -- grep -q '^OK framework' "$work/out-2"
assert_cmd "block 3 (backup) runs" -- run_block 3 600
assert_cmd "backup: both databases dumped" -- sh -c "gzip -dc '$work/izpbx-20.16-db.sql.gz' | grep -c '^CREATE DATABASE' | grep -qx 2"
assert_cmd "backup: data archive" -- sh -c "tar -tzf '$work/izpbx-20.16-data.tar.gz' 2>/dev/null | grep -q '^data/izpbx/.initialized$'"
assert_cmd "block 4 (opt-in, start) runs" -- run_block 4 300
assert_cmd "block 5 (wait healthy) runs: migrated" -- run_block 5 2700
echo 'docker compose logs izpbx 2>&1 | grep -E "migration: (FreePBX 16 ->|VERIFICATION)|MAINTENANCE" || true' | runner 60 | sed 's/^/    | /' >&2
assert_cmd "block 6 (report) runs" -- run_block 6 60
assert_contains "$(cat "$work/out-6")" "izPBX migration FreePBX 16 -> " "the report is shown"
assert_cmd "block 7 (rollback) runs" -- run_block 7 900
tail -n 3 "$work/out-7" | sed 's/^/    | /' >&2
echo "SELECT version FROM asterisk.modules WHERE modulename = 'framework'" > "$work/fw.sql"
fw=$(dbsql "< fw.sql")
assert_cmd "after the rollback: FreePBX 16 framework ($fw)" -- grep -q '^16\.' <<< "$fw"

printf 'docker compose run --rm --no-deps --entrypoint izpbx-no-such-command izpbx\n' > "$work/block-bad.sh"
run_bad() { runner 120 < "$work/block-bad.sh" >/dev/null 2>&1; }
assert_cmd_fails "negative: a failing block makes the runner fail" -- run_bad
finish
