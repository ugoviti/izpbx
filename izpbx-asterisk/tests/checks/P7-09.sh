#!/usr/bin/env bash
# P7-09: izpbx-asterisk/tools/make-release.sh on a scratch copy of the repository (offline):
# - first release of a series: "## [22.17.0] - Unreleased" becomes
#   "## [22.17.0] - <date>", an empty "## [Unreleased]" stays on top, tag 22.17.0;
# - patch: 22.17.1 with the hand written Unreleased entries plus one line per
#   component changed in versions.env and freepbx-modules.txt, compose.yml
#   (${IZPBX_VERSION:-...}), default.env (IZPBX_VERSION=) and README.md moved
#   from 22.17.0 to 22.17.1 (the 20.16 examples of the README untouched, P7-10);
# - empty Unreleased: draft from the commit subjects, or from --ai (a fake
#   claude in PATH);
# - no option (or --dry-run) is a dry run that writes nothing and prints how to
#   release (--commit, --push);
# - negatives: dirty tree, existing tag, wrong branch.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
rel="$REPO_DIR/izpbx-asterisk/tools/make-release.sh"
r="$work/repo"
today=$(date +%F)

mkdir -p "$r/izpbx-asterisk/build" "$r/izpbx-asterisk/tools"
cp "$REPO_DIR/CHANGELOG.md" "$REPO_DIR/compose.yml" "$REPO_DIR/default.env" "$REPO_DIR/README.md" "$r/"
cp "$REPO_DIR/izpbx-asterisk/versions.env" "$r/izpbx-asterisk/"
cp "$REPO_DIR/izpbx-asterisk/build/freepbx-modules.txt" "$r/izpbx-asterisk/build/"
cp "$rel" "$r/izpbx-asterisk/tools/"
g() { git -C "$r" -c user.name=t -c user.email=t@t "$@"; }
g init -q -b main
g add -A && g commit -q -m "base"
g tag -a 20.16.22 -m old      # previous series, as on the real repository
rr() { (cd "$r" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
        "$r/izpbx-asterisk/tools/make-release.sh" --no-fetch "$@"); }

# --- dry run writes nothing
head_before=$(g rev-parse HEAD)
rr > "$work/dry.txt" 2>&1
assert_cmd "dry run prints the entry 22.17.0" -- grep -qF "## [22.17.0] - $today" "$work/dry.txt"
assert_eq "$head_before" "$(g rev-parse HEAD)" "dry run: no commit"
assert_eq "" "$(g status --porcelain)" "dry run: no file changed"
assert_eq "" "$(g tag -l 22.17.0)" "dry run: no tag"
assert_cmd "dry run says how to release" -- grep -qF 'izpbx-asterisk/tools/make-release.sh --commit' "$work/dry.txt"
assert_cmd "--dry-run is the default too" -- rr --dry-run
assert_eq "" "$(g tag -l 22.17.0)" "--dry-run: no tag"

# --- first release of the series
rr --commit --yes > "$work/r0.txt" 2>&1 || { cat "$work/r0.txt" >&2; die "release 22.17.0 failed"; }
assert_eq "22.17.0" "$(g tag -l '22.17.*')" "tag 22.17.0 created"
assert_eq "22.17.0 release" "$(g log -1 --format=%s)" "release commit"
assert_cmd "heading dated" -- grep -qxF "## [22.17.0] - $today" "$r/CHANGELOG.md"
assert_cmd "no '- Unreleased' heading left" -- bash -c "! grep -q '22.17.0\] - Unreleased' '$r/CHANGELOG.md'"
assert_eq "## [Unreleased]" "$(grep -m1 '^## \[' "$r/CHANGELOG.md")" "empty Unreleased on top"
assert_cmd "the 22.17.0 sections are kept" -- grep -q '^### Migration' "$r/CHANGELOG.md"
assert_cmd "older entries kept" -- grep -qF '## [20.16.22] - 2026-10-22' "$r/CHANGELOG.md"
assert_cmd "compose.yml still on 22.17.0" -- grep -qF 'IZPBX_VERSION:-22.17.0}' "$r/compose.yml"

# --- patch release with hand written entries and component updates
sed -i 's/^ASTERISK_VER=.*/ASTERISK_VER=22.12.0/' "$r/izpbx-asterisk/versions.env"
sed -i -E 's/^(core +)[0-9.]+/\117.0.99.1/' "$r/izpbx-asterisk/build/freepbx-modules.txt"
awk '{print} /^## \[Unreleased\]/ {print ""; print "### Fixed"; print "- Voicemail greetings kept by the migration"}' "$r/CHANGELOG.md" > "$work/c" && cp "$work/c" "$r/CHANGELOG.md"
g add -A && g commit -q -m "fix voicemail greetings, Asterisk 22.12.0"

