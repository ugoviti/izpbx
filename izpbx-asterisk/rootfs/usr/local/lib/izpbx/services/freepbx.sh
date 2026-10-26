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

# mode of this start, for the steps after the detection (M1):
#   install    new installation (empty /data)
#   normal     FreePBX 17 found
#   migration  FreePBX 16 found: nothing may write to its data (M2 checks)
#   none       FreePBX not used (IZPBX_ENABLED=false)
: "${IZPBX_MODE_FILE:=/run/izpbx/mode}"
izpbx_mode() { cat "$IZPBX_MODE_FILE" 2>/dev/null || echo none; }
izpbx_mode_set() { mkdir -p "$(dirname "$IZPBX_MODE_FILE")"; echo "$1" > "$IZPBX_MODE_FILE"; }

# FreePBX version in the database (admin.version), empty if not readable
freepbx_db_version() { izpbx_sql_query "SELECT value FROM admin WHERE variable = 'version'" 2>/dev/null | head -n 1 || true; }

# M1: an initialized /data (or a freepbx.conf): the FreePBX version of the
# database says what this start does; prints the mode, dies on a version
# izPBX 22.17 cannot run nor migrate
freepbx_detect() {
  local v major
  _fpbx_dbuser=$MYSQL_USER _fpbx_dbpass=$MYSQL_PASSWORD
  _fpbx_wait_db || die "freepbx: cannot read the FreePBX version: database ${MYSQL_SERVER}:${APP_PORT_MYSQL} not reachable as '${MYSQL_USER}'"
  v=$(freepbx_db_version)
  major=${v%%.*}
  case "$major" in
    17) log_info "freepbx: FreePBX $v found: normal start" >&2; echo normal ;;
    16) log_info "freepbx: FreePBX $v found (izPBX 20.16): migration to FreePBX 17 (M1)" >&2; echo migration ;;
    *)  log_error "freepbx: FreePBX ${v:-<no version>} found in the database '${MYSQL_DATABASE}' on ${MYSQL_SERVER}"
        log_error "freepbx: izPBX 22.17 runs FreePBX 17 and migrates only FreePBX 16 (izPBX 20.16.x)."
        log_error "freepbx: FreePBX 15 or older: upgrade first with izPBX 20.16.x (it upgrades FreePBX to 16), then start 22.17;"
        log_error "freepbx: otherwise check MYSQL_SERVER/MYSQL_DATABASE, or go back to the izPBX image that created this data."
        die "freepbx: unsupported FreePBX version '${v:-unknown}': start refused, nothing changed" ;;
  esac
}

# migration mode: the read only checks M2 (izpbx-preflight), report in the
# log, result ("ok" or "blocked") in /run/izpbx/preflight, then the gate
freepbx_migration_preflight() {
  local report result line
  report=$(izpbx-preflight) && result=ok || result=blocked
  while IFS= read -r line; do log_info "preflight: $line"; done <<< "$report"
  echo "$result" > /run/izpbx/preflight
  freepbx_migration_gate "$result"
}

# after the checks M2 of a FreePBX 16 start (preflight result "ok" or
# "blocked"): without the opt-in IZPBX_MIGRATE_FREEPBX=true, or with a
# blocking check, maintenance mode (D4, S10): the flag keeps every service
# down (service_gate) and makes the healthcheck unhealthy; the logged
# instructions say how to migrate or go back to izPBX 20.16. Returns 1 in
# maintenance mode, 0 when the migration may start.
freepbx_migration_gate() { # preflight-result
  local reason
  if [ "$1" != ok ]; then
    reason="the migration checks found blocking problems (report above and in ${APP_DATA:-/data}/.izpbx-migration)"
  elif [ "$IZPBX_MIGRATE_FREEPBX" != "true" ]; then
    reason="FreePBX 16 data found and the migration to FreePBX 17 is not enabled (IZPBX_MIGRATE_FREEPBX=true)"
  else
    log_info "freepbx: migration to FreePBX 17 enabled (IZPBX_MIGRATE_FREEPBX=true) and nothing blocks it: starting"
    return 0
  fi
  mkdir -p "$(dirname "$IZPBX_MAINTENANCE_FLAG")"
  echo "$reason" > "$IZPBX_MAINTENANCE_FLAG"
  log_warn "freepbx: MAINTENANCE MODE: $reason"
  log_warn "freepbx: no service is started and the healthcheck reports unhealthy; /data and the databases are not changed."
  log_warn "freepbx: to migrate: fix what the checks report (if anything), back up /data and the databases, set IZPBX_MIGRATE_FREEPBX=true and recreate the container;"
  log_warn "freepbx: to keep FreePBX 16: go back to the izPBX 20.16.x image that created this data."
  return 1
}

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

