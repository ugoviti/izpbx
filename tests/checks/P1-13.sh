#!/usr/bin/env bash
# P1-13: debug tools in the runtime image (D15): command -v succeeds for
# tcpdump, strace, sngrep, mtr, iftop, vim, lsof, nc, jq, and those with a
# version option answer it (the binary runs, its libraries resolve).
# Negative: a command that does not exist is reported missing.
source "$(dirname "$0")/../lib.sh"

image=izpbx-asterisk:p1-13
tools="tcpdump strace sngrep mtr iftop vim lsof nc jq"
assert_cmd "image builds" -- docker build -q -t "$image" "$REPO_DIR/izpbx-asterisk"
missing() { docker run --rm --entrypoint "" "$image" sh -c "for t in $*; do command -v \$t >/dev/null || echo \$t; done"; }
assert_eq "" "$(missing $tools)" "command -v succeeds for: $tools"
assert_eq "izpbx-nosuch-tool" "$(missing jq izpbx-nosuch-tool)" "control: a missing command is reported"
for v in "tcpdump --version" "strace -V" "sngrep -V" "mtr --version" "vim --version" "jq --version"; do
  assert_cmd "$v runs" -- docker run --rm --entrypoint "" "$image" $v
done
docker rmi "$image" >/dev/null 2>&1 || true
finish
