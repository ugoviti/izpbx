#!/usr/bin/env bash
# P3-20: FreePBX Advanced Settings (FREEPBX_*) and SIP Settings (C19, C20).
# - golden: the fwconsole setting / sipsettings calls recorded by
#   izpbx-init --dry-run for tests/fixtures/freepbx-settings/case.env = the
#   calls of the 20.16.22 loops (run from entrypoint-hooks.sh of the tag, with stubs of
#   fwconsole and php) without the chan_sip bindport; no izPBX variable
#   (FREEPBX_MODULES_*, FREEPBX_AUTOUPGRADE_*, ...) and no empty value applied;
# - after a real start with FreePBX the values in freepbx_settings and the SIP
#   Settings match the environment; a new container on the same data with a
#   different FREEPBX_TONEZONE and APP_PORT_RTP_END changes them;
# - controls: the 20.16 calls with bindport differ from ours; before the
#   change the value was not the new one.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-20
fx="$TESTS_DIR/fixtures/freepbx-settings"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
# the 20.16.22 entrypoint, from its tag (no longer in rootfs, P3-22)
hooks="$work/entrypoint-hooks.sh"
git -C "$REPO_DIR" show 20.16.22:izpbx-asterisk/rootfs/entrypoint-hooks.sh > "$hooks" || die "tag 20.16.22 not available"
assert_cmd "image builds" -- t_build_image "$image"

# --- golden: 20.16 loops with stubs
{
  echo '#!/bin/bash'
  sed -n '/^declare -A fpbxSipSettings=(/,/^)/p' "$hooks"
  sed -n '/^: \${FREEPBX_FIX_PERMISSION/,/^: \${FREEPBX_HTTPBINDPORT/p' "$hooks"
  sed -n '/reconfiguring FreePBX Advanced Settings if needed/,/FIXME: 20200315 iaxsettings/p' "$hooks"
} > "$work/old.sh"
assert_cmd "20.16 loops extracted" -- grep -q 'compgen -v FREEPBX_' "$work/old.sh"
docker run --rm --entrypoint "" --env-file "$fx/case.env" -v "$work/old.sh:/old.sh:ro" \
  -v "$fx/fwconsole:/stub/fwconsole:ro" -v "$fx/php:/stub/php:ro" "$image" \
  bash -c 'PATH=/stub:$PATH bash /old.sh >/dev/null 2>&1; cat /tmp/old-calls' | LC_ALL=C sort > "$work/old"
docker run --rm --entrypoint "" --env-file "$fx/case.env" "$image" \
  bash -c 'izpbx-init --dry-run >/dev/null 2>&1; grep -E "^(fwconsole setting|sipsettings) " /run/izpbx/dry-run.log' | LC_ALL=C sort > "$work/new"
grep -v '^sipsettings bindport ' "$work/old" > "$work/old-nobind"
assert_cmd "20.16 records calls" -- test -s "$work/old"
if diff -u "$work/old-nobind" "$work/new" > "$work/diff"; then
  pass "golden: recorded calls = 20.16 without bindport ($(wc -l < "$work/new") calls)"
else
  fail "golden: recorded calls differ from 20.16"; cat "$work/diff" >&2
fi
assert_cmd_fails "no chan_sip bindport" -- grep -q bindport "$work/new"
assert_cmd_fails "izPBX variables are not settings" -- grep -qE ' (MODULES_PRE|AUTOUPGRADE_CORE|FIX_PERMISSION) ' "$work/new"
assert_cmd_fails "empty values are not applied" -- grep -q ' RSSFEEDS' "$work/new"
assert_cmd_fails "control: the 20.16 calls with bindport differ" -- diff -q "$work/old" "$work/new"

# --- real start with FreePBX
net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
vol=$(t_volume data)
# Asterisk also runs during the install: healthy only when the web UI answers
# too (httpd starts after izpbx-init)
health=(--health-cmd "asterisk -rx 'core waitfullybooted' >/dev/null && curl -fsS -o /dev/null http://localhost/admin/config.php"
        --health-interval 10s --health-timeout 10s --health-retries 3 --health-start-period 30m)
pbx() { # name [args]
  local n=$1; shift
  t_run "$n" "$image" --network "$net" -v "$vol:/data" -e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw \
    -e MYSQL_ROOT_PASSWORD=rootpw --env-file "$fx/case.env" "${health[@]}" "$@"
}
setting() { docker exec "$1" mysql -h db -uasterisk -pastpw asterisk -N -B -e "SELECT value FROM freepbx_settings WHERE keyword='$2'" 2>/dev/null; }
sip() { docker exec "$1" bash -c '. /usr/local/lib/izpbx/actions.sh; fpbx_sipsetting_get "$1"' _ "$2"; }

c=$(pbx one)
assert_cmd "FreePBX installed and healthy" -- t_wait_healthy "$c" 1500
assert_eq "izPBX golden" "$(setting "$c" FREEPBX_SYSTEM_IDENT)" "freepbx_settings FREEPBX_SYSTEM_IDENT from the .env"
assert_eq "it" "$(setting "$c" TONEZONE)" "freepbx_settings TONEZONE from the .env"
assert_eq "Europe/Rome" "$(setting "$c" PHPTIMEZONE)" "freepbx_settings PHPTIMEZONE from the .env"
assert_eq "8088" "$(setting "$c" HTTPBINDPORT)" "freepbx_settings HTTPBINDPORT = APP_PORT_AMI"
assert_eq "10000" "$(sip "$c" rtpstart)" "sip setting rtpstart = APP_PORT_RTP_START"
assert_eq "10200" "$(sip "$c" rtpend)" "sip setting rtpend = APP_PORT_RTP_END"
assert_eq "5060" "$(sip "$c" udpport-0.0.0.0)" "sip setting udpport-0.0.0.0 = APP_PORT_PJSIP"
assert_eq "5060" "$(sip "$c" tcpport-0.0.0.0)" "sip setting tcpport-0.0.0.0 = APP_PORT_PJSIP"
assert_ne "de" "$(setting "$c" TONEZONE)" "control: TONEZONE is not yet the new value"
docker rm -f "$c" >/dev/null

c2=$(pbx two -e FREEPBX_TONEZONE=de -e APP_PORT_RTP_END=10300)
assert_cmd "same data, new environment: healthy" -- t_wait_healthy "$c2" 600
assert_cmd_fails "same data: no new installation" -- sh -c "docker logs '$c2' 2>&1 | grep -q 'NEW INSTALLATION'"
assert_eq "de" "$(setting "$c2" TONEZONE)" "a changed FREEPBX_TONEZONE is applied at the next start"
assert_eq "10300" "$(sip "$c2" rtpend)" "a changed APP_PORT_RTP_END is applied at the next start"
finish
