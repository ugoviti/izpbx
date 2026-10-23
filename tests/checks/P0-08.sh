#!/usr/bin/env bash
# P0-08: fixtures for the real migration cases regenerate and show their
# characteristic. Each characteristic is checked on its fixture and must NOT
# hold on the plain 20.16.22 fixture (negative control).
#
# TEST_REUSE_FIXTURES=1 (set by run.sh all-done) reuses fixtures built from
# unchanged inputs instead of regenerating them.
source "$(dirname "$0")/../lib.sh"

out="$TESTS_DIR/fixtures/out"
base="$out/20.16.22"
make() { "$TESTS_DIR/fixtures/make-fixture.sh" -o "$out" ${TEST_REUSE_FIXTURES:+--reuse} "$@" >/dev/null 2>&1; }
verify() { "$TESTS_DIR/fixtures/verify-fixture.sh" "$1" >/dev/null 2>&1; }
mf() { sed -n "s/^$2=//p" "$1/manifest.txt"; }
dump() { gzip -dc "$1/asterisk.sql.gz"; }
# grep -c reads all its input: "gzip -dc | grep -q" would end in SIGPIPE, a
# failure under pipefail even when the text is there
dump_has() { gzip -dc "$1/$2" | grep -cE -- "$3" >/dev/null; }
enabled_modules() { dump "$1" | grep -oE "\([0-9]+,'[a-z0-9_]+','[0-9.]+',1," | cut -d"'" -f2; }

# throwaway MariaDB for the counts of the large fixture
db=$(t_run db docker.io/mariadb:10.11.19 -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
q() { docker exec "$db" mariadb -uroot -N -B -e "$1"; }
load() { # fixture -> config and cdr databases loaded (names from the manifest)
  q "DROP DATABASE IF EXISTS \`$(mf "$1" db_config)\`; DROP DATABASE IF EXISTS \`$(mf "$1" db_cdr)\`;"
  gzip -dc "$1/asterisk.sql.gz" | docker exec -i "$db" mariadb -uroot
  gzip -dc "$1/asteriskcdrdb.sql.gz" | docker exec -i "$db" mariadb -uroot
}

# --- characteristics: 0 when the fixture has it
is_fp15() {
  mf "$1" chain | grep -q '^18\.15\.' || return 1
  dump_has "$1" asterisk.sql.gz "\([0-9]+,'[a-z0-9_]+','15\.[0-9.]+',1," || return 1   # module left at a 15.x release
  dump_has "$1" asterisk.sql.gz '^CREATE TABLE `kvstore_Fax`'                            # table only FreePBX 15 created
}
is_noroot() {
  [ "$(mf "$1" db_root)" == "none" ] || return 1
  local g; g=$(mf "$1" db_grants)
  [[ "$g" == *"ON \`asterisk\`.*"* && "$g" == *"ON \`asteriskcdrdb\`.*"* ]] || return 1
  [[ "$g" != *"ALL PRIVILEGES ON *.*"* && "$g" != *"WITH GRANT OPTION"* ]]   # created by hand, not by izPBX
}
is_extdb() {
  [ "$(mf "$1" db_config)" == "pbxconfig" ] && [ "$(mf "$1" db_cdr)" == "pbxcdr" ] && [ "$(mf "$1" db_port)" == "3307" ] || return 1
  dump_has "$1" asterisk.sql.gz 'CREATE DATABASE .*`pbxconfig`' && dump_has "$1" asteriskcdrdb.sql.gz 'CREATE DATABASE .*`pbxcdr`'
}
is_large() {
  load "$1"
  local ext cdr mb
  ext=$(q "SELECT count(*) FROM \`$(mf "$1" db_config)\`.devices")
  cdr=$(q "SELECT count(*) FROM \`$(mf "$1" db_cdr)\`.cdr")
  mb=$(tar -tvzf "$1/data.tar.gz" ./var/spool/asterisk/monitor 2>/dev/null | awk '{s += $3} END {print int(s / 1048576)}')
  log "$(basename "$1"): $ext extensions, $cdr CDR rows, $mb MiB of recordings"
  [ "$ext" -ge 500 ] && [ "$cdr" -ge 2000000 ] && [ "$mb" -ge 5000 ]
}
is_interrupted() {
  tar -tzf "$1/data.tar.gz" ./.initialized ./etc/freepbx.conf >/dev/null 2>&1 || return 1
  local n full
  n=$(enabled_modules "$1" | wc -l); full=$(enabled_modules "$base" | wc -l)
  log "$(basename "$1"): $n enabled modules (complete install: $full)"
  [ "$n" -lt "$full" ] && ! enabled_modules "$1" | grep -cx ucp >/dev/null
}

assert_cmd "base 20.16.22 fixture available" -- make -v 20.16.22

# (a) sample versions
for v in 20.16.0 20.16.10; do
  assert_cmd "fixture $v regenerates" -- make -v "$v"
  assert_eq "$v" "$(mf "$out/$v" version)" "fixture $v declares image version $v"
  assert_cmd "fixture $v holds every T5 element" -- verify "$out/$v"
done

# (b)..(f): variant, characteristic, whether the T5 content is expected
for spec in fp15:is_fp15:yes noroot:is_noroot:yes extdb:is_extdb:yes large:is_large:yes interrupted:is_interrupted:no; do
  IFS=: read -r variant check full <<< "$spec"
  d="$out/20.16.22-$variant"
  assert_cmd "fixture $variant regenerates" -- make -v 20.16.22 --variant "$variant"
  assert_cmd "fixture $variant: $check" -- "$check" "$d"
  assert_cmd_fails "control: plain 20.16.22 is not $check" -- "$check" "$base"
  [ "$full" == "yes" ] && assert_cmd "fixture $variant holds every T5 element" -- verify "$d"
done

finish