# negative: dirty tree
echo x >> "$r/README.md"
assert_cmd_fails "dirty tree refused" -- rr --commit --yes
g checkout -q README.md

rr --commit --yes > "$work/r1.txt" 2>&1 || { cat "$work/r1.txt" >&2; die "release 22.17.1 failed"; }
assert_cmd "tag 22.17.1" -- g rev-parse -q --verify refs/tags/22.17.1
awk '/^## \[22\.17\.1\]/ {p = 1; print; next} /^## \[/ {p = 0} p' "$r/CHANGELOG.md" > "$work/e1"
log "entry 22.17.1:"; sed 's/^/    /' "$work/e1" >&2
assert_cmd "hand written Fixed entry kept" -- grep -qF -- '- Voicemail greetings kept by the migration' "$work/e1"
# shellcheck disable=SC2016  # literal backticks
assert_cmd "Asterisk component line added" -- grep -qF 'Updated PBX engine to Asterisk `22.12.0` LTS' "$work/e1"
# shellcheck disable=SC2016  # literal backticks
assert_cmd "FreePBX modules line added" -- grep -qE 'Updated FreePBX modules: `core` [0-9.]+ → 17\.0\.99\.1' "$work/e1"
assert_cmd "component lines under ### Changed" -- bash -c "grep -A3 '^### Changed' '$work/e1' | grep -q 'Asterisk'"
assert_cmd "compose.yml moved to 22.17.1" -- grep -qF 'izdock/izpbx-asterisk:${IZPBX_VERSION:-22.17.1}' "$r/compose.yml"
assert_cmd "default.env moved to 22.17.1" -- grep -qx 'IZPBX_VERSION=22.17.1' "$r/default.env"
assert_cmd "README upgrade steps moved to 22.17.1" -- grep -qF "echo 'IZPBX_VERSION=22.17.1' >> .env" "$r/README.md"
assert_cmd "release commit has default.env" -- sh -c "git -C '$r' show --name-only --format= HEAD | grep -qx default.env"
assert_cmd "README image references moved to 22.17.1" -- grep -qF 'izpbx-asterisk:22.17.1' "$r/README.md"
assert_eq "0" "$(cat "$r/README.md" "$r/compose.yml" "$r/default.env" | grep -cE 'izpbx-asterisk:22\.17\.0|IZPBX_VERSION(:-|=)22\.17\.0' || true)" "no 22.17.0 image reference left"
assert_cmd "MARIADB_VERSION untouched" -- grep -qx 'MARIADB_VERSION=10.11.19' "$r/default.env"
assert_cmd "20.16 examples of the README untouched" -- grep -qF 'izpbx-asterisk:20\.16\.[0-9]*' "$r/README.md"

# negative: existing tag, empty entry, wrong branch
assert_cmd_fails "existing tag refused" -- rr --commit --yes --version 22.17.1
g commit -q --allow-empty -m "release: nothing"     # a commit, no Unreleased entry, no component change
rr --commit --yes > "$work/r2.txt" 2>&1 || true
assert_cmd "empty Unreleased: draft from the commit subjects" -- grep -qF -- '- release: nothing' <(awk '/^## \[22\.17\.2\]/ {p = 1} p' "$r/CHANGELOG.md")
g branch release/22.17
assert_cmd_fails "release/22.17 exists: main refused" -- rr --commit --yes
g branch -D release/22.17 >/dev/null

# --ai with a fake claude
mkdir -p "$work/bin"
printf '#!/bin/sh\nprintf "### Fixed\\n- Drafted by the AI\\n"\n' > "$work/bin/claude"; chmod +x "$work/bin/claude"
g commit -q --allow-empty -m "something"
PATH="$work/bin:$PATH" rr --commit --yes --ai > "$work/r3.txt" 2>&1 || { cat "$work/r3.txt" >&2; die "release --ai failed"; }
assert_cmd "--ai draft used" -- grep -qF -- '- Drafted by the AI' <(awk '/^## \[22\.17\.3\]/ {p = 1; print; next} /^## \[/ {p = 0} p' "$r/CHANGELOG.md")
assert_eq "4" "$(g tag -l '22.17.*' | wc -l)" "four releases of the series"

finish
