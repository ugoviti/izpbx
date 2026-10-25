#!/usr/bin/env bash
# Image tags of a version (the scheme of .gitea/actions/image-tags), one full
# reference per line. Environment:
#   IMAGES         image names, newline separated
#   VERSION        20.16.22 | 20.16.22-rc1 | dev-22.17 ...
#   BUILD_NUMBER   optional: adds <version>-<build-number>
#   LATEST         true | false | branch (latest only when BRANCH is LATEST_BRANCH)
#   BRANCH, LATEST_BRANCH   for LATEST=branch (V2/V3: latest stays on release/20.16
#                  until the decision Q1)
# Scheme:
#   20.16.22      -> 20.16.22, 20.16, 20 [, 20.16.22-<build>] [, latest]
#   20.16.22-rc1  -> 20.16.22-rc1 [, 20.16.22-rc1-<build>]   (prerelease: never X.Y, X, latest)
#   dev-22.17     -> dev-22.17                               (not semver: as-is, never latest)
set -euo pipefail
: "${IMAGES:?}" "${VERSION:?}"
latest=false
case "${LATEST:-false}" in
  true) latest=true ;;
  branch) [ -n "${BRANCH:-}" ] && [ "$BRANCH" == "${LATEST_BRANCH:-}" ] && latest=true ;;
esac
tags=("$VERSION")
if [[ "$VERSION" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.-]+)?$ ]]; then
  ver=${VERSION#v}
  if [ -z "${BASH_REMATCH[4]}" ]; then
    tags=("$ver" "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}")
  else
    tags=("$ver") latest=false
  fi
  [ -z "${BUILD_NUMBER:-}" ] || tags+=("$ver-$BUILD_NUMBER")
else
  latest=false
fi
[ "$latest" == false ] || tags+=(latest)
while IFS= read -r image; do
  [ -n "$image" ] || continue
  for t in "${tags[@]}"; do printf '%s:%s\n' "$image" "$t"; done
done <<< "$IMAGES"
