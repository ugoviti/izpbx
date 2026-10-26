#!/usr/bin/env bash
# P5-05: chan_dongle (software side, no real USB modem: P5-06 is manual).
# Asterisk without FreePBX with the dongle.conf of the 20.16.22 fixture
# (P0-04: [general], [defaults], device dongle0 on /dev/ttyUSB1-2):
# - chan_dongle is Running; "dongle show devices" answers without errors and
#   lists dongle0 (not connected: no modem in the container);
# - after "module reload chan_dongle.so" and a full "module reload" the
#   module is still Running and dongle0 still listed;
# - negative check: without dongle.conf (the image has none, as 20.16)
#   chan_dongle runs with no device: dongle0 is not listed.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-05
fx="$TESTS_DIR/fixtures/out/20.16.22"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
tar -xzOf "$fx/data.tar.gz" ./etc/asterisk/dongle.conf > "$work/dongle.conf" 2>/dev/null
chmod 644 "$work/dongle.conf"
assert_cmd "the fixture has a dongle.conf with dongle0" -- grep -qx '\[dongle0\]' "$work/dongle.conf"

ast_run() { # name [docker args]
  local n=$1; shift
  t_run "$n" "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true -e HTTPD_ENABLED=false \
    -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false "$@"
}
running() { docker exec "$1" asterisk -rx 'module show like chan_dongle' | grep -E '^chan_dongle\.so ' | grep -q ' Running '; }

c=$(ast_run dongle -v "$work/dongle.conf:/etc/asterisk/dongle.conf:ro")
assert_cmd "Asterisk starts" -- t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted'
assert_cmd "chan_dongle is Running" -- running "$c"
out=$(docker exec "$c" asterisk -rx 'dongle show devices' 2>&1)
log "dongle show devices:"$'\n'"$out"
assert_contains "$out" "dongle0" "dongle show devices lists dongle0"
assert_cmd_fails "dongle show devices answers without errors" -- grep -qiE 'no such command|error|unable' <<< "$out"

docker exec "$c" asterisk -rx 'module reload chan_dongle.so' >/dev/null
assert_cmd "after module reload chan_dongle.so: Running" -- running "$c"
docker exec "$c" asterisk -rx 'module reload' >/dev/null
assert_cmd "after module reload: Running" -- t_wait_for 30 -- running "$c"
assert_contains "$(docker exec "$c" asterisk -rx 'dongle show devices' 2>&1)" "dongle0" "after the reloads: dongle0 still listed"

n=$(ast_run noconf)
assert_cmd "control: Asterisk starts without dongle.conf" -- t_wait_for 120 -- docker exec "$n" asterisk -rx 'core waitfullybooted'
assert_cmd_fails "control: without dongle.conf no dongle0" -- \
  sh -c "docker exec $n asterisk -rx 'dongle show devices' | grep -q dongle0"
finish
