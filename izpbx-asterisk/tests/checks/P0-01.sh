#!/usr/bin/env bash
# P0-01: the 22.17 series is developed on main (feature/22.17 was merged and
# removed with 22.17.0): HEAD is main, or a feature/* branch that descends
# from main; never a branch that does not contain main.
set -Eeuo pipefail
cd "$(git rev-parse --show-toplevel)"

branch=$(git rev-parse --abbrev-ref HEAD)
case "$branch" in
  main|feature/*) ;;
  *) echo "FAIL: current branch is '$branch', expected main or feature/*" >&2; exit 1 ;;
esac

if ! git merge-base --is-ancestor main HEAD; then
  echo "FAIL: main is not an ancestor of HEAD" >&2
  exit 1
fi

# Negative check: a commit that does not contain main must be rejected.
root=$(git rev-list --max-parents=0 HEAD | tail -n1)
if [ "$(git rev-parse main)" != "$root" ] && git merge-base --is-ancestor main "$root"; then
  echo "FAIL: ancestry check accepts a commit older than main" >&2
  exit 1
fi

echo "OK: on $branch, based on main"
