# shellcheck shell=bash
# FreePBX 16 -> 17 migration (design §7), the phases after the checks M2:
#   migration_snapshot   M4: verified dumps, directories moved, spool hardlinked
#   migration_archive    M5.1: FreePBX "legacy" backup archive from the raw data
# State in ${APP_DATA}/.izpbx-migration/state ("KEY=value" lines): the
# snapshot directory and the phases completed; every phase is idempotent and
# a restart resumes from the last completed one. Nothing is deleted: the
# directories are moved (same filesystem: instant, no extra space) and the
# spool, possibly many GB, is copied with hardlinks.
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh

: "${IZPBX_MIGRATION_DIR:=${APP_DATA:-/data}/.izpbx-migration}"
# moved into the snapshot (M4.2), relative to APP_DATA
IZPBX_MIGRATION_MOVE=(var/www var/lib/asterisk etc/asterisk home/asterisk usr/local/fop2 var/spool/cron etc/freepbx.conf etc/amportal.conf)
# copied with hardlinks (M4.3): it stays in place for the restore
IZPBX_MIGRATION_LINK=(var/spool/asterisk)

migration_state() { # KEY -> value ("" if not set)
  [ -f "$IZPBX_MIGRATION_DIR/state" ] || return 0
  sed -n "s/^$1=//p" "$IZPBX_MIGRATION_DIR/state" | tail -n 1
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
  find "$snap/fs/etc/asterisk" -maxdepth 1 -name '*_custom*.conf' -exec cp -p {} "$work/etc/asterisk/" \; 2>/dev/null || true

  tar -C "$work" -czf "$arc.part" . && mv "$arc.part" "$arc" || { log_error "migration: cannot write $arc"; return 1; }
  (cd "$(dirname "$arc")" && sha256sum "$(basename "$arc")" > "$(basename "$arc").sha256")
  log_info "migration: archive $arc (FreePBX $version, $(wc -l < "$work/mysql-2.sql") SQL lines, $(find "$work/etc/asterisk" -type f | wc -l) custom files)"
  rm -rf "${work:?}"
  migration_state_set archive_file "$arc"
  migration_state_set archive "done"
}
