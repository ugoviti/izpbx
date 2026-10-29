#!/usr/bin/env bash
# P7-09: izpbx-asterisk/tools/make-release.sh on a scratch copy of the repository (offline):
# - first release of a series: "## [22.17.0] - Unreleased" becomes
#   "## [22.17.0] - <date>", an empty "## [Unreleased]" stays on top, tag 22.17.0;
# - patch: 22.17.1 with the hand written Unreleased entries plus one line per
#   component changed in versions.env and freepbx-modules.txt, compose.yml
#   (${IZPBX_VERSION:-...}), default.env (IZPBX_VERSION=), README.md and
#   docs/*.md moved from 22.17.0 to 22.17.1 (the 20.16 examples untouched, P7-10);
# - empty Unreleased: draft from the commit subjects, or from --ai (a fake
#   claude in PATH);
# - no option (or --dry-run) is a dry run that writes nothing and prints how to
#   release (--commit, --push);
# - --rc: dry run, then tags 22.17.0-rc1 and -rc2 from a feature branch, no
#   file or commit written; after 22.17.0 the next rc is 22.17.1-rc1;
# - negatives: dirty tree, existing tag, wrong branch.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
rel="$REPO_DIR/izpbx-asterisk/tools/make-release.sh"
r="$work/repo"
today=$(date +%F)

