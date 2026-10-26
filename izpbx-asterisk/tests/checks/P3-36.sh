#!/usr/bin/env bash
# P3-36: ports of the UCP node server. APP_PORT_UCP_HTTP / APP_PORT_UCP_HTTPS
# were only published (also in 20.16): FreePBX kept 8001/8003 whatever the
# .env said, so a deploy with network_mode host and 8001 taken by a program
# of the host had UCP "errored" (pm2: 15 restarts, EADDRINUSE) and the
# dashboard said "UCP node is not running", with no way out from the .env.
# Now they are the defaults of FREEPBX_NODEJSBINDPORT / FREEPBX_NODEJSHTTPSBINDPORT
# (applied as every FREEPBX_* setting), and freepbx-start says in the log when
# the port is taken.
# - APP_PORT_UCP_HTTP=8011, APP_PORT_UCP_HTTPS=8013: NODEJSBINDPORT 8011,
#   NODEJSHTTPSBINDPORT 8013, pm2 ucp online, listening on 8011 and not 8001;
# - same data, 8011 taken in the network namespace of the container: pm2 gives
#   up (errored) and the log names the port and APP_PORT_UCP_HTTP, ucp not online
#   (negative: it is the failure of the user's deploy);
# - no warning when the port is free (on the new installation UCP already
#   runs from the install when freepbx-start checks: no false alarm).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-36
assert_cmd "image builds" -- t_build_image "$image"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
vol=$(t_volume data)
health=(--health-cmd "asterisk -rx 'core waitfullybooted' >/dev/null && curl -fsS -o /dev/null http://localhost/admin/config.php"
        --health-interval 10s --health-timeout 10s --health-retries 3 --health-start-period 30m)
pbx() { # name network-option [args]
  local n=$1 netopt=$2; shift 2
  t_run "$n" "$image" "$netopt" -v "$vol:/data" -e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw \
    -e MYSQL_ROOT_PASSWORD=rootpw -e APP_PORT_UCP_HTTP=8011 -e APP_PORT_UCP_HTTPS=8013 "${health[@]}" "$@"
}
setting() { docker exec "$1" mysql -h db -uasterisk -pastpw asterisk -N -B -e "SELECT value FROM freepbx_settings WHERE keyword='$2'" 2>/dev/null; }
ucp_status() { docker exec "$1" su -s /bin/bash asterisk -c 'fwconsole pm2 --list' 2>/dev/null | awk -F'|' '$2 ~ /^ ucp / {gsub(/ /, "", $4); print $4}'; }

c=$(pbx one --network="$net")
assert_cmd "FreePBX installed and healthy" -- t_wait_healthy "$c" 1500
assert_eq 8011 "$(setting "$c" NODEJSBINDPORT)" "NODEJSBINDPORT = APP_PORT_UCP_HTTP"
assert_eq 8013 "$(setting "$c" NODEJSHTTPSBINDPORT)" "NODEJSHTTPSBINDPORT = APP_PORT_UCP_HTTPS"
assert_cmd "ucp online" -- t_wait_for 120 -- sh -c "[ \"\$(docker exec '$c' su -s /bin/bash asterisk -c 'fwconsole pm2 --list' 2>/dev/null | awk -F'|' '\$2 ~ /^ ucp / {gsub(/ /, \"\", \$4); print \$4}')\" = online ]"
assert_cmd "UCP listens on 8011" -- t_wait_for 60 -- sh -c "docker exec '$c' ss -ltnH 'sport = :8011' | grep -q LISTEN"
assert_cmd_fails "nothing on the default 8001" -- sh -c "docker exec '$c' ss -ltnH 'sport = :8001' | grep -q LISTEN"
assert_cmd_fails "port free: no warning" -- sh -c "docker logs '$c' 2>&1 | grep -q 'UCP node server does not start'"
docker rm -f "$c" >/dev/null

# 8011 taken: a program listening in the network namespace the PBX joins
holder=$(t_run holder "$image" --network "$net" --entrypoint "" -- \
  perl -MIO::Socket::INET -e '$s = IO::Socket::INET->new(LocalAddr => "0.0.0.0", LocalPort => 8011, Listen => 5, ReuseAddr => 1) or die; sleep 3600')
t_wait_for 30 -- docker exec "$holder" perl -MIO::Socket::INET -e 'IO::Socket::INET->new(PeerAddr => "127.0.0.1:8011") or exit 1' || die "the holder does not listen"
c2=$(pbx two --network="container:$holder")
assert_cmd "same data, port taken: healthy (Asterisk and web UI)" -- t_wait_healthy "$c2" 900
assert_cmd "warning with the port and the variable" -- t_wait_for 120 -- sh -c \
  "docker logs '$c2' 2>&1 | grep -q 'UCP node server does not start (pm2: errored):.*port 8011 (APP_PORT_UCP_HTTP) is already in use by another program.*set APP_PORT_UCP_HTTP to a free port'"
sleep 20
assert_ne online "$(ucp_status "$c2")" "negative: with 8011 taken ucp is not online ($(ucp_status "$c2"))"
finish
