#!/usr/bin/env bash
# P1-03: build/check-updates.sh reports every component of versions.env and,
# with versions deliberately old, flags the update and proposes the new
# version with its sha256. Needs internet (upstream release pages).
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
cu="$REPO_DIR/izpbx-asterisk/build/check-updates.sh"
venv="$REPO_DIR/izpbx-asterisk/versions.env"

"$cu" > "$work/current.txt" 2>"$work/current.err" && rc=0 || rc=$?
log "current: exit $rc, $(grep -c ' ok$' "$work/current.txt" || true) ok, $(grep -c 'UPDATE' "$work/current.txt" || true) update(s), $(grep -c ' manual' "$work/current.txt" || true) manual"
assert_cmd "exit code is 0 (current) or 10 (updates), not an error" -- test "$rc" -eq 0 -o "$rc" -eq 10
missing=
for k in DEBIAN_IMAGE $(grep -oE '^[A-Z0-9_]+_VER(_[A-Z0-9]+)?=' "$venv" | tr -d '='); do
  grep -qE "^$k +" "$work/current.txt" || missing+=" $k"
done
assert_eq "" "$missing" "the report lists every component of versions.env"
assert_eq "" "$(grep -vE '^(curl: \(22\)|$)' "$work/current.err" || true)" "no errors on stderr"

# negative: old versions must be flagged and proposed with a sha256
sed -e 's/^ASTERISK_VER=.*/ASTERISK_VER=22.0.0/' -e 's/^SNGREP_VER=.*/SNGREP_VER=1.8.0/' \
    -e 's/^FOP2_VER=.*/FOP2_VER=2.31.40/' "$venv" > "$work/old.env"
"$cu" --versions "$work/old.env" > "$work/old.txt" 2>&1 && rc=0 || rc=$?
assert_eq 10 "$rc" "old versions: exit code 10"
for k in ASTERISK_VER SNGREP_VER FOP2_VER; do
  assert_cmd "old $k is flagged UPDATE" -- grep -qE "^$k +.*UPDATE" "$work/old.txt"
done
assert_cmd "new ASTERISK_VER is proposed" -- grep -qE "^  ASTERISK_VER=22\.[0-9]+\.[0-9]+$" "$work/old.txt"
assert_cmd "new ASTERISK_SHA256 is proposed" -- grep -qE "^  ASTERISK_SHA256=[0-9a-f]{64}$" "$work/old.txt"
assert_cmd "new SNGREP_SHA256 is proposed" -- grep -qE "^  SNGREP_SHA256=[0-9a-f]{64}$" "$work/old.txt"

finish
