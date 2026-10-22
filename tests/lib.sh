#!/usr/bin/env bash
# Shared helpers for tests/checks/*.sh. Source it, never execute it.
#
# Every container, network and volume a test creates carries the label
# izpbx.test=$TEST_PROJECT, so the EXIT trap can remove all of it even
# when the test fails half way.

set -Eeuo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$TESTS_DIR/.." && pwd)
export REPO_DIR
COMPOSE_FILE="$TESTS_DIR/compose.test.yml"

: "${TEST_ID:=$(basename "${0%.sh}")}"
# Lowercase and safe for compose project names; unique per run.
: "${TEST_PROJECT:=izpbxt-$(printf '%s' "$TEST_ID" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')$$}"
: "${TEST_TIMEOUT:=300}"
export TEST_ID TEST_PROJECT

TEST_FAILS=0
TEST_CLEANUP_HOOKS=()

log()  { printf '[%s] %s\n' "$TEST_ID" "$*" >&2; }
pass() { printf '[%s] PASS: %s\n' "$TEST_ID" "$*" >&2; }
fail() { printf '[%s] FAIL: %s\n' "$TEST_ID" "$*" >&2; TEST_FAILS=$((TEST_FAILS + 1)); }
die()  { printf '[%s] ERROR: %s\n' "$TEST_ID" "$*" >&2; exit 2; }

# --- assertions: record a failure and keep going, finish() sets the exit code

assert_eq() { # expected actual message
  if [ "$1" == "$2" ]; then pass "$3"; else fail "$3 (expected '$1', got '$2')"; fi
}

assert_ne() { # unexpected actual message
  if [ "$1" != "$2" ]; then pass "$3"; else fail "$3 (got unexpected '$2')"; fi
}

assert_contains() { # haystack needle message
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (missing '$2')"; fi
}

assert_cmd() { # message -- command...
  local msg=$1; shift; [ "${1:-}" == "--" ] && shift
  if "$@" >/dev/null 2>&1; then pass "$msg"; else fail "$msg (command failed: $*)"; fi
}

assert_cmd_fails() { # message -- command...  (negative checks)
  local msg=$1; shift; [ "${1:-}" == "--" ] && shift
  if "$@" >/dev/null 2>&1; then fail "$msg (command unexpectedly succeeded: $*)"; else pass "$msg"; fi
}

assert_file() { # path message
  if [ -s "$1" ]; then pass "$2"; else fail "$2 (missing or empty: $1)"; fi
}

# Call at the end of every check.
finish() {
  if [ "$TEST_FAILS" -eq 0 ]; then
    log "OK"; exit 0
  fi
  log "$TEST_FAILS assertion(s) failed"; exit 1
}

# --- containers

t_compose() { docker compose -p "$TEST_PROJECT" -f "$COMPOSE_FILE" "$@"; }

t_up() { t_compose up -d --quiet-pull "$@" >&2; }

# Container id of a compose service in this project.
t_cid() { t_compose ps -q "$1"; }

# Start a standalone container with the cleanup label; prints its name.
t_run() { # name image [docker run args...] [-- command...]
  local name="$TEST_PROJECT-$1" image=$2; shift 2
  local args=() cmd=()
  while [ $# -gt 0 ]; do
    if [ "$1" == "--" ]; then shift; cmd=("$@"); break; fi
    args+=("$1"); shift
  done
  docker run -d --name "$name" --label "izpbx.test=$TEST_PROJECT" "${args[@]}" "$image" "${cmd[@]}" >/dev/null
  printf '%s\n' "$name"
}

t_volume() { # name -> prints volume name
  local name="$TEST_PROJECT-$1"
  docker volume create --label "izpbx.test=$TEST_PROJECT" "$name" >/dev/null
  printf '%s\n' "$name"
}

t_exec() { local c=$1; shift; docker exec "$c" "$@"; }

# Wait until a container's healthcheck reports healthy; fails on timeout,
# on unhealthy, or if the container exits.
t_wait_healthy() { # container [timeout_s]
  local c=$1 timeout=${2:-$TEST_TIMEOUT} start=$SECONDS state
  while :; do
    state=$(docker inspect -f '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null || echo "gone/none")
    case "$state" in
      running/healthy) return 0 ;;
      running/none) die "container $c has no healthcheck" ;;
      exited/*|dead/*|gone/*) log "container $c is $state"; docker logs --tail 50 "$c" >&2 2>&1 || true; return 1 ;;
    esac
    if [ $((SECONDS - start)) -ge "$timeout" ]; then
      log "timeout after ${timeout}s waiting for $c (state $state)"
      docker logs --tail 50 "$c" >&2 2>&1 || true
      return 1
    fi
    sleep 2
  done
}

# Poll a command until it succeeds or the timeout expires.
t_wait_for() { # timeout_s -- command...
  local timeout=$1 start=$SECONDS; shift; [ "${1:-}" == "--" ] && shift
  until "$@" >/dev/null 2>&1; do
    [ $((SECONDS - start)) -ge "$timeout" ] && return 1
    sleep 2
  done
}

# --- cleanup

t_on_cleanup() { TEST_CLEANUP_HOOKS+=("$1"); }

t_cleanup() {
  local rc=$? hook
  trap - EXIT
  set +e
  for hook in "${TEST_CLEANUP_HOOKS[@]}"; do eval "$hook"; done
  if [ -z "${TEST_KEEP:-}" ]; then
    t_compose down -v --remove-orphans --timeout 10 >/dev/null 2>&1
    docker ps -aq --filter "label=izpbx.test=$TEST_PROJECT" | xargs -r docker rm -fv >/dev/null 2>&1
    docker volume ls -q --filter "label=izpbx.test=$TEST_PROJECT" | xargs -r docker volume rm -f >/dev/null 2>&1
    docker network ls -q --filter "label=izpbx.test=$TEST_PROJECT" | xargs -r docker network rm >/dev/null 2>&1
  else
    log "TEST_KEEP set: leaving project $TEST_PROJECT in place"
  fi
  exit "$rc"
}

trap t_cleanup EXIT
trap 'log "error at $0:${LINENO}: $BASH_COMMAND"' ERR
