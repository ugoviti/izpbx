#!/usr/bin/env bash
# P5-04: g729 (codec_g729 of asterisk-g72x, bcg729) on a call.
# Asterisk without FreePBX (izpbx-asterisk/tests/fixtures/g729): endpoint anonymous with
# g729 and ulaw, the dialplan answers and plays tones (slin encoded for the
# caller).
# - sipp offers g729 only (izpbx-asterisk/tests/sipp/scenarios/codec-call.xml): 200 OK with
#   "a=rtpmap:18 G729/8000" in the answer; during the call the channel has
#   g729 as native format and encodes to it (WriteTranscode);
# - "core show translation paths": g729 <-> ulaw;
# - negative check: an offer with a codec Asterisk does not have (payload 98
#   "nosuch/8000") gets 488 Not Acceptable Here.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-04
sipp_image=izpbx-test-sipp:p5-04
fx="$TESTS_DIR/fixtures/g729"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
t_on_cleanup "docker image rm $sipp_image >/dev/null 2>&1"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "sipp image builds" -- docker build -q -t "$sipp_image" "$TESTS_DIR/sipp"
chmod 777 "$work"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
c=$(t_run ast "$image" --network "$net" --network-alias pbx -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true \
  -e HTTPD_ENABLED=false -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false \
  -v "$fx/pjsip.conf:/etc/asterisk/pjsip.conf:ro" -v "$fx/extensions.conf:/etc/asterisk/extensions.conf:ro")
assert_cmd "Asterisk starts" -- t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted'
ast() { docker exec "$c" asterisk -rx "$1"; }
call() { # pt codec
  rm -f "$work"/codec-call_*_messages.log
  docker run --rm --network "$net" -v "$TESTS_DIR/sipp/scenarios:/sc:ro" -v "$work:/w" -w /w "$sipp_image" \
    pbx:5060 -sf /sc/codec-call.xml -s 1234 -key pt "$1" -key codec "$2" -m 1 -timeout 30 -trace_msg >/dev/null 2>&1 || true
}

( t_wait_for 20 -- sh -c "docker exec $c asterisk -rx 'core show channels concise' | grep -q '^PJSIP/anonymous-.*!Up!'"
  ch=$(docker exec "$c" asterisk -rx 'core show channels concise' | awk -F'!' '/^PJSIP\/anonymous-/{print $1; exit}')
  docker exec "$c" asterisk -rx "core show channel $ch" > "$work/channel.txt" ) &
call 18 G729/8000
wait
msgs=$(cat "$work"/codec-call_*_messages.log 2>/dev/null)
assert_contains "$msgs" "SIP/2.0 200 OK" "g729 only: 200 OK"
assert_contains "$(awk '/^SIP\/2.0 200 OK/{p=1} p' <<< "$msgs")" "a=rtpmap:18 G729/8000" "g729 only: g729 negotiated in the answer"
log "channel:"$'\n'"$(grep -iE 'NativeFormats|WriteFormat|ReadFormat|Transcode' "$work/channel.txt")"
assert_cmd "the channel runs g729" -- grep -qE 'NativeFormats: *\(g729\)' "$work/channel.txt"
assert_cmd "Asterisk encodes to g729 for the caller" -- grep -qE 'WriteTranscode: *Yes.*g729' "$work/channel.txt"
assert_contains "$(ast 'core show translation paths g729')" "(g729@8000)->(slin@8000)->(ulaw@8000)" "translation g729 -> ulaw"
assert_contains "$(ast 'core show translation paths ulaw')" "(ulaw@8000)->(slin@8000)->(g729@8000)" "translation ulaw -> g729"

call 98 nosuch/8000
assert_contains "$(cat "$work"/codec-call_*_messages.log 2>/dev/null)" "SIP/2.0 488" "control: a codec Asterisk lacks gets 488"
finish