mkdir -p "$r/izpbx-asterisk/build" "$r/izpbx-asterisk/tools" "$r/docs"
cp "$REPO_DIR"/docs/*.md "$r/docs/"
cp "$REPO_DIR/CHANGELOG.md" "$REPO_DIR/compose.yml" "$REPO_DIR/default.env" "$REPO_DIR/README.md" "$r/"
cp "$REPO_DIR/izpbx-asterisk/versions.env" "$r/izpbx-asterisk/"
cp "$REPO_DIR/izpbx-asterisk/build/freepbx-modules.txt" "$r/izpbx-asterisk/build/"
cp "$rel" "$r/izpbx-asterisk/tools/"
# the CHANGELOG as before the first release of the series (the real one has
# 22.17.0 dated and an empty "## [Unreleased]" on top since the release)
sed -i -E -e '/^## \[Unreleased\]$/{N;/\n$/d}' -e 's/^## \[22\.17\.0\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$/## [22.17.0] - Unreleased/' "$r/CHANGELOG.md"
grep -qx '## \[22.17.0\] - Unreleased' "$r/CHANGELOG.md" || die "fixture: no '## [22.17.0] - Unreleased' in CHANGELOG.md"
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

# --- release candidates, from a feature branch: only the tags
g checkout -q -b feature/22.17
rr --rc > "$work/rc0.txt" 2>&1
assert_cmd "--rc dry run names 22.17.0-rc1" -- grep -qF 'release candidate 22.17.0-rc1' "$work/rc0.txt"
assert_eq "" "$(g tag -l '22.17.0-rc*')" "--rc dry run: no tag"
rr --rc --commit > "$work/rc1.txt" 2>&1 || { cat "$work/rc1.txt" >&2; die "--rc --commit failed"; }
g commit -q --allow-empty -m "fix after rc1"
rr --rc --commit > "$work/rc2.txt" 2>&1 || { cat "$work/rc2.txt" >&2; die "second --rc --commit failed"; }
assert_eq "22.17.0-rc1 22.17.0-rc2" "$(g tag -l '22.17.0-rc*' | sort -V | xargs)" "rc1 then rc2"
assert_eq "izPBX 22.17.0-rc2" "$(g for-each-ref refs/tags/22.17.0-rc2 --format='%(objecttype) %(contents:subject)' | sed 's/^tag //')" "rc2 annotated"
assert_eq "$(g rev-parse HEAD)" "$(g rev-parse '22.17.0-rc2^{commit}')" "rc2 on HEAD"
rcmsg=$(g for-each-ref refs/tags/22.17.0-rc2 --format='%(contents)')
assert_cmd "rc2 message: the Unreleased entry of 22.17.0 (### lines kept)" -- grep -qx '### Migration' <<< "$rcmsg"
assert_cmd_fails "rc2 message: not the older entries" -- grep -qF '## [20.16.22]' <<< "$rcmsg"
assert_eq "" "$(g status --porcelain)" "--rc: no file changed"
assert_cmd "--rc: CHANGELOG still Unreleased" -- grep -qF '## [22.17.0] - Unreleased' "$r/CHANGELOG.md"
g checkout -q main
g merge -q --ff-only feature/22.17

# --- first release of the series
rr --commit --yes > "$work/r0.txt" 2>&1 || { cat "$work/r0.txt" >&2; die "release 22.17.0 failed"; }
assert_eq "22.17.0" "$(g tag -l '22.17.*' | grep -v -- -rc)" "tag 22.17.0 created"
assert_eq "22.17.0 release" "$(g log -1 --format=%s)" "release commit"
assert_cmd "heading dated" -- grep -qxF "## [22.17.0] - $today" "$r/CHANGELOG.md"
assert_cmd "no '- Unreleased' heading left" -- bash -c "! grep -q '22.17.0\] - Unreleased' '$r/CHANGELOG.md'"
assert_eq "## [Unreleased]" "$(grep -m1 '^## \[' "$r/CHANGELOG.md")" "empty Unreleased on top"
assert_cmd "the 22.17.0 sections are kept" -- grep -q '^### Migration' "$r/CHANGELOG.md"
assert_cmd "older entries kept" -- grep -qF '## [20.16.22] - 2026-10-22' "$r/CHANGELOG.md"
assert_cmd "compose.yml still on 22.17.0" -- grep -qF 'IZPBX_VERSION:-22.17.0}' "$r/compose.yml"
rr --rc > "$work/rc3.txt" 2>&1
assert_cmd "after 22.17.0 the next rc is 22.17.1-rc1" -- grep -qF 'release candidate 22.17.1-rc1' "$work/rc3.txt"

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
assert_eq "izPBX 22.17.1" "$(g for-each-ref refs/tags/22.17.1 --format='%(contents:subject)')" "22.17.1 tag: subject"
assert_eq "$(tail -n +2 "$work/e1" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')" "$(g for-each-ref refs/tags/22.17.1 --format='%(contents:body)' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')" "22.17.1 tag: the CHANGELOG entry as its body"
log "entry 22.17.1:"; sed 's/^/    /' "$work/e1" >&2
assert_cmd "hand written Fixed entry kept" -- grep -qF -- '- Voicemail greetings kept by the migration' "$work/e1"
# shellcheck disable=SC2016  # literal backticks
assert_cmd "Asterisk component line added" -- grep -qF 'Updated PBX engine to Asterisk `22.12.0` LTS' "$work/e1"
# shellcheck disable=SC2016  # literal backticks
assert_cmd "FreePBX modules line added" -- grep -qE 'Updated FreePBX modules: `core` [0-9.]+ → 17\.0\.99\.1' "$work/e1"
assert_cmd "component lines under ### Changed" -- bash -c "grep -A3 '^### Changed' '$work/e1' | grep -q 'Asterisk'"
assert_cmd "compose.yml moved to 22.17.1" -- grep -qF 'izdock/izpbx-asterisk:${IZPBX_VERSION:-22.17.1}' "$r/compose.yml"
assert_cmd "default.env moved to 22.17.1" -- grep -qx 'IZPBX_VERSION=22.17.1' "$r/default.env"
assert_cmd "upgrade guide steps moved to 22.17.1" -- grep -qF "echo 'IZPBX_VERSION=22.17.1' >> .env" "$r/docs/upgrade-20.16-to-22.17.md"
assert_cmd "multi-tenant guide moved to 22.17.1" -- grep -qF 'izpbx-asterisk:22.17.1' "$r/docs/multi-tenant.md"
assert_cmd "release commit has the docs" -- sh -c "git -C '$r' show --name-only --format= HEAD | grep -qx docs/upgrade-20.16-to-22.17.md"
assert_cmd "release commit has default.env" -- sh -c "git -C '$r' show --name-only --format= HEAD | grep -qx default.env"
assert_cmd "README image references moved to 22.17.1" -- grep -qF 'izpbx-asterisk:22.17.1' "$r/README.md"
assert_eq "0" "$(cat "$r/README.md" "$r"/docs/*.md "$r/compose.yml" "$r/default.env" | grep -cE 'izpbx-asterisk:22\.17\.0|IZPBX_VERSION(:-|=)22\.17\.0' || true)" "no 22.17.0 image reference left"
assert_cmd "MARIADB_VERSION untouched" -- grep -qx 'MARIADB_VERSION=10.11.19' "$r/default.env"
assert_cmd "20.16 examples of the upgrade guide untouched" -- grep -qF 'izpbx-asterisk:20\.16\.[0-9]*' "$r/docs/upgrade-20.16-to-22.17.md"

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
assert_eq "4" "$(g tag -l '22.17.*' | grep -vc -- -rc)" "four releases of the series"

finish
