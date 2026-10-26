#!/usr/bin/env bash
# P3-09: fail2ban configured by izpbx-init (services/fail2ban.sh).
# - golden: jail.d/99-local.conf of the default and fail2ban cases equals
#   20.16.22 apart from the Apache log path (/var/log/httpd ->
#   /var/log/apache2, design C12); the settings of fail2ban.conf too;
#   backend=auto (jail.d/00-izpbx-debian.conf); fail2ban-client -t OK;
# - ban: with Asterisk refusing every SIP request, sipp sends INVITEs from two
#   addresses: maxretry (3) failures ban the address, 1 failure does not;
# - negative checks: a different FAIL2BAN_DEFAULT_BANTIME changes the view;
#   the address under maxretry is not banned.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-09
sipp_image=izpbx-test-sipp:p3-09
golden="$TESTS_DIR/golden"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "sipp image builds" -- docker build -q -t "$sipp_image" "$TESTS_DIR/sipp"
t_on_cleanup "docker image rm $sipp_image >/dev/null 2>&1"

# --- golden
APACHE_MAP='s|/var/log/httpd/|/var/log/apache2/|'
settings() { grep -Ev '^[[:space:]]*([#;]|$)' "$1"; }
gen() { # case outdir [docker args]
  local name=$1 out=$2; shift 2
  mkdir -p "$out"
  docker run --rm --entrypoint "" --hostname izpbx-golden --env-file "$golden/cases/$name.env" "$@" "$image" \
    bash -c 'izpbx-init --dry-run >/tmp/init.log 2>&1 || cat /tmp/init.log >&2
             fail2ban-client -t >&2 && echo "config ok" >&2
             tar -chf - /etc/fail2ban/jail.d /etc/fail2ban/fail2ban.conf 2>/dev/null' 2>"$out.err" | tar -C "$out" -xf -
}
for name in default fail2ban; do
  gen "$name" "$work/$name"
  assert_contains "$(cat "$work/$name.err")" "config ok" "$name: fail2ban-client -t"
  old="$golden/20.16.22/$name/files/etc/fail2ban"
  if diff -u <(sed "$APACHE_MAP" "$old/jail.d/99-local.conf") "$work/$name/etc/fail2ban/jail.d/99-local.conf" > "$work/$name.diff"; then
    pass "$name: 99-local.conf same as 20.16.22 (apart from the Apache log path)"
  else
    fail "$name: 99-local.conf differs"; head -30 "$work/$name.diff" >&2
  fi
  if diff -u <(settings "$old/fail2ban.conf") <(settings "$work/$name/etc/fail2ban/fail2ban.conf") > "$work/$name.f2b.diff"; then
    pass "$name: fail2ban.conf settings same as 20.16.22"
  else
    fail "$name: fail2ban.conf settings differ"; cat "$work/$name.f2b.diff" >&2
  fi
done
assert_contains "$(settings "$work/default/etc/fail2ban/jail.d/00-izpbx-debian.conf")" "backend = auto" "backend auto (no systemd journal)"
gen fail2ban "$work/neg" -e FAIL2BAN_DEFAULT_BANTIME=999
assert_cmd_fails "control: a different bantime is caught" -- diff -q <(sed "$APACHE_MAP" "$golden/20.16.22/fail2ban/files/etc/fail2ban/jail.d/99-local.conf") "$work/neg/etc/fail2ban/jail.d/99-local.conf"

# --- ban with sipp
net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" --subnet 10.199.99.0/24 "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
fx="$TESTS_DIR/fixtures/asterisk-f2b"
c=$(t_run pbx "$image" --network "$net" --ip 10.199.99.10 --cap-add NET_ADMIN \
  -v "$fx/pjsip.conf:/etc/asterisk/pjsip.conf:ro" -v "$fx/logger.conf:/etc/asterisk/logger.conf:ro" \
  -e FAIL2BAN_DEFAULT_MAXRETRY=3 -e FAIL2BAN_DEFAULT_IGNOREIP=127.0.0.0/8 -e FAIL2BAN_RECIDIVE_ENABLED=false \
  -e HTTPD_ENABLED=false -e CRON_ENABLED=false -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true)
t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted' >/dev/null || log "asterisk not booted"
assert_cmd "jail asterisk active" -- t_wait_for 60 -- docker exec "$c" fail2ban-client status asterisk
sipp() { # ip calls
  docker run --rm --network "$net" --ip "$1" "$sipp_image" -sn uac 10.199.99.10:5060 \
    -m "$2" -r 2 -timeout 20s -recv_timeout 5s -nostdin >/dev/null 2>&1 || true
}
sipp 10.199.99.21 1
sipp 10.199.99.22 10
banned() { docker exec "$c" fail2ban-client status asterisk | sed -n 's/.*Banned IP list:[[:space:]]*//p'; }
assert_cmd "10 failures: the address is banned" -- t_wait_for 30 -- sh -c "docker exec $c fail2ban-client status asterisk | grep -q '10.199.99.22'"
assert_cmd_fails "control: 1 failure (under maxretry) is not banned" -- grep -q '10.199.99.21' <<<"$(banned)"
assert_cmd "the ban is an iptables rule" -- sh -c "docker exec $c iptables -S | grep -q '10.199.99.22'"
log "banned: $(banned)"
finish
