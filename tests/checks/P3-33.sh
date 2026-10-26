#!/usr/bin/env bash
# P3-33: banner and prompt of the izPBX shell for 22.17 (design chosen by the
# user: modern logo with the live state; two-line prompt with the health and
# the calls). On an Asterisk running in the image:
# - the banner: the logo, "Cloud Native Telephony", the version line, the live
#   state (health of izpbx-healthcheck, calls, endpoints, trunk
#   registrations) and the tools line; with a call up: "1 calls";
# - the prompt: "╭─ izpbx  user@host  dir  ● N calls" / "╰─❯ ", the arrow in
#   the accent color (45) after a command that worked, red (203) after one
#   that failed;
# - maintenance mode (/run/izpbx/maintenance): banner "● maintenance <why>",
#   prompt "● maintenance"; Asterisk stopped: prompt "● asterisk down";
# - NO_COLOR: no escape sequence at all.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-33
assert_cmd "image builds" -- t_build_image "$image"
c=$(t_run ast "$image" --hostname pbx01 --entrypoint "" -- asterisk -f -U asterisk -G asterisk)
assert_cmd "Asterisk boots" -- t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted'
plain() { sed 's/\x1b\[[0-9;]*m//g; s/[\x01\x02]//g; s/\r//g'; }
shell() { docker exec -t -e TERM=xterm-256color "$c" bash -ic "$1" 2>/dev/null; }   # a terminal: with colors
prompt='_iz_state_ts=0; _iz_prompt; printf "%s\n" "${PS1@P}"'

docker exec "$c" asterisk -rx 'dialplan add extension s,1,Wait(600) into izpbxtest' >/dev/null
docker exec "$c" asterisk -rx 'channel originate Local/s@izpbxtest application Wait 600' >/dev/null
t_wait_for 20 -- sh -c "docker exec '$c' asterisk -rx 'core show channels count' | grep -q '^1 active call'"
banner=$(shell 'true' | plain)
log "$(tr '\n' '|' <<< "$banner")"
assert_cmd "logo" -- grep -qF '█  ▄▀  █▄▄▀ █▀▀▄  ▄▀▄    Cloud Native Telephony' <<< "$banner"
assert_cmd "version line" -- grep -qE '^ +[^ ]+.* · Asterisk [0-9.]+ · FreePBX [0-9.]+ · Debian GNU/Linux 12$' <<< "$banner"
assert_cmd "live state: health, 1 calls, endpoints, trunks" -- \
  grep -qE '^ +● .*   1 calls   [0-9]+/[0-9]+ endpoints   (no trunk registration|[0-9]+/[0-9]+ trunks registered)$' <<< "$banner"
assert_cmd "health from izpbx-healthcheck (here: no s6, unhealthy)" -- grep -qF '● s6 supervisor not running (unhealthy)' <<< "$banner"
assert_cmd "tools line" -- grep -qF 'tools: izpbx-<Tab> (-h for help)' <<< "$banner"
p=$(shell "$prompt" | plain | tail -n 2)
assert_cmd "prompt line 1: ╭─ izpbx  root@pbx01  /  ● 1 calls" -- grep -qx '╭─ izpbx  root@pbx01  /  ● 1 calls' <<< "$p"
assert_cmd "prompt line 2: ╰─❯" -- grep -qx '╰─❯ ' <<< "$p"
nomark() { tr -d '\001\002'; }   # \[ \] of PS1 expand to \x01 \x02
# _iz_prompt first, as PROMPT_COMMAND runs it: it reads the exit status of the last command
raw_ok=$(shell 'true; _iz_prompt; printf "%s\n" "${PS1@P}"' | nomark | tail -n 1)
raw_ko=$(shell 'false; _iz_prompt; printf "%s\n" "${PS1@P}"' | nomark | tail -n 1)
assert_contains "$raw_ok" $'\e[38;5;45m❯' "arrow in the accent color after a command that worked"
assert_contains "$raw_ko" $'\e[38;5;203m❯' "arrow red after a command that failed"

docker exec "$c" sh -c 'mkdir -p /run/izpbx && echo "FreePBX 16 data found and the migration is not enabled" > /run/izpbx/maintenance'
assert_cmd "maintenance: banner" -- sh -c "docker exec -t '$c' bash -ic true 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -qF '● maintenance  FreePBX 16 data found'"
assert_contains "$(shell "$prompt" | plain | tail -n 2)" "● maintenance" "maintenance: prompt"
docker exec "$c" rm -f /run/izpbx/maintenance
# Asterisk not reachable: its control socket moved away (stopping it would end this container)
docker exec "$c" sh -c 'mv /var/run/asterisk/asterisk.ctl /var/run/asterisk/asterisk.ctl.off' 
assert_contains "$(shell "$prompt" | plain | tail -n 2)" "● asterisk down" "Asterisk stopped: prompt"
assert_eq "" "$(docker exec -t -e TERM=xterm-256color -e NO_COLOR=1 "$c" bash -ic "$prompt" 2>/dev/null | grep -c $'\e\[' | grep -v '^0$' || true)" \
  "NO_COLOR: no escape sequence"
finish
