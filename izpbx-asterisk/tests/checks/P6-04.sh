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
# - izpbx-promote, its first step (before gitleaks): version "last" (the
#   default) is the most recent version tag, rc included (a newer tag that is
#   no version is skipped), none or empty = branch only (empty version; Gitea
#   runs an empty field with the default, so none is what the user types), any other value
#   as it is; latest only for 20.16.x (Q1): for any other version it is
#   ignored with a warning, the publish goes on; every later step uses the
#   resolved version and latest.
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

# izpbx-promote: version "last" and latest only for the 20.16 line (decision of
# the user, 2026-10-25: never refused, ignored with a warning since 2026-10-28)
promote="$REPO_DIR/.gitea/workflows/promote.yml"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
awk '/- name: version$/ {s = 1} s && /- name: gitleaks/ {exit} s && r {print substr($0, 11)} s && /run: \|/ {r = 1}' "$promote" > "$work/version.sh"
latest_versions=$(sed -nE "s/^  LATEST_VERSIONS: '(.*)'$/\1/p" "$promote")
# a repository with tags in a known order (tagger dates)
git init -q "$work/repo" && git -C "$work/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m c
n=0
for t in 20.16.22 22.17.0-rc6 22.17.0-rc7 not-a-version; do
  n=$((n + 1))
  GIT_COMMITTER_DATE="2026-10-2${n}T10:00:00Z" git -C "$work/repo" -c user.name=t -c user.email=t@t tag -a -m "$t" "$t"
done
resolve() { # version latest -> "version=... latest=..." (the outputs of the step)
  : > "$work/out"
  (cd "$work/repo" && VERSION=$1 LATEST=$2 LATEST_VERSIONS=$latest_versions GITHUB_OUTPUT="$work/out" bash "$work/version.sh" > "$work/log" 2>&1) || echo "failed"
  tr '\n' ' ' < "$work/out" | sed 's/ $//'
}
assert_cmd "the step runs before gitleaks" -- grep -q 'GITHUB_OUTPUT' "$work/version.sh"
assert_cmd "promote: the default version is last" -- grep -qE '^ +default: last$' "$promote"
assert_eq "version=22.17.0-rc7 latest=false" "$(resolve last true)" "promote: last = the most recent version tag (a newer non-version tag skipped)"
assert_contains "$(cat "$work/log")" "version last = 22.17.0-rc7" "promote: the log says which tag last is"
assert_eq "version=20.16.23 latest=true" "$(resolve 20.16.23 true)" "promote: 20.16.23 with latest: latest"
assert_eq "version=22.17.0 latest=false" "$(resolve 22.17.0 true)" "promote: 22.17.0 with latest: not moved, the publish goes on"
assert_contains "$(cat "$work/log")" "::warning::" "promote: and a warning says so"
assert_eq "version=dev-22.17 latest=false" "$(resolve dev-22.17 true)" "promote: dev-22.17 with latest: not moved"
assert_eq "version= latest=false" "$(resolve '' true)" "promote: empty version (branch only) stays empty"
assert_eq "version= latest=false" "$(resolve none true)" "promote: none = branch only, the version becomes empty"
assert_cmd "promote: the description says none" -- grep -qF 'none = push only the branch to GitHub' "$promote"
assert_cmd_fails "promote: no later step reads inputs.version" -- grep -q 'inputs\.version' <(grep -v '^ *description:' "$promote" | sed '/- name: version$/,/- name: gitleaks/d')
assert_cmd "promote: the image tags get the checked latest" -- grep -qF 'latest: ${{ steps.ver.outputs.latest }}' "$promote"
finish
