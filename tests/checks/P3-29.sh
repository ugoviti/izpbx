#!/usr/bin/env bash
# P3-29: the shell of root as 20.16 (cfgBashEnv): figlet banner, version line,
# prompt "(izPBX)[user@host.domain: dir]#", aliases. /usr/local/share/izpbx/bashrc
# in the image, /root/.bashrc (persisted) written at every start after the
# persistence step, own lines in /root/.bashrc.local.
# - bash -i in the image: the banner, the line with Asterisk and FreePBX of
#   versions.env, Debian GNU/Linux 12 and the kernel; PS1 "(izPBX)"; alias d;
# - a hostname with a domain shows it in the prompt, one without does not;
# - a volume with the .bashrc of 20.16 (figlet and the versions of then):
#   replaced at start; /root/.bashrc.local stays and is loaded;
# - control: a shell that is not interactive prints no banner.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-29
assert_cmd "image builds" -- t_build_image "$image"
ast=$(sed -n 's/^ASTERISK_VER=//p' "$REPO_DIR/izpbx-asterisk/versions.env")
fpbx=$(sed -n 's/^FREEPBX_VER=//p' "$REPO_DIR/izpbx-asterisk/versions.env")
plain() { sed 's/\x1b\[[0-9;]*m//g'; }
ishell() { docker run --rm --entrypoint "" "$@" "$image" bash -ic 'echo "PS1=$PS1"; alias d' 2>/dev/null | plain; }

out=$(ishell --hostname pbx01)
log "$(head -n 7 <<< "$out" | tr '\n' '|')"
assert_cmd "figlet banner" -- grep -qF ' _     ____  ______  __' <<< "$out"
line=$(grep '^izPBX ' <<< "$out" || true)
assert_contains "$line" "Asterisk $ast, FreePBX $fpbx, Debian GNU/Linux 12, Kernel $(uname -r)" "version line: Asterisk, FreePBX, OS, kernel"
assert_cmd "version line: build, commit, date" -- grep -qE '^izPBX [^ ]+ \(build: [^ ]+ commit: [^ ]+ date: [^ )]+\)' <<< "$line"
assert_cmd "prompt (izPBX)[user@host" -- grep -qF 'PS1=(izPBX)' <<< "$out"
assert_cmd_fails "hostname without a domain: no domain in the prompt" -- grep -qF '\h\[\e[2m\].' <<< "$out"
assert_cmd "alias d" -- grep -qF "alias d='ls -lAsh --color'" <<< "$out"
assert_cmd "hostname pbx01.quantico: .quantico in the prompt" -- grep -qF '\h\[\e[2m\].quantico' <<< "$(ishell --hostname pbx01.quantico)"
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
assert_contains "$got" "Asterisk $ast, FreePBX $fpbx" "and the banner of 22.17"
finish
