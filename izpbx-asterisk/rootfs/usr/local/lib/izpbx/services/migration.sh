# shellcheck shell=bash
# FreePBX 16 -> 17 migration (design §7), the phases after the checks M2:
#   migration_inventory_before  M3: inventory of FreePBX 16 (DB + files)
#   migration_snapshot   M4: verified dumps, directories moved, spool hardlinked
#   migration_archive    M5.1: FreePBX "legacy" backup archive from the raw data
#   migration_restore    M5.2-M5.4: config database recreated, FreePBX 17
#                        installed with the modules of the 16, archive restored
#   migration_sip_transport  M6: PJSIP transport on APP_PORT_SIP for the
#                        trunks that were on chan_sip (D3, C19)
#   migration_audio      M6: custom prompts, sounds/custom and music on hold
#                        from the snapshot
#   migration_astdb      M6: astdb keys the restore did not bring back
#   migration_spool      M6: voicemail and recordings left in place: counted,
#                        owned by asterisk
#   migration_crontab    M6: custom crontab lines of 20.16 in the Debian spool
#   migration_fop2       M6: FOP2 installed from its Debian package, fop2.cfg
#                        and the license of 20.16 kept
#   migration_confs      M6: configuration files FreePBX does not write
#                        (dongle.conf) from the snapshot
#   migration_verify     M7: inventory after = before (mapping), or maintenance
# State in ${APP_DATA}/.izpbx-migration/state ("KEY=value" lines): the
# snapshot directory and the phases completed; every phase is idempotent and
# a restart resumes from the last completed one. Nothing is deleted: the
# directories are moved (same filesystem: instant, no extra space) and the
# spool, possibly many GB, is copied with hardlinks.
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=freepbx.sh
. /usr/local/lib/izpbx/services/freepbx.sh

: "${IZPBX_MIGRATION_DIR:=${APP_DATA:-/data}/.izpbx-migration}"
# moved into the snapshot (M4.2), relative to APP_DATA
IZPBX_MIGRATION_MOVE=(var/www var/lib/asterisk etc/asterisk home/asterisk usr/local/fop2 var/spool/cron etc/freepbx.conf etc/amportal.conf)
# copied with hardlinks (M4.3): it stays in place for the restore
IZPBX_MIGRATION_LINK=(var/spool/asterisk)
# modules with no FreePBX 17 release the migration leaves out on purpose
# (D28: phonebook, installed by default by izPBX 20.16; its data: P4-31)
IZPBX_MIGRATION_REMOVED_MODULES="phonebook"

migration_state() { # KEY -> value ("" if not set)
  [ -f "$IZPBX_MIGRATION_DIR/state" ] || return 0
  sed -n "s/^$1=//p" "$IZPBX_MIGRATION_DIR/state" | tail -n 1
}
# a migration started (snapshot) and not completed (state "migration=done",
# M8): resumed at the next start whatever the database holds (it may be
# empty after M5.2); the phases already done are skipped
migration_in_progress() { [ -n "$(migration_state snapshot_dir)" ] && [ "$(migration_state migration)" != "done" ]; }

# expected differences of the inventories before and after (M7)
: "${IZPBX_MIGRATION_MAPPING:=/usr/local/share/izpbx/migration-mapping.tsv}"

# test hook (P4-06, design T7): IZPBX_TEST_KILL_AT=<point> kills izpbx-init
# (kill -9) once at that point of the migration, as a crash or a container
# killed there; the restart must resume and complete it. Points: snapshot
# (after the first directory moved), archive (before the tar), dbreset
# (after the DROP of the config database), install (after FreePBX 17 is
# installed), restore (after the restore), audio (in M6, after the copy).
: "${IZPBX_TEST_KILL_AT:=}"
# test hook (P4-19): IZPBX_TEST_AFTER_RESTORE_SQL, a statement run on the
# config database right before the verification M7 (a discrepancy injected
# after the restore)
: "${IZPBX_TEST_AFTER_RESTORE_SQL:=}"

migration_kill_point() { # point
  [ -n "$IZPBX_TEST_KILL_AT" ] && [ "$IZPBX_TEST_KILL_AT" == "$1" ] || return 0
  [ ! -e "$IZPBX_MIGRATION_DIR/test-killed-$1" ] || return 0
  mkdir -p "$IZPBX_MIGRATION_DIR" && touch "$IZPBX_MIGRATION_DIR/test-killed-$1"
  log_warn "migration: test kill at '$1' (IZPBX_TEST_KILL_AT)"
  kill -KILL $$
}

