#!/usr/bin/env bash
# P3-11: chronyd configured by izpbx-init (services/ntp.sh).
# - golden: /etc/chrony/chrony.conf of the ntp case equals the 20.16.22
#   /etc/chrony.conf apart from the keyfile path (Debian
#   /etc/chrony/chrony.keys, design C10);
# - chronyd -p parses the file; bindcmdaddress 127.0.0.1 (chronyc commands
#   only from localhost); without NTP_SERVERS the default pool is used;
# - the ntp service runs chronyd with the file (s6, pid); /run/chrony owned by
#   _chrony 0750, so chronyd keeps the command socket (no "Wrong permissions");
# - negative checks: a different NTP_ALLOW_FROM changes the file; an invalid
#   directive makes chronyd -p fail.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-11
golden="$TESTS_DIR/golden"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

gen() { # outfile [docker args]
  local out=$1; shift
  docker run --rm --entrypoint "" --hostname izpbx-golden "$@" "$image" \
    bash -c 'izpbx-init --dry-run >/tmp/init.log 2>&1 || cat /tmp/init.log >&2
             chronyd -p -f /etc/chrony/chrony.conf >/dev/null 2>&1 && echo "chronyd parse ok" >&2
             cat /etc/chrony/chrony.conf' >"$out" 2>"$out.err"
}
logs_grep() { docker logs "$1" 2>&1 | grep -q "$2"; } # container pattern
gen "$work/ntp" --env-file "$golden/cases/ntp.env"
sed 's|^keyfile /etc/chrony.keys$|keyfile /etc/chrony/chrony.keys|' "$golden/20.16.22/ntp/files/etc/chrony.conf" > "$work/ntp.old"
if diff -u "$work/ntp.old" "$work/ntp" > "$work/ntp.diff"; then
  pass "ntp: chrony.conf same as 20.16.22 (apart from the keyfile path)"
else
  fail "ntp: chrony.conf differs"; cat "$work/ntp.diff" >&2
fi
assert_contains "$(cat "$work/ntp.err")" "chronyd parse ok" "chronyd -p parses the file"
assert_cmd "bindcmdaddress 127.0.0.1" -- grep -qx 'bindcmdaddress 127.0.0.1' "$work/ntp"
gen "$work/default" -e NTP_ENABLED=true
assert_cmd "default pool without NTP_SERVERS" -- grep -qx 'pool 2.pool.ntp.org iburst' "$work/default"
assert_contains "$(cat "$work/default.err")" "chronyd parse ok" "chronyd -p parses the default file"

c=$(t_run run "$image" -e NTP_ENABLED=true -e NTP_ALLOW_FROM=10.0.0.0/8 -e HTTPD_ENABLED=false -e ASTERISK_ENABLED=false \
  -e IZPBX_ENABLED=false -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false)
assert_cmd "ntp service runs chronyd" -- t_wait_for 60 -- docker exec "$c" pgrep -x chronyd
assert_cmd "chronyc answers on localhost" -- t_wait_for 30 -- docker exec "$c" chronyc -h 127.0.0.1 tracking
assert_eq "_chrony:_chrony 750" "$(docker exec "$c" stat -c '%U:%G %a' /run/chrony)" "/run/chrony owned by _chrony, 0750"
assert_cmd "chronyd command socket in place" -- t_wait_for 30 -- docker exec "$c" test -S /run/chrony/chronyd.sock
assert_cmd "chronyc answers on the command socket" -- docker exec "$c" chronyc -h /run/chrony/chronyd.sock tracking
assert_cmd_fails "no wrong permissions on /run/chrony" -- logs_grep "$c" "Wrong permissions on /run/chrony"

gen "$work/neg" --env-file "$golden/cases/ntp.env" -e NTP_ALLOW_FROM=172.16.0.0/12
assert_cmd_fails "control: a different NTP_ALLOW_FROM is caught" -- diff -q "$work/ntp.old" "$work/neg"
gen "$work/bad" -e NTP_ENABLED=true -e "NTP_ALLOW_FROM=not/a/subnet"
assert_cmd_fails "control: an invalid allow makes chronyd -p fail" -- grep -q "chronyd parse ok" "$work/bad.err"
finish
