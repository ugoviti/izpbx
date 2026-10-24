#!/usr/bin/env bash
# P3-22: dead code removed from izpbx-asterisk/rootfs (tests/dead-code.sh):
# - no alpine / rhel / microdnf / chan_local / FREEPBX-21703 / FREEPBX-22983;
# - no block of more than 3 commented-out code lines;
# - the 20.16 entrypoint and supervisord files (replaced by izpbx-init and
#   s6) are gone, the tests read the 20.16.22 entrypoint from its tag;
# - negative checks: a tree with a "microdnf" line, or with 4 commented-out
#   code lines, fails the check; 5 lines of prose comments do not.
source "$(dirname "$0")/../lib.sh"
rootfs="$REPO_DIR/izpbx-asterisk/rootfs"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

out=$("$TESTS_DIR/dead-code.sh" "$rootfs" 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "no dead code in rootfs"
[ "$rc" -eq 0 ] || printf '%s\n' "$out" | head -20 >&2
for f in entrypoint.sh entrypoint-hooks.sh usr/local/sbin/startizpbx etc/supervisord.d etc/php.d/99-local.ini; do
  assert_cmd_fails "removed: $f" -- test -e "$rootfs/$f"
done
assert_cmd "the 20.16.22 entrypoint is available from its tag" -- \
  sh -c "git -C '$REPO_DIR' show 20.16.22:izpbx-asterisk/rootfs/entrypoint-hooks.sh | grep -q cfgService_freepbx_install"

mkdir -p "$work/a" "$work/b" "$work/c"
printf '#!/bin/sh\nmicrodnf install -y foo\n' > "$work/a/x.sh"
printf '#!/bin/sh\necho a\n#echo b\n# sed -i s/a/b/ f\n#[ $? = 0 ] && reload\n# fwconsole reload\necho c\n' > "$work/b/x.sh"
printf '#!/bin/sh\n# This script does\n# several things\n# for the PBX,\n# explained here\n# in prose.\necho ok\n' > "$work/c/x.sh"
assert_cmd_fails "control: a microdnf line is found" -- "$TESTS_DIR/dead-code.sh" "$work/a"
assert_cmd_fails "control: 4 commented-out code lines are found" -- "$TESTS_DIR/dead-code.sh" "$work/b"
assert_cmd "control: prose comments are not dead code" -- "$TESTS_DIR/dead-code.sh" "$work/c"
finish
