#!/usr/bin/env bash
# P2-02: s6-rc oneshot "izpbx-init" (/usr/local/sbin/izpbx-init, steps in
# /usr/local/lib/izpbx/init.d), and every service depends on it.
# - static: every service of rootfs/etc/s6-overlay/s6-rc.d (not bundles) has
#   dependencies.d/izpbx-init; izpbx-init is a oneshot of the "user" bundle
#   (etc/s6-overlay/user-bundles.d, not the deprecated s6-rc.d/user);
# - runtime (tests/s6probe: a longrun "probe" + an init step): from the logs
#   the probe starts after "izpbx-init: done", and the container environment
#   reaches the init; when izpbx-init fails, the error shows file:line, the
#   probe never starts and the container stops (exit != 0); no s6-overlay
#   deprecation warning; a non-root start (-u asterisk) does not hang.
# Negative: a service without dependencies.d/izpbx-init is reported.
source "$(dirname "$0")/../lib.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
rc_dir="$REPO_DIR/izpbx-asterisk/rootfs/etc/s6-overlay/s6-rc.d"
image=izpbx-asterisk:p2-02
probe=izpbx-s6probe:p2-02

# --- static
without_init() { # s6-rc.d dir -> services missing dependencies.d/izpbx-init
  local d
  for d in "$1"/*/; do
    d=${d%/}
    case "$(basename "$d")" in izpbx-init) continue ;; esac
    [ -f "$d/type" ] || { echo "$(basename "$d") (no type)"; continue; }
    [ "$(cat "$d/type")" == bundle ] && continue
    [ -e "$d/dependencies.d/izpbx-init" ] || basename "$d"
  done
}
assert_eq "oneshot" "$(cat "$rc_dir/izpbx-init/type")" "izpbx-init is a oneshot"
bundles="$REPO_DIR/izpbx-asterisk/rootfs/etc/s6-overlay/user-bundles.d"
assert_cmd "izpbx-init is in the user bundle (user-bundles.d)" -- test -e "$bundles/user/contents.d/izpbx-init"
assert_eq "bundle" "$(cat "$bundles/user/type")" "user-bundles.d/user is a bundle"
# s6-overlay 3.2: a user bundle under s6-rc.d is deprecated, and as non-root
# it makes /init write s6-rc.d/user/type (permission denied, container hangs)
assert_cmd_fails "no user bundle under s6-rc.d (deprecated layout)" -- test -e "$rc_dir/user"
assert_eq "" "$(without_init "$rc_dir")" "every service depends on izpbx-init ($(find "$rc_dir" -mindepth 1 -maxdepth 1 -type d | wc -l) entries)"
cp -a "$rc_dir" "$work/rc" && mkdir -p "$work/rc/izpbx-fake" && echo longrun > "$work/rc/izpbx-fake/type"
assert_eq "izpbx-fake" "$(without_init "$work/rc")" "control: a service without the dependency is reported"
assert_eq "" "$(without_init "$TESTS_DIR/s6probe/rootfs/etc/s6-overlay/s6-rc.d")" "the probe service depends on izpbx-init"

# --- runtime
assert_cmd "image builds" -- docker build -q -t "$image" "$REPO_DIR/izpbx-asterisk"
assert_cmd "probe image builds" -- docker build -q -t "$probe" --build-arg BASE="$image" "$TESTS_DIR/s6probe"
line() { grep -n -m1 -F -- "$2" <<< "$1" | cut -d: -f1; }

c=$(t_run ok "$probe" -e IZPBX_PROBE_VALUE=hello)
t_wait_for 60 -- sh -c "docker logs $c 2>&1 | grep -q 'probe: started'" || log "$(docker logs "$c" 2>&1 | tail -20)"
logs=$(docker logs "$c" 2>&1)
done_at=$(line "$logs" "izpbx: info: izpbx-init: done"); start_at=$(line "$logs" "s6-rc: info: service probe: starting"); up_at=$(line "$logs" "probe: started")
assert_ne "" "$done_at" "izpbx-init completes"
assert_cmd "the probe service starts after izpbx-init is done" -- test -n "$start_at" -a "${start_at:-0}" -gt "${done_at:-999999}" -a "${up_at:-0}" -gt "${done_at:-999999}"
assert_contains "$logs" "probe step: IZPBX_PROBE_VALUE=hello" "the container environment reaches izpbx-init"
assert_contains "$(docker exec "$c" /command/s6-svstat /run/service/probe)" "up " "the probe service is up"
assert_eq 0 "$(grep -c 'deprecated' <<< "$logs" || true)" "no s6-overlay deprecation warning at start"
rc=0; timeout 90 docker run --rm -u asterisk "$image" true >/dev/null 2>&1 || rc=$?
assert_eq 0 "$rc" "the image starts and runs a command as a non-root user (asterisk) within 90 s"

f=$(t_run fail "$probe" -e IZPBX_PROBE_FAIL=1)
t_wait_for 60 -- sh -c "[ \"\$(docker inspect -f '{{.State.Status}}' $f)\" = exited ]" || log "container still running"
logs=$(docker logs "$f" 2>&1)
assert_contains "$logs" "izpbx: error: /usr/local/lib/izpbx/init.d/50-probe.sh:7: 'false' exited with status 1" "a failing izpbx-init logs file:line"
assert_eq 0 "$(grep -c -e 'probe: started' -e 'service probe: starting' <<< "$logs" || true)" "when izpbx-init fails the probe service does not start"
assert_ne 0 "$(docker inspect -f '{{.State.ExitCode}}' "$f")" "when izpbx-init fails the container stops with exit != 0"

docker rmi "$probe" "$image" >/dev/null 2>&1 || true
finish
