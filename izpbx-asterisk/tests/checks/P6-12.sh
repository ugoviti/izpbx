#!/usr/bin/env bash
# P6-12: CI actions pinned to a commit (izpbx-asterisk/tools/make-updates.sh,
# --apply-actions), offline: local git repositories in place of GitHub
# (ACTIONS_GIT_URL) and a test .gitea (ACTIONS_DIR).
# - pinned and current: no ACTION line;
# - pinned to an older release of the major: "ACTION repo vOLD -> vNEW <sha>",
#   --apply-actions rewrites every "uses:" of it (sha and "# vNEW"), in every file;
# - on a tag (@v1): "not pinned", pinned by --apply-actions;
# - a newer major upstream: only noted, the pin stays in its major;
# - an annotated tag: the commit, never the tag object;
# - local actions (./.gitea/...) untouched; a second run: nothing to apply;
# - negative: an upstream that does not answer -> unavailable, exit 2,
#   nothing of it written; --apply with --apply-actions refused.
source "$(dirname "$0")/../lib.sh"

mu="$REPO_DIR/izpbx-asterisk/tools/make-updates.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
gh="$work/gh"

mkrepo() { # owner/repo tag... (a commit per tag; "tag:a" = annotated)
  local d="$gh/$1" t; shift
  git init -q "$d"
  for t in "$@"; do
    git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "${t%:a}"
    case "$t" in
      *:a) git -C "$d" -c user.name=t -c user.email=t@t tag -a -m r "${t%:a}" ;;
      *) git -C "$d" tag "$t" ;;
    esac
  done
}
sha() { git -C "$gh/$1" rev-parse "$2^{commit}"; }
mkrepo acme/checkout v4.0.0 v4.1.0 v5.0.0
mkrepo acme/upload v3.0.0 v3.1.0:a
mkrepo acme/login v1.0.0 v1.2.0 v2.0.0-beta1
mkrepo acme/current v2.0.0 v2.1.0

d="$work/gitea"
mkdir -p "$d/workflows" "$d/actions/x"
cat > "$d/workflows/a.yml" <<EOF
jobs:
  j:
    steps:
      - uses: acme/checkout@$(sha acme/checkout v4.0.0) # v4.0.0
      - uses: acme/upload@$(sha acme/upload v3.0.0) # v3.0.0
      - uses: acme/current@$(sha acme/current v2.1.0) # v2.1.0
      - uses: ./.gitea/actions/x
EOF
cat > "$d/workflows/b.yml" <<EOF
jobs:
  j:
    steps:
      - name: checkout
        uses: acme/checkout@$(sha acme/checkout v4.0.0) # v4.0.0
      - uses: acme/login@v1
EOF
cat > "$d/actions/x/action.yml" <<'EOF'
runs:
  using: composite
  steps:
    - uses: acme/gone@0123456789abcdef0123456789abcdef01234567 # v1.0.0
EOF
cp -r "$d" "$work/gitea.orig"
run() { ACTIONS_DIR="$d" ACTIONS_GIT_URL="file://$gh" NO_COLOR=1 "$mu" "$@"; }

out=$(run --apply-actions 2>&1) && rc=0 || rc=$?
log "first run (exit $rc):"$'\n'"$out"
assert_eq 2 "$rc" "acme/gone does not answer: exit 2 (incomplete)"
assert_contains "$out" "ACTION acme/gone v1.0.0: unavailable" "acme/gone: unavailable"
assert_contains "$out" "ACTION acme/checkout v4.0.0 -> v4.1.0 $(sha acme/checkout v4.1.0) (v5.0.0 available: a new major, by hand)" "checkout: v4.1.0 of its major, v5 noted"
assert_contains "$out" "ACTION acme/upload v3.0.0 -> v3.1.0 $(sha acme/upload v3.1.0)" "upload: annotated tag resolved to its commit"
assert_ne "$(git -C "$gh/acme/upload" rev-parse v3.1.0)" "$(sha acme/upload v3.1.0)" "control: the annotated tag object differs from its commit"
assert_contains "$out" "ACTION acme/login @v1 not pinned -> v1.2.0 $(sha acme/login v1.2.0)" "login: on a tag, not pinned (a pre-release ignored)"
assert_cmd_fails "current: no ACTION line" -- grep -q 'acme/current' <<< "$out"

a=$(cat "$d/workflows/a.yml") b=$(cat "$d/workflows/b.yml")
assert_contains "$a" "uses: acme/checkout@$(sha acme/checkout v4.1.0) # v4.1.0" "a.yml: checkout rewritten"
assert_contains "$b" "uses: acme/checkout@$(sha acme/checkout v4.1.0) # v4.1.0" "b.yml: checkout rewritten too"
assert_contains "$a" "uses: acme/upload@$(sha acme/upload v3.1.0) # v3.1.0" "a.yml: upload pinned to the commit"
assert_contains "$b" "uses: acme/login@$(sha acme/login v1.2.0) # v1.2.0" "b.yml: login pinned"
assert_contains "$a" "uses: acme/current@$(sha acme/current v2.1.0) # v2.1.0" "a.yml: current untouched"
assert_contains "$a" "      - uses: ./.gitea/actions/x" "a.yml: local action untouched"
assert_eq "$(cat "$work/gitea.orig/actions/x/action.yml")" "$(cat "$d/actions/x/action.yml")" "unavailable action: its file untouched"
assert_eq "$(sed '/uses:/d' "$work/gitea.orig/workflows/b.yml")" "$(sed '/uses:/d' "$d/workflows/b.yml")" "b.yml: only the uses: lines changed"

rm -r "$d/actions"
out=$(run --apply-actions 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "second run: exit 0"
assert_contains "$out" "all CI actions are current" "second run: nothing to apply"
assert_contains "$out" "ACTION acme/checkout v4.1.0 current (v5.0.0 available: a new major, by hand)" "second run: the new major still noted"

out=$(run --apply --apply-actions 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "negative: --apply with --apply-actions refused"

# the repository: every external action pinned to a commit, with its version
assert_eq "" "$(grep -rhE 'uses: +[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@' "$REPO_DIR/.gitea" | grep -vE '@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$' || true)" "repository: every external action pinned (sha # vX.Y.Z)"

finish
