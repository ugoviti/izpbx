#!/usr/bin/env bash
# P5-07: conference, queue, IVR with DTMF, ring group and time conditions,
# one sipp call each from extension 1001 (izpbx-asterisk/tests/fixtures/pbx-setup/
# features.php; ringgroups installed from the local modules, as 20.16 did not
# install it by default). Extension 1002 is a sipp UAS (scenarios/uas.xml).
# - the FreePBX post-start hooks ran (freepbx-start): core-fastagi online
#   (ring groups use dialparties.agi through FastAGI);
# - conference 8000: answered (200), "confbridge list" has 8000 with one
#   user, 1002 not called;
# - queue 7000: 1002 (static member) is called and answers, queue_log has
#   CONNECT for 7000;
# - IVR (misc application 7100): after the digit 2 (SIP INFO, 1001 with
#   dtmfmode info; scenarios/dtmf-call.xml) the IVR sends the call to 1002;
# - ring group 6000: 1002 rings and answers;
# - time conditions with the time forced by their time groups: tc-true
#   (always, 7201) -> 1002; tc-false (another month, 7202) -> the false
#   branch (congestion: 503), 1002 not called.
# sipp exit codes are not used (EPERM on epoll, see P5-01).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-07
sipp_image=izpbx-test-sipp:p5-07
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
  -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw -v "$TESTS_DIR/fixtures/pbx-setup:/setup:ro")
assert_cmd "FreePBX installed: healthy" -- t_wait_healthy "$c" 1500
assert_cmd "post-start hooks: core-fastagi online" -- t_wait_for 120 -- \
  sh -c "docker exec -u asterisk $c fwconsole pm2 --list 2>/dev/null | grep -E 'core-fastagi +\| [0-9]+ +\| online'"

docker exec -u asterisk "$c" sh -c 'fwconsole ma install ringgroups
  printf "extension,name,tech,secret,direct_media,qualifyfreq,dtmfmode\n1001,One,pjsip,Secret1001x,no,0,info\n1002,Two,pjsip,Secret1002x,no,0,rfc4733\n" > /tmp/p5-07.csv
  fwconsole bulkimport --type=extensions --replace /tmp/p5-07.csv' >/dev/null 2>&1
log "$(docker exec -u asterisk "$c" php /setup/features.php 2>&1)"
docker exec -u asterisk "$c" fwconsole reload >/dev/null 2>&1

ns=$(t_run ns "$sipp_image" --network "$net" --entrypoint sleep -- infinity)
nsip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$ns")
printf 'SEQUENTIAL\n1002;%s:5070\n' "$nsip" > "$work/reg.csv"; printf 'SEQUENTIAL\n1001\n' > "$work/call.csv"
sipp() { docker run --rm --network "$1" -v "$sc:/sc:ro" -v "$work:/w" -w /w "$sipp_image" "${@:2}"; }
sipp "container:$ns" pbx:5060 -sf /sc/register.xml -inf /w/reg.csv -au 1002 -ap Secret1002x -m 1 -p 5070 -timeout 15 >/dev/null 2>&1 || true
t_run uas "$sipp_image" --network "container:$ns" -t -v "$sc:/sc:ro" -v "$work:/w" -w /w -- \
  -sf /sc/uas.xml -p 5070 -rtp_echo -mp 6000 -aa -deadcall_wait 1 -trace_msg >/dev/null
assert_cmd "1002 registered" -- sh -c "docker exec $c asterisk -rx 'pjsip show contacts' | grep -q 'Contact:  1002/'"

invites() { cat "$work"/uas_*_messages.log 2>/dev/null | grep -c '^INVITE' || true; }
idle() { docker exec "$c" asterisk -rx 'core show channels count' | grep -q '^0 active channels'; }
# feature NUMBER SCENARIO: one call; sets CODES and CALLED (INVITEs to 1002)
feature() {
  local before; t_wait_for 30 -- idle || log "channels still up before $1"
  before=$(invites)
  find "$work" -name "${2:?}_*_messages.log" -delete
  sipp "$net" pbx:5060 -sf "/sc/$2.xml" -inf /w/call.csv -au 1001 -ap Secret1001x -s "$1" -m 1 -p 5090 -mp 7000 \
    -aa -timeout 40 -trace_msg >/dev/null 2>&1 || true
  CODES=$(cat "$work"/"$2"_*_messages.log 2>/dev/null | grep -E '^SIP/2.0 [0-9]+' | awk '{print $2}' | tr '\n' ' ')
  CALLED=$(( $(invites) - before ))
  log "$1: codes $CODES, 1002 called $CALLED time(s)"
}

( t_wait_for 20 -- sh -c "docker exec $c asterisk -rx 'confbridge list' | grep -qE '^8000 +1 '"
  docker exec "$c" asterisk -rx 'confbridge list' > "$work/conf.txt" ) &
feature 8000 feature-call; wait
assert_contains "$CODES" "200" "conference 8000: answered"
assert_cmd "conference 8000: one user in ConfBridge" -- grep -qE '^8000 +1 ' "$work/conf.txt"
assert_eq 0 "$CALLED" "conference 8000: 1002 not called"

n0=$(docker exec "$c" sh -c 'wc -l < /var/log/asterisk/full')
feature 7100 dtmf-call
assert_contains "$CODES" "200" "IVR 7100: answered"
assert_eq 1 "$CALLED" "IVR 7100: DTMF 2 -> extension 1002"
if [ "$CALLED" -ne 1 ]; then
  docker exec "$c" sh -c "tail -n +$((n0 + 1)) /var/log/asterisk/full" > "$work/ivr.log"
  log "IVR steps:"$'\n'"$(grep -aE 'ivr-[0-9]|DTMF|INFO|Hangup|hangup' "$work/ivr.log" | sed -E 's/^\[[^]]*\] //' | grep -v '^VERBOSE.*Set(' | tail -14)"
  log "dialplan 2@ivr-1 now:"$'\n'"$(docker exec "$c" asterisk -rx 'dialplan show 2@ivr-1' | head -3)"
fi

feature 7000 feature-call
assert_eq 1 "$CALLED" "queue 7000: member 1002 called"
assert_cmd "queue 7000: queue_log has CONNECT" -- docker exec "$c" grep -qE '\|7000\|[^|]*\|CONNECT\|' /var/log/asterisk/queue_log

feature 6000 feature-call
assert_eq 1 "$CALLED" "ring group 6000: 1002 rings"
assert_contains "$CODES" "200" "ring group 6000: answered"

feature 7201 feature-call
assert_eq 1 "$CALLED" "time condition true (always): -> 1002"
feature 7202 feature-call
assert_eq 0 "$CALLED" "time condition false (other month): 1002 not called"
assert_contains "$CODES" "503" "time condition false: the false branch (congestion, 503)"
finish
