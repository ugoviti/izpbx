#!/usr/bin/env bash
# P5-02: trunks in and out, with a simulated provider (sipp).
# Configuration through the FreePBX API (tests/fixtures/pbx-setup/
# trunks-routes.php): trunk prov-reg (registration with username/secret),
# trunk prov-ip (identified by the provider address), outbound route test-out
# (9 + 0XXXXXX -> prov-reg, the 9 removed), IVR test-ivr, inbound route DID
# 5551234 -> test-ivr; extension 1001 by bulkimport.
# - the provider (tests/sipp/scenarios/provider.xml) answers the REGISTER:
#   prov-reg is Registered;
# - outbound: 1001 dials 90612345 -> 401, then 100/180/200 to the caller,
#   the provider receives "INVITE sip:0612345@", 200 OK to the BYE;
# - inbound: the IP provider calls DID 5551234 without auth -> 200 OK, the
#   channel is in the IVR (ivr-<id>), 200 OK to the BYE;
# - expected codes: the same inbound call from an address that is not the
#   provider's -> 401 Unauthorized (no anonymous calls).
# The exit code of sipp is not used (EPERM on epoll after the call, see P5-01).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-02
sipp_image=izpbx-test-sipp:p5-02
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
  -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw \
  -v "$TESTS_DIR/fixtures/pbx-setup:/setup:ro")
assert_cmd "FreePBX installed: healthy" -- t_wait_healthy "$c" 1500

# network namespaces of the two providers (their addresses go in the trunks)
regns=$(t_run regprov "$sipp_image" --network "$net" --entrypoint sleep -- infinity)
ipns=$(t_run ipprov "$sipp_image" --network "$net" --entrypoint sleep -- infinity)
ip() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"; }
regip=$(ip "$regns"); ipip=$(ip "$ipns")
out=$(docker exec -u asterisk "$c" php /setup/trunks-routes.php "$regip" "$ipip" 2>&1)
log "$out"
docker exec -u asterisk "$c" sh -c 'printf "extension,name,tech,secret,direct_media,qualifyfreq\n1001,Test One,pjsip,Secret1001x,no,0\n" > /tmp/p5-02.csv
  fwconsole bulkimport --type=extensions --replace /tmp/p5-02.csv && fwconsole reload' >/dev/null 2>&1
assert_eq 3 "$(docker exec "$c" asterisk -rx 'pjsip show endpoints' | grep -cE '^ Endpoint: +(prov-reg|prov-ip|1001/)')" "trunks prov-reg, prov-ip and extension 1001 configured"

# the provider: REGISTER, OPTIONS and INVITE on one port (-deadcall_wait 1:
# the REGISTER refresh reuses the Call-ID of the ended registration dialog)
t_run provider "$sipp_image" --network "container:$regns" -t -v "$sc:/sc:ro" -v "$work:/w" -w /w -- \
  -sf /sc/provider.xml -p 5060 -rtp_echo -mp 6000 -deadcall_wait 1 -trace_msg >/dev/null
sleep 1
docker exec "$c" asterisk -rx 'pjsip send register prov-reg' >/dev/null
assert_cmd "prov-reg registered with the provider" -- \
  t_wait_for 30 -- sh -c "docker exec $c asterisk -rx 'pjsip show registrations' | grep -E '^ prov-reg/.* Registered'"

sipp() { docker run --rm --network "$1" -v "$sc:/sc:ro" -v "$work:/w" -w /w "$sipp_image" "${@:2}"; }
codes() { grep -hE '^SIP/2.0 [0-9]+' "$work"/$1_*_messages.log 2>/dev/null | awk '{print $2}' | tr '\n' ' ' | sed 's/ $//'; }

# --- outbound
printf 'SEQUENTIAL\n1001\n' > "$work/call.csv"
sipp "$net" pbx:5060 -sf /sc/call.xml -inf /w/call.csv -au 1001 -ap Secret1001x -s 90612345 -m 1 -p 5090 -mp 7000 \
  -timeout 40 -trace_msg >/dev/null 2>&1 || true
assert_eq "401 100 180 200 200" "$(codes call)" "outbound: codes to the caller (auth, trying, ringing, answer, BYE)"
assert_cmd "outbound: the provider receives the number without the 9" -- grep -q '^INVITE sip:0612345@' "$work"/provider_*_messages.log

# --- inbound
( t_wait_for 15 -- sh -c "docker exec $c asterisk -rx 'core show channels concise' | grep -q '^PJSIP/prov-ip-.*!ivr-[0-9]*!'"
  docker exec "$c" asterisk -rx 'core show channels concise' > "$work/channels.txt" ) &
sipp "container:$ipns" pbx:5060 -sf /sc/inbound.xml -s 5551234 -m 1 -p 5060 -mp 7000 -timeout 30 -trace_msg >/dev/null 2>&1 || true
wait
assert_eq "100 200 200" "$(codes inbound)" "inbound: codes to the provider (trying, answer, BYE)"
assert_cmd "inbound: DID 5551234 reaches the IVR" -- grep -qE '^PJSIP/prov-ip-[^!]*!ivr-[0-9]+!' "$work/channels.txt"

# --- expected codes: not the provider's address
rm -f "$work"/inbound_*_messages.log
sipp "$net" pbx:5060 -sf /sc/inbound.xml -s 5551234 -m 1 -p 5060 -mp 7000 -timeout 10 -trace_msg >/dev/null 2>&1 || true
assert_contains "$(codes inbound)" "401" "control: the same call from another address is refused (401)"
assert_cmd_fails "control: and gets no answer" -- sh -c "grep -qE '^SIP/2.0 200' $work/inbound_*_messages.log"
finish
