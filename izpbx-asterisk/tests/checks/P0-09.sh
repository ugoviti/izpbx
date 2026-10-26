#!/usr/bin/env bash
# P0-09: izpbx-asterisk/tests/run.sh -j N runs the checks in parallel.
# On a set of synthetic checks (TEST_CHECKS_DIR):
# - four 4 s checks with -j 4 finish in less than half the -j 1 time;
# - a "# serial" check never overlaps another one (timestamps of
#   izpbx-asterisk/tests/.logs/timings.txt); control: without the marker it does;
# - a failing check is reported with its log, the summary keeps the order;
# - the izpbx-asterisk image is built once and every check gets it
#   (TEST_IMAGE, t_build_image).
# TEST_P0_09_FULL=1 also measures the real list: -j 4 all-done twice (green)
# and -j 1 all-done, -j 4 under 50% of -j 1.
source "$(dirname "$0")/../lib.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
mk() { # id body [serial]
  { echo '#!/usr/bin/env bash'; [ -n "${3:-}" ] && echo '# serial'; printf '%s\n' "$2"; } > "$work/checks/$1.sh"
}
mkdir -p "$work/checks"
for id in T1 T2 T3 T4; do mk "$id" 'sleep 4'; done
mk S1 'sleep 3' serial
mk F1 'echo "boom-marker from F1" >&2; exit 1'
mk I1 "source '$TESTS_DIR/lib.sh'; t_build_image izpbx-asterisk:p0-09-i1 >/dev/null; echo \"image=\$TEST_IMAGE\"; finish"
mk I2 "source '$TESTS_DIR/lib.sh'; t_build_image izpbx-asterisk:p0-09-i2 >/dev/null; echo \"image=\$TEST_IMAGE\"; finish"
t_on_cleanup "docker rmi izpbx-asterisk:p0-09-i1 izpbx-asterisk:p0-09-i2 >/dev/null 2>&1"

runner() { # logs-dir args...
  local logs=$1; shift
  TEST_CHECKS_DIR="$work/checks" TEST_LOGS_DIR="$logs" "$TESTS_DIR/run.sh" "$@"
}
elapsed() { local s=$SECONDS; "$@" >/dev/null 2>&1 || true; echo $((SECONDS - s)); }
# overlap LOGS ID: 0 if ID ran at the same time as another check
overlap() {
  awk -v id="$2" '{s[$1] = $2; e[$1] = $3}
    END {for (k in s) if (k != id && s[k] < e[id] && s[id] < e[k]) exit 0; exit 1}' "$1/timings.txt"
}

t1=$(elapsed runner "$work/l1" -j 1 T1 T2 T3 T4)
t4=$(elapsed runner "$work/l4" -j 4 T1 T2 T3 T4)
log "synthetic: -j 1 ${t1}s, -j 4 ${t4}s"
assert_cmd "-j 4 takes less than 50% of -j 1 (${t4}s vs ${t1}s)" -- test $((t4 * 2)) -lt "$t1"
assert_eq 4 "$(wc -l < "$work/l4/timings.txt")" "timings.txt has a line per check"

out=$(runner "$work/ls" -j 4 T1 S1 T2 T3 F1 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "a failing check makes the run fail"
assert_contains "$out" "F1         FAIL(1)" "the failing check is in the summary"
assert_contains "$out" "boom-marker from F1" "the log of the failing check is shown"
assert_file "$work/ls/F1.log" "the log of the failing check is kept in the logs dir"
assert_eq "T1 S1 T2 T3 F1" "$(sed -n '/^---$/,$p' <<< "$out" | awk '/^[A-Z][0-9] /{printf "%s%s", sep, $1; sep=" "}')" \
  "summary in the order asked"
assert_cmd_fails "the serial check never runs with another one" -- overlap "$work/ls" S1
sed -i '/^# serial$/d' "$work/checks/S1.sh"
runner "$work/ln" -j 4 T1 S1 T2 >/dev/null 2>&1 || true
assert_cmd "control: without '# serial' it runs with the others" -- overlap "$work/ln" S1

# without the TEST_IMAGE of an outer run (all-done runs this check too): the build path
out=$(TEST_IMAGE='' runner "$work/li" -j 2 I1 I2 2>&1) || true
assert_contains "$out" "built once" "the image is built once for the run"
i1=$(grep -o 'image=.*' "$work/li/I1.log"); i2=$(grep -o 'image=.*' "$work/li/I2.log")
assert_ne "image=" "$i1" "the checks get the image of the run (TEST_IMAGE)"
assert_eq "$i1" "$i2" "both checks use the same image"
assert_eq "$(docker image inspect -f '{{.Id}}' izpbx-asterisk:p0-09-i1)" "$(docker image inspect -f '{{.Id}}' izpbx-asterisk:p0-09-i2)" \
  "t_build_image tags the same image"

if [ -n "${TEST_P0_09_FULL:-}" ]; then
  logs="$TESTS_DIR/.logs"
  s=$SECONDS; "$TESTS_DIR/run.sh" -j 4 all-done > "$work/full4a" 2>&1 && r4a=0 || r4a=$?; f4=$((SECONDS - s))
  "$TESTS_DIR/run.sh" -j 4 all-done > "$work/full4b" 2>&1 && r4b=0 || r4b=$?
  s=$SECONDS; "$TESTS_DIR/run.sh" -j 1 all-done > "$work/full1" 2>&1 && r1=0 || r1=$?; f1=$((SECONDS - s))
  log "all-done: -j 4 ${f4}s, -j 1 ${f1}s"
  echo "$(date -Iseconds) all-done -j 4 ${f4}s, -j 1 ${f1}s" >> "$logs/p0-09-measure.txt"
  assert_eq 0 "$r4a" "all-done -j 4 green (first run)"
  assert_eq 0 "$r4b" "all-done -j 4 green (second run)"
  assert_eq 0 "$r1" "all-done -j 1 green"
  assert_cmd "all-done -j 4 under 50% of -j 1 (${f4}s vs ${f1}s)" -- test $((f4 * 2)) -lt "$f1"
fi
finish
