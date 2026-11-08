#!/bin/bash
# The Gitea copy of the pinned gitleaks release (linux x64 tarball).
#
#   izpbx-asterisk/tools/gitleaks-mirror.sh [--fetch DIR]
#
# Version and sha256: GITLEAKS_VERSION / GITLEAKS_SHA256 of
# .gitea/actions/gitleaks/action.yml. The CI (that action) and the local hook
# .githooks/pre-commit read the tarball from the Gitea generic package
# "gitleaks" of the owner of the repository, GitHub only when it is missing:
# an outage of the GitHub release downloads (HTTP 504) failed izpbx-promote.
#
# No argument: uploads the release to Gitea, run it after every change of
# GITLEAKS_VERSION (the tarball comes from GitHub and is checked with the
# sha256 before the upload; a copy already there is checked and kept).
# --fetch DIR: the tarball verified in DIR (Gitea copy, else GitHub), prints
# its path (the local hook).
# Environment:
#   GITEA_URL    web URL of Gitea (default: the server of the remote origin)
#   GITEA_OWNER  owner of the package (default: the owner of the remote origin)
#   GITEA_TOKEN  token with package access (default: the content of
#                ${XDG_CONFIG_HOME:-~/.config}/izpbx-ci/gitea-token); without
#                one --fetch uses GitHub only

set -Eeuo pipefail
die() { echo "gitleaks-mirror: ERROR: $*" >&2; exit 1; }
usage() { sed -n '4p' "$0" | sed 's/^# \{0,1\}/usage: /' >&2; exit 2; }

fetch=
case "${1:-}" in
  --fetch) fetch=${2:-}; [ -n "$fetch" ] || usage ;;
  "") ;;
  *) usage ;;
esac

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
action="$root/.gitea/actions/gitleaks/action.yml"
wf_env() { sed -n "s/^ *$1: *//p" "$action" | head -1 | tr -d "'\" "; }
ver=$(wf_env GITLEAKS_VERSION)
sha=$(wf_env GITLEAKS_SHA256)
[ -n "$ver" ] && [ -n "$sha" ] || die "no GITLEAKS_VERSION/GITLEAKS_SHA256 in $action"
tgz="gitleaks_${ver}_linux_x64.tar.gz"
github="https://github.com/gitleaks/gitleaks/releases/download/v${ver}/${tgz}"

# server and owner from the remote origin: https://host/owner/repo(.git) or git@host:owner/repo
origin=$(git -C "$root" remote get-url origin 2>/dev/null || true)
case "$origin" in
  http://*|https://*) o_url=$(sed -E 's#^(https?://[^/]+)/.*#\1#' <<< "$origin"); o_owner=$(sed -E 's#^https?://[^/]+/([^/]+)/.*#\1#' <<< "$origin") ;;
  *@*:*) o_url="https://$(sed -E 's#^[^@]+@([^:]+):.*#\1#' <<< "$origin")"; o_owner=$(sed -E 's#^[^:]+:([^/]+)/.*#\1#' <<< "$origin") ;;
  *) o_url='' o_owner='' ;;
esac
url=${GITEA_URL:-$o_url}
owner=${GITEA_OWNER:-$o_owner}
token=${GITEA_TOKEN:-}
tokfile="${XDG_CONFIG_HOME:-$HOME/.config}/izpbx-ci/gitea-token"
[ -n "$token" ] || [ ! -r "$tokfile" ] || token=$(tr -d '[:space:]' < "$tokfile")
pkg="${url}/api/packages/${owner}/generic/gitleaks/${ver}/${tgz}"

verified() { echo "$sha  $1" | sha256sum -c --quiet - >/dev/null 2>&1; }
from_gitea() { # $1 = file; false without a token or a copy
  [ -n "$url" ] && [ -n "$owner" ] && [ -n "$token" ] || return 1
  curl -fsSL --max-time 120 -H "Authorization: token $token" -o "$1" "$pkg" 2>/dev/null
}
# GitHub: the release download URL, else the same asset through the API (the
# download URL answered 504 for hours while the API served the asset)
from_github() {
  curl -fsSL --retry 2 --retry-all-errors --retry-delay 10 -o "$1" "$github" && return 0
  local id
  id=$(curl -fsSL --retry 2 "https://api.github.com/repos/gitleaks/gitleaks/releases/tags/v${ver}" |
    jq -r --arg n "$tgz" '.assets[] | select(.name == $n) | .id') && [ -n "$id" ] || return 1
  curl -fsSL --retry 2 --retry-all-errors --retry-delay 10 -H 'Accept: application/octet-stream' \
    -o "$1" "https://api.github.com/repos/gitleaks/gitleaks/releases/assets/${id}"
}

if [ -n "$fetch" ]; then
  mkdir -p "$fetch"
  f="$fetch/$tgz"
  if from_gitea "$f" && verified "$f"; then :; else
    echo "gitleaks: downloading v$ver from GitHub..." >&2
    from_github "$f" || die "cannot download $github"
    verified "$f" || { rm -f "$f"; die "$tgz: sha256 mismatch"; }
  fi
  echo "$f"
  exit 0
fi

[ -n "$url" ] && [ -n "$owner" ] || die "no Gitea URL/owner (remote origin, or GITEA_URL and GITEA_OWNER)"
[ -n "$token" ] || die "no token (GITEA_TOKEN or $tokfile)"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
if from_gitea "$work/$tgz"; then
  verified "$work/$tgz" || die "the Gitea copy of $tgz does not match the sha256 of action.yml: delete the package version gitleaks $ver and run again"
  echo "gitleaks $ver: the Gitea copy is there and verified"
  exit 0
fi
from_github "$work/$tgz" || die "cannot download $github"
verified "$work/$tgz" || die "$tgz from GitHub: sha256 mismatch"
code=$(curl -sS --max-time 300 -H "Authorization: token $token" -o "$work/resp" -w '%{http_code}' \
  --upload-file "$work/$tgz" "$pkg") || die "upload failed"
[ "$code" == 201 ] || die "upload: HTTP $code $(head -c 300 "$work/resp")"
from_gitea "$work/check" && verified "$work/check" || die "the uploaded copy cannot be read back"
echo "gitleaks $ver: uploaded to Gitea and verified"
