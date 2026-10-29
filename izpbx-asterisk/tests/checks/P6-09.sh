#!/usr/bin/env bash
# P6-09: release page of a tag on GitHub (izpbx-promote, step "github
# release") and on Gitea (izpbx-release, job "page"; izpbx-release-page by
# hand), izpbx-asterisk/tools/forge-release.sh, offline: a test repository
# with tags and a CHANGELOG, a fake forge API on localhost.
# - X.Y.Z: the CHANGELOG entry of the tag (up to the next "## ["), relative
#   links absolute at the tag, Docker tags X.Y.Z, X.Y, X, the upgrade guide of
#   the line; not a pre-release; GitHub "Latest" only for the highest X.Y.Z
#   (a 20.16.x published after 22.17.0 does not take it);
# - X.Y.Z-rcN: pre-release with the entry of X.Y.Z (still "Unreleased"), never Latest;
# - no release yet: POST; already there: PATCH of the same id (a rerun does not fail);
# - negative: no tag, no entry in the CHANGELOG, GitHub error -> exit != 0;
# - Gitea: links at src/tag, the container package of the registry, no
#   make_latest, "Authorization: token", API under /api/v1;
# - promote.yml: input github_release (default true), the step after the
#   image copy, only with github, with GH_PUSH_TOKEN; release.yml: job page
#   after amd64 and arm64 (arm64 skipped for 20.16), release-page.yml by hand.
source "$(dirname "$0")/../lib.sh"

tool="$REPO_DIR/izpbx-asterisk/tools/forge-release.sh"
promote="$REPO_DIR/.gitea/workflows/promote.yml"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

# --- test repository: 20.16.22, 22.17.0-rc1, 22.17.0, then 20.16.23
r="$work/repo"
git init -q "$r"
g() { git -C "$r" -c user.name=t -c user.email=t@t "$@"; }
mkdir -p "$r/docs" && echo guide > "$r/docs/upgrade-20.16-to-22.17.md"
changelog() { # entries, newest first
  printf '# Changelog\n\n'; printf '%s\n' "$@"
}
changelog '## [20.16.22] - 2026-10-22' '### Security' '- PHP fixed' > "$r/CHANGELOG.md"
g add -A && g commit -q -m 20.16.22 && g tag -a -m t 20.16.22
changelog '## [22.17.0] - Unreleased' 'New major: read [Upgrade](docs/upgrade-20.16-to-22.17.md), see [site](https://example.org) and [top](#x).' '### Changed' '- FreePBX 17' \
  '## [20.16.22] - 2026-10-22' '### Security' '- PHP fixed' > "$r/CHANGELOG.md"
g commit -q -am rc1 && g tag -a -m t 22.17.0-rc1
sed -i 's/^## \[22.17.0\] - Unreleased/## [Unreleased]\n\n## [22.17.0] - 2026-10-29/' "$r/CHANGELOG.md"
g commit -q -am 22.17.0 && g tag -a -m t 22.17.0
# 20.16.23 on the 20.16 line, tagged after 22.17.0
g checkout -q -b release/20.16 20.16.22
changelog '## [20.16.23] - 2026-11-05' '### Security' '- PHP fixed again' '## [20.16.22] - 2026-10-22' '### Security' '- PHP fixed' > "$r/CHANGELOG.md"
g commit -q -am 20.16.23 && g tag -a -m t 20.16.23
dry() { (cd "$r" && FORGE_REPO=o/r "$tool" "$1" --dry-run); }

