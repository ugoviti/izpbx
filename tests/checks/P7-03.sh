#!/usr/bin/env bash
# P7-03: CHANGELOG entry 22.17.0.
# - the entry "## [22.17.0]" has the sections Security, Changed, Removed,
#   Migration;
# - every item of the release notes (§13 of the design) is there: a keyword
#   list per item, plus every name in backticks of §13 when .specs is there;
# - negative checks: an entry without the Removed section, and one without a
#   keyword of §13, are reported.
source "$(dirname "$0")/../lib.sh"
changelog="$REPO_DIR/CHANGELOG.md"
spec="$REPO_DIR/.specs/2026-10-23-release-22.17.0-freepbx17.md"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

entry() { awk '/^## \[22\.17\.0\]/ {e = 1; print; next} e && /^## \[/ {exit} e' "$1"; }
entry "$changelog" > "$work/entry"
assert_ne "" "$(head -n 1 "$work/entry")" "the entry 22.17.0 exists"
sections() { grep -oE '^### (Security|Changed|Removed|Migration)$' "$1" | tr '\n' ' ' | sed 's/ $//'; }
assert_eq "### Security ### Changed ### Removed ### Migration" "$(sections "$work/entry")" "sections Security, Changed, Removed, Migration"

# one line per item of §13: the keywords that item must bring to the entry
cat > "$work/keywords" <<'KW'
Debian 12|APP_CUSTOM_SCRIPTS|PMA_CONFIG|/etc/phpmyadmin/config.inc.php
PHP `8.2`|php-fpm
chan_sip|PJSIP|APP_PORT_SIP|5160
Macro()|Monitor()|GoSub()|MixMonitor()|**before** the migration
IZPBX_MIGRATE_FREEPBX|IZPBX_MIGRATE_IGNORE_MODULES|IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN
FREEPBX_AUTOUPGRADE_CORE
ASTERISK_VER|FREEPBX_VER|FOP2_VER|ZABBIX_VER|/usr/src/izpbx/versions.env|Asterisk `22|FreePBX `17`|FOP2_SHA256|ZABBIX_REL
FREEPBX_MODULES_EXTRA|phonebook
APP_RUNAS|MULTISERVICE|CMD_OVERRIDE|ENTRYPOINT_TINI|warning|UMASK
/data/.izpbx-migration/|until you remove it
`latest` stays on 20.16
arm64
KW
if [ -f "$spec" ]; then
  sed -n '/^## 13\./,/^## 14\./p' "$spec" | grep -oE '`[^`]+`' | tr -d '`' | sort -u > "$work/spec-names"
  log "§13: $(wc -l < "$work/spec-names") names in backticks"
fi
missing() { # entry file -> the keywords it lacks
  local k
  tr '|' '\n' < "$work/keywords" | while IFS= read -r k; do grep -qF -- "$k" "$1" || printf '[%s] ' "$k"; done
  [ ! -s "$work/spec-names" ] || while IFS= read -r k; do grep -qF -- "$k" "$1" || printf '[%s] ' "$k"; done < "$work/spec-names"
}
assert_eq "" "$(missing "$work/entry")" "every item of §13 in the entry"

grep -v '^### Removed$' "$work/entry" > "$work/no-removed"
assert_ne "### Security ### Changed ### Removed ### Migration" "$(sections "$work/no-removed")" "negative: an entry without Removed is reported"
grep -v 'ENTRYPOINT_TINI' "$work/entry" > "$work/no-kw"
assert_contains "$(missing "$work/no-kw")" "[ENTRYPOINT_TINI]" "negative: an entry without a keyword of §13 is reported"
finish
