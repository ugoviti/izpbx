#!/usr/bin/env bash
# P3-41: the "-custom" contexts that FreePBX includes and nobody defines are
# defined empty in /etc/asterisk/freepbx_custom_fix_missing_contexts.conf,
# included from extensions_custom.conf, as 20.16 (lost in 22.17: every start
# and reload wrote ~130 WARNING "tries to include nonexistent context").
# - new installation: the file lists the contexts (the -custom ones, and
#   ext-meetme, ext-queues, app-recordings, ext-cf-hints when included and
#   undefined), extensions_custom.conf
#   includes it once, a dialplan reload writes no such WARNING;
# - negative: without the #include the same reload writes them (> 50);
# - a context the user defines in extensions_custom.conf leaves the list at
#   the next run, and running twice keeps one #include.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-41
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
fix=/etc/asterisk/freepbx_custom_fix_missing_contexts.conf
custom=/etc/asterisk/extensions_custom.conf
warnings() { # container -> WARNINGs about nonexistent contexts written by a dialplan reload
  docker exec "$1" bash -c 'n=$(wc -l < /var/log/asterisk/full); asterisk -rx "dialplan reload" >/dev/null; sleep 2; tail -n +$((n + 1)) /var/log/asterisk/full | grep -c "nonexistent context"' || true
}
again() { docker exec "$1" bash -c '. /usr/local/lib/izpbx/services/freepbx.sh; freepbx_missing_contexts' >/dev/null 2>&1; }

c=$(pbx one)
assert_cmd "FreePBX installed and healthy" -- t_wait_healthy "$c" 1500
n=$(docker exec "$c" grep -c '^\[.*-custom\]' "$fix")
log "$n empty contexts"
assert_cmd "the file lists the -custom contexts ($n)" -- test "$n" -gt 50
assert_cmd "only -custom contexts and the fixed list" -- sh -c "! docker exec '$c' grep '^\[' '$fix' | grep -v -- '-custom\]$' | grep -vxE '\[(ext-cf-hints|ext-meetme|ext-queues|app-recordings)\]'"
assert_eq 1 "$(docker exec "$c" grep -cxF '#include freepbx_custom_fix_missing_contexts.conf' "$custom")" "extensions_custom.conf includes it once"
assert_eq 0 "$(warnings "$c")" "dialplan reload: no nonexistent context WARNING"
assert_cmd_fails "parkedcalls (created by res_parking) not defined" -- docker exec "$c" grep -q '^\[parkedcalls\]' "$fix"

docker exec "$c" sed -i '/^#include freepbx_custom_fix_missing_contexts.conf$/d' "$custom"
neg=$(warnings "$c")
assert_cmd "negative: without the #include the reload warns ($neg)" -- test "$neg" -gt 50

ctx=$(docker exec "$c" grep -m 1 -o '^\[.*-custom\]' "$fix" | tr -d '[]')
docker exec "$c" bash -c "printf '[%s]\nexten => 9999,1,Answer()\n' '$ctx' >> $custom"
again "$c"; again "$c"
assert_eq 1 "$(docker exec "$c" grep -cxF '#include freepbx_custom_fix_missing_contexts.conf' "$custom")" "two runs: still one #include"
assert_cmd_fails "a context defined by the user ($ctx) leaves the list" -- docker exec "$c" grep -qxF "[$ctx]" "$fix"
assert_eq "$((n - 1))" "$(docker exec "$c" grep -c '^\[.*-custom\]' "$fix")" "one context less"
assert_eq 0 "$(warnings "$c")" "reload after the change: no WARNING"
finish
