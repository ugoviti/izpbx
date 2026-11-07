#!/usr/bin/env bash
# P6-11: unattended release of the component updates,
# izpbx-asterisk/tools/make-auto-release.sh, offline: a test repository (the
# real make-release.sh and make-auto-release.sh, a fake make-updates.sh), a
# bare repository as origin, TESTS_CMD instead of the real tests.
# - all current: exit 3, no commit, no tag;
# - tests failed: exit 1, versions.env restored, no commit, no tag;
# - make-updates.sh error: exit 1, nothing applied;
# - wrong branch: refused before make-updates.sh runs;
# - released: commit "updates: ASTERISK_VER 22.11.0 -> 22.12.0", commit
#   "22.17.1 release", tag 22.17.1 pushed with main; the CHANGELOG entry has
#   the component line and never a draft of the commit subjects; default.env
#   moves to 22.17.1;
# - repeatable: two runs from the same start give the same tree;
# - updates.yml: the job release after check (only on updates), the tests
#   before the release, RELEASE_PUSH_TOKEN, never Docker Hub nor izpbx-promote.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
src="$REPO_DIR/izpbx-asterisk/tools"
deploy=izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy

# --- the start: origin with tag 22.17.0 (Asterisk 22.11.0), an empty Unreleased
seed="$work/seed"
mkdir -p "$seed/izpbx-asterisk/tools" "$seed/izpbx-asterisk/build" "$seed/$deploy"
cp "$src/make-release.sh" "$src/make-auto-release.sh" "$seed/izpbx-asterisk/tools/"
cat > "$seed/izpbx-asterisk/tools/make-updates.sh" <<'EOF'
#!/bin/bash
# fake: FAKE_UPDATES=1 moves Asterisk to 22.12.0; FAKE_RC is the exit code
touch "${FAKE_MARK:-/dev/null}"
v="$(dirname "$0")/../versions.env"
[ -z "${FAKE_UPDATES:-}" ] || sed -i -e 's/^ASTERISK_VER=.*/ASTERISK_VER=22.12.0/' -e "s/^ASTERISK_SHA256=.*/ASTERISK_SHA256=$(printf 'b%.0s' {1..64})/" "$v"
exit "${FAKE_RC:-0}"
EOF
chmod +x "$seed/izpbx-asterisk/tools/"*.sh
printf 'ASTERISK_VER=22.11.0\nASTERISK_SHA256=%s\nFREEPBX_VER=17\n' "$(printf 'a%.0s' {1..64})" > "$seed/izpbx-asterisk/versions.env"
printf 'core 17.0.1 %s\n' "$(printf 'c%.0s' {1..64})" > "$seed/izpbx-asterisk/build/freepbx-modules.txt"
printf 'IZPBX_VERSION=22.17.0\n' > "$seed/$deploy/default.env"
printf 'FROM docker.io/library/debian:bookworm-slim@sha256:%s AS base\n' "$(printf 'd%.0s' {1..64})" > "$seed/izpbx-asterisk/Dockerfile"
printf '# Changelog\n\n## [Unreleased]\n\n## [22.17.0] - 2026-10-30\n### Changed\n- FreePBX 17\n' > "$seed/CHANGELOG.md"
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
git init -q -b main "$seed"
g "$seed" add -A && g "$seed" commit -q -m "22.17.0 release" && g "$seed" tag -a -m t 22.17.0
g "$seed" commit -q --allow-empty -m "a commit subject that must not reach the CHANGELOG"
git clone -q --bare "$seed" "$work/origin.git"

clone() { # name -> a clone of origin on main, identity set
  git clone -q "$work/origin.git" "$work/$1"
  git -C "$work/$1" config user.name t; git -C "$work/$1" config user.email t@t
}
auto() { # clone args... -> exit code; output in $work/<clone>.out
  local c=$1; shift
  (cd "$work/$c" && FAKE_MARK="$work/$c.mark" izpbx-asterisk/tools/make-auto-release.sh "$@") > "$work/$c.out" 2>&1
}
ntags() { git -C "$work/$1" tag | grep -c . || true; }

# --- all current
clone current
auto current && rc=0 || rc=$?
assert_eq 3 "$rc" "all current: exit 3"
assert_eq "1 $(git -C "$work/seed" rev-parse HEAD)" "$(ntags current) $(git -C "$work/current" rev-parse HEAD)" "all current: no commit, no tag"

