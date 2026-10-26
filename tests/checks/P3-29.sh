#!/usr/bin/env bash
# P3-29: the shell of root as 20.16 (cfgBashEnv), in the 22.17 design (P3-33):
# banner with the izPBX logo and the version line,
# prompt "(izPBX)[user@host.domain: dir]#", aliases. /usr/local/share/izpbx/bashrc
# in the image, /root/.bashrc (persisted) written at every start after the
# persistence step, own lines in /root/.bashrc.local.
# - bash -i in the image: the logo, the line with Asterisk and FreePBX of
#   versions.env and Debian GNU/Linux 12; the two-line prompt
#   "╭─ izpbx  user@host.domain  dir  ...", "╰─❯ "; alias d;
# - a hostname with a domain shows it in the prompt, one without does not;
# - a volume with the .bashrc of 20.16 (figlet and the versions of then):
#   replaced at start; /root/.bashrc.local stays and is loaded;
# - control: a shell that is not interactive prints no banner.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-29
assert_cmd "image builds" -- t_build_image "$image"
ast=$(sed -n 's/^ASTERISK_VER=//p' "$REPO_DIR/izpbx-asterisk/versions.env")
fpbx=$(sed -n 's/^FREEPBX_VER=//p' "$REPO_DIR/izpbx-asterisk/versions.env")
plain() { sed 's/\x1b\[[0-9;]*m//g; s/[\x01\x02]//g'; }
ishell() { docker run --rm --entrypoint "" "$@" "$image" bash -ic '_iz_prompt; printf "PS1=%s\n" "${PS1@P}"; alias d' 2>/dev/null | plain; }

out=$(ishell --hostname pbx01)
log "$(head -n 8 <<< "$out" | tr '\n' '|')"
assert_cmd "the izPBX logo" -- grep -qF '▀  ▀▀█ █▀▀▄ █▀▀▄ ▀▄ ▄▀' <<< "$out"
line=$(grep -E '^ +[^ ]+ .*Asterisk ' <<< "$out" | head -n 1 || true)
assert_contains "$line" "Asterisk $ast · FreePBX $fpbx · Debian GNU/Linux 12" "version line: Asterisk, FreePBX, OS"
assert_cmd "prompt: ╭─ izpbx  user@host" -- grep -qE '^PS1=╭─ izpbx  root@pbx01  ' <<< "$out"
assert_cmd "prompt: second line ╰─❯" -- grep -qx '╰─❯ ' <<< "$out"
assert_cmd_fails "hostname without a domain: no domain in the prompt" -- grep -qE '^PS1=╭─ izpbx  root@pbx01\.' <<< "$out"
assert_cmd "alias d" -- grep -qF "alias d='ls -lAsh --color'" <<< "$out"
assert_cmd "hostname pbx01.quantico: .quantico in the prompt" -- grep -qE '^PS1=╭─ izpbx  root@pbx01\.quantico  ' <<< "$(ishell --hostname pbx01.quantico)"
quiet=$(docker run --rm --entrypoint "" "$image" bash -c '. /root/.bashrc; echo done' 2>&1 | plain)
assert_eq "done" "$quiet" "control: a shell that is not interactive prints no banner"

# --- a volume of 20.16: its .bashrc replaced at start, .bashrc.local kept
v=$(t_volume data)
docker run --rm --entrypoint "" -v "$v:/data" "$image" sh -c 'mkdir -p /data/root
  printf "%s\n" ". /etc/os-release" "figlet -w 120 izPBX" "echo Asterisk \${ASTERISK_VER:-unknown}, FreePBX 16" > /data/root/.bashrc
  echo "alias izpbxlocal=\"echo local-ok\"" > /data/root/.bashrc.local'
c=$(t_run pbx "$image" -v "$v:/data" -e APP_DATA=/data -e IZPBX_ENABLED=false)
t_wait_for 120 -- sh -c "docker logs '$c' 2>&1 | grep 'shell: /root/.bashrc written' >/dev/null"
assert_cmd "the 20.16 .bashrc is replaced" -- docker exec "$c" grep -qF '. /usr/local/share/izpbx/bashrc' /data/root/.bashrc
assert_cmd_fails "nothing of the 20.16 one left" -- docker exec "$c" grep -q 'FreePBX 16' /data/root/.bashrc
assert_cmd ".bashrc.local kept" -- docker exec "$c" grep -q izpbxlocal /data/root/.bashrc.local
got=$(docker exec "$c" bash -ic 'izpbxlocal' 2>/dev/null | plain)
assert_contains "$got" "local-ok" ".bashrc.local loaded by the interactive shell"
assert_contains "$got" "Asterisk $ast · FreePBX" "and the banner of 22.17"
finish
