#!/usr/bin/env bash
# P6-06: dev.yml reads versions.env, tag dev-22.17 (V5). The check runs the
# "resolve versions" step of .gitea/workflows/dev.yml as written there:
# - on the repository: tag dev-22.17, Asterisk = ASTERISK_VER of versions.env,
#   the same version that asterisk -V reports in the image built from it;
# - negative checks: the tag follows versions.env (ASTERISK_VER 21.x ->
#   dev-21.17), and the step fails when ASTERISK_VER is missing;
# - dev.yml no longer reads Dockerfile ARGs nor passes version build-args.
# The manual run in Gitea (image dev-22.17 in the registry) is the same step
# followed by build-push.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p6-06
wf="$REPO_DIR/.gitea/workflows/dev.yml"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

awk '/- name: resolve versions/ {s = 1} s && /- name: build and push/ {exit} s && r {print substr($0, 11)} s && /run: \|/ {r = 1}' "$wf" > "$work/resolve.sh"
assert_cmd "the resolve step is found" -- grep -q 'versions.env' "$work/resolve.sh"
resolve() { # dir with izpbx-asterisk/versions.env -> the step outputs
  : > "$work/out"
  (cd "$1" && GITHUB_OUTPUT="$work/out" bash "$work/resolve.sh" >/dev/null 2>&1) || return 1
  cat "$work/out"
}
out=$(resolve "$REPO_DIR")
want=$(sed -n 's/^ASTERISK_VER=//p' "$REPO_DIR/izpbx-asterisk/versions.env")
assert_cmd "tag dev-22.17" -- grep -qx 'tag=dev-22.17' <<< "$out"
assert_cmd "Asterisk of versions.env ($want)" -- grep -qx "asterisk=$want" <<< "$out"
astv=$(docker run --rm --entrypoint "" "$image" asterisk -V 2>/dev/null)
assert_eq "Asterisk $want" "$astv" "asterisk -V of the image: the version of versions.env"

mkdir -p "$work/r/izpbx-asterisk"
sed 's/^ASTERISK_VER=.*/ASTERISK_VER=21.12.0/' "$REPO_DIR/izpbx-asterisk/versions.env" > "$work/r/izpbx-asterisk/versions.env"
assert_cmd "negative: ASTERISK_VER 21.12.0 -> dev-21.17" -- grep -qx 'tag=dev-21.17' <<< "$(resolve "$work/r")"
sed -i '/^ASTERISK_VER=/d' "$work/r/izpbx-asterisk/versions.env"
assert_cmd_fails "negative: ASTERISK_VER missing -> the step fails" -- resolve "$work/r"

assert_cmd_fails "dev.yml does not read the Dockerfile" -- grep -q 'Dockerfile' "$work/resolve.sh"
assert_cmd_fails "no version build-args" -- grep -qE '(ASTERISK|FREEPBX)_VER=\$\{\{' "$wf"
finish
