#!/usr/bin/env bash
# P7-04: compose/compose-dev-22.17.yml, compose-dev-20.16.yml removed (V6).
# - the command of docs/development.md, from the repository root:
#   docker compose --project-directory . -f <deploy>/compose.yml -f izpbx-asterisk/compose/compose-dev-22.17.yml
#   config is valid (default.env as .env at the root), gives izpbx the image
#   dev-22.17 and the data in ./data of the root;
# - compose-dev-20.16.yml exists neither in the tree nor among the files git
#   tracks, and nothing but the CHANGELOG names it; the development notes (docs/development.md) build
#   and runs dev-22.17;
# - negative check: the same command with a compose file that does not exist
#   fails.
source "$(dirname "$0")/../lib.sh"
cli=docker.io/library/docker:27.5.1-cli
dev=izpbx-asterisk/compose/compose-dev-22.17.yml
old=izpbx-asterisk/compose/compose-dev-20.16.yml
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
deploy=izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy
mkdir -p "$work/izpbx-asterisk/compose" "$work/$deploy"
cp "$DEPLOY_FILES/compose.yml" "$work/$deploy/"; cp "$DEPLOY_FILES/default.env" "$work/.env"
cp "$REPO_DIR/$dev" "$work/$dev"
config() { docker run --rm -v "$work:/w:ro" -w /w "$cli" docker compose --project-directory . -f "$deploy/compose.yml" -f "$1" config 2>&1; }

out=$(config "$dev") && rc=0 || rc=$?
assert_eq 0 "$rc" "compose.yml + compose-dev-22.17.yml: config valid"
assert_cmd "izpbx image dev-22.17" -- grep -qE '^ +image: izpbx-asterisk:dev-22\.17$' <<< "$out"
assert_cmd "data in ./data of the root" -- grep -qE '^ +source: /w/data/izpbx$' <<< "$out"
assert_cmd "the command of docs/development.md" -- grep -qF -- "--project-directory . -f $deploy/compose.yml -f $dev" "$REPO_DIR/docs/development.md"
assert_cmd_fails "compose-dev-20.16.yml not in the tree" -- test -e "$REPO_DIR/$old"
assert_eq "" "$(git -C "$REPO_DIR" ls-files -- "$old")" "compose-dev-20.16.yml not tracked by git"
assert_eq "" "$(git -C "$REPO_DIR" grep -l 'compose-dev-20\.16' -- . ':!CHANGELOG.md' ':!izpbx-asterisk/tests/checks/P7-04.sh' || true)" "only the CHANGELOG (and this check) names compose-dev-20.16.yml"
assert_eq "" "$(git -C "$REPO_DIR" grep -n 'dev-20\.16' -- docs/development.md || true)" "the development notes have no dev-20.16 left"
assert_cmd "the development notes use compose-dev-22.17.yml" -- grep -qF "$dev" "$REPO_DIR/docs/development.md"
assert_cmd_fails "negative: a compose file that does not exist fails" -- config "$old"
finish
