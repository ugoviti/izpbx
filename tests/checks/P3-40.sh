#!/usr/bin/env bash
# P3-40: FREEPBX_FIX_PERMISSION=true runs "fwconsole chown" at every start, as
# 20.16 (lost in 22.17: declared and skipped by the settings loop, run by
# nobody). Not after the first installation, which has just done it.
# - new installation: no "fixing the permissions" line (the install chowns);
# - a file of FreePBX made root:root, restart with FREEPBX_FIX_PERMISSION=false:
#   still root (negative), restart with true: asterisk again, logged.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-40
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
f=/var/lib/asterisk/agi-bin/dialparties.agi
owner() { docker exec "$1" stat -L -c %U:%G "$f"; }

c=$(pbx one -e FREEPBX_FIX_PERMISSION=true)
assert_cmd "FreePBX installed and healthy" -- t_wait_healthy "$c" 1500
assert_cmd_fails "new installation: no extra chown" -- sh -c "docker logs '$c' 2>&1 | grep -q 'fixing the permissions'"
assert_eq asterisk:asterisk "$(owner "$c")" "after the install $f is asterisk's"
docker exec "$c" chown root:root "$(docker exec "$c" readlink -f "$f")"
assert_eq root:root "$(owner "$c")" "made root:root"
docker rm -f "$c" >/dev/null

c2=$(pbx two -e FREEPBX_FIX_PERMISSION=false)
assert_cmd "restart with false: healthy" -- t_wait_healthy "$c2" 900
assert_eq root:root "$(owner "$c2")" "negative: FREEPBX_FIX_PERMISSION=false leaves it root"
docker rm -f "$c2" >/dev/null

c3=$(pbx three -e FREEPBX_FIX_PERMISSION=true)
assert_cmd "restart with true: healthy" -- t_wait_healthy "$c3" 900
assert_eq asterisk:asterisk "$(owner "$c3")" "FREEPBX_FIX_PERMISSION=true: fwconsole chown at the start"
assert_cmd "logged" -- sh -c "docker logs '$c3' 2>&1 | grep -q 'fixing the permissions of the FreePBX and Asterisk files'"
finish
