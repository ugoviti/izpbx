#!/usr/bin/env bash
# P7-02: default.env and compose.yml of 22.17.
# - docker compose config is valid (compose.yml with default.env as .env);
# - the izpbx image is IZPBX_VERSION of default.env, an explicit tag of 22.17 (P7-10);
# - every variable of the contract (izpbx-asterisk/tests/expected/env-contract-20.16.22.md) is in default.env,
#   even commented, except the internal ones: sections 1 (image and build
#   metadata), 14 (legacy entrypoint, removed in 22.17) and 15 (internal
#   names), and the rows declared "not used" or "Internal"; the new 22.17
#   variables (IZPBX_MIGRATE_*, IZPBX_LOG_*) too;
# - removed values: FREEPBX_MODULES_EXTRA without phonebook, no variable of
#   the legacy entrypoint;
# - negative checks: a default.env without a contract variable, and a
#   compose.yml with an invalid key, are reported.
source "$(dirname "$0")/../lib.sh"
cli=docker.io/library/docker:27.5.1-cli
contract="$REPO_DIR/izpbx-asterisk/tests/expected/env-contract-20.16.22.md"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

compose_config() { # dir with compose.yml and .env
  docker run --rm -v "$1:/w:ro" -w /w "$cli" docker compose -f compose.yml config -q >"$work/config.out" 2>&1
}
cp "$DEPLOY_FILES/compose.yml" "$work/compose.yml"; cp "$DEPLOY_FILES/default.env" "$work/.env"
assert_cmd "docker compose config valid" -- compose_config "$work"
iv=$(sed -n 's/^IZPBX_VERSION=//p' "$DEPLOY_FILES/default.env")
assert_cmd "IZPBX_VERSION=22.17.N in default.env ($iv)" -- grep -qxE 'IZPBX_VERSION=22\.17\.[0-9]+' "$DEPLOY_FILES/default.env"
assert_cmd "izpbx image \${IZPBX_VERSION:?...}, required, no version (P7-10)" -- grep -qE '^    image: docker.io/izdock/izpbx-asterisk:\$\{IZPBX_VERSION:\?[^}]*\}$' "$DEPLOY_FILES/compose.yml"

# the configurable variables of the contract
awk '/^## / {sec = $2} /^\| `[A-Z]/ {split($0, a, "`"); print sec "\t" a[2] "\t" $0}' "$contract" |
  awk -F '\t' '$1 != "1." && $1 != "14." && $1 != "15." && $3 !~ /not used|Internal/ {print $2}' | sort -u > "$work/vars"
printf '%s\n' IZPBX_MIGRATE_FREEPBX IZPBX_MIGRATE_IGNORE_MODULES IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN IZPBX_LOG_FORMAT IZPBX_LOG_COLOR >> "$work/vars"
log "$(wc -l < "$work/vars") variables to find in default.env"
assert_cmd "the contract has the configurable variables (MYSQL_ROOT_USER among them)" -- grep -qx MYSQL_ROOT_USER "$work/vars"
assert_cmd_fails "internal names left out (HOSTNAME)" -- grep -qx HOSTNAME "$work/vars"
missing() { # env file -> the variables it lacks
  local v; while read -r v; do grep -qE "^#? ?$v=" "$1" || printf '%s ' "$v"; done < "$work/vars"
}
assert_eq "" "$(missing "$DEPLOY_FILES/default.env")" "every contract variable in default.env"
grep -v '^#\?UMASK=' "$DEPLOY_FILES/default.env" > "$work/without.env"
assert_eq "UMASK " "$(missing "$work/without.env")" "negative: a default.env without UMASK is reported"

# removed values
assert_cmd_fails "FREEPBX_MODULES_EXTRA without phonebook" -- grep -qE '^#?FREEPBX_MODULES_EXTRA=.*\bphonebook\b' "$DEPLOY_FILES/default.env"
assert_cmd_fails "no variable of the legacy entrypoint" -- grep -qE '^#? ?(APP_RUNAS|MULTISERVICE|CMD_OVERRIDE|ENTRYPOINT_TINI)=' "$DEPLOY_FILES/default.env"

sed 's/^    restart: unless-stopped$/    restart: unless-stopped\n    no_such_key: true/' "$DEPLOY_FILES/compose.yml" > "$work/compose.yml"
assert_cmd_fails "negative: a compose.yml with an invalid key is reported" -- compose_config "$work"
finish
