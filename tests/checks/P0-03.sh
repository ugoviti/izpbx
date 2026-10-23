#!/usr/bin/env bash
# P0-03: shellcheck + hadolint are clean on the repository, fail on bad
# input, and block a commit through the pre-commit hook.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

lint() { "$TESTS_DIR/lint.sh" "$@" >"$work/lint.log" 2>&1; }

assert_cmd "lint is clean on the repository" -- lint "$REPO_DIR"

# control: an empty tree with a clean script and Dockerfile passes
mkdir -p "$work/ok/tests"
printf '#!/bin/bash\necho "hello"\n' > "$work/ok/tests/good.sh"
printf 'FROM debian:bookworm-slim\nCOPY good.sh /\n' > "$work/ok/Dockerfile"
assert_cmd "lint passes on a clean tree" -- lint "$work/ok"

# negative: a shell script with a shellcheck error
mkdir -p "$work/badsh/tests"
printf '#!/bin/bash\nfor x in $@; do echo "$x"; done\n' > "$work/badsh/tests/bad.sh"
assert_cmd_fails "lint fails on a shellcheck error" -- lint "$work/badsh"
assert_contains "$(cat "$work/lint.log")" "SC2068" "shellcheck finding is reported"

# negative: a Dockerfile with a hadolint error
mkdir -p "$work/baddf"
printf 'FROM debian:bookworm-slim\nADD good.sh /\n' > "$work/baddf/Dockerfile"
assert_cmd_fails "lint fails on a hadolint error" -- lint "$work/baddf"
assert_contains "$(cat "$work/lint.log")" "DL3020" "hadolint finding is reported"

# the pre-commit hook blocks a commit that adds a bad script
clone="$work/clone"
git clone -q --no-hardlinks "$REPO_DIR" "$clone"
# test the working tree as it is now, not the last commit
git -C "$REPO_DIR" ls-files -z -co --exclude-standard | tar -C "$REPO_DIR" --null -T - -cf - | tar -C "$clone" -xf -
git -C "$clone" config core.hooksPath .githooks
git -C "$clone" config user.email test@example.invalid
git -C "$clone" config user.name test
git -C "$clone" add -A
assert_cmd "hook lets a clean commit through" -- git -C "$clone" commit -q -m clean
cp "$work/badsh/tests/bad.sh" "$clone/tests/bad.sh"
git -C "$clone" add tests/bad.sh
out=$(git -C "$clone" commit -q -m bad 2>&1) && rc=0 || rc=$?
assert_ne 0 "$rc" "hook blocks a commit with a shellcheck error"
assert_contains "$out" "lint: commit blocked" "hook explains why the commit was blocked"

finish
