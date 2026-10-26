#!/usr/bin/env bash
# P5-01: a call between two PJSIP extensions through FreePBX 17 (sipp).
# - FreePBX installed, extensions 1001 and 1002 created with
#   "fwconsole bulkimport" (direct media off: the audio goes through
#   Asterisk; qualify off: no OPTIONS to the sipp UAS);
# - 1002: sipp registers from the address and port of the sipp UAS (the
#   PBX rewrites the Contact with the source address), then the UAS answers
#   there (also the MWI NOTIFY, -aa) and echoes the RTP (-rtp_echo);
# - 1001: sipp calls 1002 with digest auth, sends G.711 a-law audio for 8 s
#   and hangs up (izpbx-asterisk/tests/sipp/scenarios/call.xml);
# - checks: 200 OK to the INVITE and to the BYE; during the call both
#   Asterisk channels receive and send RTP ("pjsip show channelstats"); the
#   CDR in asteriskcdrdb: 1001 -> 1002 ANSWERED with billsec > 0;
# - the "full" log holds the call (Asterisk runs with -vvv as in 20.16);
# - negative check: a call to an extension with no registration is not
#   answered (no ANSWERED CDR).
# The exit code of sipp is not used: after a successful call it reports
# "Failed to delete FD from epoll" (EPERM in the container) and exits 1.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-01
sipp_image=izpbx-test-sipp:p5-01
sc="$TESTS_DIR/sipp/scenarios"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
t_on_cleanup "docker image rm $sipp_image >/dev/null 2>&1"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "sipp image builds" -- docker build -q -t "$sipp_image" "$TESTS_DIR/sipp"
chmod 777 "$work"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
c=$(t_run pbx "$image" --network "$net" --network-alias pbx -v "$(t_volume data):/data" -e APP_DATA=/data \
  -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw)
assert_cmd "FreePBX installed: healthy" -- t_wait_healthy "$c" 1500

# NOTE: bulkimport of FreePBX 17 needs --replace ("Undefined variable $replace" without it)
docker exec -u asterisk "$c" sh -c 'printf "extension,name,tech,secret,direct_media,qualifyfreq\n1001,Test One,pjsip,Secret1001x,no,0\n1002,Test Two,pjsip,Secret1002x,no,0\n1003,Test Three,pjsip,Secret1003x,no,0\n" > /tmp/p5-01.csv
  fwconsole bulkimport --type=extensions --replace /tmp/p5-01.csv && fwconsole reload' >/dev/null 2>&1
assert_eq 3 "$(docker exec "$c" asterisk -rx 'pjsip show endpoints' | grep -cE '^ Endpoint: +100[123]/')" "extensions 1001, 1002, 1003 created"

# 1002: the UAS and its registration share one network namespace and port
ns=$(t_run ns "$sipp_image" --network "$net" --entrypoint sleep -- infinity)
nsip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$ns")
printf 'SEQUENTIAL\n1002;%s:5070\n' "$nsip" > "$work/reg.csv"; printf 'SEQUENTIAL\n1001\n' > "$work/call.csv"
sipp() { docker run --rm --network "$1" -v "$sc:/sc:ro" -v "$work:/w" -w /w "$sipp_image" "${@:2}"; }
sipp "container:$ns" pbx:5060 -sf /sc/register.xml -inf /w/reg.csv -au 1002 -ap Secret1002x -m 1 -p 5070 -timeout 15 >/dev/null 2>&1 || true
assert_cmd "1002 registered" -- sh -c "docker exec $c asterisk -rx 'pjsip show contacts' | grep -q 'Contact:  1002/sip:1002@$nsip:5070'"
# no call limit (-m): after the registration Asterisk sends a NOTIFY (MWI of
# the voicemail box), which -aa answers and which would count as the call
t_run uas "$sipp_image" --network "container:$ns" -t -- -sn uas -p 5070 -rtp_echo -mp 6000 -aa >/dev/null
sleep 1

# "core show channels concise": Channel!Context!Exten!Prio!State!...
up2() { [ "$(docker exec "$c" asterisk -rx 'core show channels concise' | grep -cE '^PJSIP/100[12]-[^!]*![^!]*![^!]*![^!]*!Up!')" -ge 2 ]; }
( t_wait_for 20 -- up2 || docker exec "$c" asterisk -rx 'core show channels concise' > "$work/channels.txt"
  sleep 3; docker exec "$c" asterisk -rx 'pjsip show channelstats' > "$work/stats.txt" ) &
sipp "$net" pbx:5060 -sf /sc/call.xml -inf /w/call.csv -au 1001 -ap Secret1001x -s 1002 -m 1 -p 5090 -mp 7000 \
  -timeout 40 -trace_msg >/dev/null 2>&1 || true
wait
msgs=$(cat "$work"/call_*_messages.log 2>/dev/null)
assert_eq 2 "$(grep -cE '^SIP/2.0 200 OK' <<< "$msgs")" "200 OK to the INVITE and to the BYE"
log "channel stats:"$'\n'"$(cat "$work/stats.txt" "$work/channels.txt" 2>/dev/null || true)"
for ch in 1001 1002; do
  # BridgeId ChannelId UpTime Codec RxCount Lost Pct Jitter TxCount ... (no "PJSIP/" prefix)
  line=$(grep -E "^ *[^ ]+ +$ch-" "$work/stats.txt" | head -1 || true)
  rx=$(awk '{print $5}' <<< "$line"); tx=$(awk '{print $9}' <<< "$line")
  assert_cmd "channel $ch receives RTP ($rx packets)" -- test "${rx:-0}" -gt 0
  assert_cmd "channel $ch sends RTP ($tx packets)" -- test "${tx:-0}" -gt 0
done
cdr() { docker exec "$db" mariadb -uroot -prootpw asteriskcdrdb -N -e "$1"; }
assert_cmd "CDR: 1001 -> 1002 ANSWERED with billsec > 0" -- t_wait_for 30 -- \
  sh -c "[ \"\$(docker exec $db mariadb -uroot -prootpw asteriskcdrdb -N -e \"SELECT count(*) FROM cdr WHERE src='1001' AND dst='1002' AND disposition='ANSWERED' AND billsec > 0\")\" -ge 1 ]"

assert_cmd "the full log has the call (Asterisk verbose 3, as 20.16)" -- \
  sh -c "docker exec $c grep -a 'Called PJSIP/1002/' /var/log/asterisk/full >/dev/null"

# negative check: 1003 never registered
rm -f "$work"/call_*_messages.log
sipp "$net" pbx:5060 -sf /sc/call.xml -inf /w/call.csv -au 1001 -ap Secret1001x -s 1003 -m 1 -p 5090 -mp 7000 \
  -timeout 25 -trace_msg >/dev/null 2>&1 || true
sleep 3
assert_eq 0 "$(cdr "SELECT count(*) FROM cdr WHERE dst='1003' AND disposition='ANSWERED'")" "control: a call to an unregistered extension is not answered"
finish