# the backup spool: the backup module of FreePBX 17 creates backup/uploads
# with a non recursive mkdir, so uploading a backup to restore (the first
# thing on a new 22.17 for a 20.16 user) fails until a backup has run
freepbx_backup_dir() {
  install -d -o "$APP_USR" -g "$APP_GRP" "$(freepbx_dir ASTSPOOLDIR)/backup"
}

# fwconsole and amportal in /usr/sbin (not persisted: at every start, 20.16)
freepbx_links() {
  local f
  for f in fwconsole amportal; do
    [ -e "$(freepbx_dir AMPBIN)/$f" ] && ln -sfn "$(freepbx_dir AMPBIN)/$f" "/usr/sbin/$f"
  done
  return 0
}

# umask 002: the files FreePBX writes (reload, module install) get the modes
# of "fwconsole chown" (664), so the chown at every start of
# FREEPBX_FIX_PERMISSION (P3-40) does not change them again (P3-26)
fwconsole_as_asterisk() { su -s /bin/bash "$APP_USR" -c "umask 002; fwconsole $*"; }

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

# FreePBX settings izPBX needs, set by the install and again after the
# restore of a migration (the restore brings back the settings of the 16):
# node 18 resolves localhost to ::1 and AMI listens on IPv4 only, so the UCP
# node server cannot connect with ASTMANAGERHOST=localhost (P0-14); the CDR
# database name of the environment
freepbx_izpbx_settings() {
  fwconsole setting ASTMANAGERHOST 127.0.0.1 >/dev/null 2>&1 || true
  fwconsole setting CDRDBNAME "$MYSQL_DATABASE_CDR" >/dev/null 2>&1 || true
}

