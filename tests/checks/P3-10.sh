#!/usr/bin/env bash
# P3-10: dnsmasq for DHCP and TFTP configured by izpbx-init
# (services/dnsmasq.sh) on the rootfs template /etc/dnsmasq.d/local.conf.
# - golden: local.conf of the default, dnsmasq (DHCP + TFTP, every option),
#   dhcp-nodomain and hostile cases equals 20.16.22;
# - dnsmasq --test OK with and without DHCP_DOMAIN (Debian reads
#   /etc/dnsmasq.d through conf-dir, set at build);
# - TFTP: /var/lib/tftpboot owned by asterisk, /tftpboot links to it;
# - negative checks: a different pool changes the file; an invalid pool
#   address makes dnsmasq --test fail (the test reads local.conf).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-10
golden="$TESTS_DIR/golden"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- docker build -q -t "$image" "$REPO_DIR/izpbx-asterisk"

gen() { # case outfile [docker args]: local.conf on the file, checks on .err
  local name=$1 out=$2; shift 2
  docker run --rm --entrypoint "" --hostname izpbx-golden --env-file "$golden/cases/$name.env" "$@" "$image" \
    bash -c 'izpbx-init --dry-run >/tmp/init.log 2>&1 || cat /tmp/init.log >&2
             dnsmasq --test >&2 2>&1 && echo "dnsmasq test ok" >&2
             stat -c "%U %n" /var/lib/tftpboot >&2; readlink /tftpboot >&2
             cat /etc/dnsmasq.d/local.conf' >"$out" 2>"$out.err"
}
for name in default dnsmasq dhcp-nodomain hostile; do
  gen "$name" "$work/$name"
  if diff -u "$golden/20.16.22/$name/files/etc/dnsmasq.d/local.conf" "$work/$name" > "$work/$name.diff"; then
    pass "$name: local.conf same as 20.16.22"
  else
    fail "$name: local.conf differs"; cat "$work/$name.diff" >&2
  fi
done
assert_contains "$(cat "$work/dnsmasq.err")" "dnsmasq test ok" "dnsmasq --test with DHCP_DOMAIN"
assert_contains "$(cat "$work/dhcp-nodomain.err")" "dnsmasq test ok" "dnsmasq --test without DHCP_DOMAIN"
assert_contains "$(cat "$work/dnsmasq.err")" "asterisk /var/lib/tftpboot" "TFTP root owned by asterisk"
assert_contains "$(cat "$work/dnsmasq.err")" "/var/lib/tftpboot" "/tftpboot links to the TFTP root"
assert_cmd "dnsmasq reads /etc/dnsmasq.d" -- docker run --rm --entrypoint "" "$image" grep -qx 'conf-dir=/etc/dnsmasq.d/,\*\.conf' /etc/dnsmasq.conf

gen dnsmasq "$work/neg" -e DHCP_POOL_START=10.1.1.100
assert_cmd_fails "control: a different pool is caught" -- diff -q "$golden/20.16.22/dnsmasq/files/etc/dnsmasq.d/local.conf" "$work/neg"
gen dnsmasq "$work/bad" -e DHCP_POOL_START=not-an-address
assert_cmd_fails "control: an invalid pool fails dnsmasq --test" -- grep -q "dnsmasq test ok" "$work/bad.err"
finish
