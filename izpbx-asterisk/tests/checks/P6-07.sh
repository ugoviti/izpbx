#!/usr/bin/env bash
# P6-07: lint (shellcheck, hadolint) and izpbx-asterisk/tests/run.sh all-done in CI.
# - .gitea/workflows/lint.yml runs on every push and pull request the command
#   "izpbx-asterisk/tests/ci/dind-run.sh --lint" (izpbx-asterisk/tests/lint.sh in Docker-in-Docker, as on a
#   containerized runner); tests-22.17.yml has the all-done job on pull
#   requests (and by hand), on the image of the run;
# - the lint command, run as the job does on a copy of the repository: green
#   on the repository, red on the same copy with a shellcheck error added (the
#   PR is blocked: "lint" required in the branch protection).
source "$(dirname "$0")/../lib.sh"
lint_wf="$REPO_DIR/.gitea/workflows/lint.yml"
tests_wf="$REPO_DIR/.gitea/workflows/tests-22.17.yml"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

assert_cmd "lint.yml on pull requests" -- grep -qE '^  pull_request:' "$lint_wf"
assert_cmd "lint.yml on every push" -- grep -qF "      - '**'" "$lint_wf"
assert_cmd "lint.yml runs izpbx-asterisk/tests/ci/dind-run.sh --lint" -- grep -qE '^ +run: izpbx-asterisk/tests/ci/dind-run.sh --lint$' "$lint_wf"
assert_cmd "tests-22.17.yml on pull requests" -- grep -qE '^  pull_request:' "$tests_wf"
assert_cmd "all-done job on pull requests" -- grep -qF "if: github.event_name == 'pull_request' || inputs.all_done == 'true'" "$tests_wf"
assert_cmd "all-done job runs all-done in DinD on the image of the run" -- grep -qF 'izpbx-asterisk/tests/ci/dind-run.sh "$IMAGE" -j 4 all-done' "$tests_wf"

# a checkout of the working tree: the tracked files, committed in a scratch repository
copy() {
  rm -rf "$work/repo" && mkdir -p "$work/repo"
  (cd "$REPO_DIR" && git ls-files -z | tar --null -T - -cf -) | tar -C "$work/repo" -xf -
  local g=(git -C "$work/repo")
  "${g[@]}" init -q && "${g[@]}" add -A && "${g[@]}" -c user.email=t@t -c user.name=t commit -qm pr
}
lint_job() { (cd "$work/repo" && izpbx-asterisk/tests/ci/dind-run.sh --lint) > "$work/lint.out" 2>&1; }
copy
assert_cmd "lint job green on the repository" -- lint_job
tail -n 3 "$work/lint.out" | sed 's/^/    | /' >&2
printf '#!/usr/bin/env bash\necho "$undefined_in_p6_07"\n' > "$work/repo/izpbx-asterisk/tests/p6-07-broken.sh"
git -C "$work/repo" add izpbx-asterisk/tests/p6-07-broken.sh
git -C "$work/repo" -c user.email=t@t -c user.name=t commit -qm "pr with a shellcheck error"
assert_cmd_fails "negative: the PR with a shellcheck error makes the lint job red" -- lint_job
assert_cmd "the finding names the file" -- grep -q 'izpbx-asterisk/tests/p6-07-broken.sh:2:.*SC2154' "$work/lint.out"
finish
