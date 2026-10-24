# shellcheck shell=bash
# FreePBX 17 first install, as cfgService_freepbx_install of 20.16, from the
# tree the image carries (/usr/src/freepbx, build/freepbx.sh): offline, the
# modules are already unpacked and verified (D19).
# - databases MYSQL_DATABASE and MYSQL_DATABASE_CDR and the user MYSQL_USER
#   created with MYSQL_ROOT_PASSWORD; without it they must exist (20.16);
# - installer with --skip-install (framework, core, dashboard, voicemail,
#   sipsettings), then the repos extended and unsupported, the modules of
#   FREEPBX_MODULES_PRE and FREEPBX_MODULES_EXTRA (the 20.16 lists, without
#   phonebook: no FreePBX 17 release, D28), FREEPBX_MODULES_DISABLED disabled,
#   FREEPBX_AUTOUPDATE_MODULES_FIRSTDEPLOY=true upgrades them;
# - Asterisk runs during the install outside s6 (the services start after
#   izpbx-init) and is stopped at the end;
# - ${APP_DATA}/.initialized gets the FreePBX version.
# fwconsole runs as asterisk: as root it exits 1 even on success (P0-10).
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh
# shellcheck source=../persistence.sh
. /usr/local/lib/izpbx/persistence.sh
# shellcheck source=../actions.sh
. /usr/local/lib/izpbx/actions.sh

: "${IZPBX_FREEPBX_SRC:=/usr/src/freepbx}"
: "${IZPBX_FREEPBX_CONF:=/etc/freepbx.conf}"
: "${IZPBX_FREEPBX_INSTALL_TRIES:=5}"
: "${IZPBX_FREEPBX_DB_WAIT:=120}"
: "${FREEPBX_MODULES_PRE:=userman pm2}"
: "${FREEPBX_MODULES_EXTRA:=soundlang callrecording cdr conferences customappsreg featurecodeadmin infoservices logfiles music manager arimanager filestore recordings announcement asteriskinfo backup callforward callwaiting daynight calendar certman cidlookup contactmanager donotdisturb fax findmefollow iaxsettings miscapps miscdests ivr parking presencestate printextensions queues cel timeconditions bulkhandler weakpasswords ucp}"
: "${FREEPBX_MODULES_DISABLED:=}"
: "${FREEPBX_AUTOUPDATE_MODULES_FIRSTDEPLOY:=false}"

freepbx_installed() { [ -s "$IZPBX_FREEPBX_CONF" ]; }

# FreePBX directories, as fpbxDirs of 20.16: under APP_DATA the real paths,
# not the symlinks of persistence.sh ("fwconsole chown" does not follow a
# symlinked /etc/asterisk); the settings of a restored 20.16 backup match
freepbx_dir() { # setting
  local d
  case "$1" in
    AMPWEBROOT) d=/var/www/html ;;
    ASTETCDIR) d=/etc/asterisk ;;
    ASTVARLIBDIR) d=/var/lib/asterisk ;;
    ASTAGIDIR) d=/var/lib/asterisk/agi-bin ;;
    ASTSPOOLDIR) d=/var/spool/asterisk ;;
    ASTLOGDIR) d=/var/log/asterisk ;;
    AMPBIN) d=/var/lib/asterisk/bin ;;
    AMPSBIN) d=/var/lib/asterisk/sbin ;;
    AMPCGIBIN) d=/var/www/cgi-bin ;;
    AMPPLAYBACK) d=/var/lib/asterisk/playback ;;
    *) return 1 ;;
  esac
  echo "$APP_DATA$d"
}
freepbx_dir_options() {
  printf -- '--webroot=%s --astetcdir=%s --astvarlibdir=%s --astagidir=%s --astspooldir=%s --astlogdir=%s ' \
    "$(freepbx_dir AMPWEBROOT)" "$(freepbx_dir ASTETCDIR)" "$(freepbx_dir ASTVARLIBDIR)" "$(freepbx_dir ASTAGIDIR)" \
    "$(freepbx_dir ASTSPOOLDIR)" "$(freepbx_dir ASTLOGDIR)"
  printf -- '--ampbin=%s --ampsbin=%s --ampcgibin=%s --ampplayback=%s --astrundir=/var/run/asterisk --astmoddir=/usr/lib64/asterisk/modules\n' \
    "$(freepbx_dir AMPBIN)" "$(freepbx_dir AMPSBIN)" "$(freepbx_dir AMPCGIBIN)" "$(freepbx_dir AMPPLAYBACK)"
}

