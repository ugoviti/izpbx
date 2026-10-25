#!/usr/bin/env bash
# P6-05: weekly rebuild of both branches (V4). .gitea/workflows/weekly-rebuild.yml
# has a matrix with release/20.16 and main; each entry checks out its branch
# (its own CI tooling) and rebuilds the latest X.Y.Z tag of that branch. The
# check runs the "resolve latest release" step of the workflow, as written
# there, in a scratch git repository with the tags of both lines:
# - release/20.16 -> 20.16.22 (not the prerelease 20.16.23-rc1), main -> 22.17.1;
# - main with no 22.x tag yet: nothing to rebuild, no tag (build skipped);
# - negative check: main without its exclude would rebuild a 20.16 tag;
# - the build is skipped without a tag, the cache is per branch.
# The manual run producing the images of both branches is checked in the
# Gitea UI (release/20.16 created from the tag 20.16.22 and pushed by the user).
source "$(dirname "$0")/../lib.sh"
wf="$REPO_DIR/.gitea/workflows/weekly-rebuild.yml"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

assert_eq "release/20.16 main" "$(sed -nE 's/^ +- branch: (.*)$/\1/p' "$wf" | tr '\n' ' ' | sed 's/ $//')" \
  "the matrix has the two branches"
assert_cmd "each entry checks out its branch" -- grep -qF 'ref: ${{ matrix.branch }}' "$wf"
assert_cmd "the build is skipped without a tag" -- grep -qF "if: steps.ver.outputs.tag != ''" "$wf"
assert_cmd "build cache per branch" -- grep -qF 'cache-tag: buildcache-weekly-${{ matrix.line }}' "$wf"
assert_cmd "never latest" -- grep -qE "^ +latest: 'false'$" "$wf"

# the step script and the matrix values, as in the workflow
awk '/- name: resolve latest release/ {s = 1} s && /- name: build and push/ {exit} s && r {print substr($0, 11)} s && /run: \|/ {r = 1}' "$wf" > "$work/resolve.sh"
assert_cmd "the resolve step is found" -- grep -q 'git tag --list' "$work/resolve.sh"
mval() { # branch key -> the value of the matrix entry
  awk -v b="$1" -v k="$2" '$1 == "-" && $2 == "branch:" {e = ($3 == b)} e && $1 == k":" {v = $2; gsub(/^'"'"'|'"'"'$/, "", v); print v}' "$wf"
}

repo() { # tags... -> a repository with izpbx-asterisk/ and those tags, origin itself
  local g=(git -C "$work/repo")
  rm -rf "$work/repo" && mkdir -p "$work/repo/izpbx-asterisk" && echo x > "$work/repo/izpbx-asterisk/Dockerfile"
  "${g[@]}" init -q && "${g[@]}" add . && "${g[@]}" -c user.email=t@t -c user.name=t commit -qm init
  for t in "$@"; do "${g[@]}" tag "$t"; done
  "${g[@]}" remote add origin "$work/repo"
}
resolve() { # branch [exclude] -> the step outputs (tag=...), or nothing
  local out="$work/out"; : > "$out"
  (cd "$work/repo" && TAGS=$(mval "$1" tags) EXCLUDE=${2-$(mval "$1" exclude)} BRANCH=$1 GITHUB_OUTPUT=$out \
    bash "$work/resolve.sh" >/dev/null 2>&1)
  sed -n 's/^tag=//p' "$out"
}
repo 20.16.21 20.16.22 20.16.23-rc1 22.17.0 22.17.1 dev-22.17
assert_eq "20.16.22" "$(resolve release/20.16)" "release/20.16 rebuilds 20.16.22"
assert_eq "22.17.1" "$(resolve main)" "main rebuilds 22.17.1"
repo 20.16.21 20.16.22 dev-22.17
assert_eq "" "$(resolve main)" "main with no 22.x tag: nothing to rebuild"
assert_eq "20.16.22" "$(resolve release/20.16)" "release/20.16 unaffected"
assert_eq "20.16.22" "$(resolve main '^$')" "negative: main without its exclude would rebuild a 20.16 tag"
finish
