#!/bin/bash
# The GitHub release page of a version, from its CHANGELOG.md entry.
#
#   izpbx-asterisk/tools/github-release.sh VERSION [--dry-run]
#
# Run in the git repository, after the tag VERSION is on GitHub (izpbx-promote,
# step "github release"). The text is the "## [X.Y.Z] ..." entry of the
# CHANGELOG.md of the tag (for X.Y.Z-rcN the entry of X.Y.Z, usually still
# "Unreleased"), with the Docker image tags and, for a major line, the link to
# the upgrade guide. Release candidates are GitHub pre-releases. The GitHub
# "Latest" mark goes only to the highest X.Y.Z tag: a 20.16.x published after
# 22.17.0 does not take it. A release that already exists is updated (a rerun
# of the workflow never fails on it).
# --dry-run prints the JSON that would be sent, no network.
# Environment: GH_TOKEN (Contents: write on the repository), PUBLIC_REPO
# (default ugoviti/izpbx), GITHUB_API (default https://api.github.com),
# DOCKERHUB_IMAGE (default izdock/izpbx-asterisk).

set -Eeuo pipefail
die() { echo "github-release: ERROR: $*" >&2; exit 1; }

: "${PUBLIC_REPO:=ugoviti/izpbx}"
: "${GITHUB_API:=https://api.github.com}"
: "${DOCKERHUB_IMAGE:=izdock/izpbx-asterisk}"
version=${1:-}
dry=false
[ "${2:-}" == --dry-run ] && dry=true
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]] || { sed -n '4p' "$0" | sed 's/^# \{0,1\}/usage: /' >&2; exit 2; }
git rev-parse -q --verify "refs/tags/${version}" >/dev/null || die "no git tag ${version}"
base=${version%%-rc*}
prerelease=false
[ "$base" != "$version" ] && prerelease=true

# the entry of the version: from its "## [X.Y.Z]" line to the next "## [" line
changelog=$(git show "refs/tags/${version}:CHANGELOG.md" 2>/dev/null) || die "no CHANGELOG.md in ${version}"
notes=$(awk -v v="$base" '
  index($0, "## [" v "]") == 1 { s = 1; next }
  s && /^## \[/ { exit }
  s { print }' <<< "$changelog")
[ -n "${notes//[[:space:]]/}" ] || die "no \"## [${base}]\" entry in the CHANGELOG.md of ${version}"
# relative links (eg. docs/...) do not resolve on a release page: absolute at the tag
rel='[^):/#[:space:]][^):[:space:]]*'
notes=$(sed -E "s#(\\]\\()($rel)\\)#\\1https://github.com/${PUBLIC_REPO}/blob/${version}/\\2)#g" <<< "$notes")

# image tags as izpbx-promote publishes them
IFS=. read -r major minor _ <<< "$base"
if $prerelease; then
  tags="\`${version}\`"
else
  tags="\`${version}\`, \`${major}.${minor}\`, \`${major}\`"
fi
footer="---"$'\n'"Docker image: \`docker pull ${DOCKERHUB_IMAGE}:${version}\` (tags ${tags}; https://hub.docker.com/r/${DOCKERHUB_IMAGE}/tags)"
guide=$(git ls-tree -r --name-only "refs/tags/${version}" docs/ 2>/dev/null | grep -E "^docs/upgrade-.*-to-${major}\.${minor}\.md$" | head -1 || true)
[ -n "$guide" ] && footer+=$'\n'"Upgrade guide: https://github.com/${PUBLIC_REPO}/blob/${version}/${guide}"
$prerelease && notes="**Release candidate** of ${base}: for testing, not for production."$'\n\n'"$notes"

# "Latest" only for the highest X.Y.Z tag
make_latest=false
if ! $prerelease; then
  top=$(git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
  [ "$top" == "$version" ] && make_latest=true
fi

payload=$(jq -n --arg tag "$version" --arg name "izPBX ${version}" --arg body "$notes"$'\n\n'"$footer" \
  --argjson pre "$prerelease" --arg latest "$make_latest" \
  '{tag_name: $tag, name: $name, body: $body, draft: false, prerelease: $pre, make_latest: $latest}')
if $dry; then echo "$payload"; exit 0; fi

[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN not set"
api() { # method path [data] -> HTTP code, answer in $out (000: GitHub not reached)
  local args=(-sS --max-time 30 -o "$out" -w '%{http_code}' -X "$1"
    -H "Authorization: Bearer ${GH_TOKEN}" -H 'Accept: application/vnd.github+json'
    -H 'X-GitHub-Api-Version: 2022-11-28')
  [ $# -ge 3 ] && args+=(-H 'Content-Type: application/json' --data-binary "$3")
  curl "${args[@]}" "${GITHUB_API}/repos/${PUBLIC_REPO}$2" || true
}
out=$(mktemp)
trap 'rm -f "$out"' EXIT
code=$(api GET "/releases/tags/${version}")
case "$code" in
  200) id=$(jq -r .id "$out"); code=$(api PATCH "/releases/${id}" "$payload"); action=updated ;;
  404) code=$(api POST /releases "$payload"); action=created ;;
  *) die "GitHub answered HTTP ${code} reading the release ${version}: $(jq -r '.message // empty' "$out" 2>/dev/null || head -c 200 "$out")" ;;
esac
[[ "$code" =~ ^20[01]$ ]] || die "GitHub answered HTTP ${code} writing the release ${version}: $(jq -r '.message // empty' "$out" 2>/dev/null || head -c 200 "$out")"
echo "github-release: ${version} ${action} ($(jq -r .html_url "$out"); prerelease ${prerelease}, latest ${make_latest})"
