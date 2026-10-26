#!/usr/bin/env bash
# P6-04: tag scheme of the image-tags action (V1-V3). The action computes the
# tags with .gitea/actions/image-tags/tags.sh; the check runs it as the action
# does, latest 'branch' as in release.yml:
# - 22.17.0 on main: 22.17.0, 22.17, 22, 22.17.0-<build>, no latest (V1/V3);
# - 20.16.23 on release/20.16: its tags and latest (V2, until Q1);
# - negative checks: 22.17.0 with latest 'branch' on any other branch, a
#   prerelease (no X.Y, X, latest even when asked) and dev-22.17 (as-is,
#   never latest) get no latest;
# - release.yml passes latest 'branch' and the branch of the version;
# - izpbx-promote refuses latest for a version outside 20.16.x (Q1), before
#   any other step.
source "$(dirname "$0")/../lib.sh"
dir="$REPO_DIR/.gitea/actions/image-tags"
tags() { # version branch [latest] -> the tags, space separated, without the image
  IMAGES=reg/izpbx-asterisk VERSION=$1 BRANCH=$2 LATEST=${3:-branch} LATEST_BRANCH=release/20.16 BUILD_NUMBER=42 \
    "$dir/tags.sh" | sed 's|^reg/izpbx-asterisk:||' | tr '\n' ' ' | sed 's/ $//'
}
assert_cmd "the action computes the tags with tags.sh" -- grep -qF '"$GITHUB_ACTION_PATH/tags.sh"' "$dir/action.yml"
assert_cmd_fails "the action no longer uses docker/metadata-action" -- grep -q 'metadata-action' "$dir/action.yml"

assert_eq "22.17.0 22.17 22 22.17.0-42" "$(tags 22.17.0 main)" "22.17.0 on main: the expected tags, no latest"
assert_eq "20.16.23 20.16 20 20.16.23-42 latest" "$(tags 20.16.23 release/20.16)" "20.16.23 on release/20.16: latest"
assert_eq "22.17.0 22.17 22 22.17.0-42" "$(tags 22.17.0 release/22.17)" "negative: latest only on release/20.16"
assert_eq "22.17.0 22.17 22 22.17.0-42" "$(tags 22.17.0 '')" "negative: no branch, no latest"
assert_eq "22.17.0-rc1 22.17.0-rc1-42" "$(tags 22.17.0-rc1 main true)" "negative: prerelease, no X.Y, X, latest even when asked"
assert_eq "dev-22.17" "$(IMAGES=r/i VERSION=dev-22.17 LATEST=true "$dir/tags.sh" | sed 's|^r/i:||')" \
  "negative: dev-22.17 as-is, never latest"
assert_eq "20.16.23 20.16 20 20.16.23-42" "$(tags 20.16.23 release/20.16 false)" "latest 'false': no latest"
assert_eq "2" "$(IMAGES=$'a/x\nb/x' VERSION=dev-22.17 "$dir/tags.sh" | grep -c ':dev-22.17$')" "every image gets the tags"

rel="$REPO_DIR/.gitea/workflows/release.yml"
assert_cmd "release.yml: latest 'branch'" -- grep -qE '^ +latest: branch$' "$rel"
assert_cmd "release.yml: 20.16.x -> release/20.16" -- grep -qF '20.16.*) echo "branch=release/20.16"' "$rel"
assert_cmd "release.yml: other versions -> main" -- grep -qF '*) echo "branch=main"' "$rel"
assert_cmd "build-push passes the branch" -- grep -qF 'branch: ${{ inputs.branch }}' "$REPO_DIR/.gitea/actions/build-push/action.yml"

# izpbx-promote refuses "latest" outside the 20.16 line (decision of the user, 2026-10-25)
promote="$REPO_DIR/.gitea/workflows/promote.yml"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
awk '/- name: check latest/ {s = 1} s && /- name: gitleaks/ {exit} s && r {print substr($0, 11)} s && /run: \|/ {r = 1}' "$promote" > "$work/check.sh"
latest_versions=$(sed -nE "s/^  LATEST_VERSIONS: '(.*)'$/\1/p" "$promote")
guard() { VERSION=$1 LATEST=$2 LATEST_VERSIONS=$latest_versions bash "$work/check.sh" >/dev/null 2>&1; }
assert_cmd "the guard runs before gitleaks" -- grep -q 'latest' "$work/check.sh"
assert_cmd "promote: 20.16.23 with latest accepted" -- guard 20.16.23 true
assert_cmd_fails "promote: 22.17.0 with latest refused" -- guard 22.17.0 true
assert_cmd_fails "promote: dev-22.17 with latest refused" -- guard dev-22.17 true
assert_cmd "promote: 22.17.0 without latest accepted" -- guard 22.17.0 false
finish
