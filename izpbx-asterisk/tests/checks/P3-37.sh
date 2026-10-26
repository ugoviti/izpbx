#!/usr/bin/env bash
# P3-37: the FreePBX dashboard of a new installation is clean (user report of
# a clean deploy: Mail Queue "Unknown output from mailq", UCP Daemon "UCP Node
# is not running", notices "Sangoma Debian Repository GPG Key Expiring Soon"
# and "Updated Asterisk Mini HTTP Server Bind Address to Localhost").
# - the dashboard checks of FreePBX itself (Overview::checkmailq,
#   Ucp::dashboardService) say ok (mail queue: P3-35);
# - izPBX removes framework GPG_KEY_EXPIRY (izPBX installs nothing from the
#   Sangoma Debian repository; raised by FreePBX only when the key download
#   fails, so the test raises it before a restart) at every start, and core
#   core_bindaddress_changed (raised during the install, freepbx.log) on the
#   new installation; the other notices stay (control);
# - the HTTP bind address stays the FreePBX 17 one, 127.0.0.1; on a restart
#   FREEPBX_HTTPBINDADDRESS=0.0.0.0 (default.env) opens it: the changed
#   setting is applied with a fwconsole reload once Asterisk is up (20.16 left
#   it to the next Apply Config), Asterisk listens on 0.0.0.0:8088 (negative:
#   before, 127.0.0.1).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-37
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
pbx() { # name [args]
  local n=$1; shift
  t_run "$n" "$image" --network "$net" -v "$vol:/data" -e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw \
    -e MYSQL_ROOT_PASSWORD=rootpw "${health[@]}" "$@"
}
setting() { docker exec "$1" mysql -h db -uasterisk -pastpw asterisk -N -B -e "SELECT value FROM freepbx_settings WHERE keyword='$2'" 2>/dev/null; }
notices() { docker exec "$1" fwconsole notifications --list 2>/dev/null | awk -F'|' 'NF > 3 {gsub(/ /, "", $2); gsub(/ /, "", $3); print $2 ":" $3}'; }
dashboard() { # container check -> type of the dashboard status (ok, critical...)
  docker exec -u asterisk "$1" php -r 'include "/etc/freepbx.conf";
    include_once "/var/www/html/admin/modules/dashboard/sections/Overview.class.php";
    if ($argv[1] == "mailq") { $o = new \FreePBX\modules\Dashboard\Sections\Overview(); $m = new ReflectionMethod($o, "checkmailq"); $m->setAccessible(true); $r = $m->invoke($o); }
    else { $r = \FreePBX::Ucp()->dashboardService()[0]; }
    echo $r["type"], " ", $r["tooltip"], "\n";' "$2" 2>/dev/null | tail -n 1
}

c=$(pbx one)
assert_cmd "FreePBX installed and healthy" -- t_wait_healthy "$c" 1500
mq=$(dashboard "$c" mailq)
assert_contains "$mq" "ok No outbound mail in queue" "dashboard Mail Queue ok ($mq)"
for _ in $(seq 1 24); do # pm2 starts ucp after the healthcheck may already pass
  ucp=$(dashboard "$c" ucp); [[ "$ucp" == ok* ]] && break; sleep 5
done
assert_contains "$ucp" "ok Running" "dashboard UCP Daemon ok ($ucp)"
log=$(docker exec "$c" cat /var/log/asterisk/freepbx.log)
assert_contains "$log" "core_bindaddress_changed" "control: FreePBX raised the bind address notice during the install"
n=$(notices "$c"); log "notices: $(tr '\n' ' ' <<< "$n")"
assert_cmd_fails "GPG key notice removed" -- grep -q '^framework:GPG_KEY_EXPIRY$' <<< "$n"
assert_cmd_fails "bind address notice removed on the new installation" -- grep -q '^core:core_bindaddress_changed$' <<< "$n"
assert_cmd "control: the other notices stay" -- grep -q '^core:EXTENSIONS_MOVE$' <<< "$n"
assert_eq 127.0.0.1 "$(setting "$c" HTTPBINDADDRESS)" "HTTPBINDADDRESS stays 127.0.0.1"
assert_cmd "negative: Asterisk HTTP on 127.0.0.1:8088 only" -- sh -c "docker exec '$c' asterisk -rx 'http show status' | grep -q 'Bound to 127.0.0.1:8088'"
# the GPG notice depends on the network (FreePBX raises it when it cannot
# download the key): raised here as FreePBX does, then a restart removes it
docker exec -u asterisk "$c" php -r 'include "/etc/freepbx.conf"; \FreePBX::Notifications()->add_error("framework", "GPG_KEY_EXPIRY", "Sangoma Debian Repository GPG Key Expiring Soon", "test", false, false, true);' >/dev/null 2>&1
assert_cmd "control: the GPG key notice is there before the restart" -- sh -c "docker exec '$c' fwconsole notifications --list 2>/dev/null | grep -q GPG_KEY_EXPIRY"
docker rm -f "$c" >/dev/null

c2=$(pbx two -e FREEPBX_HTTPBINDADDRESS=0.0.0.0)
assert_cmd "restart with FREEPBX_HTTPBINDADDRESS: healthy" -- t_wait_healthy "$c2" 900
assert_eq 0.0.0.0 "$(setting "$c2" HTTPBINDADDRESS)" "FREEPBX_HTTPBINDADDRESS applied"
assert_cmd "the changed setting is applied with fwconsole reload" -- t_wait_for 120 -- sh -c "docker logs '$c2' 2>&1 | grep -q 'FreePBX settings changed at start, applied'"
assert_cmd "Asterisk HTTP on 0.0.0.0:8088" -- t_wait_for 60 -- sh -c "docker exec '$c2' asterisk -rx 'http show status' | grep -q 'Bound to 0.0.0.0:8088'"
assert_cmd_fails "restart: GPG key notice removed" -- sh -c "docker exec '$c2' fwconsole notifications --list 2>/dev/null | grep -q GPG_KEY_EXPIRY"
assert_contains "$(dashboard "$c2" mailq)" "ok " "restart: Mail Queue ok"
finish
