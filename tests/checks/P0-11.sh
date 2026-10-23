#!/usr/bin/env bash
# P0-11: chan_sip -> PJSIP conversion of extensions AND trunks, non interactive.
# Mechanism chosen: the FreePBX 17 restore options --convertchansipexts2pjsip
# and --convertchansiptrunks2pjsip (no own conversion code needed).
# After the restore: no tech='sip' in devices/trunks, and every former chan_sip
# endpoint is listed by "pjsip show endpoints". Negative: a restore that skips
# chan_sip (--skipchansipexts --skipchansiptrunks) loses those endpoints.
source "$(dirname "$0")/../lib.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
# shellcheck source=../proto/proto.sh
source "$TESTS_DIR/proto/proto.sh"

fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

# former chan_sip endpoints of the fixture: extensions and trunk peers
ref=$(t_run ref docker.io/mariadb:10.11.19 -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$ref" 120 || die "reference MariaDB did not start"
gzip -dc "$fx/asterisk.sql.gz" | docker exec -i "$ref" mariadb -uroot
chansip=$(docker exec "$ref" mariadb -uroot -N -B asterisk -e \
  "SELECT id FROM devices WHERE tech='sip' UNION SELECT channelid FROM trunks WHERE tech='sip'" | sort | tr '\n' ' ')
log "chan_sip endpoints in the fixture: $chansip"
assert_ne "" "${chansip// /}" "the fixture has chan_sip endpoints to convert"

assert_cmd "FreePBX 17 prototype installs" -- proto_up
assert_cmd "legacy archive builds" -- "$TESTS_DIR/proto/build-legacy-archive.sh" "$fx" "$work/convert.tar.gz"
cp "$work/convert.tar.gz" "$work/skip.tar.gz"

endpoints() {
  docker exec "$pbx" fwconsole reload >/dev/null 2>&1 || true
  docker exec "$pbx" asterisk -rx "pjsip show endpoints" | awk '$1=="Endpoint:" && $2 !~ /^</ {split($2, a, "/"); print a[1]}' | sort -u
}

# negative first, on the fresh install: a restore that skips chan_sip leaves
# no PJSIP endpoint for the former chan_sip ones (afterwards the converting
# restore would leave them in place)
assert_cmd "restore that skips chan_sip" -- proto_restore "$work/skip.tar.gz" --skipchansipexts --skipchansiptrunks
eps=$(endpoints)
log "pjsip endpoints after skip: $(echo $eps)"
for e in $chansip; do
  assert_cmd_fails "control: without conversion $e is not a PJSIP endpoint" -- grep -qx "$e" <<< "$eps"
done

assert_cmd "restore with conversion" -- proto_restore "$work/convert.tar.gz" --convertchansipexts2pjsip --convertchansiptrunks2pjsip
assert_eq "0" "$(proto_sql "SELECT (SELECT count(*) FROM devices WHERE tech='sip') + (SELECT count(*) FROM trunks WHERE tech='sip')")" \
  "no tech='sip' left in devices and trunks"
eps=$(endpoints)
log "pjsip endpoints: $(echo $eps)"
for e in $chansip; do
  assert_cmd "former chan_sip endpoint $e is a PJSIP endpoint" -- grep -qx "$e" <<< "$eps"
done
# the converted IP-auth trunk still points to the provider
assert_contains "$(docker exec "$pbx" asterisk -rx 'pjsip show endpoint prov-sip-ip' 2>/dev/null)" "192.0.2.10" \
  "converted trunk prov-sip-ip keeps the provider address"

finish
