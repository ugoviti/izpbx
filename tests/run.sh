#!/usr/bin/env bash
# Test runner for the 22.17 checklist.
#
#   tests/run.sh <ID>...    run tests/checks/<ID>.sh
#   tests/run.sh all        run every check
#   tests/run.sh all-done   run the checks of the items already done (tests/done.list)
#   tests/run.sh selftest   test the harness itself
#
# Exit code: 0 if every selected check passed, 1 otherwise.

set -Eeuo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECKS_DIR="$TESTS_DIR/checks"
DONE_LIST="$TESTS_DIR/done.list"

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

run_one() { # id
  local id=$1 script="$CHECKS_DIR/$1.sh" start=$SECONDS rc=0
  if [ ! -f "$script" ]; then
    printf '%-10s MISSING  %s\n' "$id" "$script"
    return 1
  fi
  TEST_ID=$id bash "$script" || rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%-10s PASS     %ss\n' "$id" "$((SECONDS - start))"
  else
    printf '%-10s FAIL(%s)  %ss\n' "$id" "$rc" "$((SECONDS - start))"
  fi
  return "$rc"
}

run_many() { # ids...
  local id failed=()
  for id in "$@"; do run_one "$id" || failed+=("$id"); done
  echo "---"
  if [ ${#failed[@]} -eq 0 ]; then
    echo "all $# check(s) passed"
    return 0
  fi
  echo "${#failed[@]}/$# failed: ${failed[*]}"
  return 1
}

done_ids() { grep -vE '^\s*(#|$)' "$DONE_LIST" | awk '{print $1}'; }

[ $# -ge 1 ] || usage

case "$1" in
  -h|--help) usage ;;
  selftest)  TEST_ID=selftest exec bash "$TESTS_DIR/selftest.sh" ;;
  all)       mapfile -t ids < <(find "$CHECKS_DIR" -name '*.sh' -printf '%f\n' | sed 's/\.sh$//' | sort -V)
             run_many "${ids[@]}" ;;
  all-done)  mapfile -t ids < <(done_ids)
             [ ${#ids[@]} -gt 0 ] || { echo "no items in $DONE_LIST"; exit 0; }
             run_many "${ids[@]}" ;;
  *)         run_many "$@" ;;
esac