# --- tests failed
clone failed
FAKE_UPDATES=1 TESTS_CMD=false auto failed && rc=0 || rc=$?
assert_eq 1 "$rc" "tests failed: exit 1"
assert_contains "$(cat "$work/failed.out")" "tests failed: updates not released" "tests failed: said so"
assert_cmd "tests failed: versions.env restored" -- git -C "$work/failed" diff --quiet
assert_eq "1 $(git -C "$work/seed" rev-parse HEAD)" "$(ntags failed) $(git -C "$work/failed" rev-parse HEAD)" "tests failed: no commit, no tag"

# --- make-updates.sh error
clone uerr
FAKE_UPDATES=1 FAKE_RC=1 TESTS_CMD=true auto uerr && rc=0 || rc=$?
assert_eq 1 "$rc" "make-updates.sh error: exit 1"
assert_cmd "make-updates.sh error: nothing applied" -- git -C "$work/uerr" diff --quiet

# --- wrong branch: refused before make-updates.sh
clone branch
git -C "$work/branch" checkout -q -b feature/x
FAKE_UPDATES=1 TESTS_CMD=true auto branch && rc=0 || rc=$?
assert_eq 1 "$rc" "wrong branch: exit 1"
assert_contains "$(cat "$work/branch.out")" "is released from 'main'" "wrong branch: the reason"
assert_cmd_fails "wrong branch: make-updates.sh not run" -- test -e "$work/branch.mark"

# --- released, twice from the same start
for c in rel1 rel2; do
  clone "$c"
  FAKE_UPDATES=1 TESTS_CMD=true auto "$c" --push && rc=0 || rc=$?
  assert_eq 0 "$rc" "$c: released (exit 0)"
  [ "$c" == rel1 ] || break
  # the second run starts from the same origin as the first
  rm -rf "$work/origin.git"; git clone -q --bare "$seed" "$work/origin.git"
done
r="$work/rel1"
assert_eq "22.17.1 release
updates: ASTERISK_VER 22.11.0 -> 22.12.0" "$(git -C "$r" log -2 --format=%s)" "the two commits"
assert_eq "22.17.1" "$(git -C "$r" describe --tags --exact-match HEAD)" "tag 22.17.1 on the release commit"
cl=$(cat "$r/CHANGELOG.md")
assert_contains "$cl" "## [22.17.1] - $(date +%F)" "CHANGELOG: the dated entry"
assert_contains "$cl" '- Updated PBX engine to Asterisk `22.12.0` LTS' "CHANGELOG: the component line"
assert_cmd_fails "CHANGELOG: no draft of the commit subjects" -- grep -q 'must not reach' "$r/CHANGELOG.md"
assert_eq "IZPBX_VERSION=22.17.1" "$(cat "$r/$deploy/default.env")" "default.env moved to 22.17.1"
assert_eq "22.17.1" "$(git -C "$work/rel2" ls-remote --tags origin 22.17.1 | sed 's#.*refs/tags/##')" "the tag pushed to origin"
assert_eq "$(git -C "$work/rel2" rev-parse HEAD)" "$(git -C "$work/rel2" rev-parse origin/main)" "main pushed to origin"
assert_eq "$(git -C "$r" rev-parse 'HEAD^{tree}')" "$(git -C "$work/rel2" rev-parse 'HEAD^{tree}')" "repeatable: two runs give the same tree"

# --- the workflow
wf="$REPO_DIR/.gitea/workflows/updates.yml"
job=$(awk '/^  release:$/ {s = 1} s' "$wf")
assert_cmd "job release after check, only on updates" -- grep -qF "if: needs.check.outputs.status == 'updates'" <<< "$job"
assert_cmd "job release pushes with RELEASE_PUSH_TOKEN" -- grep -qF 'token: ${{ secrets.RELEASE_PUSH_TOKEN }}' <<< "$job"
order=$(grep -oE 'make-auto-release\.sh (apply|release --push)|dind-run\.sh "\$IMAGE" -j 4 all-done' <<< "$job" | tr '\n' '|')
assert_eq 'make-auto-release.sh apply|dind-run.sh "$IMAGE" -j 4 all-done|make-auto-release.sh release --push|' "$order" "apply, tests, release in this order"
assert_cmd_fails "never Docker Hub nor izpbx-promote" -- grep -qiE 'dockerhub|docker\.io/izdock|promote\.yml' <(grep -v '^ *#' "$wf")

finish
