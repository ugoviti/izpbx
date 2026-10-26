#!/usr/bin/env bash
# P0-10: variant B prototype. An archive rebuilt from the raw data of the
# 20.16.22 fixture is restored by FreePBX 17 (fwconsole backup --restore) on a
# fresh install: exit 0, and extensions, trunks, IVR, queues, ring groups and
# routes match the fixture. Negative: an archive without the IVR table is
# restored too, and the comparison catches the missing IVR.
source "$(dirname "$0")/../lib.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
# shellcheck source=../proto/proto.sh
source "$TESTS_DIR/proto/proto.sh"

fx="$TESTS_DIR/fixtures/out/20.16.22"
CONVERT="--convertchansipexts2pjsip --convertchansiptrunks2pjsip"

assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
# reference DB with the fixture content
ref=$(t_run ref docker.io/mariadb:10.11.19 -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
assert_cmd "FreePBX 17 prototype installs" -- proto_up
t_wait_healthy "$ref" 120 || die "reference MariaDB did not start"
gzip -dc "$fx/asterisk.sql.gz" | docker exec -i "$ref" mariadb -uroot

assert_cmd "legacy archive builds from the fixture" -- "$TESTS_DIR/proto/build-legacy-archive.sh" "$fx" "$work/restore.tar.gz"
assert_cmd "legacy archive without IVR builds" -- "$TESTS_DIR/proto/build-legacy-archive.sh" "$fx" "$work/restore-noivr.tar.gz" --drop-table ivr_details

TABLES="devices trunks ivr_details queues_config ringgroups outbound_routes incoming timeconditions userman_users recordings fax_incoming"
counts() { # sql-function -> "table=count ..."
  local t
  for t in $TABLES; do printf '%s=%s ' "$t" "$("$1" "SELECT count(*) FROM $t" 2>/dev/null || echo missing)"; done
}
ref_sql() { docker exec "$ref" mariadb -uroot -N -B asterisk -e "$1"; }
pick() { tr ' ' '\n' <<< "$2" | grep "^$1="; }
expected=$(counts ref_sql)
log "fixture:  $expected"

# shellcheck disable=SC2086  # CONVERT holds two options
proto_restore "$work/restore.tar.gz" $CONVERT && rc=0 || rc=$?
assert_eq 0 "$rc" "fwconsole backup --restore exits 0"
assert_contains "$(cat "$work/restore.log")" "Restore completed successfully" "restore reports success"
got=$(counts proto_sql)
log "restored: $got"
for t in $TABLES; do
  assert_eq "$(pick "$t" "$expected")" "$(pick "$t" "$got")" "restored $t matches the fixture"
done

# negative: the IVR missing from the archive must show up in the comparison
# shellcheck disable=SC2086
proto_restore "$work/restore-noivr.tar.gz" $CONVERT || true
assert_ne "$(pick ivr_details "$expected")" "$(pick ivr_details "$(counts proto_sql)")" "an archive without the IVR is caught by the comparison"

finish
