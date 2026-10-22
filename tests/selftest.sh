#!/usr/bin/env bash
# Harness self-test (P0-02): assertions report pass/fail correctly and
# cleanup removes containers and volumes even when a test errors out.
source "$(dirname "$0")/lib.sh"

work=$(mktemp -d)
t_on_cleanup "rm -rf '$work'"

# Write a throwaway check that sources lib.sh, run it, return its exit code.
run_check() { # name project body
  local script="$work/$1.sh"
  { echo "source '$TESTS_DIR/lib.sh'"; echo "$3"; } > "$script"
  local rc=0
  TEST_ID="self-$1" TEST_PROJECT="$2" bash "$script" >"$work/$1.log" 2>&1 || rc=$?
  echo "$rc"
}

leftovers() { # project
  {
    docker ps -aq --filter "label=izpbx.test=$1"
    docker ps -aq --filter "label=com.docker.compose.project=$1"
    docker volume ls -q --filter "label=izpbx.test=$1"
    docker volume ls -q --filter "label=com.docker.compose.project=$1"
    docker network ls -q --filter "label=com.docker.compose.project=$1"
  } | wc -l
}

# 1. a true assertion passes
rc=$(run_check pass "$TEST_PROJECT-a" 'assert_eq 1 1 "one is one"; assert_cmd "true works" -- true; finish')
assert_eq 0 "$rc" "true assertions exit 0"

# 2. a false assertion fails with exit != 0
rc=$(run_check fail "$TEST_PROJECT-b" 'assert_eq 1 2 "one is two"; finish')
assert_ne 0 "$rc" "false assertion exits non-zero"
assert_contains "$(cat "$work/fail.log")" "FAIL: one is two" "failure is reported in the log"

# 3. assert_cmd_fails turns a succeeding command into a failure
rc=$(run_check neg "$TEST_PROJECT-c" 'assert_cmd_fails "true must fail" -- true; finish')
assert_ne 0 "$rc" "assert_cmd_fails rejects a succeeding command"

# 4. a test that starts services and then crashes leaves nothing behind
proj="$TEST_PROJECT-d"
rc=$(run_check crash "$proj" '
t_up mariadb
db=$(t_cid mariadb)
t_wait_healthy "$db" 120
t_exec "$db" mariadb -uroot -pizpbx-test-root -e "SELECT 1" >/dev/null
t_volume extra >/dev/null
t_run side docker.io/mariadb:10.11.19 --entrypoint sleep -- infinity >/dev/null
echo "resources: $(docker ps -q --filter label=izpbx.test=$TEST_PROJECT | wc -l)" >&2
false
echo "not reached"')
assert_ne 0 "$rc" "crashing test exits non-zero"
assert_contains "$(cat "$work/crash.log")" "resources: 2" "crashing test had started its containers"
assert_contains "$(cat "$work/crash.log")" "error at" "error location is logged"
assert_eq 0 "$(leftovers "$proj")" "no containers, volumes or networks left after the crash"

# 5. t_wait_healthy gives up on a container that never becomes healthy
proj="$TEST_PROJECT-e"
rc=$(run_check timeout "$proj" '
c=$(t_run sick docker.io/mariadb:10.11.19 --entrypoint sleep --health-cmd false --health-interval 1s -- infinity)
if t_wait_healthy "$c" 6; then echo "healthy?!"; exit 0; fi
exit 3')
assert_eq 3 "$rc" "t_wait_healthy times out on an unhealthy container"
assert_eq 0 "$(leftovers "$proj")" "timeout test cleaned up"

# 6. the runner rejects an unknown item
assert_cmd_fails "run.sh fails on a missing check" -- "$TESTS_DIR/run.sh" NOPE-99

finish
