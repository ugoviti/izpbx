# shellcheck shell=bash
# FreePBX 16 -> 17 migration (design §7), the phases after the checks M2:
#   migration_snapshot   M4: verified dumps, directories moved, spool hardlinked
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

# mariadb-dump of one database, gzip, verified: exit status of the dump and
# of gzip, the whole file read back (gzip -t and the "Dump completed" last
# line), sha256 in SHA256SUMS. Root when MYSQL_ROOT_PASSWORD is set, else
# MYSQL_USER (secrets in the environment, not on the command line).
_migration_dump() { # database file
  local user=$MYSQL_USER pass=$MYSQL_PASSWORD tmp="$2.part" st
  if [ -n "$MYSQL_ROOT_PASSWORD" ]; then user=$MYSQL_ROOT_USER pass=$MYSQL_ROOT_PASSWORD; fi
  MYSQL_PWD="$pass" mariadb-dump -h "$MYSQL_SERVER" -P "$APP_PORT_MYSQL" -u "$user" \
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
