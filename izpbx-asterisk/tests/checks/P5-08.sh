#!/usr/bin/env bash
# P5-08: voicemail to email. FreePBX with mail through msmtp to a mailpit
# (SMTP_RELAYHOST, no TLS); extension 1002 (never registered) has a voicemail
# box with email 1002@example.com and attach=yes (bulkimport voicemail_*).
# - 1001 calls 1002 (sipp, scenarios/voicemail-call.xml: 25 s of G.711 tone,
#   past the prompts and the beep): VoiceMail() runs (app_voicemail_odbc is
#   not built: its failed load at a reload removed VoiceMail(), P5-08);
# - the message is in INBOX of 1002;
# - mailpit receives "PBX Voicemail Notification" for 1002@example.com with
#   one audio attachment (msg0000.WAV, audio/x-wav);
# - control: no voicemail mail before the call.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-08
sipp_image=izpbx-test-sipp:p5-08
mailpit_image=docker.io/axllent/mailpit:v1.20.0
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
t_run mailpit "$mailpit_image" --network "$net" --network-alias mailpit >/dev/null
t_wait_healthy "$db" 120 || die "MariaDB did not start"
c=$(t_run pbx "$image" --network "$net" --network-alias pbx -v "$(t_volume data):/data" -e APP_DATA=/data \
  -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw \
  -e SMTP_RELAYHOST=mailpit -e SMTP_RELAYHOST_PORT=1025 -e SMTP_STARTTLS=false -e SMTP_MAIL_FROM=pbx@example.com)
assert_cmd "FreePBX installed: healthy" -- t_wait_healthy "$c" 1500
assert_cmd_fails "app_voicemail_odbc is not installed" -- docker exec "$c" test -e /usr/lib64/asterisk/modules/app_voicemail_odbc.so

docker exec -u asterisk "$c" sh -c 'printf "extension,name,tech,secret,direct_media,qualifyfreq,voicemail,voicemail_enable,voicemail_vmpwd,voicemail_email,voicemail_attach\n1001,One,pjsip,Secret1001x,no,0,novm,no,,,\n1002,Two,pjsip,Secret1002x,no,0,default,yes,4321,1002@example.com,attach=yes\n" > /tmp/p5-08.csv
  fwconsole bulkimport --type=extensions --replace /tmp/p5-08.csv && fwconsole reload' >/dev/null 2>&1
assert_cmd "voicemail box 1002 with email and attach" -- docker exec "$c" grep -qx '1002=4321,Two,1002@example.com,,attach=yes' /etc/asterisk/voicemail.conf

mails() { docker exec "$c" curl -s http://mailpit:8025/api/v1/messages; }
vmmail() { mails | jq -r '.messages[] | select(.Subject == "PBX Voicemail Notification") | .ID' | head -1; }
assert_eq "" "$(vmmail)" "control: no voicemail mail before the call"

docker run --rm --entrypoint "" -v "$work:/w" "$image" sox -n -r 8000 -c 1 -t al /w/tone.al synth 3 sine 440
printf 'SEQUENTIAL\n1001\n' > "$work/call.csv"
docker run --rm --network "$net" -v "$TESTS_DIR/sipp/scenarios:/sc:ro" -v "$work:/w" -w /w "$sipp_image" pbx:5060 \
  -sf /sc/voicemail-call.xml -inf /w/call.csv -au 1001 -ap Secret1001x -s 1002 -m 1 -p 5090 -mp 7000 -timeout 60 \
  -trace_msg >/dev/null 2>&1 || true
assert_contains "$(grep -hE '^SIP/2.0 200' "$work"/voicemail-call_*_messages.log 2>/dev/null | head -1)" "200 OK" "the call to 1002 is answered by the voicemail"
assert_cmd "VoiceMail() ran for 1002" -- sh -c "docker exec $c grep -a 'VoiceMail(\"PJSIP/1001-[^\"]*\", \"1002@default' /var/log/asterisk/full >/dev/null"
assert_cmd "the message is in INBOX of 1002" -- t_wait_for 30 -- docker exec "$c" test -s /var/spool/asterisk/voicemail/default/1002/INBOX/msg0000.txt
assert_cmd "mailpit receives the voicemail notification" -- t_wait_for 60 -- sh -c "[ -n \"\$(docker exec $c curl -s http://mailpit:8025/api/v1/messages | jq -r '.messages[] | select(.Subject == \"PBX Voicemail Notification\") | .ID')\" ]"
id=$(vmmail)
msg=$(docker exec "$c" curl -s "http://mailpit:8025/api/v1/message/$id")
assert_eq "1002@example.com" "$(jq -r '.To[0].Address' <<< "$msg")" "the notification is for 1002@example.com"
att=$(jq -r '.Attachments[] | "\(.FileName) \(.ContentType) \(.Size)"' <<< "$msg")
log "attachments: $att"
assert_cmd "one audio attachment (.wav)" -- grep -qiE '^msg0000\.wav audio/[a-z-]*wav [0-9]+$' <<< "$att"
assert_cmd "the attachment is not empty" -- test "$(awk '{print $3}' <<< "$att")" -gt 1000
finish
