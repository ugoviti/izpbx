#!/usr/bin/env bash
# P7-08: izpbx-asterisk/tools/make-updates.sh --apply writes the proposed versions into
# versions.env. Needs internet (deferred). On a copy of versions.env with
# Asterisk, pjproject and libjwt deliberately old (and, on a scratch tree, FreePBX modules): --apply brings them back to the
# pinned versions with the same sha256 (pjproject and libjwt read from the
# third-party/versions.mak of the Asterisk tarball), so the copy equals the
# repository file; a second run reports them ok. Negative: a lookup that fails
# (unknown Asterisk major) never writes a partial file.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
cu="$REPO_DIR/izpbx-asterisk/tools/make-updates.sh"
venv="$REPO_DIR/izpbx-asterisk/versions.env"
zero=0000000000000000000000000000000000000000000000000000000000000000

sed -e 's/^ASTERISK_VER=.*/ASTERISK_VER=22.10.1/' -e "s/^ASTERISK_SHA256=.*/ASTERISK_SHA256=$zero/" \
    -e 's/^PJPROJECT_VER=.*/PJPROJECT_VER=2.16/' -e "s/^PJPROJECT_SHA256=.*/PJPROJECT_SHA256=$zero/" \
    -e 's/^LIBJWT_VER=.*/LIBJWT_VER=1.15.2/' -e "s/^LIBJWT_SHA256=.*/LIBJWT_SHA256=$zero/" \
    "$venv" > "$work/old.env"
"$cu" --apply --versions "$work/old.env" > "$work/apply.txt" 2>&1 && rc=0 || rc=$?
log "apply: exit $rc"
assert_cmd "exit code 0 (applied) or 2 (applied, other lookups unavailable)" -- test "$rc" -eq 0 -o "$rc" -eq 2
assert_cmd "ASTERISK_VER flagged UPDATE" -- grep -qE '^ASTERISK_VER +22\.10\.1 .*UPDATE' "$work/apply.txt"
assert_cmd "PJPROJECT_VER follows the Asterisk tarball" -- grep -qE '^PJPROJECT_VER +2\.16 .*UPDATE' "$work/apply.txt"
assert_cmd "LIBJWT_VER follows the Asterisk tarball (a .tar.gz)" -- grep -qE '^LIBJWT_VER +1\.15\.2 .*UPDATE' "$work/apply.txt"
assert_cmd "the applied lines are reported" -- grep -qE '^applied [0-9]+ line\(s\)' "$work/apply.txt"
for k in ASTERISK_VER ASTERISK_SHA256 PJPROJECT_VER PJPROJECT_SHA256 JANSSON_VER JANSSON_SHA256 LIBJWT_VER LIBJWT_SHA256; do
  assert_eq "$(grep "^$k=" "$venv")" "$(grep "^$k=" "$work/old.env")" "$k equals the pinned value after --apply"
done
assert_eq "$(grep -vE '^(ASTERISK|PJPROJECT|JANSSON|LIBJWT)_' "$venv")" "$(grep -vE '^(ASTERISK|PJPROJECT|JANSSON|LIBJWT)_' "$work/old.env")" \
  "the other lines and the comments are unchanged"
"$cu" --versions "$work/old.env" > "$work/again.txt" 2>&1 || true
assert_cmd "second run: Asterisk ok" -- grep -qE '^ASTERISK_VER +22\.[0-9.]+ +22\.[0-9.]+ +ok$' "$work/again.txt"

# FreePBX modules, on a scratch copy of izpbx-asterisk (the module list belongs to
# the versions.env of its own tree): core pinned to an old version with a wrong
# sha256 comes back to the repository line; a new module written by name only
# (ringgroups) is completed with its version and sha256
m="$work/img"; mkdir -p "$m/build" "$m/tools"
cp "$venv" "$m/versions.env"; cp "$REPO_DIR/izpbx-asterisk/build/lib.sh" "$m/build/"; cp "$cu" "$m/tools/"
mlist="$REPO_DIR/izpbx-asterisk/build/freepbx-modules.txt"
sed -E "s/^(core +)[0-9.]+ +[0-9a-f]{64}$/\117.0.1 $zero/" "$mlist" > "$m/build/freepbx-modules.txt"
echo ringgroups >> "$m/build/freepbx-modules.txt"
"$m/tools/make-updates.sh" --apply > "$work/mods.txt" 2>&1 && rc=0 || rc=$?
assert_cmd "modules: applied (exit 0 or 2)" -- test "$rc" -eq 0 -o "$rc" -eq 2
assert_cmd "modules: core and ringgroups reported" -- bash -c "grep -q 'core: 17.0.1 -> ' '$work/mods.txt' && grep -q 'ringgroups: new -> ' '$work/mods.txt'"
assert_eq "$(grep '^core ' "$mlist")" "$(grep '^core ' "$m/build/freepbx-modules.txt")" "modules: core line equals the repository one (version and sha256)"
assert_cmd "modules: ringgroups completed with version and sha256" -- grep -qE '^ringgroups +17\.[0-9.]+ +[0-9a-f]{64}$' "$m/build/freepbx-modules.txt"
assert_eq "$(grep -vE '^(core|ringgroups)( |$)' "$mlist")" "$(grep -vE '^(core|ringgroups)( |$)' "$m/build/freepbx-modules.txt")" "modules: the other lines unchanged"
echo izpbxnonexistent >> "$m/build/freepbx-modules.txt"; cp "$m/build/freepbx-modules.txt" "$work/mods.orig"
"$m/tools/make-updates.sh" --apply > "$work/mods2.txt" 2>&1 || true
assert_cmd "modules: a module not on the mirror is an error" -- grep -q 'not on the FreePBX 17 mirror: izpbxnonexistent' "$work/mods2.txt"
assert_eq "$(cat "$work/mods.orig")" "$(cat "$m/build/freepbx-modules.txt")" "modules: list untouched when a module is not on the mirror"

# negative: Asterisk 99 has no release, the other proposals are still not
# written partially when one value is missing (here: s6 with a bogus sha file)
sed -e 's/^ASTERISK_VER=.*/ASTERISK_VER=99.0.0/' "$venv" > "$work/bad.env"
cp "$work/bad.env" "$work/bad.orig"
"$cu" --apply --versions "$work/bad.env" > "$work/bad.txt" 2>&1 && rc=0 || rc=$?
assert_eq "$(cat "$work/bad.orig")" "$(cat "$work/bad.env")" "unknown Asterisk major: versions file untouched"
assert_cmd "unknown Asterisk major: not exit 0 without updates applied" -- test "$rc" -ne 1 -o -s "$work/bad.txt"

finish
