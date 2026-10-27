#!/usr/bin/env bash
# P3-19 (T2): FreePBX 17 new install from an empty /data (services/freepbx.sh).
# - with a MariaDB and MYSQL_ROOT_PASSWORD the container installs FreePBX and
#   becomes healthy (Asterisk fully booted, HTTP 200 on /admin/config.php);
# - "fwconsole ma list" (module and status) = izpbx-asterisk/tests/expected/freepbx-modules.txt
#   (the 20.16 default modules, without phonebook, D28);
# - repos extended and unsupported enabled; "fwconsole reload" exit 0;
#   /admin/config.php and /ucp/ answer HTTP 200; ${APP_DATA}/.initialized
#   holds the FreePBX version; a restart does not install again;
# - FREEPBX_MODULES_DISABLED=weakpasswords: that module is disabled, so the
#   list differs from the expected one (control);
# - negative check: a wrong MYSQL_ROOT_PASSWORD fails the install and the
#   container stops.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-19
expected="$TESTS_DIR/expected/freepbx-modules.txt"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db() { # name alias
  t_run "$1" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$2" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60
}
health=(--health-cmd "asterisk -rx 'core waitfullybooted' >/dev/null && curl -fsS -o /dev/null http://localhost/admin/config.php"
        --health-interval 10s --health-timeout 10s --health-retries 3 --health-start-period 30m)
pbx() { # name db-alias [args]
  local name=$1 alias=$2 vol; shift 2
  vol=$(t_volume "$name-data")
  t_run "$name" "$image" --network "$net" -v "$vol:/data" -e APP_DATA=/data -e MYSQL_SERVER="$alias" \
    -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw "${health[@]}" "$@"
}
modules() { # container: "module status" lines, sorted
  docker exec -u asterisk "$1" fwconsole ma list 2>/dev/null |
    awk -F'|' 'NF > 4 && $2 !~ /Module/ {gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $4); print $2, $4}' | LC_ALL=C sort || true
}

d1=$(db db1 db1); d2=$(db db2 db2)
t_wait_healthy "$d1" 120 || die "MariaDB did not start"
t_wait_healthy "$d2" 120 || die "MariaDB did not start"
c=$(pbx pbx db1)
v=$(pbx pbxdis db2 -e FREEPBX_MODULES_DISABLED=weakpasswords)
bad=$(pbx bad db1 -e MYSQL_ROOT_PASSWORD=wrong -e MYSQL_DATABASE=other -e IZPBX_FREEPBX_INSTALL_TRIES=1 -e IZPBX_FREEPBX_DB_WAIT=10)

assert_cmd "new install: the container becomes healthy" -- t_wait_healthy "$c" 1500
docker logs "$c" > "$work/pbx.log" 2>&1
[ "$(docker inspect -f '{{.State.Running}}' "$c")" == true ] ||
  { grep -E "$T_LOG_ISSUE_RE" "$work/pbx.log" | tail -n 20 >&2; die "the container stopped"; }
assert_contains "$(cat "$work/pbx.log")" "freepbx: NEW INSTALLATION" "the init detects the new installation"
modules "$c" > "$work/modules.txt"
if diff -u "$expected" "$work/modules.txt" > "$work/modules.diff"; then
  pass "fwconsole ma list = izpbx-asterisk/tests/expected/freepbx-modules.txt"
else
  fail "fwconsole ma list differs from izpbx-asterisk/tests/expected/freepbx-modules.txt"; cat "$work/modules.diff" >&2
fi
assert_cmd_fails "phonebook not installed (no FreePBX 17 release)" -- grep -q '^phonebook Enabled' "$work/modules.txt"
assert_contains "$(docker exec -u asterisk "$c" fwconsole ma list 2>&1 | awk "NR <= 3")" "standard,extended,unsupported" \
  "repos extended and unsupported enabled"
assert_cmd "fwconsole reload exit 0" -- docker exec -u asterisk "$c" fwconsole reload
for u in /admin/config.php /ucp/; do
  assert_eq 200 "$(docker exec "$c" curl -s -o /dev/null -w '%{http_code}' "http://localhost$u")" "HTTP 200 on $u"
done
ver=$(docker exec "$c" cat /data/.initialized)
assert_contains "$ver" "17.0" "/data/.initialized holds the FreePBX version ($ver)"

since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
docker restart "$c" >/dev/null
assert_cmd "after a restart: healthy" -- t_wait_healthy "$c" 300
assert_cmd_fails "after a restart: no new installation" -- sh -c "docker logs --since '$since' '$c' 2>&1 | grep -q 'NEW INSTALLATION'"
assert_contains "$(docker logs --since "$since" "$c" 2>&1)" "freepbx: installed" "after a restart: FreePBX found installed"

assert_cmd "FREEPBX_MODULES_DISABLED: the container becomes healthy" -- t_wait_healthy "$v" 1500
modules "$v" > "$work/modules-dis.txt"
assert_cmd "FREEPBX_MODULES_DISABLED=weakpasswords: the module is disabled" -- grep -qx 'weakpasswords Disabled' "$work/modules-dis.txt"
assert_cmd_fails "control: the module list then differs from the expected one" -- diff -q "$expected" "$work/modules-dis.txt"

assert_cmd "control: a wrong MYSQL_ROOT_PASSWORD stops the container" -- \
  t_wait_for 300 -- sh -c "[ \"\$(docker inspect -f '{{.State.Running}}' $bad)\" != true ]"
assert_contains "$(docker logs "$bad" 2>&1)" "freepbx: install failed" "control: the failed install is reported"
finish