migration_state_set() { # KEY VALUE
  mkdir -p "$IZPBX_MIGRATION_DIR"
  printf '%s=%s\n' "$1" "$2" >> "$IZPBX_MIGRATION_DIR/state"
}

# database credentials for the migration: root when MYSQL_ROOT_PASSWORD is
# set, else MYSQL_USER
_migration_dbuser() { if [ -n "$MYSQL_ROOT_PASSWORD" ]; then echo "$MYSQL_ROOT_USER"; else echo "$MYSQL_USER"; fi; }
_migration_dbpass() { if [ -n "$MYSQL_ROOT_PASSWORD" ]; then echo "$MYSQL_ROOT_PASSWORD"; else echo "$MYSQL_PASSWORD"; fi; }

# mariadb-dump of one database, gzip, verified: exit status of the dump and
# of gzip, the whole file read back (gzip -t and the "Dump completed" last
# line), sha256 in SHA256SUMS. Root when MYSQL_ROOT_PASSWORD is set, else
# MYSQL_USER (secrets in the environment, not on the command line).
_migration_dump() { # database file
  local tmp="$2.part" st
  MYSQL_PWD="$(_migration_dbpass)" mariadb-dump -h "$MYSQL_SERVER" -P "$APP_PORT_MYSQL" -u "$(_migration_dbuser)" \
    --single-transaction --routines --triggers --events --databases "$1" | gzip > "$tmp"
  st="${PIPESTATUS[0]}${PIPESTATUS[1]}"
  [ "$st" == 00 ] || { rm -f "$tmp"; log_error "migration: dump of '$1' failed"; return 1; }
  gzip -t "$tmp" || { rm -f "$tmp"; log_error "migration: dump of '$1' unreadable"; return 1; }
  gzip -dc "$tmp" | tail -n 1 | grep -q '^-- Dump completed' || { rm -f "$tmp"; log_error "migration: dump of '$1' incomplete"; return 1; }
  mv "$tmp" "$2"
  (cd "$(dirname "$2")" && sha256sum "$(basename "$2")") >> "$(dirname "$2")/SHA256SUMS"
  log_info "migration: database '$1' dumped to $2 ($(du -k "$2" | cut -f1) KB)"
}

_migration_dump_ok() { # file: present and matching its SHA256SUMS line
  [ -s "$1" ] && (cd "$(dirname "$1")" && grep " $(basename "$1")\$" SHA256SUMS 2>/dev/null | tail -n 1 | sha256sum -c --status)
}

migration_snapshot() {
  local ts snap rel src dst
  if [ "$(migration_state snapshot)" == "done" ]; then
    log_info "migration: snapshot already done ($(migration_state snapshot_dir))"
    return 0
  fi
  snap=$(migration_state snapshot_dir)
  if [ -z "$snap" ]; then
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    snap="$IZPBX_MIGRATION_DIR/$ts"
    migration_state_set snapshot_dir "$snap"
  fi
  mkdir -p "$snap/db" "$snap/fs"
  log_info "migration: snapshot in $snap"

  # 1. databases: before anything is moved
  for db in "$MYSQL_DATABASE" "$MYSQL_DATABASE_CDR"; do
    _migration_dump_ok "$snap/db/$db.sql.gz" && continue
    _migration_dump "$db" "$snap/db/$db.sql.gz" || return 1
  done

  # 2. directories and files moved (a missing source already moved, or never there)
  for rel in "${IZPBX_MIGRATION_MOVE[@]}"; do
    src="$APP_DATA/$rel" dst="$snap/fs/$rel"
    if [ -e "$src" ] || [ -L "$src" ]; then
      [ -e "$dst" ] && { log_error "migration: $rel is both in $APP_DATA and in the snapshot"; return 1; }
      mkdir -p "$(dirname "$dst")"
      mv "$src" "$dst"
      log_info "migration: $rel moved to the snapshot"
      migration_kill_point snapshot
    elif [ ! -e "$dst" ]; then
      log_info "migration: $rel not present, nothing to move"
    fi
  done

  # 3. spool copied with hardlinks (a partial copy of an interrupted run is redone)
  for rel in "${IZPBX_MIGRATION_LINK[@]}"; do
    src="$APP_DATA/$rel" dst="$snap/fs/$rel"
    [ -e "$src" ] || { log_info "migration: $rel not present, nothing to link"; continue; }
    [ ! -e "$dst" ] || rm -rf "${dst:?}"
    mkdir -p "$(dirname "$dst")"
    cp -al "$src" "$dst"
    log_info "migration: $rel linked in the snapshot"
  done

  migration_state_set snapshot "done"
  log_info "migration: snapshot done"
}

