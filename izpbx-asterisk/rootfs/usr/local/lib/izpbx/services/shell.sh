# shellcheck shell=bash
# The interactive shell of root (P3-29): /root/.bashrc sources the izPBX
# bashrc of the image (banner, version line, prompt, aliases as 20.16). /root
# is persisted under APP_DATA: written at every start after the persistence
# step, as 20.16 did (cfgBashEnv), so a volume of 20.16, whose .bashrc calls
# figlet with the versions of then, gets the 22.17 one. Your own lines go in
# /root/.bashrc.local, which stays.
# shellcheck source=../common.sh
. /usr/local/lib/izpbx/common.sh

IZPBX_BASHRC_LINE='[ -r /usr/local/share/izpbx/bashrc ] && . /usr/local/share/izpbx/bashrc'

cfg_shell() {
  mkdir -p "${IZPBX_ROOT:-}/root"
  printf '# written by izpbx-init at every start: your own lines go in /root/.bashrc.local\n%s\n' \
    "$IZPBX_BASHRC_LINE" > "${IZPBX_ROOT:-}/root/.bashrc"
  log_info "shell: /root/.bashrc written (izPBX banner and prompt; own lines in /root/.bashrc.local)"
}
