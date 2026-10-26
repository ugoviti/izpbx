#!/usr/bin/env bash
# P6-08: the weekly job "migration from every 20.16.x" (.gitea/workflows/migration-matrix.yml).
# - its matrix has one entry per 20.16.x release tag, computed at run time:
#   the "20.16.x release tags" step, run as written in the workflow, on a
#   scratch repository (prereleases, dev and 22.17 tags left out) and on this
#   repository (as many entries as `git tag -l '20.16.*'` release tags);
# - each entry runs izpbx-asterisk/tests/ci/checks/MIGRATE.sh; here on 20.16.22: result ok;
#   broken on purpose (MIGRATE_BREAK=1): the check fails, result "failed"
#   with the difference the verification M7 found;
# - the report (izpbx-asterisk/tests/ci/migration-report.sh) makes the table version ->
#   result: green with ok and blocked, red with a failed version or an
#   expected version without result; the table goes in the Matrix
#   notification (details of matrix-notify), sent also when a job failed.
source "$(dirname "$0")/../lib.sh"
wf="$REPO_DIR/.gitea/workflows/migration-matrix.yml"
report="$REPO_DIR/izpbx-asterisk/tests/ci/migration-report.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

assert_cmd "weekly schedule" -- grep -qE "^    - cron: '0 4 \* \* 2'$" "$wf"
assert_cmd "the matrix comes from the versions job" -- grep -qF 'version: ${{ fromJSON(needs.versions.outputs.list) }}' "$wf"
assert_cmd "a failed version does not stop the others" -- grep -qE '^      fail-fast: false$' "$wf"
assert_cmd "each entry runs MIGRATE in DinD" -- grep -qF 'TEST_CHECKS_DIR=izpbx-asterisk/tests/ci/checks izpbx-asterisk/tests/ci/dind-run.sh "$IMAGE" MIGRATE' "$wf"
assert_cmd "the report runs always and notifies the table" -- grep -qF 'details: ${{ steps.table.outputs.table }}' "$wf"
assert_cmd "matrix-notify takes the details" -- grep -qE '^  details:$' "$REPO_DIR/.gitea/actions/matrix-notify/action.yml"

# --- the versions step, as written in the workflow
awk '/- name: 20.16.x release tags/ {s = 1} s && /^  [a-z]+:$/ {exit} s && r {print substr($0, 11)} s && /run: \|/ {r = 1}' "$wf" > "$work/tags.sh"
assert_cmd "the versions step is found" -- grep -q 'git tag --list' "$work/tags.sh"
versions() { # repository -> the step outputs
  : > "$work/out"
  (cd "$1" && GITHUB_OUTPUT="$work/out" bash "$work/tags.sh" >/dev/null 2>&1) || return 1
  cat "$work/out"
}
r="$work/repo"; g=(git -C "$r")
mkdir -p "$r" && "${g[@]}" init -q && "${g[@]}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
for t in 20.16.0 20.16.10 20.16.2 20.16.3-rc1 dev-20.16 22.17.0; do "${g[@]}" tag "$t"; done
"${g[@]}" remote add origin "$r"
assert_eq 'list=["20.16.0","20.16.2","20.16.10"]' "$(versions "$r" | grep '^list=')" "scratch repository: the release tags in version order, nothing else"
want=$(git -C "$REPO_DIR" tag --list | grep -cE '^20\.16\.[0-9]+$')
assert_eq "count=$want" "$(versions "$REPO_DIR" | grep '^count=')" "this repository: one entry per 20.16.x release tag ($want)"

# --- the report
mkdir -p "$work/res"
res() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$work/res/migrate-$1.txt"; }
res 20.16.10 ok "FreePBX 16 -> 17.0.33"; res 20.16.2 blocked "framework: FreePBX framework 16.0.20 older than 16.0.26"
out=$("$report" "$work/res" 20.16.2 20.16.10) && rc=0 || rc=$?
assert_eq 0 "$rc" "report: ok and blocked are green"
assert_eq "20.16.2 20.16.10" "$(awk 'NR <= 2 {print $1}' <<< "$out" | tr '\n' ' ' | sed 's/ $//')" "report: version order"
assert_contains "$out" "summary: 2 version(s): 1 ok, 1 blocked with instructions, 0 failed or missing" "report: the summary"
assert_cmd_fails "report: an expected version without result is red" -- "$report" "$work/res" 20.16.2 20.16.10 20.16.22
assert_contains "$("$report" "$work/res" 20.16.2 20.16.10 20.16.22 || true)" "20.16.22  missing" "report: listed as missing"
res 20.16.0 failed "verification M7: extensions: - extension=1003"
assert_cmd_fails "report: a failed version is red" -- "$report" "$work/res" 20.16.0 20.16.2 20.16.10

# --- MIGRATE on 20.16.22, then broken on purpose
migrate() { # [MIGRATE_BREAK value] -> exit status of the check; result in $work/m.txt
  MIGRATE_VERSION=20.16.22 MIGRATE_BREAK=${1:-} MIGRATE_RESULT="$work/m.txt" TEST_CHECKS_DIR="$REPO_DIR/izpbx-asterisk/tests/ci/checks" \
    TEST_LOGS_DIR="$work/logs" "$TESTS_DIR/run.sh" MIGRATE >/dev/null 2>&1
}
assert_cmd "MIGRATE 20.16.22 passes" -- migrate
assert_cmd "MIGRATE 20.16.22: result ok" -- grep -qP '^20\.16\.22\tok\tFreePBX 16 -> 17' "$work/m.txt"
assert_cmd_fails "negative: MIGRATE 20.16.22 broken on purpose fails" -- migrate 1
log "broken: $(cat "$work/m.txt")"
assert_cmd "negative: result failed with the difference of the verification M7" -- grep -qP '^20\.16\.22\tfailed\tbroken on purpose \(break_version\): verification M7: extensions: - extension=1003' "$work/m.txt"
finish
