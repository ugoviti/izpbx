#!/usr/bin/env bash
# P3-31: pbx_lua is not built (D37): it loaded the sample extensions.lua, a
# "demo" context with hints on SIP/1000 and SIP/1001; FreePBX writes the
# dialplan in extensions*.conf and uses no Lua.
# - the image has no pbx_lua.so, no /etc/asterisk/extensions.lua, no liblua5.4
#   (liblua5.3 stays: apache2-bin depends on it);
# - Asterisk started in the image: module show like pbx_lua lists 0 modules,
#   no context created by pbx_lua;
# - control: pbx_config (the dialplan of the .conf files) is loaded.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-31
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd_fails "no pbx_lua.so" -- docker run --rm --entrypoint "" "$image" sh -c 'ls /usr/lib64/asterisk/modules/pbx_lua.so'
assert_cmd_fails "no sample extensions.lua" -- docker run --rm --entrypoint "" "$image" test -e /etc/asterisk/extensions.lua
# liblua5.4 was the one of pbx_lua; liblua5.3 stays, a dependency of apache2-bin (mod_lua)
assert_eq "" "$(docker run --rm --entrypoint "" "$image" sh -c 'dpkg -l "liblua5.4*" 2>/dev/null | grep "^ii"' || true)" "no liblua5.4 (the library of pbx_lua)"
c=$(t_run ast "$image" --entrypoint "" -- asterisk -f -U asterisk -G asterisk)
assert_cmd "Asterisk boots" -- t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted'
assert_contains "$(docker exec "$c" asterisk -rx 'module show like pbx_lua')" "0 modules loaded" "module show like pbx_lua: 0 modules"
assert_cmd_fails "no context created by pbx_lua" -- sh -c "docker exec '$c' asterisk -rx 'dialplan show' | grep -q \"created by 'pbx_lua'\""
assert_contains "$(docker exec "$c" asterisk -rx 'module show like pbx_config')" "1 modules loaded" "control: pbx_config loaded"
finish
