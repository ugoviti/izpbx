#!/usr/bin/env bash
# P3-12: Zabbix agent 2 configured by izpbx-init (services/zabbix.sh).
# - golden: zabbix_agent2.d/local.conf of the zabbix case equals 20.16.22,
#   the settings of zabbix_agent2.conf too (Server, Hostname, LogFile...
#   commented); 640 root:zabbix; zabbix_agent2 -T accepts the configuration;
#   with ZABBIX_HOSTNAME = hostname, HostnameItem=system.hostname;
# - sudoers (/etc/sudoers.d/zabbix, 0440): as zabbix,
#   "sudo -u asterisk asterisk -rx 'core show uptime'" works, "sudo asterisk"
#   (as root) is refused;
# - negative check: a different ZABBIX_SERVER changes the file.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-12
golden="$TESTS_DIR/golden"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"
settings() { grep -Ev '^[[:space:]]*(#|$)' "$1"; }

gen() { # outdir [docker args]
  local out=$1; shift
  mkdir -p "$out"
  docker run --rm --entrypoint "" --hostname izpbx-golden "$@" "$image" \
    bash -c 'izpbx-init --dry-run >/tmp/init.log 2>&1 || cat /tmp/init.log >&2
             zabbix_agent2 -T -c /etc/zabbix/zabbix_agent2.conf >/dev/null 2>&1 && echo "agent test ok" >&2
             stat -c "%a %U:%G %n" /etc/zabbix/zabbix_agent2.conf /etc/sudoers.d/zabbix >&2
             tar -chf - /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.d/local.conf 2>/dev/null' 2>"$out.err" | tar -C "$out" -xf -
}
gen "$work/zabbix" --env-file "$golden/cases/zabbix.env"
old="$golden/20.16.22/zabbix/files/etc/zabbix"
if diff -u "$old/zabbix_agent2.d/local.conf" "$work/zabbix/etc/zabbix/zabbix_agent2.d/local.conf" > "$work/local.diff"; then
  pass "local.conf same as 20.16.22"
else
  fail "local.conf differs"; cat "$work/local.diff" >&2
fi
if diff -u <(settings "$old/zabbix_agent2.conf") <(settings "$work/zabbix/etc/zabbix/zabbix_agent2.conf") > "$work/main.diff"; then
  pass "zabbix_agent2.conf settings same as 20.16.22"
else
  fail "zabbix_agent2.conf settings differ"; cat "$work/main.diff" >&2
fi
err=$(cat "$work/zabbix.err")
assert_contains "$err" "agent test ok" "zabbix_agent2 -T accepts the configuration"
assert_contains "$err" "640 root:zabbix /etc/zabbix/zabbix_agent2.conf" "zabbix_agent2.conf 640 root:zabbix"
assert_contains "$err" "440 root:root /etc/sudoers.d/zabbix" "sudoers.d/zabbix 0440 root"
gen "$work/default" -e ZABBIX_ENABLED=true
assert_cmd "hostname from the system (HostnameItem)" -- grep -qx 'HostnameItem=system.hostname' "$work/default/etc/zabbix/zabbix_agent2.d/local.conf"
gen "$work/neg" --env-file "$golden/cases/zabbix.env" -e ZABBIX_SERVER=other.example.com
assert_cmd_fails "control: a different ZABBIX_SERVER is caught" -- diff -q "$old/zabbix_agent2.d/local.conf" "$work/neg/etc/zabbix/zabbix_agent2.d/local.conf"

# --- sudo for the Asterisk template
c=$(t_run sudo "$image" -e ZABBIX_ENABLED=true -e HTTPD_ENABLED=false -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false)
t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted' >/dev/null || log "asterisk not booted"
assert_cmd "zabbix agent runs" -- t_wait_for 30 -- docker exec "$c" pgrep -x zabbix_agent2
assert_cmd "as zabbix: sudo -u asterisk asterisk -rx works" -- sh -c "docker exec -u zabbix $c sudo -n -u asterisk asterisk -rx 'core show uptime' | grep -q 'System uptime'"
assert_cmd_fails "as zabbix: sudo asterisk (root) is refused" -- docker exec -u zabbix "$c" sudo -n asterisk -rx 'core show uptime'
assert_cmd_fails "as zabbix: sudo of another command is refused" -- docker exec -u zabbix "$c" sudo -n -u asterisk id
finish
