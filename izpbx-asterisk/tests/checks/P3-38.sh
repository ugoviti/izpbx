#!/usr/bin/env bash
# P3-38: user hooks of APP_CUSTOM_SCRIPTS, as 20.16 (lost in 22.17: declared,
# documented in the README, run by nobody): ${APP_CUSTOM_SCRIPTS}/pre-init/
# *.custom-inc sourced before the izpbx-init steps, post-init/*.custom-inc
# after them, before the services, in lexical order, in the shell of
# izpbx-init (a variable set in pre-init is seen by post-init and by the steps).
# Plus the start line with APP_DESCRIPTION and the version (20.16: "Starting
# container ...").
# - pre-init runs before the first step, post-init after "step" lines and
#   before "izpbx-init: done", both in lexical order, only *.custom-inc;
# - a hook that fails (written for the non strict shell of 20.16) is logged
#   and the start goes on: Asterisk runs;
# - a missing stage directory is a warning;
# - negatives: without APP_CUSTOM_SCRIPTS and in dry-run no hook runs.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-38
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

h="$work/hooks"
mkdir -p "$h/pre-init" "$h/post-init"
cat > "$h/pre-init/10-first.custom-inc" <<'HOOK'
echo "pre-10 $(ls /run/izpbx/mode 2>/dev/null || echo no-mode)" >> /tmp/hooks.log
HOOK_VAR=from-pre
HOOK
cat > "$h/pre-init/20-fails.custom-inc" <<'HOOK'
false
echo "pre-20 after a failing command" >> /tmp/hooks.log
ls /nonexistent
HOOK
echo 'echo "not a hook" >> /tmp/hooks.log' > "$h/pre-init/30-ignored.sh"
cat > "$h/post-init/10-last.custom-inc" <<'HOOK'
echo "post-10 $HOOK_VAR $(cat /run/izpbx/mode 2>/dev/null)" >> /tmp/hooks.log
HOOK
chmod -R a+rX "$h"

c=$(t_run on "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true -e APP_CUSTOM_SCRIPTS=/hooks -v "$h:/hooks:ro")
t_wait_for 120 -- sh -c "docker logs '$c' 2>&1 | grep -q 'izpbx-init: done'" || die "izpbx-init did not finish"
assert_eq "pre-10 no-mode
pre-20 after a failing command
post-10 from-pre none" "$(docker exec "$c" cat /tmp/hooks.log)" "pre-init before the steps, post-init after, lexical order, variables shared, only *.custom-inc"
logs=$(docker logs "$c" 2>&1)
order=$(grep -nE 'izpbx-init: (pre|post)-init hook [^ ]+\.custom-inc$|---- 01 |---- 40 |izpbx-init: done' <<< "$logs" | cut -d: -f1 | tr '\n' ' ')
grep -nE 'izpbx-init: (pre|post)-init hook [^ ]+\.custom-inc$|---- 01 |---- 40 |izpbx-init: done' <<< "$logs" | sed 's/^/  /' >&2
read -r a b s1 s40 p d <<< "$order"
assert_cmd "log order: pre-init hooks, steps, post-init hook, done" -- test "$a" -lt "$s1" -a "$b" -lt "$s1" -a "$s40" -lt "$p" -a "$p" -lt "$d"
assert_contains "$logs" "pre-init hook /hooks/pre-init/20-fails.custom-inc exited with status 2" "a failing hook is logged with its status"
assert_cmd "the start goes on after a failing hook: Asterisk runs" -- t_wait_for 60 -- docker exec "$c" asterisk -rx 'core show uptime'
assert_contains "$logs" "izpbx-init: start izPBX Cloud Native Telephony System" "start line with APP_DESCRIPTION"

m=$(t_run missing "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=false -e APP_CUSTOM_SCRIPTS=/nothere)
t_wait_for 120 -- sh -c "docker logs '$m' 2>&1 | grep -q 'izpbx-init: done'" || die "izpbx-init did not finish (missing dir)"
assert_contains "$(docker logs "$m" 2>&1)" "custom scripts directory /nothere/pre-init does not exist" "missing stage directory: warning"

n=$(t_run none "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=false -v "$h:/hooks:ro")
t_wait_for 120 -- sh -c "docker logs '$n' 2>&1 | grep -q 'izpbx-init: done'" || die "izpbx-init did not finish (none)"
assert_cmd_fails "negative: without APP_CUSTOM_SCRIPTS no hook runs" -- docker exec "$n" test -e /tmp/hooks.log
dry=$(docker run --rm --entrypoint "" -e IZPBX_ENABLED=false -e APP_CUSTOM_SCRIPTS=/hooks -v "$h:/hooks:ro" "$image" \
  bash -c 'izpbx-init --dry-run 2>&1; if test -e /tmp/hooks.log; then echo HOOKS-RAN; fi')
assert_cmd_fails "negative: dry-run runs no hook" -- grep -q HOOKS-RAN <<< "$dry"
assert_contains "$dry" "pre-init hooks of /hooks/pre-init not run (dry-run)" "dry-run says so"
finish
