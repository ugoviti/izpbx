#!/usr/bin/env bash
# P5-09: SLA with app_sla only, MeetMe stays off as in 20.16 (design D23).
# Asterisk without FreePBX with an example sla.conf (tests/fixtures/sla: one
# trunk line1, one station station1):
# - app_sla.so is installed and Running;
# - "sla show stations" lists station1 with its trunk line1, "sla show
#   trunks" lists line1;
# - app_meetme.so is not installed;
# - negative check: without sla.conf station1 is not listed.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-09
assert_cmd "image builds" -- t_build_image "$image"
mods=/usr/lib64/asterisk/modules
assert_cmd "app_sla.so is installed" -- docker run --rm --entrypoint "" "$image" test -f "$mods/app_sla.so"
assert_cmd_fails "app_meetme.so is not installed" -- docker run --rm --entrypoint "" "$image" test -e "$mods/app_meetme.so"

ast_run() { # name [docker args]
  local n=$1; shift
  t_run "$n" "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true -e HTTPD_ENABLED=false \
    -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false "$@"
}
c=$(ast_run sla -v "$TESTS_DIR/fixtures/sla/sla.conf:/etc/asterisk/sla.conf:ro")
assert_cmd "Asterisk starts" -- t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted'
assert_cmd "app_sla is Running" -- sh -c "docker exec $c asterisk -rx 'module show like app_sla' | grep -E '^app_sla\.so ' | grep -q ' Running '"
st=$(docker exec "$c" asterisk -rx 'sla show stations' 2>&1)
log "sla show stations:"$'\n'"$st"
assert_contains "$st" "station1" "sla show stations lists station1"
assert_contains "$st" "line1" "station1 uses trunk line1"
assert_contains "$(docker exec "$c" asterisk -rx 'sla show trunks' 2>&1)" "line1" "sla show trunks lists line1"
assert_cmd_fails "MeetMe is not loaded" -- sh -c "docker exec $c asterisk -rx 'module show like meetme' | grep -q 'app_meetme'"

n=$(ast_run nosla)
assert_cmd "control: Asterisk starts without sla.conf" -- t_wait_for 120 -- docker exec "$n" asterisk -rx 'core waitfullybooted'
assert_cmd_fails "control: without sla.conf no station1" -- sh -c "docker exec $n asterisk -rx 'sla show stations' | grep -q station1"
finish