# M5.1: the archive the FreePBX 17 Backup module restores as a "legacy"
# backup (format validated by the prototype P0-10, Handlers/Restore/Legacy.php):
#   manifest      JSON: pbx_version, fpbx_db, fpbx_cdrdb, file_list
#   astdb         JSON: family -> key -> value (astdb.sqlite3 of the snapshot)
#   mysql-2.sql   config database, one INSERT per line (the restore parses it
#                 line by line into SQLite), no CREATE DATABASE
#   etc/asterisk/*_custom*.conf   of the snapshot
#   etc/asterisk/voicemail.conf   the mailboxes: the voicemail module restores
#                 it from a legacy archive (not the spool, which would be
#                 deleted and copied again: it stays in place)
#   etc/asterisk/keys/            the certificates: certman restores them from a
#                 legacy archive, its tables point to them (default certificate,
#                 used by the HTTPS vhost too)
# The CDR database is not in the archive: the migration does not touch it.
# Output: <snapshot>/backup/izpbx-migration.tar.gz (+ .sha256).
migration_archive() {
  local snap work arc version st
  if [ "$(migration_state archive)" == "done" ]; then
    log_info "migration: archive already built ($(migration_state archive_file))"
    return 0
  fi
  [ "$(migration_state snapshot)" == "done" ] || { log_error "migration: no snapshot, the archive needs it"; return 1; }
  snap=$(migration_state snapshot_dir)
  arc="$snap/backup/izpbx-migration.tar.gz" work="$snap/backup/legacy"
  [ ! -e "$work" ] || rm -rf "${work:?}"
  mkdir -p "$work/etc/asterisk"

  st=0
  MYSQL_PWD="$(_migration_dbpass)" mariadb-dump -h "$MYSQL_SERVER" -P "$APP_PORT_MYSQL" -u "$(_migration_dbuser)" \
    --skip-extended-insert --skip-dump-date --skip-comments --no-create-db --single-transaction \
    "$MYSQL_DATABASE" > "$work/mysql-2.sql" || st=$?
  [ "$st" -eq 0 ] && grep -q '^CREATE TABLE `admin`' "$work/mysql-2.sql" || { log_error "migration: legacy dump of '$MYSQL_DATABASE' failed"; return 1; }
  version=$(printf "SELECT value FROM admin WHERE variable = 'version'\n" | MYSQL_PWD="$(_migration_dbpass)" mariadb -h "$MYSQL_SERVER" \
    -P "$APP_PORT_MYSQL" -u "$(_migration_dbuser)" --batch --skip-column-names "$MYSQL_DATABASE")
  [ -n "$version" ] || { log_error "migration: no FreePBX version (admin.version) in '$MYSQL_DATABASE'"; return 1; }

  # astdb and manifest as JSON (PHP: pdo_sqlite is in the image)
  php -r '
    [$astdbfile, $out, $version, $db, $cdrdb] = array_slice($argv, 1);
    $astdb = [];
    if (is_file($astdbfile)) {
      foreach ((new PDO("sqlite:" . $astdbfile))->query("SELECT key, value FROM astdb") as $r) {
        $p = explode("/", trim($r[0], "/"), 2);
        if (count($p) == 2) $astdb[$p[0]][$p[1]] = $r[1];
      }
    }
    file_put_contents("$out/astdb", json_encode($astdb ?: new stdClass));
    file_put_contents("$out/manifest", json_encode([
      "pbx_version" => $version, "fpbx_db" => $db, "fpbx_cdrdb" => $cdrdb,
      "name" => "izpbx-migration", "hostname" => gethostname(), "emailaddr" => "", "ctime" => time(),
      "mysql_count" => 1, "astdb_count" => count($astdb), "file_count" => 0,
      "file_list" => ["etc" => ["asterisk" => new stdClass]],
    ]));
  ' -- "$snap/fs/var/lib/asterisk/astdb.sqlite3" "$work" "$version" "$MYSQL_DATABASE" "$MYSQL_DATABASE_CDR" ||
    { log_error "migration: cannot write astdb and manifest"; return 1; }
  find "$snap/fs/etc/asterisk" -maxdepth 1 \( -name '*_custom*.conf' -o -name voicemail.conf \) \
    -exec cp -p {} "$work/etc/asterisk/" \; 2>/dev/null || true
  [ ! -d "$snap/fs/etc/asterisk/keys" ] || cp -a "$snap/fs/etc/asterisk/keys" "$work/etc/asterisk/"

  migration_kill_point archive
  tar -C "$work" -czf "$arc.part" . && mv "$arc.part" "$arc" || { log_error "migration: cannot write $arc"; return 1; }
  (cd "$(dirname "$arc")" && sha256sum "$(basename "$arc")" > "$(basename "$arc").sha256")
  log_info "migration: archive $arc (FreePBX $version, $(wc -l < "$work/mysql-2.sql") SQL lines, $(find "$work/etc/asterisk" -type f | wc -l) files of etc/asterisk)"
  rm -rf "${work:?}"
  migration_state_set archive_file "$arc"
  migration_state_set archive "done"
}

