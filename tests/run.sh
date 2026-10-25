#!/usr/bin/env bash
# Test runner for the 22.17 checklist.
#
#   tests/run.sh [-j N] <ID>...    run tests/checks/<ID>.sh
#   tests/run.sh [-j N] all        run every check
#   tests/run.sh [-j N] all-done   run the checks of the items already done (tests/done.list),
#                                  except the slow ones of tests/deferred.list (arm64 under
#                                  emulation): TEST_INCLUDE_DEFERRED=1 runs them too
#   tests/run.sh golden [all|CASE...]  golden matrix: 22.17 files vs 20.16.22 (tests/golden)
#   tests/run.sh selftest          test the harness itself
#
# -j N runs N checks at a time (default: CPUs / 2, at most 4); a check with a
# "# serial" line in its header runs after the others, alone. The output of
# each check goes to tests/.logs/<ID>.log (shown for the failed ones), the
# times to tests/.logs/timings.txt. The izpbx-asterisk image is built once and
# passed to the checks as TEST_IMAGE (t_build_image in lib.sh).
#
# Exit code: 0 if every selected check passed, 1 otherwise.

set -Eeuo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$TESTS_DIR/.." && pwd)
CHECKS_DIR=${TEST_CHECKS_DIR:-$TESTS_DIR/checks}
DONE_LIST=${TEST_DONE_LIST:-$TESTS_DIR/done.list}
DEFERRED_LIST=${TEST_DEFERRED_LIST:-$TESTS_DIR/deferred.list}
LOGS_DIR=${TEST_LOGS_DIR:-$TESTS_DIR/.logs}
# run by a check (TEST_ID set by lib.sh): its own logs, not those of the caller
if [ -z "${TEST_LOGS_DIR:-}" ] && [ -n "${TEST_ID:-}" ]; then
  LOGS_DIR=$(mktemp -d)
  trap 'rm -rf "$LOGS_DIR"' EXIT
fi

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

is_serial() { head -n 20 "$CHECKS_DIR/$1.sh" 2>/dev/null | grep -qx '# serial'; }

# run_one ID: run the check, its output to stdout, the result line to
# LOGS_DIR/ID.result and "ID start end seconds result" to LOGS_DIR/ID.time
run_one() {
  local id=$1 script="$CHECKS_DIR/$1.sh" start end rc=0 res
  start=$(date +%s.%N)
  if [ ! -f "$script" ]; then
    echo "missing $script"; rc=127; res=MISSING
  else
    TEST_ID=$id bash "$script" || rc=$?
    if [ "$rc" -eq 0 ]; then res=PASS; else res="FAIL($rc)"; fi
  fi
  end=$(date +%s.%N)
  printf '%-10s %-8s %ss\n' "$id" "$res" "$(awk -v s="$start" -v e="$end" 'BEGIN {printf "%d", e - s}')" > "$LOGS_DIR/$id.result"
  printf '%s %s %s %s %s\n' "$id" "$start" "$end" "$(awk -v s="$start" -v e="$end" 'BEGIN {printf "%.1f", e - s}')" "$res" > "$LOGS_DIR/$id.time"
  return "$rc"
}

# build the izpbx-asterisk image once when a selected check uses it
build_image() { # ids...
  local id need=
  for id in "$@"; do grep -q 't_build_image' "$CHECKS_DIR/$id.sh" 2>/dev/null && need=1; done
  [ -n "$need" ] || return 0
  if TEST_IMAGE=$(docker build -q -t "izpbx-asterisk:test-run" "$REPO_DIR/izpbx-asterisk" 2>"$LOGS_DIR/image-build.log"); then
    export TEST_IMAGE
    echo "image izpbx-asterisk:test-run built once (${TEST_IMAGE#sha256:})" | cut -c1-80
  else
    unset TEST_IMAGE
    echo "image build failed (tests/.logs/image-build.log): every check builds it on its own"
  fi
}

