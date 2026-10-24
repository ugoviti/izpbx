#!/usr/bin/env bash
# P2-08 (design S9): the first install and a migration can keep izpbx-init
# busy for tens of minutes; s6 must wait for it, then start the services.
# - the image sets S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 and
#   S6_BEHAVIOUR_IF_STAGE2_FAILS=2, and the izpbx-init oneshot has no
#   timeout-up (0 = none);
# - negative check: with a 30 s limit given at run time, a 60 s izpbx-init
#   stops the container (so the hook below really makes the init slow and a
#   limit would be seen);
# - an init step that lasts 15 minutes (P2_08_INIT_SECONDS; 3 in all-done): the container
#   keeps running, Asterisk waits for the init, and then it becomes healthy.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p2-08
# the 15 minutes of the item run alone and at the end of a phase; in the
# regression runs (all-done without TEST_INCLUDE_DEFERRED) 3 minutes, still
# past every default limit of s6 and docker
if [ -n "${TEST_REGRESSION:-}" ] && [ -z "${TEST_INCLUDE_DEFERRED:-}" ]; then
  init_seconds=${P2_08_INIT_SECONDS:-180}
else
  init_seconds=${P2_08_INIT_SECONDS:-900}
fi
assert_cmd "image builds" -- t_build_image "$image"

envs=$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$image")
assert_contains "$envs" "S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0" "no limit on the wait for the services"
assert_contains "$envs" "S6_BEHAVIOUR_IF_STAGE2_FAILS=2" "a failed init stops the container"
tu=$(docker run --rm --entrypoint "" "$image" cat /etc/s6-overlay/s6-rc.d/izpbx-init/timeout-up)
assert_eq 0 "$tu" "izpbx-init has no timeout-up"

# init step used by the test: sourced by izpbx-init after the real steps
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
hook="$work/99-test-slow.sh"
cat > "$hook" <<'EOF'
log_info "test hook: izpbx-init busy for ${IZPBX_TEST_INIT_SLEEP}s"
sleep "$IZPBX_TEST_INIT_SLEEP"
log_info "test hook: done"
EOF
chmod 644 "$hook"
mount=(-v "$hook:/usr/local/lib/izpbx/init.d/99-test-slow.sh:ro")
health=(--health-cmd "asterisk -rx 'core waitfullybooted' >/dev/null" --health-interval 10s
        --health-timeout 10s --health-retries 3 --health-start-period 20m)
state() { docker inspect -f '{{.State.Status}}/{{.State.Health.Status}}' "$1" 2>/dev/null || echo gone/none; }

# --- negative check: a limit is enforced
c=$(t_run limit "$image" "${mount[@]}" "${health[@]}" -e IZPBX_TEST_INIT_SLEEP=60 \
    -e S6_CMD_WAIT_FOR_SERVICES_MAXTIME=30000)
t_wait_for 120 -- sh -c "[ \"\$(docker inspect -f '{{.State.Running}}' $c)\" != true ]" && rc=0 || rc=$?
assert_eq 0 "$rc" "control: with a 30 s limit the 60 s init stops the container"
assert_ne 0 "$(docker inspect -f '{{.State.ExitCode}}' "$c")" "control: exit code != 0"

# --- a 15 minute init
c=$(t_run slow "$image" "${mount[@]}" "${health[@]}" -e IZPBX_TEST_INIT_SLEEP="$init_seconds")
t_wait_for 60 -- sh -c "docker logs $c 2>&1 | grep -q 'test hook: izpbx-init busy'" ||
  fail "the test hook did not start"
t0=$SECONDS bad=
while [ $((SECONDS - t0)) -lt "$((init_seconds - 30))" ]; do
  s=$(state "$c")
  case "$s" in
    running/starting) ;;
    *) bad="state $s after $((SECONDS - t0)) s"; break ;;
  esac
  if docker exec "$c" pgrep -x asterisk >/dev/null 2>&1; then
    bad="asterisk started before the end of izpbx-init ($((SECONDS - t0)) s)"; break
  fi
  sleep 30
done
assert_eq "" "$bad" "during the ${init_seconds}s init: running, health 'starting', no Asterisk"
assert_cmd "izpbx-init completes" -- t_wait_for 120 -- sh -c "docker logs $c 2>&1 | grep -q 'izpbx-init: done'"
assert_cmd "then the container becomes healthy" -- t_wait_healthy "$c" 180
assert_cmd_fails "no s6 timeout in the log" -- sh -c "docker logs $c 2>&1 | grep -Eiq 'timed out|timeout'"
finish