# SQL as the migration database user (statement on stdin), on DATABASE or none
_migration_sql() { # [database] statement
  local dbarg=()
  [ $# -lt 2 ] || { dbarg=("$1"); shift; }
  printf '%s\n' "$1" | MYSQL_PWD="$(_migration_dbpass)" mariadb -h "$MYSQL_SERVER" -P "$APP_PORT_MYSQL" \
    -u "$(_migration_dbuser)" --connect-timeout=5 --batch --skip-column-names "${dbarg[@]}"
}

# M5.2-M5.4, after the persistence step has seeded the directories moved by
# the snapshot: each part recorded in the state, resumed after a restart.
# - the enabled modules of the FreePBX 16 recorded, then the config
#   database dropped and created again (its dump is verified, M4); the CDR
#   database is not touched;
# - FreePBX 17 installed as a new installation (freepbx_install), then the
#   modules of the 16 it does not install by default (local tree first, the
#   mirror otherwise; a failure is a warning);
# - the archive restored with "fwconsole backup --restore" as asterisk,
#   chan_sip extensions and trunks converted to PJSIP (P0-11), Asterisk
#   running (the astdb is restored through it), TMPDIR under APP_DATA;
#   output in <snapshot>/restore.log; then the FreePBX settings izPBX needs
#   (freepbx_izpbx_settings: the restore puts back ASTMANAGERHOST=localhost,
#   and the UCP node server cannot reach AMI with it).
migration_restore() {
  local snap arc mods m failed=() rc log tmp
  if [ "$(migration_state restore)" == "done" ]; then
    log_info "migration: restore already done"
    return 0
  fi
  [ "$(migration_state archive)" == "done" ] || { log_error "migration: no archive, the restore needs it"; return 1; }
  snap=$(migration_state snapshot_dir) arc=$(migration_state archive_file)

  if [ "$(migration_state dbreset)" != "done" ]; then
    # what the 16 had, read once (a resumed run may find the database dropped)
    if [ -z "$(migration_state modules)" ]; then
      mods=$(_migration_sql "$MYSQL_DATABASE" "SELECT modulename FROM modules WHERE enabled = 1 ORDER BY modulename" | tr '\n' ' ') ||
        { log_error "migration: cannot read the modules of '$MYSQL_DATABASE'"; return 1; }
      # chan_sip extensions and trunks of the 16 (converted by the restore, M6)
      migration_state_set sip_devices "$(_migration_sql "$MYSQL_DATABASE" "SELECT COUNT(*) FROM devices WHERE tech = 'sip'")"
      migration_state_set sip_trunks "$(_migration_sql "$MYSQL_DATABASE" "SELECT channelid FROM trunks WHERE tech = 'sip' ORDER BY channelid" | tr '\n' ' ' | sed 's/ $//')"
      migration_state_set modules "${mods% }"
    fi
    _migration_sql "DROP DATABASE IF EXISTS \`$MYSQL_DATABASE\`" ||
      { log_error "migration: cannot drop the database '$MYSQL_DATABASE'"; return 1; }
    migration_kill_point dbreset
    _migration_sql "CREATE DATABASE \`$MYSQL_DATABASE\`" ||
      { log_error "migration: cannot create the database '$MYSQL_DATABASE'"; return 1; }
    migration_state_set dbreset "done"
    log_info "migration: database '$MYSQL_DATABASE' recreated (dump in $snap/db), '$MYSQL_DATABASE_CDR' left as it is"
  fi

  if [ "$(migration_state install)" != "done" ]; then
    # a resumed run may find FreePBX 17 installed already (killed after it)
    if freepbx_installed && [ "$(freepbx_db_version | cut -d. -f1)" == 17 ]; then
      log_info "migration: FreePBX $(freepbx_db_version) already installed"
    else
      freepbx_install
    fi
    migration_kill_point install
    migration_state_set install "done"
  fi

  if [ "$(migration_state modules_installed)" != "done" ]; then
    for m in $(migration_state modules); do
      [[ " $IZPBX_MIGRATION_REMOVED_MODULES " == *" $m "* ]] && continue
      fwconsole_as_asterisk ma list 2>/dev/null | grep -qE "^\| $m +\| [^ ]+ +\| Enabled" && continue
      log_info "migration: installing module $m (installed in FreePBX 16)"
      fwconsole_as_asterisk ma install "$m" > "/tmp/migration-module-$m.log" 2>&1 ||
        fwconsole_as_asterisk ma downloadinstall "$m" >> "/tmp/migration-module-$m.log" 2>&1 || true
      fwconsole_as_asterisk ma list 2>/dev/null | grep -qE "^\| $m +\| [^ ]+ +\| Enabled" || failed+=("$m")
    done
    [ ${#failed[@]} -eq 0 ] || log_warn "migration: modules of FreePBX 16 not installed, their data is not restored: ${failed[*]}"
    migration_state_set modules_installed "done"
  fi

  log="$snap/restore.log" tmp="$IZPBX_MIGRATION_DIR/tmp"
  mkdir -p "$tmp" && chown "$APP_USR:$APP_GRP" "$tmp"
  _fpbx_asterisk_start || return 1
  log_info "migration: restoring $arc (output in $log)"
  rc=0
  TMPDIR=$tmp fwconsole_as_asterisk backup --restore="$arc" --convertchansipexts2pjsip --convertchansiptrunks2pjsip -n > "$log" 2>&1 || rc=$?
  _fpbx_asterisk_stop
  if [ "$rc" -ne 0 ] || ! grep -q 'Restore completed successfully' "$log"; then
    log_error "migration: restore failed (exit $rc), last lines of $log:"
    tail -n 15 "$log" | while IFS= read -r line; do log_error "  $line"; done
    return 1
  fi
  # the restore brought back the settings of the 16: those izPBX needs again
  freepbx_izpbx_settings
  migration_kill_point restore
  migration_state_set restore "done"
  log_info "migration: FreePBX 16 configuration restored on FreePBX 17"
}

# M6: the chan_sip of izPBX 20.16 listened on APP_PORT_SIP (5160): providers
# and phones of the trunks and extensions converted to PJSIP still send
# there. If the 16 had chan_sip extensions or trunks, a PJSIP transport
# udp (and tcp, when FreePBX has one) on APP_PORT_SIP in
# pjsip.transports_custom.conf, with the settings of the FreePBX transport
# 0.0.0.0-<protocol> (external addresses, local networks) at this moment;
# the converted trunks use it through pjsip.endpoint_custom_post.conf
# ("[trunk](+)": FreePBX keeps one transport per address and protocol, so it
# cannot be a SIP Settings bind, and it writes only its own transports in
# the endpoints). New installations get no such transport (Q8).
IZPBX_MIGRATION_SIP_TRANSPORT=izpbx-legacy-sip
migration_sip_transport() {
  local devices trunks conf custom post proto base t names=()
  [ "$(migration_state sip_transport)" == "done" ] && return 0
  devices=$(migration_state sip_devices) trunks=$(migration_state sip_trunks)
  if [ "${devices:-0}" -eq 0 ] && [ -z "$trunks" ]; then
    log_info "migration: no chan_sip extension or trunk in FreePBX 16, no transport on port $APP_PORT_SIP"
    migration_state_set sip_transport "done"
    return 0
  fi
  conf=$(freepbx_dir ASTETCDIR)/pjsip.transports.conf custom=$(freepbx_dir ASTETCDIR)/pjsip.transports_custom.conf
  post=$(freepbx_dir ASTETCDIR)/pjsip.endpoint_custom_post.conf
  [ -s "$conf" ] || fwconsole_as_asterisk reload >/dev/null 2>&1 || true
  {
    echo "; izPBX migration from 20.16 (M6): the port of chan_sip ($APP_PORT_SIP) for the"
    echo "; extensions and trunks converted to PJSIP; a copy of the FreePBX transports"
    echo "; at the migration: change it here if the SIP Settings change"
    for proto in udp tcp; do
      base="0.0.0.0-$proto"
      grep -q "^\[$base\]" "$conf" 2>/dev/null || continue
      t="$IZPBX_MIGRATION_SIP_TRANSPORT-$proto"
      names+=("$t")
      echo
      echo "[$t]"
      awk -v s="[$base]" '$0 == s {on = 1; next} /^\[/ {on = 0} on && NF && $1 !~ /^bind/ {print}' "$conf"
      echo "bind=0.0.0.0:$APP_PORT_SIP"
    done
  } > "$custom.izpbx"
  if [ ${#names[@]} -eq 0 ]; then
    rm -f "$custom.izpbx"
    log_error "migration: no FreePBX transport 0.0.0.0-udp/tcp in $conf to copy"
    return 1
  fi
  [ ! -s "$custom" ] || { echo; cat "$custom"; } >> "$custom.izpbx"
  mv "$custom.izpbx" "$custom"
  chown "$APP_USR:$APP_GRP" "$custom"
  log_info "migration: PJSIP transport(s) ${names[*]} on port $APP_PORT_SIP in $custom"

  if [ -n "$trunks" ]; then
    {
      [ ! -s "$post" ] || { cat "$post"; echo; }
      echo "; izPBX migration from 20.16 (M6): trunks on chan_sip in FreePBX 16, on port $APP_PORT_SIP"
      for t in $trunks; do printf '[%s](+)\ntransport=%s\n' "$t" "${names[0]}"; done
    } > "$post.izpbx"
    mv "$post.izpbx" "$post"
    chown "$APP_USR:$APP_GRP" "$post"
    log_info "migration: trunks on chan_sip in FreePBX 16 use the transport ${names[0]} ($post): $trunks"
  fi
  # no reload: Asterisk is stopped during izpbx-init and reads the files when it starts
  migration_state_set sip_transport "done"
}

# M6: the restore does not bring back the audio files (custom prompts are
# reported lost on the FreePBX forum): sounds/custom, sounds/<language>/custom
# and the music on hold categories are copied from the snapshot, without
# overwriting what FreePBX 17 has (cp -n), owned by asterisk.
migration_audio() {
  local snap src dst rel n=0
  [ "$(migration_state audio)" == "done" ] && return 0
  snap=$(migration_state snapshot_dir)
  src="$snap/fs/var/lib/asterisk" dst=$(freepbx_dir ASTVARLIBDIR)
  for rel in $(cd "$src" 2>/dev/null && find sounds -mindepth 1 -maxdepth 2 -type d -name custom) moh; do
    [ -d "$src/$rel" ] || continue
    mkdir -p "$dst/$rel"
    n=$((n + $(cd "$src/$rel" && find . -type f | while read -r f; do [ -e "$dst/$rel/$f" ] || echo; done | wc -l)))
    cp -an "$src/$rel/." "$dst/$rel/"
    chown -R "$APP_USR:$APP_GRP" "$dst/$rel"
  done
  log_info "migration: $n audio file(s) (sounds/custom, music on hold) copied from the snapshot"
  migration_kill_point audio
  migration_state_set audio "done"
}

# M6: the restore brings back most of the astdb (call forward, DND, devices),
# not every family (CustomPresence, RINGGROUP, TRUNK seen missing): the keys
# of astdb.sqlite3 of the snapshot that the new astdb lacks are added
# (INSERT OR IGNORE: a key already there, such as a device converted from
# SIP to PJSIP, is kept), with Asterisk stopped (izpbx-init, before the
# services). Families left out: SIP (chan_sip registrations), registrar
# (stale PJSIP contacts), dundi and pbx (generated by this installation).
IZPBX_MIGRATION_ASTDB_SKIP="SIP registrar dundi pbx"
migration_astdb() {
  local snap old new n
  [ "$(migration_state astdb)" == "done" ] && return 0
  snap=$(migration_state snapshot_dir)
  old="$snap/fs/var/lib/asterisk/astdb.sqlite3" new="$(freepbx_dir ASTVARLIBDIR)/astdb.sqlite3"
  if [ ! -s "$old" ]; then
    log_info "migration: no astdb.sqlite3 in the snapshot"
  else
    n=$(php -r '
      [$old, $new, $skip] = array_slice($argv, 1);
      $skip = array_flip(explode(" ", $skip));
      $db = new PDO("sqlite:" . $new);
      $db->exec("CREATE TABLE IF NOT EXISTS astdb (key VARCHAR(256), value VARCHAR(256), PRIMARY KEY(key))");
      $ins = $db->prepare("INSERT OR IGNORE INTO astdb (key, value) VALUES (?, ?)");
      $n = 0;
      $db->beginTransaction();
      foreach ((new PDO("sqlite:" . $old))->query("SELECT key, value FROM astdb") as $r) {
        if (isset($skip[explode("/", trim($r[0], "/"))[0]])) continue;
        $ins->execute([$r[0], $r[1]]);
        $n += $ins->rowCount();
      }
      $db->commit();
      echo $n;
    ' -- "$old" "$new" "$IZPBX_MIGRATION_ASTDB_SKIP") || { log_error "migration: cannot import the astdb of the snapshot"; return 1; }
    chown "$APP_USR:$APP_GRP" "$new"
    log_info "migration: $n astdb key(s) of FreePBX 16 added (missing after the restore)"
  fi
  migration_state_set astdb "done"
}

# M6: voicemail messages and call recordings stay in var/spool/asterisk (the
# snapshot holds hardlinks): counted in the log, and the files not owned by
# asterisk (written as root in 20.16) given to asterisk, as FreePBX needs.
migration_spool() {
  local spool msgs recs fixed
  [ "$(migration_state spool)" == "done" ] && return 0
  spool=$(freepbx_dir ASTSPOOLDIR)
  msgs=$(find "$spool/voicemail" -name 'msg*.txt' 2>/dev/null | wc -l)
  recs=$(find "$spool/monitor" -type f 2>/dev/null | wc -l)
  fixed=$(find "$spool/voicemail" "$spool/monitor" \( ! -user "$APP_USR" -o ! -group "$APP_GRP" \) -print 2>/dev/null | wc -l)
  if [ "$fixed" -gt 0 ]; then
    find "$spool/voicemail" "$spool/monitor" \( ! -user "$APP_USR" -o ! -group "$APP_GRP" \) -exec chown -h "$APP_USR:$APP_GRP" {} + 2>/dev/null || true
  fi
  log_info "migration: spool in place: $msgs voicemail message(s), $recs recording(s); $fixed file(s) given to $APP_USR"
  migration_state_set spool "done"
}

# M6, C4: 20.16 kept the crontabs in /var/spool/cron/<user> (CentOS), Debian
# reads /var/spool/cron/crontabs/<user>. The FreePBX jobs (fwconsole) are
# written again by FreePBX 17 with its own paths: copying the old ones would
# run them twice. The other lines of each user of the snapshot (custom jobs,
# variables) are added to the Debian crontab of that user, under a comment,
# unless already there; owner <user>:crontab 0600 (the cron step fixes it at
# every start too).
migration_crontab() {
  local snap src spool f user lines n=0
  [ "$(migration_state crontab)" == "done" ] && return 0
  snap=$(migration_state snapshot_dir)
  src="$snap/fs/var/spool/cron" spool=${CRON_SPOOL:-/var/spool/cron/crontabs}
  for f in "$src"/*; do
    [ -f "$f" ] || continue
    user=${f##*/}
    id -u "$user" >/dev/null 2>&1 || { log_warn "migration: crontab of $user (20.16) skipped: no such user"; continue; }
    lines=$(grep -vE '^[[:space:]]*(#|$)' "$f" | grep -v 'fwconsole' || true)
    [ -n "$lines" ] || continue
    mkdir -p "$spool"
    touch "$spool/$user"
    lines=$(while IFS= read -r l; do grep -qxF -- "$l" "$spool/$user" || printf '%s\n' "$l"; done <<< "$lines")
    [ -n "$lines" ] || continue
    { echo "# izPBX migration from 20.16 (M6): custom lines of /var/spool/cron/$user"; printf '%s\n' "$lines"; } >> "$spool/$user"
    chown "$user:crontab" "$spool/$user"
    chmod 0600 "$spool/$user"
    n=$((n + $(wc -l <<< "$lines")))
    log_info "migration: $(wc -l <<< "$lines") custom crontab line(s) of $user moved to $spool/$user"
  done
  [ "$n" -gt 0 ] || log_info "migration: no custom crontab line in 20.16 (the FreePBX jobs are written by FreePBX 17)"
  migration_state_set crontab "done"
}

# M6: FOP2 of 20.16 was the CentOS build, moved to the snapshot. With fop2
# enabled the Debian package is installed (verified, as on a new
# installation: services/fop2.sh), then the configuration (*.cfg), the
# license (fop2.lic) and the settings database (fop2settings.db: user
# preferences and chat log, tables the new empty one lacks) of 20.16 are
# put back; the fop2 step reconfigures the
# AMI keys and the certificates at every start. FOP2 disabled: its files
# stay in the snapshot. A failed install (download) does not stop the
# migration: logged, retried at the next start.
migration_fop2() {
  local snap src f n=0
  [ "$(migration_state fop2)" == "done" ] && return 0
  snap=$(migration_state snapshot_dir) src="$snap/fs/usr/local/fop2"
  if [ ! -f "$src/fop2.cfg" ]; then
    log_info "migration: no FOP2 in 20.16"
  elif ! service_is_enabled fop2; then
    log_info "migration: FOP2 not enabled (FOP2_ENABLED): its configuration stays in $src"
  else
    # shellcheck source=fop2.sh
    . /usr/local/lib/izpbx/services/fop2.sh
    log_info "migration: installing FOP2 $FOP2_VER from the Debian package (20.16 had the CentOS build)"
    if ! fop2_install; then
      log_error "migration: FOP2 install failed: retried at the next start, its configuration is in $src"
      return 0
    fi
    for f in "$src"/*.cfg "$src"/fop2.lic "$src"/fop2settings.db; do
      [ -f "$f" ] || continue
      cp -p "$f" "$FOP2_DIR/"
      n=$((n + 1))
    done
    log_info "migration: FOP2 configuration, license and settings of 20.16 kept ($n file(s): $(cd "$src" && ls -- *.cfg fop2.lic fop2settings.db 2>/dev/null | tr '\n' ' '))"
  fi
  migration_state_set fop2 "done"
}

# M3: inventory of the FreePBX 16 database and files (izpbx-inventory),
# taken once before the snapshot moves the files away
migration_inventory_before() {
  local inv="$IZPBX_MIGRATION_DIR/inventory-before.json"
  [ -s "$inv" ] && return 0
  mkdir -p "$IZPBX_MIGRATION_DIR"
  izpbx-inventory > "$inv.part" || { rm -f "$inv.part"; log_error "migration: inventory of FreePBX 16 failed"; return 1; }
  mv "$inv.part" "$inv"
  log_info "migration: inventory of FreePBX 16 in $inv ($(jq '[.categories[] | length] | add' "$inv") records)"
}

# M6: configuration files of etc/asterisk FreePBX neither writes nor
# restores, and the inventory checks: copied from the snapshot when FreePBX 17
# has none (chan_dongle: dongle.conf)
IZPBX_MIGRATION_CONFS="dongle.conf"
migration_confs() {
  local snap etc f
  [ "$(migration_state confs)" == "done" ] && return 0
  snap=$(migration_state snapshot_dir) etc=$(freepbx_dir ASTETCDIR)
  for f in $IZPBX_MIGRATION_CONFS; do
    [ -f "$snap/fs/etc/asterisk/$f" ] && [ ! -e "$etc/$f" ] || continue
    cp -p "$snap/fs/etc/asterisk/$f" "$etc/$f"
    chown "$APP_USR:$APP_GRP" "$etc/$f"
    log_info "migration: $f of 20.16 copied to $etc"
  done
  migration_state_set confs "done"
}

# M7: the inventory after the migration (DB + files, Asterisk is stopped:
# the astdb from astdb.sqlite3) compared with the one before; the expected
# differences are in IZPBX_MIGRATION_MAPPING. Any other difference: the
# migration is not completed, maintenance mode (no service, unhealthy), the
# report in the log and in verify-<ts>.txt; a restart checks again.
# Returns 1 in maintenance mode.
migration_verify() {
  local before="$IZPBX_MIGRATION_DIR/inventory-before.json" after="$IZPBX_MIGRATION_DIR/inventory-after.json"
  local report rc=0 line
  [ "$(migration_state verify)" == "done" ] && return 0
  if [ -n "$IZPBX_TEST_AFTER_RESTORE_SQL" ]; then
    log_warn "migration: test statement on '$MYSQL_DATABASE' before the verification (IZPBX_TEST_AFTER_RESTORE_SQL)"
    _migration_sql "$MYSQL_DATABASE" "$IZPBX_TEST_AFTER_RESTORE_SQL" || true
  fi
  report="$IZPBX_MIGRATION_DIR/verify-$(date -u +%Y%m%dT%H%M%SZ).txt"
  if [ ! -s "$before" ]; then
    echo "no inventory of FreePBX 16 ($before)" > "$report"; rc=2
  elif ! izpbx-inventory > "$after"; then
    echo "inventory after the migration failed" > "$report"; rc=2
  else
    izpbx-inventory --diff "$before" "$after" --mapping "$IZPBX_MIGRATION_MAPPING" > "$report" 2>&1 || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    log_info "migration: verification passed: the inventory of FreePBX 17 matches the one of FreePBX 16 ($report)"
    migration_state_set verify "done"
    return 0
  fi
  log_error "migration: VERIFICATION FAILED: the inventory after the migration differs from the one before ($report):"
  while IFS= read -r line; do log_error "  $line"; done < <(head -n 50 "$report")
  mkdir -p "$(dirname "$IZPBX_MAINTENANCE_FLAG")"
  echo "the migration verification found differences (report in $report)" > "$IZPBX_MAINTENANCE_FLAG"
  log_warn "freepbx: MAINTENANCE MODE: the migration is not completed, no service is started and the healthcheck reports unhealthy."
  log_warn "freepbx: the FreePBX 16 data is in $(migration_state snapshot_dir) (database dumps and files): check the report,"
  log_warn "freepbx: then restart the container to verify again, or go back to izPBX 20.16 with the snapshot."
  return 1
}
