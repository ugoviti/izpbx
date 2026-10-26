#!/usr/bin/env bash
# P0-06: izpbx-asterisk/docs/env-contract.md documents every variable read by the 20.16.22
# entrypoint (entrypoint-hooks.sh + entrypoint.sh), plus the variables
# declared by that release's default.env and Dockerfile ENV.
source "$(dirname "$0")/../lib.sh"

REF=20.16.22
contract="$REPO_DIR/izpbx-asterisk/docs/env-contract.md"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

old() { git -C "$REPO_DIR" show "$REF:$1"; }

# variables referenced by the old entrypoint, comment lines excluded:
# ${VAR, $VAR, : ${VAR:=  and any FREEPBX_* / FAIL2BAN_* word
{
  old izpbx-asterisk/rootfs/entrypoint-hooks.sh
  old izpbx-asterisk/rootfs/entrypoint.sh
} | grep -vE '^\s*#' | grep -oE '\$\{?[A-Z][A-Z0-9_]*|\b(FREEPBX|FAIL2BAN)_[A-Z0-9_]+' | sed -E 's/^\$\{?//' > "$work/vars"
# variables offered to users (default.env, also commented) and set by the image
old default.env | grep -oE '^#?[A-Z][A-Z0-9_]+=' | tr -d '#=' >> "$work/vars"
old izpbx-asterisk/Dockerfile | grep -oE '^ENV [A-Z][A-Z0-9_]+=' | sed -E 's/^ENV //; s/=$//' >> "$work/vars"
sort -u -o "$work/vars" "$work/vars"
total=$(wc -l < "$work/vars")
log "$total variables from $REF"
assert_cmd "at least 150 variables extracted (extraction works)" -- test "$total" -ge 150

missing() { # contract file -> prints variables not documented as `VAR`
  local v
  while read -r v; do grep -qF "\`$v\`" "$1" || echo "$v"; done < "$work/vars"
}

miss=$(missing "$contract")
[ -z "$miss" ] || log "missing from the contract: $(echo $miss)"
assert_eq "0" "$(printf '%s' "$miss" | grep -c . || true)" "every $REF variable is in izpbx-asterisk/docs/env-contract.md"

# negative: a contract where APP_FQDN is no longer documented must be reported
sed 's/`APP_FQDN`/APP_FQDN/g' "$contract" > "$work/broken.md"
assert_eq "APP_FQDN" "$(missing "$work/broken.md")" "a variable removed from the contract is reported"

finish
