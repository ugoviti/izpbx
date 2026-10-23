#!/usr/bin/env bash
# P1-06: Asterisk 22.11.0 built by build/asterisk.sh. asterisk -V = 22.11.0;
# the module list equals tests/expected/asterisk-modules.txt (no chan_sip.so,
# app_macro.so, app_meetme.so; app_sla.so, res_fax_spandsp.so, codec_opus.so,
# format_mp3.so, res_xmpp.so present); every module resolves its libraries;
# menuselect.makeopts has no DONT_OPTIMIZE / BETTER_BACKTRACES (D10).
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
dir="$REPO_DIR/izpbx-asterisk"
expected="$TESTS_DIR/expected/asterisk-modules.txt"
image=izpbx-asterisk:p1-06

assert_cmd "image builds" -- docker build -q -t "$image" "$dir"
assert_cmd "builder stage builds" -- docker build -q --target builder -t "$image-builder" "$dir"

assert_eq "Asterisk 22.11.0" "$(docker run --rm "$image" asterisk -V)" "asterisk -V"
docker run --rm "$image" sh -c 'ls /usr/lib64/asterisk/modules/ | grep "\.so$"' | LC_ALL=C sort > "$work/modules"
grep -v '^#' "$expected" > "$work/expected"
diff "$work/expected" "$work/modules" > "$work/diff" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || log "module list differs from $expected:"$'\n'"$(cat "$work/diff")"
assert_eq 0 "$rc" "module list equals tests/expected/asterisk-modules.txt ($(wc -l < "$work/modules") modules)"
for m in app_sla res_fax_spandsp codec_opus format_mp3 res_xmpp chan_pjsip; do
  assert_cmd "$m.so is present" -- grep -qx "$m.so" "$work/modules"
done
for m in chan_sip app_macro app_meetme res_digium_phone; do
  assert_cmd_fails "$m.so is absent" -- grep -qx "$m.so" "$work/modules"
done
missing=$(docker run --rm "$image" sh -c 'for m in /usr/sbin/asterisk /usr/lib64/asterisk/modules/*.so; do ldd "$m" | grep -q "not found" && basename "$m"; done; true')
assert_eq "" "$missing" "every module resolves its shared libraries"
# MENUSELECT_CFLAGS lists the enabled build options
debug_flags() { grep -E '^MENUSELECT_CFLAGS=' | grep -oE 'DONT_OPTIMIZE|BETTER_BACKTRACES' || true; }
cflags=$(docker run --rm "$image-builder" grep -E '^MENUSELECT_CFLAGS=' /usr/src/build/asterisk/menuselect.makeopts)
log "$cflags"
assert_eq "" "$(debug_flags <<< "$cflags")" "no DONT_OPTIMIZE / BETTER_BACKTRACES in menuselect.makeopts (D10)"
assert_eq "DONT_OPTIMIZE" "$(debug_flags <<< "MENUSELECT_CFLAGS=OPTIONAL_API DONT_OPTIMIZE")" "control: an enabled DONT_OPTIMIZE is detected"

# negative: a list with an extra module is caught
{ cat "$work/expected"; echo chan_sip.so; } | LC_ALL=C sort > "$work/expected2"
assert_cmd_fails "a different expected list is caught" -- diff -q "$work/expected2" "$work/modules"

finish
