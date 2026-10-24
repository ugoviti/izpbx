# shellcheck shell=bash
# fail2ban configured from the FAIL2BAN_<SECTION>_<KEY> variables, as
# cfgService_fail2ban of 20.16: each one sets "key=value" in [section] of
# /etc/fail2ban/jail.d/99-local.conf (rootfs template), and the log of
# fail2ban goes to /var/log/fail2ban/fail2ban.log. Debian differences: the
# Apache logs in /var/log/apache2 (template) and backend=auto
# (jail.d/00-izpbx-debian.conf, design C12). An empty variable leaves the
# template value (20.16: the variable was unset).
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh

: "${FAIL2BAN_DIR:=/etc/fail2ban}"

# ini_set FILE SECTION KEY VALUE: in [SECTION] (case insensitive) uncomment
# KEY and set it to VALUE, as iniParser of 20.16; a key missing from the
# section is not added
ini_set() {
  local file=$1 section=$2 key=$3 value
  value=$(sedEscape "$4")
  sed -e "/^\[${section}\]$/I,/^\(\|;\|#\)\[/ s/^\(;\|#\)${key}/${key}/" \
      -e "/^\[${section}\]$/I,/^\[/ s|^${key}.*=.*|${key}=${value}|I" -i "$file"
}

cfg_fail2ban() {
  local var rest section key
  mkdir -p /var/log/fail2ban /run/fail2ban
  ini_set "$FAIL2BAN_DIR/fail2ban.conf" DEFAULT logtarget /var/log/fail2ban/fail2ban.log
  for var in $(compgen -v FAIL2BAN_); do
    rest=${var#FAIL2BAN_}
    [[ "$rest" == *_* ]] || continue
    [ -n "${!var}" ] || continue
    section=${rest%%_*}
    key=${rest#*_}
    ini_set "$FAIL2BAN_DIR/jail.d/99-local.conf" "$section" "${key,,}" "${!var//\'/}"
  done
  _fail2ban_logfiles
  log_info "fail2ban: jails configured (99-local.conf)"
}

# a jail without its log file stops fail2ban: create the empty files the
# enabled jails read (Asterisk and FreePBX write them later; 20.16 created
# the Asterisk full log for the same reason)
_fail2ban_logfiles() {
  local f
  for f in /var/log/asterisk/full /var/log/asterisk/freepbx_security.log ${FAIL2BAN_ASTERISK_LOGPATH:+"$FAIL2BAN_ASTERISK_LOGPATH"}; do
    [ -e "$f" ] && continue
    mkdir -p "$(dirname "$f")"
    install -m 0640 -o "$APP_USR" -g "$APP_GRP" /dev/null "$f"
  done
  # the recidive jail reads the log of fail2ban itself
  for f in /var/log/fail2ban/fail2ban.log /var/log/apache2/error.log /var/log/apache2/access.log; do
    [ -e "$f" ] || install -D -m 0640 -o root -g adm /dev/null "$f"
  done
}