run_many() { # ids...
  local id failed=() parallel=() serial=() n=0
  mkdir -p "$LOGS_DIR"
  for id in "$@"; do rm -f "$LOGS_DIR/$id.log" "$LOGS_DIR/$id.result" "$LOGS_DIR/$id.time"; done
  build_image "$@"
  for id in "$@"; do if is_serial "$id"; then serial+=("$id"); else parallel+=("$id"); fi; done
  if [ "$JOBS" -le 1 ] || [ $# -le 1 ]; then
    # one at a time: the output of each check is shown as it runs
    for id in "${parallel[@]}" "${serial[@]}"; do
      run_one "$id" 2>&1 | tee "$LOGS_DIR/$id.log" || true
      cat "$LOGS_DIR/$id.result"
    done
  else
    echo "running $# check(s), $JOBS at a time (${#serial[@]} serial after the others); logs in ${LOGS_DIR#"$REPO_DIR"/}/"
    for id in "${parallel[@]}"; do
      while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n || true; done
      run_one "$id" > "$LOGS_DIR/$id.log" 2>&1 &
    done
    wait || true
    for id in "${serial[@]}"; do run_one "$id" > "$LOGS_DIR/$id.log" 2>&1 || true; done
  fi
  # summary in the order asked, the log of each failed check after it
  [ "$JOBS" -le 1 ] || [ $# -le 1 ] || echo "---"
  for id in "$@"; do
    if [ ! -f "$LOGS_DIR/$id.result" ]; then
      printf '%-10s %-8s\n' "$id" "NO RESULT"; failed+=("$id"); continue
    fi
    [ "$JOBS" -le 1 ] || [ $# -le 1 ] || cat "$LOGS_DIR/$id.result"
    if ! grep -q ' PASS ' "$LOGS_DIR/$id.result"; then
      failed+=("$id")
      if [ "$JOBS" -gt 1 ] && [ $# -gt 1 ]; then
        echo "    --- ${LOGS_DIR#"$REPO_DIR"/}/$id.log (last 40 lines)"
        tail -n 40 "$LOGS_DIR/$id.log" | sed 's/^/    | /'
      fi
    fi
  done
  for id in "$@"; do cat "$LOGS_DIR/$id.time" 2>/dev/null; done > "$LOGS_DIR/timings.txt"
  n=$#
  echo "---"
  if [ ${#failed[@]} -eq 0 ]; then
    echo "all $n check(s) passed"
    return 0
  fi
  echo "${#failed[@]}/$n failed: ${failed[*]}"
  return 1
}

done_ids() { grep -vE '^\s*(#|$)' "$DONE_LIST" | awk '{print $1}'; }

JOBS=$(( $(nproc) / 2 ))
[ "$JOBS" -le 4 ] || JOBS=4
[ "$JOBS" -ge 1 ] || JOBS=1
if [ "${1:-}" == "-j" ]; then
  [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || usage
  JOBS=$2; shift 2
fi

[ $# -ge 1 ] || usage

case "$1" in
  -h|--help) usage ;;
  selftest)  TEST_ID=selftest exec bash "$TESTS_DIR/selftest.sh" ;;
  golden)    # golden matrix (P3-25): tests/run.sh golden [all|CASE...]
             shift; [ "${1:-all}" != all ] || set --
             mkdir -p "$LOGS_DIR"
             docker build -q -t izpbx-asterisk:golden "$REPO_DIR/izpbx-asterisk" > "$LOGS_DIR/image-build.log" 2>&1 ||
               { echo "image build failed (${LOGS_DIR#"$REPO_DIR"/}/image-build.log)"; exit 1; }
             exec "$TESTS_DIR/golden/compare.sh" izpbx-asterisk:golden "$LOGS_DIR/golden" "$@" ;;
  all)       mapfile -t ids < <(find "$CHECKS_DIR" -name '*.sh' -printf '%f\n' | sed 's/\.sh$//' | sort -V)
             run_many "${ids[@]}" ;;
  all-done)  # regression run: reuse fixtures whose inputs did not change
             export TEST_REUSE_FIXTURES=1 TEST_REGRESSION=1
             mapfile -t ids < <(done_ids)
             [ ${#ids[@]} -gt 0 ] || { echo "no items in $DONE_LIST"; exit 0; }
             deferred=()
             if [ -z "${TEST_INCLUDE_DEFERRED:-}" ] && [ -f "$DEFERRED_LIST" ]; then
               mapfile -t deferred < <(grep -vE '^(#|$)' "$DEFERRED_LIST")
               kept=()
               for id in "${ids[@]}"; do
                 [[ " ${deferred[*]} " == *" $id "* ]] || kept+=("$id")
               done
               ids=("${kept[@]}")
             fi
             [ ${#deferred[@]} -eq 0 ] || echo "deferred (not run, TEST_INCLUDE_DEFERRED=1 to run them): ${deferred[*]}"
             run_many "${ids[@]}" ;;
  *)         run_many "$@" ;;
esac
