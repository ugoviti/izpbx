#!/usr/bin/env bash
# P6-10: weekly check of the component updates (.gitea/workflows/updates.yml),
# offline: the run script of the step "make-updates" executed as Gitea does
# (bash -eo pipefail) with a fake make-updates.sh for each outcome:
# - updates (exit 10): notify, the UPDATE rows, the proposed lines and the
#   apply hint in the message, the job does not fail;
# - new majors only (exit 0 with MAJOR lines): notify, the majors listed;
# - all current: no message from the schedule, one from a run by hand;
# - incomplete (exit 2): notify; error (exit 1): the step fails;
# - the workflow: Monday schedule and workflow_dispatch, never --apply, the
#   GitHub token set explicitly (GH_READ_TOKEN), notify on news or failure.
source "$(dirname "$0")/../lib.sh"

wf="$REPO_DIR/.gitea/workflows/updates.yml"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
awk '/- name: make-updates$/ {s = 1} s && /run: \|/ {r = 1; next} r && /^      - name:/ {exit} r {print substr($0, 11)}' "$wf" > "$work/step.sh"
assert_cmd "the step script is extracted" -- grep -q 'make-updates.sh > report.txt' "$work/step.sh"

scenario() { # name exit-code report-text event -> rc of the step; outputs in $work/<name>.out
  local d="$work/$1"
  mkdir -p "$d/izpbx-asterisk/tools"
  printf '#!/bin/bash\nprintf %%s "%s"\nexit %s\n' "$3" "$2" > "$d/izpbx-asterisk/tools/make-updates.sh"
  chmod +x "$d/izpbx-asterisk/tools/make-updates.sh"
  : > "$work/$1.out"
  (cd "$d" && GITHUB_OUTPUT="$work/$1.out" EVENT=$4 GITHUB_TOKEN='' bash -eo pipefail "$work/step.sh" > "$work/$1.log" 2>&1)
}
out() { sed -n "s/^$2=//p" "$work/$1.out"; }
msg() { sed -n '/^message<<IZPBX_EOF$/,/^IZPBX_EOF$/p' "$work/$1.out"; }

upd='DEBIAN_IMAGE           sha256:a  sha256:b  UPDATE
ASTERISK_VER           22.11.0  22.12.0  UPDATE
FREEPBX_VER            17  17  ok

new major releases (a new izPBX series: not proposed, not applied):
MAJOR ASTERISK 24.0.0 LTS

2 update(s) available, proposed versions.env lines:
  ASTERISK_VER=22.12.0
  ASTERISK_SHA256=abc
'
scenario updates 10 "$upd" schedule && rc=0 || rc=$?
assert_eq 0 "$rc" "updates: the job does not fail"
assert_eq "updates true 1" "$(out updates status) $(out updates notify) $(out updates majors)" "updates: status, notify, one major"
m=$(msg updates)
assert_contains "$m" "ASTERISK_VER           22.11.0  22.12.0  UPDATE" "updates: the UPDATE rows"
assert_contains "$m" "  ASTERISK_VER=22.12.0" "updates: the proposed lines"
assert_contains "$m" "  ASTERISK 24.0.0 LTS" "updates: the new major"
assert_contains "$m" "make-updates.sh --apply" "updates: how to apply"
assert_cmd_fails "updates: the ok rows are not in the message" -- grep -q ' ok$' <<< "$m"

scenario majors 0 $'ASTERISK_VER  22.12.0  22.12.0  ok\n\nnew major releases (a new izPBX series: not proposed, not applied):\nMAJOR ASTERISK 24.0.0 LTS\nMAJOR FREEPBX 18 mirror.freepbx.org\n\nall components are current\n' schedule && rc=0 || rc=$?
assert_eq "0 current true 2" "$rc $(out majors status) $(out majors notify) $(out majors majors)" "new majors only: notify, two majors"
assert_contains "$(msg majors)" "  FREEPBX 18 mirror.freepbx.org" "new majors only: FreePBX listed"
assert_cmd_fails "new majors only: no apply hint" -- grep -q -- '--apply' <<< "$(msg majors)"

scenario current 0 $'ASTERISK_VER  22.12.0  22.12.0  ok\n\nall components are current\n' schedule && rc=0 || rc=$?
assert_eq "0 current false 0" "$rc $(out current status) $(out current notify) $(out current majors)" "all current from the schedule: no message"
scenario byhand 0 $'ASTERISK_VER  22.12.0  22.12.0  ok\n\nall components are current\n' workflow_dispatch && rc=0 || rc=$?
assert_eq "0 true" "$rc $(out byhand notify)" "all current by hand: a message"
assert_contains "$(msg byhand)" "all components are current" "all current by hand: says so"

scenario incomplete 2 $'IZSYNTH_VER  1.0  ?  unavailable (GitHub API)\n' schedule && rc=0 || rc=$?
assert_eq "0 incomplete true" "$rc $(out incomplete status) $(out incomplete notify)" "incomplete: notify, the job does not fail"
assert_contains "$(msg incomplete)" "unavailable (GitHub API)" "incomplete: the unavailable rows"
scenario error 1 'unknown option' schedule && rc=0 || rc=$?
assert_ne 0 "$rc" "error: the step fails"
assert_eq "error true" "$(out error status) $(out error notify)" "error: status error, notify"

# --- the workflow
assert_cmd "Monday schedule" -- grep -qF "cron: '0 6 * * 1'" "$wf"
assert_cmd "run by hand" -- grep -qE '^  workflow_dispatch:' "$wf"
assert_cmd_fails "never --apply" -- grep -qE 'make-updates\.sh[^#]*--apply' <(grep -v '^ *#\|echo ' "$wf")
assert_cmd "GitHub token set explicitly (never the forge token)" -- grep -qF 'GITHUB_TOKEN: ${{ secrets.GH_READ_TOKEN }}' "$wf"
assert_cmd "notify on news or failure" -- grep -qF "if: always() && (steps.check.outputs.notify == 'true' || failure())" "$wf"

finish