# the installer takes some directories from asterisk.conf (the symlinks)
# whatever the options say: set them in the FreePBX settings, as 20.16 did
# at every start ("fixing directory system paths in db configuration")
freepbx_fix_paths() {
  [ -n "$APP_DATA" ] || return 0
  local k want cur
  for k in AMPWEBROOT ASTETCDIR ASTVARLIBDIR ASTAGIDIR ASTSPOOLDIR ASTLOGDIR AMPBIN AMPSBIN AMPCGIBIN AMPPLAYBACK; do
    want=$(freepbx_dir "$k")
    cur=$(fwconsole setting "$k" 2>/dev/null | awk -F'[][]' '{print $2}') || true
    [ "$cur" == "$want" ] && continue
    log_info "freepbx: setting $k=$want (was ${cur:-unset})"
    fwconsole setting "$k" "$want" >/dev/null 2>&1 || log_warn "freepbx: cannot set $k"
  done
}

# database connection of an installed FreePBX from the environment, at every
# start (20.16): the values are PHP-escaped and written without sed, the
# password never on a command line (P3-21); an empty value is not applied
freepbx_conf_update() {
  local f=$IZPBX_FREEPBX_CONF k var _fpbx_val
  for k in AMPDBHOST:MYSQL_SERVER AMPDBPORT:APP_PORT_MYSQL AMPDBNAME:MYSQL_DATABASE AMPDBUSER:MYSQL_USER AMPDBPASS:MYSQL_PASSWORD; do
    var=${k#*:}; k=${k%%:*}
    [ -n "${!var}" ] || continue
    _fpbx_val="$(phpSquote "${!var}")';"
    set_line_secret "$f" "^[$]amp_conf[[]'$k'[]] *=" "\$amp_conf['$k'] = '" _fpbx_val ||
      { log_warn "freepbx: cannot update $k in $f"; return 0; }
  done
}

# fwconsole and amportal in /usr/sbin (not persisted: at every start, 20.16)
freepbx_links() {
  local f
  for f in fwconsole amportal; do
    [ -e "$(freepbx_dir AMPBIN)/$f" ] && ln -sfn "$(freepbx_dir AMPBIN)/$f" "/usr/sbin/$f"
  done
  return 0
}

fwconsole_as_asterisk() { su -s /bin/bash "$APP_USR" -c "fwconsole $*"; }

# database as root (or as MYSQL_USER without MYSQL_ROOT_PASSWORD)
_fpbx_dbroot() {
  # password in the environment, statement on stdin (CREATE USER holds a
  # password): nothing secret on the command line (P3-21)
  printf '%s\n' "$1" | MYSQL_PWD="${_fpbx_dbpass}" mysql --connect-timeout=5 -h "$MYSQL_SERVER" -P "$APP_PORT_MYSQL" -u "$_fpbx_dbuser" -N -B
}

_fpbx_wait_db() {
  local start=$SECONDS
  until _fpbx_dbroot "SELECT 1" >/dev/null 2>&1; do
    if [ $((SECONDS - start)) -ge "$IZPBX_FREEPBX_DB_WAIT" ]; then
      log_error "freepbx: database ${MYSQL_SERVER}:${APP_PORT_MYSQL} not reachable as '${_fpbx_dbuser}' after ${IZPBX_FREEPBX_DB_WAIT}s"
      return 1
    fi
    log_info "freepbx: waiting for the database ${MYSQL_SERVER}:${APP_PORT_MYSQL}..."
    sleep 5
  done
}

_fpbx_create_db() {
  local user pass db cdr
  user=$(sqlEscape "$MYSQL_USER"); pass=$(sqlEscape "$MYSQL_PASSWORD")
  db=${MYSQL_DATABASE//\`/\`\`}; cdr=${MYSQL_DATABASE_CDR//\`/\`\`}
  if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
    log_info "freepbx: creating the databases ${MYSQL_DATABASE}, ${MYSQL_DATABASE_CDR} and the user ${MYSQL_USER}"
    _fpbx_dbroot "CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$pass';
      CREATE DATABASE IF NOT EXISTS \`$db\`; GRANT ALL PRIVILEGES ON \`$db\`.* TO '$user'@'%' WITH GRANT OPTION;
      CREATE DATABASE IF NOT EXISTS \`$cdr\`; GRANT ALL PRIVILEGES ON \`$cdr\`.* TO '$user'@'%' WITH GRANT OPTION;" || return 1
  else
    log_info "freepbx: no MYSQL_ROOT_PASSWORD, the databases must exist"
  fi
  _fpbx_dbroot "USE \`$db\`" || { log_error "freepbx: no access to the database ${MYSQL_DATABASE}"; return 1; }
  _fpbx_dbroot "USE \`$cdr\`" || { log_error "freepbx: no access to the database ${MYSQL_DATABASE_CDR}"; return 1; }
}

# Asterisk outside s6 while izpbx-init runs
_fpbx_asterisk_start() {
  asterisk -rx 'core show version' >/dev/null 2>&1 && return 0
  asterisk -U "$APP_USR" -G "$APP_GRP"
  local _
  for _ in $(seq 1 60); do
    asterisk -rx 'core waitfullybooted' >/dev/null 2>&1 && return 0
    sleep 1
  done
  log_error "freepbx: Asterisk did not start"
  return 1
}
_fpbx_asterisk_stop() {
  asterisk -rx 'core stop now' >/dev/null 2>&1 || return 0
  local _
  for _ in $(seq 1 30); do pidof asterisk >/dev/null || return 0; sleep 1; done
  pkill -9 -x asterisk || true
}

_fpbx_install_once() {
  local log=/tmp/freepbx-install.log m failed=() dirs
  read -r -a dirs <<< "$(freepbx_dir_options)"
  _fpbx_wait_db && _fpbx_create_db || return 1
  [ -s /etc/machine-id ] || tr -d - < /proc/sys/kernel/random/uuid > /etc/machine-id
  _fpbx_asterisk_start || return 1
  log_info "freepbx: running the FreePBX $(_izpbx_version FREEPBX_FRAMEWORK_VER) installer"
  # the installer takes the password only as --dbpass: freepbx-install.php
  # adds it from the environment, so it is not on any command line (P3-21)
  # NOTE: the 17.0.33 installer exits 1 even when it reports success
  ( cd "$IZPBX_FREEPBX_SRC" && IZPBX_INSTALL_DBPASS=$MYSQL_PASSWORD php /usr/local/share/izpbx/freepbx-install.php \
      -n --skip-install --no-ansi --dbhost="$MYSQL_SERVER" --dbport="$APP_PORT_MYSQL" \
      --dbuser="$MYSQL_USER" --dbname="$MYSQL_DATABASE" --cdrdbname="$MYSQL_DATABASE_CDR" \
      "${dirs[@]}" ) > "$log" 2>&1 || true
  if ! grep -q 'You have successfully installed FreePBX' "$log"; then
    log_error "freepbx: installer failed, last lines of $log:"
    tail -n 15 "$log" >&2
    return 1
  fi
  # the installer writes freepbx.conf root:root 0660 and "fwconsole chown"
  # does not follow the symlink to /data: asterisk must read it (20.16 did
  # the same in freepbxSettingsFix)
  for m in "$IZPBX_FREEPBX_CONF" /etc/amportal.conf; do
    [ -e "$m" ] && chown "$APP_USR:$APP_GRP" "$(readlink -f "$m")"
  done
  freepbx_links
  freepbx_fix_paths
  # node 18 resolves localhost to ::1, AMI listens on IPv4 only (P0-14)
  fwconsole setting ASTMANAGERHOST 127.0.0.1 >/dev/null 2>&1 || true
  fwconsole setting CDRDBNAME "$MYSQL_DATABASE_CDR" >/dev/null 2>&1 || true
  fwconsole chown >/dev/null 2>&1 || true
  fwconsole_as_asterisk ma enablerepo extended >/dev/null 2>&1
  fwconsole_as_asterisk ma enablerepo unsupported >/dev/null 2>&1
  local total n=1
  total=$(echo "$FREEPBX_MODULES_PRE" "$FREEPBX_MODULES_EXTRA" | wc -w)
  for m in $FREEPBX_MODULES_PRE $FREEPBX_MODULES_EXTRA; do
    log_info "freepbx: [$(printf '%02d/%d' "$n" "$total")] installing module $m"
    fwconsole_as_asterisk ma install "$m" > "/tmp/freepbx-module-$m.log" 2>&1 || true
    fwconsole_as_asterisk ma list 2>/dev/null | grep -qE "^\| $m +\| [^ ]+ +\| Enabled" || failed+=("$m")
    n=$((n + 1))
  done
  for m in $FREEPBX_MODULES_DISABLED; do
    log_info "freepbx: disabling module $m"
    fwconsole_as_asterisk ma disable "$m" >/dev/null 2>&1 || log_warn "freepbx: cannot disable module $m"
  done
  if [ "$FREEPBX_AUTOUPDATE_MODULES_FIRSTDEPLOY" == "true" ]; then
    log_info "freepbx: upgrading the modules (FREEPBX_AUTOUPDATE_MODULES_FIRSTDEPLOY)"
    fwconsole_as_asterisk ma upgradeall >/dev/null 2>&1 || log_warn "freepbx: module upgrade failed"
  fi
  [ ${#failed[@]} -eq 0 ] || log_warn "freepbx: modules not installed: ${failed[*]} (logs in /tmp/freepbx-module-<name>.log)"
  fwconsole chown >/dev/null 2>&1 || true
  fwconsole_as_asterisk reload >/dev/null 2>&1 || { log_error "freepbx: fwconsole reload failed"; return 1; }
}

freepbx_install() {
  if izpbx_dry_run; then
    izpbx_record "freepbx install: databases ${MYSQL_DATABASE}/${MYSQL_DATABASE_CDR} on ${MYSQL_SERVER}, modules: $FREEPBX_MODULES_PRE $FREEPBX_MODULES_EXTRA"
    return 0
  fi
  # the installer writes the password unescaped in a PHP single quoted string:
  # a quote, or a backslash before a backslash, a quote or the end, would break it
  if [[ "$MYSQL_PASSWORD" == *"'"* || "$MYSQL_PASSWORD" == *'\\'* || "$MYSQL_PASSWORD" == *'\' ]]; then
    die "freepbx: MYSQL_PASSWORD not supported by the FreePBX installer: single quote, double backslash or final backslash"
  fi
  [ -n "$MYSQL_PASSWORD" ] || die "freepbx: MYSQL_PASSWORD is empty"
  _fpbx_dbuser=$MYSQL_ROOT_USER _fpbx_dbpass=$MYSQL_ROOT_PASSWORD
  [ -n "$MYSQL_ROOT_PASSWORD" ] || { _fpbx_dbuser=$MYSQL_USER; _fpbx_dbpass=$MYSQL_PASSWORD; }
  log_info "freepbx: NEW INSTALLATION: FreePBX not initialized, installing"
  local try=1 rc=1
  while [ "$try" -le "$IZPBX_FREEPBX_INSTALL_TRIES" ]; do
    log_info "freepbx: install attempt $try/$IZPBX_FREEPBX_INSTALL_TRIES"
    if _fpbx_install_once; then rc=0; break; fi
    try=$((try + 1))
    [ "$try" -le "$IZPBX_FREEPBX_INSTALL_TRIES" ] && sleep 10
  done
  _fpbx_asterisk_stop
  [ "$rc" -eq 0 ] || die "freepbx: install failed after $IZPBX_FREEPBX_INSTALL_TRIES attempts"
  persistence_mark_initialized "$(fwconsole -V 2>/dev/null | awk '{print $NF}')"
  log_info "freepbx: FreePBX $(fwconsole -V 2>/dev/null | awk '{print $NF}') installed"
}

# Advanced Settings and SIP Settings from the environment, at every start, as
# 20.16: every non-empty FREEPBX_<KEY> sets the FreePBX setting KEY when it
# differs (FREEPBX_* used by izPBX itself are skipped, design C20); the SIP
# Settings rtpstart/rtpend (APP_PORT_RTP_*) and the PJSIP udp/tcp port
# (APP_PORT_PJSIP). The chan_sip bindport of 20.16 (APP_PORT_SIP) is gone
# (design C19: APP_PORT_SIP becomes the legacy PJSIP transport, M6).
freepbx_setting_skipped() { # variable name
  case "$1" in
    FREEPBX_MODULES_*|FREEPBX_AUTOUPGRADE_*|FREEPBX_AUTOUPDATE_MODULES_FIRSTDEPLOY|FREEPBX_FIX_PERMISSION*|FREEPBX_VER*) return 0 ;;
    FREEPBX_FRAMEWORK_VER|FREEPBX_SHA256) return 0 ;;
  esac
  return 1
}

cfg_freepbx_settings() {
  local var k v cur
  for var in $(compgen -v FREEPBX_); do
    freepbx_setting_skipped "$var" && continue
    k=${var#FREEPBX_}
    v=${!var}
    [ -n "$v" ] || continue
    cur=
    izpbx_dry_run || cur=$(fwconsole setting "$k" 2>/dev/null | awk -F'[][{}]' '{print $2}') || true
    [ "$cur" == "true" ] && cur=1
    [ "$cur" == "false" ] && cur=0
    [ "$cur" == "$v" ] && continue
    log_info "freepbx: advanced setting $k=$v"
    fpbx_setting "$k" "$v" >/dev/null 2>&1 || true
  done

  local -A sip=([rtpstart]=$APP_PORT_RTP_START [rtpend]=$APP_PORT_RTP_END
                [udpport-0.0.0.0]=$APP_PORT_PJSIP [tcpport-0.0.0.0]=$APP_PORT_PJSIP)
  for k in "${!sip[@]}"; do
    v=${sip[$k]}
    [ -n "$v" ] || continue
    cur=
    izpbx_dry_run || cur=$(fpbx_sipsetting_get "$k") || true
    [ "$cur" == "$v" ] && continue
    log_info "freepbx: sip setting $k=$v"
    fpbx_sipsetting "$k" "$v" >/dev/null 2>&1 || log_warn "freepbx: cannot set the sip setting $k"
  done
}
