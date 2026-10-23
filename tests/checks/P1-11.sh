#!/usr/bin/env bash
# P1-11: arm64 build. "docker buildx build --platform linux/arm64" succeeds
# (QEMU emulation on an x86_64 host: the first build compiles Asterisk in
# ~30 min, later ones reuse the cache); /usr/sbin/asterisk is an aarch64
# binary; P1-06, P1-07 and P1-09 pass on the arm64 image (run with
# DOCKER_DEFAULT_PLATFORM=linux/arm64; P1-06 then expects
# tests/expected/asterisk-modules-aarch64.txt).
# Negative: the same binary check on the x86_64 image does not say aarch64.
source "$(dirname "$0")/../lib.sh"

dir="$REPO_DIR/izpbx-asterisk"
image=izpbx-asterisk:p1-11-arm64
[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || die "no QEMU binfmt handler for aarch64 on this host"

assert_cmd "docker buildx build --platform linux/arm64 succeeds" -- \
  docker buildx build -q --platform linux/arm64 --load -t "$image" "$dir"
bin() { docker run --rm --platform "$1" "$2" file -b /usr/sbin/asterisk; }
assert_contains "$(bin linux/arm64 "$image")" "ARM aarch64" "/usr/sbin/asterisk is an aarch64 binary"
assert_cmd "x86_64 image builds" -- docker build -q --platform linux/amd64 -t izpbx-asterisk:p1-11-amd64 "$dir"
assert_cmd_fails "control: the x86_64 binary is not aarch64" -- grep -q aarch64 <<< "$(bin linux/amd64 izpbx-asterisk:p1-11-amd64)"
docker rmi izpbx-asterisk:p1-11-amd64 >/dev/null 2>&1 || true

for c in P1-06 P1-07 P1-09; do
  out=$(DOCKER_DEFAULT_PLATFORM=linux/arm64 "$TESTS_DIR/checks/$c.sh" 2>&1) && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || log "$c on arm64:"$'\n'"$(grep -E '\] (FAIL|ERROR)' <<< "$out" | head -20)"
  assert_eq 0 "$rc" "$c passes on arm64 ($(grep -c '\] PASS: ' <<< "$out") assertions)"
done

docker rmi "$image" >/dev/null 2>&1 || true
finish
