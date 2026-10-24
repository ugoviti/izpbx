#!/usr/bin/env bash
# P3-02: env.sh holds every default in one place and follows the contract:
# for every variable of docs/env-contract.md (sections 1-14) the value after
# sourcing env.sh in an empty environment equals the contract default, or the
# difference is in tests/expected/env-differences.txt and §13 of the design
# mentions it (tests/unit/env-compare.py). env.sh works under "set -u".
# Negative: a changed default and a missing variable are reported.
source "$(dirname "$0")/../lib.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
dir="$REPO_DIR/izpbx-asterisk"
env_sh="$dir/rootfs/usr/local/lib/izpbx/env.sh"
contract="$REPO_DIR/docs/env-contract.md"
design="$REPO_DIR/.specs/2026-10-23-release-22.17.0-freepbx17.md"
image=izpbx-asterisk:p3-02
compare=("$TESTS_DIR/unit/env-compare.py" "$contract" "$dir/versions.env" "$TESTS_DIR/expected/env-differences.txt" "$design")
[ -r "$design" ] || die "design document not found: $design"
awk -F'|' '/^## 15\./{exit} /^\| `/{gsub(/[ `]/,"",$2); print $2}' "$contract" > "$work/vars"
assert_cmd "image builds" -- t_build_image "$image"

values() { # env.sh -> VAR<tab>value for every contract variable, empty environment, set -u
  docker run --rm --entrypoint "" -v "$1:/e/env.sh:ro" -v "$work/vars:/e/vars:ro" "$image" \
    env -i HOSTNAME=izpbx-test bash -c 'set -u; . /e/env.sh || exit 3; while read -r v; do printf "%s\t%s\n" "$v" "${!v-<UNSET>}"; done < /e/vars'
}
assert_cmd "env.sh sources under set -u in an empty environment" -- sh -c "$(declare -f values); work='$work' image='$image'; values '$env_sh' > '$work/actual'"
out=$(python3 -I "${compare[@]}" "$work/actual") && rc=0 || rc=$?
log "$out"
assert_eq 0 "$rc" "every contract default matches env.sh or is a listed difference ($(grep -o 'checked=[0-9]*' <<< "$out"))"
assert_eq "171" "$(wc -l < "$work/vars")" "the contract has 171 configurable variables"

# negative: one default changed, one variable removed
sed -e 's/^: "${HTTPD_ENABLED:=true}"/: "${HTTPD_ENABLED:=false}"/' -e '/^: "${APP_PORT_MYSQL:=/d' "$env_sh" > "$work/bad.sh"
values "$work/bad.sh" > "$work/bad"
out=$(python3 -I "${compare[@]}" "$work/bad" || true)
assert_contains "$out" "HTTPD_ENABLED: env.sh 'false', expected 'true'" "control: a changed default is reported"
assert_contains "$out" "APP_PORT_MYSQL: not declared in env.sh" "control: a missing variable is reported"
docker rmi "$image" >/dev/null 2>&1 || true
finish