j=$(dry 22.17.0)
assert_eq "izPBX 22.17.0" "$(jq -r .name <<< "$j")" "22.17.0: name"
assert_eq "22.17.0 false true false" "$(jq -r '"\(.tag_name) \(.prerelease) \(.make_latest) \(.draft)"' <<< "$j")" "22.17.0: tag, not a pre-release, Latest, not a draft"
body=$(jq -r .body <<< "$j")
assert_contains "$body" "- FreePBX 17" "22.17.0: the CHANGELOG entry"
assert_cmd_fails "22.17.0: stops at the next entry" -- grep -q 'PHP fixed' <<< "$body"
assert_cmd_fails "22.17.0: the heading line is not repeated" -- grep -qF '## [22.17.0]' <<< "$body"
assert_contains "$body" "[Upgrade](https://github.com/o/r/blob/22.17.0/docs/upgrade-20.16-to-22.17.md)" "22.17.0: relative link absolute at the tag"
assert_contains "$body" "[site](https://example.org)" "22.17.0: absolute links kept"
assert_contains "$body" "[top](#x)" "22.17.0: anchors kept"
assert_contains "$body" 'tags `22.17.0`, `22.17`, `22`' "22.17.0: Docker tags"
assert_contains "$body" "Upgrade guide: https://github.com/o/r/blob/22.17.0/docs/upgrade-20.16-to-22.17.md" "22.17.0: upgrade guide of the line"

j=$(dry 22.17.0-rc1)
assert_eq "true false" "$(jq -r '"\(.prerelease) \(.make_latest)"' <<< "$j")" "rc: pre-release, never Latest"
body=$(jq -r .body <<< "$j")
assert_contains "$body" "**Release candidate** of 22.17.0" "rc: marked as release candidate"
assert_contains "$body" "- FreePBX 17" "rc: the Unreleased entry of 22.17.0"
assert_contains "$body" 'tags `22.17.0-rc1`;' "rc: only its own Docker tag"

j=$(dry 20.16.23)
assert_eq "false false" "$(jq -r '"\(.prerelease) \(.make_latest)"' <<< "$j")" "20.16.23 after 22.17.0: not Latest"
body=$(jq -r .body <<< "$j")
assert_contains "$body" "- PHP fixed again" "20.16.23: its own entry"
assert_cmd_fails "20.16.23: no upgrade guide (none for 20.16)" -- grep -q 'Upgrade guide' <<< "$body"
assert_cmd_fails "negative: unknown tag" -- sh -c "cd '$r' && '$tool' 9.9.9 --dry-run"
assert_cmd_fails "negative: not a version" -- sh -c "cd '$r' && '$tool' latest --dry-run"
g tag -a -m t 22.17.1 "22.17.0^{}"
assert_cmd_fails "negative: no CHANGELOG entry for the version (22.17.1 on the 22.17.0 commit)" -- sh -c "cd '$r' && '$tool' 22.17.1 --dry-run"
g tag -d 22.17.1 >/dev/null

# --- fake GitHub API: GET of a missing release 404, POST 201, PATCH 200 (requests logged)
cat > "$work/gh.py" <<'PY'
import http.server, json, os, sys
state, log = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, obj):
        b = json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def record(self, body=""):
        with open(log, "a") as f:
            f.write(json.dumps({"m": self.command, "p": self.path, "auth": self.headers.get("Authorization", ""), "body": body}) + "\n")
    def do_GET(self):
        self.record()
        mode = open(state).read().strip()
        if mode == "error": return self.reply(401, {"message": "Bad credentials"})
        if mode == "exists": return self.reply(200, {"id": 7})
        self.reply(404, {"message": "Not Found"})
    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
    def do_POST(self):
        self.record(self.body()); self.reply(201, {"id": 7, "html_url": "https://github.com/o/r/releases/tag/x"})
    def do_PATCH(self):
        self.record(self.body()); self.reply(200, {"id": 7, "html_url": "https://github.com/o/r/releases/tag/x"})
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(state + ".port", "w").write(str(s.server_port))
s.serve_forever()
PY
echo missing > "$work/state"
python3 -I "$work/gh.py" "$work/state" "$work/req.log" &
gh_pid=$!
t_on_cleanup "kill $gh_pid 2>/dev/null || true"
t_wait_for 10 -- test -s "$work/state.port" || die "fake GitHub API not started"
port=$(cat "$work/state.port")
run() { (cd "$r" && FORGE_REPO=o/r FORGE_API="http://127.0.0.1:$port" FORGE_TOKEN=tok-$$ "$tool" "$@"); }

