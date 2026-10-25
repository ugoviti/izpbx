#!/usr/bin/env bash
# P5-10 (T13): Zabbix end to end, zabbix_get against the agent of the
# container (zabbix_get 7.0.32 from the official zabbix/zabbix-agent2 image,
# the agent version of the image). Asterisk without FreePBX with one PJSIP
# endpoint (tests/fixtures/g729/pjsip.conf: anonymous).
# - check.asterisk[*]: version (Asterisk 22.11.0), systemuptime (a number),
#   calls.active (0), service.status (Up), pjsip.endpoints.offline (a number);
# - discovery.asterisk[discovery.pjsip.endpoints]: JSON with {#ENDPOINT}
#   "anonymous";
# - negative check: an agent whose ZABBIX_SERVER is another address refuses
#   the request.
# ZABBIX_SERVER is a CIDR here: ServerActive (default ZABBIX_SERVER, as 20.16)
# accepts no CIDR, so ZABBIX_SERVER_ACTIVE is given.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-10
zget_image=docker.io/zabbix/zabbix-agent2:alpine-7.0.32
assert_cmd "image builds" -- t_build_image "$image"
assert_eq "zabbix_agent2 (Zabbix) 7.0.32" "$(docker run --rm --entrypoint "" "$image" zabbix_agent2 -V | head -1)" "the agent is 7.0.32 (same as zabbix_get)"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
pbx() { # name server
  t_run "$1" "$image" --network "$net" --network-alias "$1" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true \
    -e HTTPD_ENABLED=false -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false -e ZABBIX_ENABLED=true \
    -e "ZABBIX_SERVER=$2" -e ZABBIX_SERVER_ACTIVE=127.0.0.1 \
    -v "$TESTS_DIR/fixtures/g729/pjsip.conf:/etc/asterisk/pjsip.conf:ro"
}
zget() { docker run --rm --network "$net" --entrypoint zabbix_get "$zget_image" -s "$1" -k "$2" 2>&1; }
c=$(pbx pbx 0.0.0.0/0)
n=$(pbx other 10.255.255.1)
assert_cmd "Asterisk starts" -- t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted'
assert_cmd "the agent answers" -- t_wait_for 60 -- sh -c "docker run --rm --network $net --entrypoint zabbix_get $zget_image -s pbx -k agent.ping | grep -qx 1"

assert_contains "$(zget pbx 'check.asterisk[version]')" "Asterisk 22.11.0" "check.asterisk[version]"
assert_cmd "check.asterisk[systemuptime] is a number" -- grep -qE '^[0-9]+$' <<< "$(zget pbx 'check.asterisk[systemuptime]')"
assert_eq 0 "$(zget pbx 'check.asterisk[calls.active]')" "check.asterisk[calls.active]"
assert_eq "Up" "$(zget pbx 'check.asterisk[service.status]')" "check.asterisk[service.status]"
assert_cmd "check.asterisk[pjsip.endpoints.offline] is a number" -- grep -qE '^[0-9]+$' <<< "$(zget pbx 'check.asterisk[pjsip.endpoints.offline]')"
disc=$(zget pbx 'discovery.asterisk[discovery.pjsip.endpoints]')
log "discovery: $(tr -d '\n ' <<< "$disc")"
assert_eq "anonymous" "$(jq -r '.data[]."{#ENDPOINT}"' <<< "$disc" 2>/dev/null)" "discovery.pjsip.endpoints lists anonymous"

assert_cmd "control: the other agent runs" -- t_wait_for 60 -- docker exec "$n" pgrep -x zabbix_agent2
assert_cmd_fails "control: an agent for another server refuses zabbix_get" -- \
  sh -c "docker run --rm --network $net --entrypoint zabbix_get $zget_image -s other -k agent.ping | grep -qx 1"
finish
