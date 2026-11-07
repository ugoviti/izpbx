#!/bin/bash
# Unattended release of the component updates: the same steps by hand and in
# CI (.gitea/workflows/updates.yml), no choice and no AI in between.
#
#   izpbx-asterisk/tools/make-auto-release.sh [--push]    apply, tests, release (all three)
#   izpbx-asterisk/tools/make-auto-release.sh apply       make-updates.sh --apply only
#   izpbx-asterisk/tools/make-auto-release.sh release [--push]
#                                                         commit the applied updates and release
#
# apply: on a clean tree, on the branch of the release (release/X.Y when it
#   exists, else main) not behind origin, izpbx-asterisk/tools/make-updates.sh --apply. A lookup unavailable upstream
#   (exit 2) does not stop it: what was found is verified and applied, the rest
#   waits for the next run.
# tests: izpbx-asterisk/tests/run.sh all-done (TESTS_CMD replaces it, eg. CI);
#   a failure restores versions.env, build/freepbx-modules.txt and the
#   Dockerfile (FROM line of the base image): nothing
#   committed, nothing released.
# release: one commit "updates: <KEY old -> new, ...>" of those files, then make-release.sh --auto: the CHANGELOG entry
#   is the Unreleased block written by hand plus the component lines (no
#   draft), CHANGELOG.md and the version references moved, commit "X.Y.Z
#   release", tag X.Y.Z. --push pushes the branch and the tag: the tag starts
#   izpbx-release (Gitea registry only). Docker Hub stays izpbx-promote, by hand.
#
# Exit code: 0 released (apply: updates applied), 3 nothing to release (all
# components current), 1 error or tests failed.

set -Eeuo pipefail
die() { echo "auto-release: ERROR: $*" >&2; exit 1; }
log() { echo "auto-release: $*" >&2; }

step=all push=''
while [ $# -gt 0 ]; do
  case "$1" in
    apply|release) step=$1 ;;
    --push) push=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

root=$(git rev-parse --show-toplevel) || die "not in a git repository"
cd "$root"
tools=izpbx-asterisk/tools
files=(izpbx-asterisk/versions.env izpbx-asterisk/build/freepbx-modules.txt izpbx-asterisk/Dockerfile)
restore() { local f; f=$(git ls-files -- "${files[@]}"); [ -z "$f" ] || git checkout -q -- $f; }

applied() { ! git diff --quiet -- "${files[@]}"; }

do_apply() {
  # what make-release.sh requires, checked before hours of tests
  local rc=0 branch series want
  if ! git diff --quiet || ! git diff --cached --quiet; then die "uncommitted changes: commit or stash them first"; fi
  git fetch -q --tags origin || die "git fetch --tags origin failed"
  branch=$(git rev-parse --abbrev-ref HEAD)
  # shellcheck disable=SC1090
  series=$(set -a; . "./${files[0]}"; echo "${ASTERISK_VER%%.*}.$FREEPBX_VER")
  want=main
  git show-ref -q --verify "refs/heads/release/$series" && want="release/$series"
  git show-ref -q --verify "refs/remotes/origin/release/$series" && want="release/$series"
  [ "$branch" == "$want" ] || die "$series is released from '$want', current branch is '$branch'"
  ! git show-ref -q --verify "refs/remotes/origin/$branch" || git merge-base --is-ancestor "origin/$branch" HEAD ||
    die "$branch is behind or diverged from origin/$branch: pull first"
  "$tools/make-updates.sh" --apply || rc=$?
  case "$rc" in
    0) ;;
    2) log "some lookups were unavailable: the updates found are applied, the others wait for the next run" ;;
    *) restore; die "make-updates.sh --apply failed (exit $rc): nothing applied" ;;
  esac
  if ! applied; then log "all components current: nothing to release"; exit 3; fi
  log "updates applied: $(summary)"
}

# "KEY old -> new, ..." of versions.env (no checksums) and the modules, from the diff
summary() {
  local s
  s=$(git diff -U0 -- izpbx-asterisk/versions.env | awk '
    function short(v) { return v ~ /^sha256:/ ? substr(v, 1, 19) : (v ~ /^[0-9a-f]{40}$/ ? substr(v, 1, 12) : v) }
    /^[-+][A-Z0-9_]+=/ && !/_SHA256/ {
      k = substr($0, 2, index($0, "=") - 2); v = substr($0, index($0, "=") + 1); sub(/^.*@/, "", v)
      if (/^-/) old[k] = v; else { new[k] = v; order[++n] = k }
    }
    END { for (i = 1; i <= n; i++) { k = order[i]; printf "%s%s %s -> %s", (i > 1 ? ", " : ""), k, short(old[k]), short(new[k]) } }')
  local m
  m=$(git diff -U0 -- izpbx-asterisk/build/freepbx-modules.txt | grep -cE '^\+[a-z0-9]' || true)
  [ "$m" -eq 0 ] || s+="${s:+, }$m FreePBX module(s)"
  echo "$s"
}

do_tests() {
  log "tests: ${TESTS_CMD:-izpbx-asterisk/tests/run.sh all-done}"
  if [ -n "${TESTS_CMD:-}" ]; then bash -c "$TESTS_CMD" && return 0
  else izpbx-asterisk/tests/run.sh all-done && return 0; fi
  restore
  die "tests failed: updates not released, the component files restored"
}

do_release() {
  applied || die "no applied updates to release (run: $0 apply)"
  # only the component files may be changed: the rest of the tree is clean
  if ! git diff --quiet -- . "${files[@]/#/:!}" || ! git diff --cached --quiet; then
    die "uncommitted changes besides the component files"
  fi
  local msg
  msg="updates: $(summary)"
  git add -- "${files[@]}"
  git commit -q -m "$msg"
  log "commit $(git rev-parse --short HEAD) $(git log -1 --format=%s)"
  if [ -n "$push" ]; then "$tools/make-release.sh" --auto --push
  else "$tools/make-release.sh" --auto --commit; fi
}

case "$step" in
  apply) do_apply ;;
  release) do_release ;;
  all) do_apply; do_tests; do_release ;;
esac