out=$(run 22.17.0 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "new release: exit 0"
assert_contains "$out" "22.17.0 created" "new release: created"
assert_eq "GET /repos/o/r/releases/tags/22.17.0|POST /repos/o/r/releases" "$(jq -r '"\(.m) \(.p)"' "$work/req.log" | paste -sd'|')" "new release: GET then POST"
assert_eq "Bearer tok-$$" "$(jq -r .auth "$work/req.log" | sort -u)" "the token is sent as Bearer"
assert_eq "22.17.0 true" "$(tail -1 "$work/req.log" | jq -r '.body | fromjson | "\(.tag_name) \(.make_latest)"')" "new release: payload of 22.17.0"

: > "$work/req.log"; echo exists > "$work/state"
out=$(run 22.17.0 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "existing release: exit 0 (a rerun does not fail)"
assert_contains "$out" "22.17.0 updated" "existing release: updated"
assert_eq "GET /repos/o/r/releases/tags/22.17.0|PATCH /repos/o/r/releases/7" "$(jq -r '"\(.m) \(.p)"' "$work/req.log" | paste -sd'|')" "existing release: PATCH of its id"

echo error > "$work/state"
out=$(run 22.17.0 2>&1) && rc=0 || rc=$?
assert_ne 0 "$rc" "negative: GitHub error -> exit != 0"
assert_contains "$out" "HTTP 401" "negative: the HTTP code is reported"
assert_contains "$out" "Bad credentials" "negative: the GitHub message is reported"
assert_cmd_fails "negative: the token is not in the output" -- grep -qF "tok-$$" <<< "$out"
out=$(cd "$r" && env -u FORGE_TOKEN FORGE_REPO=o/r FORGE_API="http://127.0.0.1:$port" "$tool" 22.17.0 2>&1) && rc=0 || rc=$?
assert_ne 0 "$rc" "negative: no FORGE_TOKEN -> exit != 0"
out=$(cd "$r" && FORGE_REPO=o/r FORGE_API="http://127.0.0.1:1" FORGE_TOKEN=x "$tool" 22.17.0 2>&1) && rc=0 || rc=$?
assert_ne 0 "$rc" "negative: GitHub not reached -> exit != 0"
assert_contains "$out" "HTTP 000" "negative: not reached is reported"

# --- Gitea
gdry() { (cd "$r" && FORGE_URL=https://git.example FORGE_REPO=Org/izpbx "$tool" --forge gitea "$1" --dry-run); }
j=$(gdry 22.17.0)
assert_eq "22.17.0 false null" "$(jq -r '"\(.tag_name) \(.prerelease) \(.make_latest)"' <<< "$j")" "gitea 22.17.0: not a pre-release, no make_latest"
body=$(jq -r .body <<< "$j")
assert_contains "$body" "[Upgrade](https://git.example/Org/izpbx/src/tag/22.17.0/docs/upgrade-20.16-to-22.17.md)" "gitea: relative link at src/tag"
assert_contains "$body" "https://git.example/Org/-/packages/container/izpbx-asterisk/22.17.0" "gitea: container package of the registry"
assert_contains "$body" "Upgrade guide: https://git.example/Org/izpbx/src/tag/22.17.0/" "gitea: upgrade guide on Gitea"
assert_eq "true" "$(gdry 22.17.0-rc1 | jq -r .prerelease)" "gitea rc: pre-release"
assert_cmd_fails "negative: gitea without FORGE_URL" -- sh -c "cd '$r' && FORGE_REPO=o/r '$tool' --forge gitea 22.17.0 --dry-run"
assert_cmd_fails "negative: unknown forge" -- sh -c "cd '$r' && '$tool' --forge gitlab 22.17.0 --dry-run"
: > "$work/req.log"; echo missing > "$work/state"
out=$(cd "$r" && FORGE_URL=https://git.example FORGE_REPO=Org/izpbx FORGE_API="http://127.0.0.1:$port/api/v1" FORGE_TOKEN=gt-$$ "$tool" --forge gitea 22.17.0 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "gitea: exit 0"
assert_contains "$out" "gitea 22.17.0 created" "gitea: created"
assert_eq "GET /api/v1/repos/Org/izpbx/releases/tags/22.17.0|POST /api/v1/repos/Org/izpbx/releases" "$(jq -r '"\(.m) \(.p)"' "$work/req.log" | paste -sd'|')" "gitea: API under /api/v1"
assert_eq "token gt-$$" "$(jq -r .auth "$work/req.log" | sort -u)" "gitea: Authorization token"
assert_eq "null" "$(tail -1 "$work/req.log" | jq -r '.body | fromjson | .make_latest')" "gitea: no make_latest sent"

# --- release.yml and release-page.yml
rel="$REPO_DIR/.gitea/workflows/release.yml"
job=$(awk '/^  page:$/ {s = 1} s {print}' "$rel")
assert_contains "$job" "needs: [amd64, arm64]" "release.yml: page after amd64 and arm64"
assert_contains "$job" "needs.arm64.result == 'skipped'" "release.yml: also for 20.16 (arm64 skipped)"
assert_contains "$job" "fetch-depth: 0" "release.yml: page with the tags"
assert_contains "$job" "uses: ./.gitea/actions/release-page" "release.yml: page by the release-page action"
assert_contains "$(cat "$REPO_DIR/.gitea/workflows/release-page.yml")" "uses: ./.gitea/actions/release-page" "release-page.yml: by hand, same action"
action="$REPO_DIR/.gitea/actions/release-page/action.yml"
assert_contains "$(cat "$action")" "forge-release.sh --forge gitea" "release-page action: Gitea forge"
assert_eq "last" "$(awk '/^      version:/ {s = 1} s && /default:/ {print $2; exit}' "$REPO_DIR/.gitea/workflows/release-page.yml")" "release-page.yml: version last by default"
# "last" of the action: the most recent version tag (tagger date), rc included, other tags skipped
awk '/run: \|/ {r = 1; next} r {print substr($0, 9)}' "$action" > "$work/page.sh"
mkdir -p "$work/bin" && printf '#!/bin/sh\necho "tool $*"\n' > "$work/bin/forge-release.sh" && chmod +x "$work/bin/forge-release.sh"
sed -i "s#izpbx-asterisk/tools/forge-release.sh#$work/bin/forge-release.sh#" "$work/page.sh"
GIT_COMMITTER_DATE=2030-01-01T10:00:00Z g tag -a -m t 22.17.1-rc1 "22.17.0^{}"
GIT_COMMITTER_DATE=2030-01-02T10:00:00Z g tag -a -m t not-a-version "22.17.0^{}"
out=$(cd "$r" && VERSION=last FORGE_TOKEN=x GITHUB_SERVER_URL=https://git.example GITHUB_REPOSITORY=Org/izpbx bash "$work/page.sh" 2>&1) || true
assert_contains "$out" "version last = 22.17.1-rc1" "release-page: last = the most recent version tag (a newer non-version tag skipped)"
assert_contains "$out" "tool --forge gitea 22.17.1-rc1" "release-page: the tool gets the resolved version"
out=$(cd "$r" && VERSION=22.17.0 FORGE_TOKEN=x GITHUB_SERVER_URL=https://git.example GITHUB_REPOSITORY=Org/izpbx bash "$work/page.sh" 2>&1) || true
assert_contains "$out" "tool --forge gitea 22.17.0" "release-page: an explicit version as it is"

# --- promote.yml
step=$(awk '/- name: github release$/ {s = 1} s && /- name: docker hub overview$/ {exit} s {print}' "$promote")
assert_contains "$step" "izpbx-asterisk/tools/forge-release.sh" "promote: the step runs forge-release.sh"
assert_contains "$step" 'FORGE_TOKEN: ${{ secrets.GH_PUSH_TOKEN }}' "promote: with GH_PUSH_TOKEN"
assert_contains "$step" "--forge github" "promote: the GitHub forge"
assert_contains "$step" "inputs.github == true" "promote: only with github"
assert_contains "$step" "inputs.github_release == true" "promote: only with github_release"
assert_eq "true" "$(awk '/^      github_release:/ {s = 1} s && /default:/ {print $2; exit}' "$promote")" "promote: github_release checked by default"
order=$(grep -nE -- '- name: (push to github|copy image to docker hub|github release)$' "$promote" | sed -E 's/.*name: //' | paste -sd'|')
assert_eq "push to github|copy image to docker hub|github release" "$order" "promote: after the tag push and the image copy"

finish
