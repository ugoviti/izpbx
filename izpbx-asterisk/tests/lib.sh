#!/usr/bin/env bash
# Shared helpers for izpbx-asterisk/tests/checks/*.sh. Source it, never execute it.
#
# Every container, network and volume a test creates carries the label
# izpbx.test=$TEST_PROJECT, so the EXIT trap can remove all of it even
# when the test fails half way.

set -Eeuo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$TESTS_DIR/../.." && pwd)   # repository root (the tests live in izpbx-asterisk/tests)
export REPO_DIR
COMPOSE_FILE="$TESTS_DIR/compose.test.yml"

: "${TEST_ID:=$(basename "${0%.sh}")}"
# Lowercase and safe for compose project names; unique per run.
: "${TEST_PROJECT:=izpbxt-$(printf '%s' "$TEST_ID" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')$$}"
: "${TEST_TIMEOUT:=300}"
# TEST_PROJECT is not exported: a script run by a check (verify-fixture.sh,
# make-fixture.sh) gets its own project, so its cleanup cannot remove the
# containers of the caller. Pass it explicitly to share a project.
export TEST_ID

TEST_FAILS=0
TEST_CLEANUP_HOOKS=()

log()  { printf '[%s] %s\n' "$TEST_ID" "$*" >&2; }
pass() { printf '[%s] PASS: %s\n' "$TEST_ID" "$*" >&2; }
fail() { printf '[%s] FAIL: %s\n' "$TEST_ID" "$*" >&2; TEST_FAILS=$((TEST_FAILS + 1)); }
die()  { printf '[%s] ERROR: %s\n' "$TEST_ID" "$*" >&2; exit 2; }

# izPBX log lines (common.sh): an error starts with the mark "!!", a warning
# with " !", colored or not; their details and the program output have none
# shellcheck disable=SC2034 # used by the checks
T_LOG_ERROR_RE=$'^(\e\\[[0-9;]*m)?!! '
# shellcheck disable=SC2034
T_LOG_ISSUE_RE=$'^(\e\\[[0-9;]*m)?( !|!!) '
# a detail: under the line before, "- text"
# shellcheck disable=SC2034
T_LOG_DETAIL_RE=$'^ +(\e\\[[0-9;]*m)?- '
# izPBX log lines without colors, mark, level and padding: "component: text",
# "- detail"
t_log_plain() { sed -E $'s/\e\\[[0-9;]*m//g; s/^( \\*| \\+| !|!!| \\|)? (WARNING |ERROR )? *//'; }

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

assert_cmd() { # message -- command...   (on failure, shows the end of the command output)
  # _lib_ prefix: the command may be a function of the check using any name
  local _lib_msg=$1 _lib_out; shift; [ "${1:-}" == "--" ] && shift
  _lib_out=$(mktemp)
  if "$@" >"$_lib_out" 2>&1; then
    pass "$_lib_msg"
  else
    fail "$_lib_msg (command failed: $*)"
    tail -n 8 "$_lib_out" | sed 's/^/    | /' >&2
  fi
  rm -f "$_lib_out"
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

t_compose() { env TEST_PROJECT="$TEST_PROJECT" docker compose -p "$TEST_PROJECT" -f "$COMPOSE_FILE" "$@"; }

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

# Tag the izpbx-asterisk image of this run (built once by izpbx-asterisk/tests/run.sh,
# TEST_IMAGE) as TAG, or build it when the check runs on its own.
t_build_image() { # tag
  if [ -n "${TEST_IMAGE:-}" ]; then
    docker tag "$TEST_IMAGE" "$1"
  else
    docker build -q -t "$1" "$REPO_DIR/izpbx-asterisk"
  fi
}

# FreePBX 17 seen as installed, for checks that need IZPBX_ENABLED=true but
# not FreePBX itself (service switches): izpbx-asterisk/tests/fixtures/freepbx-installed
# as /etc/freepbx.conf and a MariaDB whose admin.version is 17.0.33 (what
# izpbx-init reads to choose the normal start, M1). Sets T_FREEPBX17 with the
# docker run options of the containers.
t_freepbx17() {
  local net="$TEST_PROJECT-fpbx17" db
  docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
  db=$(t_run fpbx17db docker.io/mariadb:10.11.19 --network "$net" --network-alias fpbx17db \
    -e MARIADB_ROOT_PASSWORD=rootpw -e MARIADB_DATABASE=asterisk -e MARIADB_USER=asterisk -e MARIADB_PASSWORD=astpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$db" 120 || die "MariaDB of t_freepbx17 did not start"
  docker exec "$db" mariadb -uroot -prootpw asterisk -e \
    "CREATE TABLE admin (variable VARCHAR(20) PRIMARY KEY, value VARCHAR(80)); INSERT INTO admin VALUES ('version', '17.0.33')"
  # shellcheck disable=SC2034 # used by the checks that call t_freepbx17
  T_FREEPBX17=(--network "$net" -e MYSQL_SERVER=fpbx17db -e MYSQL_PASSWORD=astpw
               -v "$TESTS_DIR/fixtures/freepbx-installed/freepbx.conf:/etc/freepbx.conf:ro")
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

# rm -rf that also removes trees unpacked from fixtures (they hold read-only dirs)
t_rmtree() { [ -e "$1" ] || return 0; chmod -R u+w "$1" 2>/dev/null; rm -rf "$1"; }

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
