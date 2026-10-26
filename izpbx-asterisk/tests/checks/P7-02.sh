#!/usr/bin/env bash
# P7-02: default.env and compose.yml of 22.17.
# - docker compose config is valid (compose.yml with default.env as .env);
# - the izpbx image is 22.17.0, an explicit tag (IZPBX_VERSION, P7-10);
# - every variable of the contract (izpbx-asterisk/docs/env-contract.md) is in default.env,
#   even commented, except the internal ones: sections 1 (image and build
#   metadata), 14 (legacy entrypoint, removed in 22.17) and 15 (internal
#   names), and the rows declared "not used" or "Internal"; the new 22.17
#   variables (IZPBX_MIGRATE_*) too;
# - removed values: FREEPBX_MODULES_EXTRA without phonebook, no variable of
#   the legacy entrypoint;
# - negative checks: a default.env without a contract variable, and a
#   compose.yml with an invalid key, are reported.
source "$(dirname "$0")/../lib.sh"
cli=docker.io/library/docker:27.5.1-cli
contract="$REPO_DIR/izpbx-asterisk/docs/env-contract.md"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

compose_config() { # dir with compose.yml and .env
  docker run --rm -v "$1:/w:ro" -w /w "$cli" docker compose -f compose.yml config -q >"$work/config.out" 2>&1
}
cp "$REPO_DIR/compose.yml" "$work/compose.yml"; cp "$REPO_DIR/default.env" "$work/.env"
assert_cmd "docker compose config valid" -- compose_config "$work"
assert_cmd "izpbx image 22.17.0 (IZPBX_VERSION, P7-10)" -- grep -qE '^    image: docker.io/izdock/izpbx-asterisk:\$\{IZPBX_VERSION:-22\.17\.0\}$' "$REPO_DIR/compose.yml"
assert_cmd "IZPBX_VERSION=22.17.0 in default.env" -- grep -qx 'IZPBX_VERSION=22.17.0' "$REPO_DIR/default.env"

# the configurable variables of the contract
awk '/^## / {sec = $2} /^\| `[A-Z]/ {split($0, a, "`"); print sec "\t" a[2] "\t" $0}' "$contract" |
  awk -F '\t' '$1 != "1." && $1 != "14." && $1 != "15." && $3 !~ /not used|Internal/ {print $2}' | sort -u > "$work/vars"
printf '%s\n' IZPBX_MIGRATE_FREEPBX IZPBX_MIGRATE_IGNORE_MODULES IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN >> "$work/vars"
log "$(wc -l < "$work/vars") variables to find in default.env"
assert_cmd "the contract has the configurable variables (MYSQL_ROOT_USER among them)" -- grep -qx MYSQL_ROOT_USER "$work/vars"
assert_cmd_fails "internal names left out (HOSTNAME)" -- grep -qx HOSTNAME "$work/vars"
missing() { # env file -> the variables it lacks
  local v; while read -r v; do grep -qE "^#? ?$v=" "$1" || printf '%s ' "$v"; done < "$work/vars"
}
assert_eq "" "$(missing "$REPO_DIR/default.env")" "every contract variable in default.env"
grep -v '^#\?UMASK=' "$REPO_DIR/default.env" > "$work/without.env"
assert_eq "UMASK " "$(missing "$work/without.env")" "negative: a default.env without UMASK is reported"

# removed values
assert_cmd_fails "FREEPBX_MODULES_EXTRA without phonebook" -- grep -qE '^#?FREEPBX_MODULES_EXTRA=.*\bphonebook\b' "$REPO_DIR/default.env"
assert_cmd_fails "no variable of the legacy entrypoint" -- grep -qE '^#? ?(APP_RUNAS|MULTISERVICE|CMD_OVERRIDE|ENTRYPOINT_TINI)=' "$REPO_DIR/default.env"

sed 's/^    restart: unless-stopped$/    restart: unless-stopped\n    no_such_key: true/' "$REPO_DIR/compose.yml" > "$work/compose.yml"
assert_cmd_fails "negative: a compose.yml with an invalid key is reported" -- compose_config "$work"
finish
