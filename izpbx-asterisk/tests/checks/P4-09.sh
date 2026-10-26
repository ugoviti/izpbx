#!/usr/bin/env bash
# P4-09: chan_sip -> PJSIP (D3, M5.5) and the PJSIP transport on
# APP_PORT_SIP (M6, C19). The 20.16.22 fixture migrated in a real start
# (IZPBX_MIGRATE_FREEPBX=true); its trunk prov-sip-ip was chan_sip with IP
# authentication (provider 192.0.2.10 sending to port 5160).
# - no tech='sip' left in devices and trunks;
# - transport izpbx-legacy-sip-udp bound to 0.0.0.0:5160, used by prov-sip-ip;
# - a sipp provider at 192.0.2.10 calls DID 0612345678 on port 5160: the
#   call is answered on 5160 (100, 200, 200 to the BYE) and the channel of
#   prov-sip-ip runs the inbound route destination, time condition 1 (Asterisk
#   full log: the time condition then goes on by the hour of the day);
# - control: the same call from another address is refused (401);
# - a new installation has no transport on 5160 (Q8).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-09
sipp_image=izpbx-test-sipp:p4-09
fx="$TESTS_DIR/fixtures/out/20.16.22"
sc="$TESTS_DIR/sipp/scenarios"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
t_on_cleanup "docker image rm $sipp_image >/dev/null 2>&1"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "sipp image builds" -- docker build -q -t "$sipp_image" "$TESTS_DIR/sipp"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
chmod 777 "$work"

# the provider address of the fixture trunk is 192.0.2.10: a network with that subnet
net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" --subnet 192.0.2.0/24 "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
mariadb_up() { # name -> a MariaDB on the network (alias = name)
  local d
  d=$(t_run "$1" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$1" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || die "MariaDB did not start"
  printf '%s\n' "$d"
}

# --- a new installation, started first (Q8)
mariadb_up dbnew >/dev/null
cnew=$(t_run new "$image" --network "$net" -v "$(t_volume datanew):/data" -e APP_DATA=/data \
  -e MYSQL_SERVER=dbnew -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw)

# --- the fixture migrated
db=$(mariadb_up db)
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
  docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot
v=$(t_volume data)
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
c=$(t_run pbx "$image" --network "$net" --network-alias pbx -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 2400
docker logs "$c" 2>&1 | grep -E 'migration: (PJSIP|trunks|no chan_sip)' | sed 's/^/    | /' >&2
sql() { echo "$1" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot -N asterisk; }
assert_eq 0 "$(sql "SELECT COUNT(*) FROM devices WHERE tech = 'sip'")" "no chan_sip extension left"
assert_eq 0 "$(sql "SELECT COUNT(*) FROM trunks WHERE tech = 'sip'")" "no chan_sip trunk left"
transports=$(docker exec "$c" asterisk -rx 'pjsip show transports')
assert_cmd "transport izpbx-legacy-sip-udp on 0.0.0.0:5160" -- grep -qE 'Transport: +izpbx-legacy-sip-udp +udp +[0-9]+ +[0-9]+ +0\.0\.0\.0:5160' <<< "$transports"
assert_contains "$(docker exec "$c" asterisk -rx 'pjsip show endpoint prov-sip-ip')" "izpbx-legacy-sip-udp" \
  "prov-sip-ip uses the transport on 5160"

# --- the provider calls on 5160
prov=$(t_run prov "$sipp_image" --network "$net" --ip 192.0.2.10 --entrypoint sleep -- infinity)
sipp() { docker run --rm --network "$1" -v "$sc:/sc:ro" -v "$work:/w" -w /w "$sipp_image" "${@:2}"; }
codes() { grep -hE '^SIP/2.0 [0-9]+' "$work"/$1_*_messages.log 2>/dev/null | awk '{print $2}' | tr '\n' ' ' | sed 's/ $//'; }
sipp "container:$prov" pbx:5160 -sf /sc/inbound.xml -s 0612345678 -m 1 -p 5060 -mp 7000 -timeout 30 -trace_msg >/dev/null 2>&1 || true
log "provider codes: $(codes inbound)"
assert_eq "100 200 200" "$(codes inbound)" "inbound on 5160: answered (trying, answer, BYE)"
# grep >/dev/null, not -q: the full log is long (SIGPIPE)
assert_cmd "inbound on 5160: the prov-sip-ip channel takes DID 0612345678 into time condition 1" -- \
  sh -c "docker exec '$c' grep -E 'Executing \\[[^]]*@timeconditions:[0-9]+\\] [A-Za-z]+\\(\"PJSIP/prov-sip-ip-' /var/log/asterisk/full >/dev/null"

# --- control: another address
rm -f "$work"/inbound_*_messages.log
sipp "$net" pbx:5160 -sf /sc/inbound.xml -s 0612345678 -m 1 -p 5060 -mp 7000 -timeout 10 -trace_msg >/dev/null 2>&1 || true
assert_contains "$(codes inbound)" "401" "control: the same call from another address is refused (401)"

# --- Q8: no transport on 5160 on a new installation
assert_cmd "new installation: healthy" -- t_wait_healthy "$cnew" 1500
assert_cmd_fails "new installation: no transport on port 5160" -- \
  sh -c "docker exec '$cnew' asterisk -rx 'pjsip show transports' | grep -q ':5160'"
assert_cmd "control: the new installation has its 5060 transport" -- \
  sh -c "docker exec '$cnew' asterisk -rx 'pjsip show transports' | grep -q '0.0.0.0:5060'"
finish
