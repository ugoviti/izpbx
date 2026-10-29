#!/bin/bash
# The release page of a version on GitHub or Gitea, from its CHANGELOG.md entry.
#
#   izpbx-asterisk/tools/forge-release.sh [--forge github|gitea] VERSION [--dry-run]
#
# Run in the git repository, after the tag VERSION is on the forge (GitHub:
# izpbx-promote, step "github release"; Gitea: izpbx-release, job "release
# page", or izpbx-release-page by hand). The text is the "## [X.Y.Z] ..." entry
# of the CHANGELOG.md of the tag (for X.Y.Z-rcN the entry of X.Y.Z, usually
# still "Unreleased"), relative links made absolute at the tag, with the image
# and, for a major line, the link to the upgrade guide. Release candidates are
# pre-releases. On GitHub the "Latest" mark goes only to the highest X.Y.Z tag
# (a 20.16.x published after 22.17.0 does not take it; Gitea has no such
# setting). A release that already exists is updated (a rerun never fails on it).
# --dry-run prints the JSON that would be sent, no network.
# Environment:
#   FORGE_TOKEN      token that can write releases (GitHub: Contents: write)
#   FORGE_REPO       owner/repo (default ugoviti/izpbx on GitHub)
#   FORGE_URL        web URL of the forge (default https://github.com; Gitea: required)
#   FORGE_API        API URL (default https://api.github.com, Gitea: FORGE_URL/api/v1)
#   DOCKERHUB_IMAGE  default izdock/izpbx-asterisk
#   PACKAGE_OWNER    Gitea owner of the container package (default the owner of FORGE_REPO)

set -Eeuo pipefail
die() { echo "forge-release: ERROR: $*" >&2; exit 1; }
usage() { sed -n '4p' "$0" | sed 's/^# \{0,1\}/usage: /' >&2; exit 2; }

forge=github
if [ "${1:-}" == --forge ]; then forge=${2:-}; shift 2 || usage; fi
version=${1:-}
dry=false
[ "${2:-}" == --dry-run ] && dry=true
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]] || usage
: "${DOCKERHUB_IMAGE:=izdock/izpbx-asterisk}"
case "$forge" in
  github)
    : "${FORGE_REPO:=ugoviti/izpbx}" "${FORGE_URL:=https://github.com}" "${FORGE_API:=https://api.github.com}"
    blob="${FORGE_URL}/${FORGE_REPO}/blob/${version}" ;;
  gitea)
    [ -n "${FORGE_URL:-}" ] && [ -n "${FORGE_REPO:-}" ] || die "Gitea needs FORGE_URL and FORGE_REPO"
    : "${FORGE_API:=${FORGE_URL}/api/v1}" "${PACKAGE_OWNER:=${FORGE_REPO%%/*}}"
    blob="${FORGE_URL}/${FORGE_REPO}/src/tag/${version}" ;;
  *) usage ;;
esac
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
notes=$(sed -E "s#(\\]\\()($rel)\\)#\\1${blob}/\\2)#g" <<< "$notes")

# image tags as release.yml and izpbx-promote publish them
IFS=. read -r major minor _ <<< "$base"
if $prerelease; then
  tags="\`${version}\`"
else
  tags="\`${version}\`, \`${major}.${minor}\`, \`${major}\`"
fi
if [ "$forge" == gitea ]; then
  footer="---"$'\n'"Image in this registry: ${FORGE_URL}/${PACKAGE_OWNER}/-/packages/container/${DOCKERHUB_IMAGE##*/}/${version} (tags ${tags}); on Docker Hub as \`${DOCKERHUB_IMAGE}:${version}\` once promoted (izpbx-promote)"
else
  footer="---"$'\n'"Docker image: \`docker pull ${DOCKERHUB_IMAGE}:${version}\` (tags ${tags}; https://hub.docker.com/r/${DOCKERHUB_IMAGE}/tags)"
fi
guide=$(git ls-tree -r --name-only "refs/tags/${version}" docs/ 2>/dev/null | grep -E "^docs/upgrade-.*-to-${major}\.${minor}\.md$" | head -1 || true)
[ -n "$guide" ] && footer+=$'\n'"Upgrade guide: ${blob}/${guide}"
$prerelease && notes="**Release candidate** of ${base}: for testing, not for production."$'\n\n'"$notes"

# GitHub "Latest" only for the highest X.Y.Z tag
make_latest=false
if ! $prerelease; then
  top=$(git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
  [ "$top" == "$version" ] && make_latest=true
fi

payload=$(jq -n --arg tag "$version" --arg name "izPBX ${version}" --arg body "$notes"$'\n\n'"$footer" \
  --argjson pre "$prerelease" --arg latest "$make_latest" --arg forge "$forge" \
  '{tag_name: $tag, name: $name, body: $body, draft: false, prerelease: $pre}
   + (if $forge == "github" then {make_latest: $latest} else {} end)')
if $dry; then echo "$payload"; exit 0; fi

[ -n "${FORGE_TOKEN:-}" ] || die "FORGE_TOKEN not set"
if [ "$forge" == github ]; then
  auth="Bearer ${FORGE_TOKEN}" accept='application/vnd.github+json'
else
  auth="token ${FORGE_TOKEN}" accept='application/json'
fi
api() { # method path [data] -> HTTP code, answer in $out (000: forge not reached)
  local args=(-sS --max-time 30 -o "$out" -w '%{http_code}' -X "$1" -H "Authorization: ${auth}" -H "Accept: ${accept}")
  [ "$forge" == github ] && args+=(-H 'X-GitHub-Api-Version: 2022-11-28')
  [ $# -ge 3 ] && args+=(-H 'Content-Type: application/json' --data-binary "$3")
  curl "${args[@]}" "${FORGE_API}/repos/${FORGE_REPO}$2" || true
}
msg() { jq -r '.message // empty' "$out" 2>/dev/null || head -c 200 "$out"; }
out=$(mktemp)
trap 'rm -f "$out"' EXIT
code=$(api GET "/releases/tags/${version}")
case "$code" in
  200) id=$(jq -r .id "$out"); code=$(api PATCH "/releases/${id}" "$payload"); action=updated ;;
  404) code=$(api POST /releases "$payload"); action=created ;;
  *) die "${forge} answered HTTP ${code} reading the release ${version}: $(msg)" ;;
esac
[[ "$code" =~ ^20[01]$ ]] || die "${forge} answered HTTP ${code} writing the release ${version}: $(msg)"
echo "forge-release: ${forge} ${version} ${action} ($(jq -r '.html_url // empty' "$out"); prerelease ${prerelease}$([ "$forge" == github ] && echo ", latest ${make_latest}"))"
