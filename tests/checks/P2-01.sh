#!/usr/bin/env bash
# P2-01: s6-overlay installed by build/s6.sh with a sha256 per architecture
# (noarch + x86_64/aarch64, versions.env); ENTRYPOINT ["/init"]: PID 1 in
# the container is s6-svscan; one-off commands keep their exit code.
# Negative: with a wrong sha256 build/s6.sh fails; a container started with
# another entrypoint does not have s6-svscan as PID 1.
source "$(dirname "$0")/../lib.sh"

dir="$REPO_DIR/izpbx-asterisk"
image=izpbx-asterisk:p2-01
for a in NOARCH X86_64 AARCH64; do
  assert_cmd "S6_OVERLAY_SHA256_$a pinned (64 hex)" -- grep -qE "^S6_OVERLAY_SHA256_$a=[0-9a-f]{64}$" "$dir/versions.env"
done
assert_cmd "image builds" -- t_build_image "$image"
assert_eq '["/init"]' "$(docker image inspect -f '{{json .Config.Entrypoint}}' "$image")" "docker inspect: entrypoint /init"

c=$(t_run svc "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true)
t_wait_for 30 -- docker exec "$c" true || die "container did not start"
# during the boot PID 1 is s6-linux-init, which then execs into s6-svscan
t_wait_for 30 -- sh -c "[ \"\$(docker exec $c cat /proc/1/comm)\" = s6-svscan ]" || true
assert_eq "s6-svscan" "$(docker exec "$c" cat /proc/1/comm)" "PID 1 is s6-svscan"
o=$(t_run other "$image" --entrypoint /bin/sleep -- infinity)
assert_ne "s6-svscan" "$(docker exec "$o" cat /proc/1/comm)" "control: with another entrypoint PID 1 is not s6-svscan"

rc=0; docker run --rm -e IZPBX_ENABLED=false "$image" sh -c 'exit 3' 2>/dev/null || rc=$?
assert_eq 3 "$rc" "a one-off command keeps its exit code through /init"

# negative: build/s6.sh, run in the image with a wrong sha256 for this arch
arch=$(docker run --rm --entrypoint "" "$image" uname -m); key=S6_OVERLAY_SHA256_${arch^^}
bad="sed -i 's/^$key=.*/$key=$(printf '0%.0s' {1..64})/' /tmp/izpbx/versions.env"
assert_cmd_fails "control: build/s6.sh fails with a wrong $key" -- \
  docker run --rm --entrypoint "" "$image" bash -c "cp -a /usr/src/izpbx /tmp/izpbx && $bad && /tmp/izpbx/build/s6.sh"
finish
