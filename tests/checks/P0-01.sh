#!/usr/bin/env bash
# P0-01: the working branch is feature/22.17 and it descends from main.
set -Eeuo pipefail
cd "$(git rev-parse --show-toplevel)"

branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != "feature/22.17" ]; then
  echo "FAIL: current branch is '$branch', expected 'feature/22.17'" >&2
  exit 1
fi

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

echo "OK: on feature/22.17, based on main"