# one attempt; its logs in /tmp/freepbx-install/<attempt>/ (install.log and
# module-<name>.log): a later attempt does not overwrite the first error
_fpbx_install_once() { # attempt
  local logdir="/tmp/freepbx-install/$1" log m failed=() dirs
  log="$logdir/install.log"
  mkdir -p "$logdir" && chmod 755 /tmp/freepbx-install "$logdir"
  # the file cache of FreePBX (ASTSPOOLDIR/cache, regenerated by FreePBX) of
  # another installation: in a migration the spool stays in place, and the
  # module list cached by FreePBX 16 ("modulelist_modules", valid a few minutes
  # after the last write) has its modules enabled whatever the new database
  # holds; the installer then builds Certman and Fax too early and stops with
  # "Undefined property: FreePBX::$Certman" (P3-30, the red of P6-03 in CI).
  # The same after a failed attempt of this installation.
  local cache
  cache="$(freepbx_dir ASTSPOOLDIR)/cache"
  if [ -d "$cache" ]; then
    rm -rf "${cache:?}"
    log_info "freepbx: FreePBX file cache $cache removed before the install"
  fi
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
  freepbx_backup_dir
  freepbx_izpbx_settings
  fwconsole chown >/dev/null 2>&1 || true
  fwconsole_as_asterisk ma enablerepo extended >/dev/null 2>&1
  fwconsole_as_asterisk ma enablerepo unsupported >/dev/null 2>&1
  local total n=1
  total=$(echo "$FREEPBX_MODULES_PRE" "$FREEPBX_MODULES_EXTRA" | wc -w)
  for m in $FREEPBX_MODULES_PRE $FREEPBX_MODULES_EXTRA; do
    log_info "freepbx: [$(printf '%02d/%d' "$n" "$total")] installing module $m"
    fwconsole_as_asterisk ma install "$m" > "$logdir/module-$m.log" 2>&1 || true
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
  [ ${#failed[@]} -eq 0 ] || log_warn "freepbx: modules not installed: ${failed[*]} (logs in $logdir/module-<name>.log)"
  fwconsole chown >/dev/null 2>&1 || true
  fwconsole_as_asterisk reload > "$logdir/reload.log" 2>&1 || { log_error "freepbx: fwconsole reload failed ($logdir/reload.log)"; return 1; }
}

# Install attempts from scratch (P3-30). The FreePBX 17 installer fails now and
# then, in a race of its own: the first fpbx_which() of a module being built
# (Certman, Fax) commits its WHICH_<binary> setting, the commit runs the hooks
# while their cache is still empty, the hooks preload that same module and
# PHP stops with "Undefined property: FreePBX::$Certman" (seen on the
# migration in CI). A failed attempt leaves the tables and freepbx.conf of a
# half installation, which a second run of the installer does not repair
# (the voicemail module registered without its tables): when the database was
# empty before the first attempt (a new installation, always the migration
# after M5.2), the tables of the attempt and freepbx.conf/amportal.conf are
# removed before the next one. A database that had tables is never touched,
# nor the CDR database.
# test hook (P3-30): IZPBX_TEST_INSTALL_FAIL_ATTEMPTS=N makes the first N attempts
# fail after the installer ran, as the race above does
_fpbx_test_fail() { # attempt
  [ "${IZPBX_TEST_INSTALL_FAIL_ATTEMPTS:-0}" -ge "$1" ] 2>/dev/null || return 1
  log_warn "freepbx: attempt $1 failed on purpose (IZPBX_TEST_INSTALL_FAIL_ATTEMPTS)"
}
_fpbx_table_count() {
  local db
  db=$(sqlEscape "$MYSQL_DATABASE")
  _fpbx_dbroot "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$db'" 2>/dev/null
}
_fpbx_reset_attempt() {
  local db t sql='SET FOREIGN_KEY_CHECKS = 0;' f
  db=${MYSQL_DATABASE//\`/\`\`}
  for t in $(_fpbx_dbroot "SELECT table_name FROM information_schema.tables WHERE table_schema = '$(sqlEscape "$MYSQL_DATABASE")'" 2>/dev/null); do
    sql+="DROP TABLE IF EXISTS \`$db\`.\`${t//\`/\`\`}\`;"
  done
  _fpbx_dbroot "$sql" >/dev/null || { log_warn "freepbx: cannot remove the tables of the failed attempt"; return 0; }
  for f in "$IZPBX_FREEPBX_CONF" /etc/amportal.conf; do
    [ -e "$f" ] && rm -f "$(readlink -f "$f")"
  done
  log_info "freepbx: the tables of the failed attempt and freepbx.conf removed: the next attempt starts from scratch"
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
  local try=1 rc=1 fresh=false
  _fpbx_wait_db && _fpbx_create_db && [ "$(_fpbx_table_count)" == 0 ] && fresh=true
  while [ "$try" -le "$IZPBX_FREEPBX_INSTALL_TRIES" ]; do
    log_info "freepbx: install attempt $try/$IZPBX_FREEPBX_INSTALL_TRIES"
    if _fpbx_install_once "$try" && ! _fpbx_test_fail "$try"; then rc=0; break; fi
    [ "$fresh" != true ] || _fpbx_reset_attempt
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

# A setting changed here reaches the files FreePBX writes (http_additional.conf,
# rtp.conf, pjsip.transports.conf...) only with a "fwconsole reload": 20.16
# left it to the next "Apply Config" of the user. The flag asks freepbx-start
# to reload once Asterisk is up (P3-37).
: "${IZPBX_FREEPBX_RELOAD_FLAG:=/run/izpbx/freepbx-reload}"
_fpbx_reload_needed() { izpbx_dry_run || { mkdir -p "$(dirname "$IZPBX_FREEPBX_RELOAD_FLAG")" && touch "$IZPBX_FREEPBX_RELOAD_FLAG"; }; }

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
    _fpbx_reload_needed
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
    _fpbx_reload_needed
  done
}

# FreePBX notices that do not apply to izPBX (P3-37), removed at every start:
# - framework GPG_KEY_EXPIRY: at every install or upgrade of framework
#   FreePBX checks the key of the Sangoma Debian repository and tries to
#   write it in /etc/apt/trusted.gpg.d; izPBX installs nothing from that
#   repository (no apt source for it), so the notice "Sangoma Debian
#   Repository GPG Key Expiring Soon" (in 0 days, on unknown) is noise;
# - core core_bindaddress_changed, on a new installation only: core moves the
#   Asterisk HTTP bind address from its default "::" to 127.0.0.1 and says it
#   "updated" it, while nothing was configured before. 127.0.0.1 stays (the
#   FreePBX 17 default): FREEPBX_HTTPBINDADDRESS / FREEPBX_HTTPTLSBINDADDRESS
#   open it to the network (WebRTC, ARI from outside).
freepbx_notices_cleanup() {
  local ids=(framework:GPG_KEY_EXPIRY) id
  [ "$(izpbx_mode)" != install ] || ids+=(core:core_bindaddress_changed)
  for id in "${ids[@]}"; do
    izpbx_do fwconsole notifications --delete "${id%%:*}" "${id#*:}" >/dev/null 2>&1 || true
  done
}

# HEP (Homer capture), as 20.16 (P3-39): "enabled" of hep.conf from
# HEP_ENABLED (true: yes, anything else: no), only when the variable is set
# and the file exists; hep.conf is not touched otherwise
cfg_asterisk_hep() {
  local f=/etc/asterisk/hep.conf v=no
  [ -n "$HEP_ENABLED" ] && [ -e "$f" ] || return 0
  [ "$HEP_ENABLED" == true ] && v=yes
  sed --follow-symlinks "s/^enabled =.*/enabled = $v/" -i "$f"
  log_info "asterisk: HEP capture enabled = $v (HEP_ENABLED)"
}

# fwconsole chown at every start with FREEPBX_FIX_PERMISSION=true, as 20.16
# (P3-40); not after the first installation, which has just done it
freepbx_fix_permission() {
  [ "$FREEPBX_FIX_PERMISSION" == true ] || return 0
  [ "$(izpbx_mode)" != install ] || return 0
  log_info "freepbx: fixing the permissions of the FreePBX and Asterisk files (FREEPBX_FIX_PERMISSION)"
  izpbx_do fwconsole chown >/dev/null 2>&1 || log_warn "freepbx: fwconsole chown failed"
}

# The dialplan of FreePBX includes a "<context>-custom" for many of its
# contexts, for the user's extensions_custom.conf; the ones nobody defines
# make Asterisk write a WARNING "tries to include nonexistent context" for
# each, at every start and reload (about 130 on a new installation). As 20.16
# (P3-41), they are defined empty in freepbx_custom_fix_missing_contexts.conf,
# included from extensions_custom.conf; a context defined later by the user
# in extensions_custom.conf leaves the list at the next start. Only the
# "-custom" ones, plus the list of 20.16 (ext-meetme, ext-queues,
# app-recordings) and ext-cf-hints (callforward writes it only when there
# are call forward hints), each only when included and defined nowhere:
# parkedcalls and others are created by Asterisk modules.
freepbx_missing_contexts() {
  local etc=/etc/asterisk out custom ctx missing
  out="$etc/freepbx_custom_fix_missing_contexts.conf"
  custom="$etc/extensions_custom.conf"
  [ -e "$etc/extensions_additional.conf" ] || return 0
  missing=$(comm -23 \
    <(grep -hE '^include[[:space:]]*=>[[:space:]]*([^[:space:],;]*-custom|ext-cf-hints|ext-meetme|ext-queues|app-recordings)([[:space:],;]|$)' "$etc"/extensions*.conf 2>/dev/null | sed 's/^include[[:space:]]*=>[[:space:]]*//; s/[,;[:space:]].*//' | sort -u) \
    <(grep -ho '^\[[^]]*\]' "$etc"/extensions*.conf 2>/dev/null | tr -d '[]' | sort -u))
  {
    echo "; generated by izPBX at every start: the contexts included by FreePBX"
    echo "; and defined nowhere, empty (define yours in extensions_custom.conf)"
    for ctx in $missing; do printf '[%s]\n\n' "$ctx"; done
  } > "$out.new"
  mv -f "$out.new" "$out"
  [ -e "$custom" ] || : > "$custom"
  grep -qxF '#include freepbx_custom_fix_missing_contexts.conf' "$custom" ||
    echo '#include freepbx_custom_fix_missing_contexts.conf' >> "$custom"
  # the owner and modes of "fwconsole chown": the same after every start (P3-26)
  chown "$APP_USR:$APP_GRP" "$out" "$custom"
  chmod 664 "$out"
  log_info "freepbx: $(wc -w <<< "$missing") empty contexts in $out"
}
