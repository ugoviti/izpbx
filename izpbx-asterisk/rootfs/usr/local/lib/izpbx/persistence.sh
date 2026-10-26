# shellcheck shell=bash
# Persistent storage under APP_DATA (izpbx-asterisk/docs/env-contract.md, APP_DATA), same
# layout as 20.16: each directory of PERSIST_DIRS is moved to <dir>.dist and
# replaced by a symlink to ${APP_DATA}<dir>; an empty target is seeded from
# <dir>.dist and gets a ".initialized" timestamp; the files of PERSIST_FILES
# are symlinked the same way. Data already in APP_DATA is never changed.
# Idempotent: on a restart the symlinks are there and nothing is moved again
# (no <dir>.dist/.dist nesting).
#
#   persistence_setup            apply PERSIST_DIRS and PERSIST_FILES
#   persistence_sync_dist        PERSIST_SYNC_DIRS equal to the image again
#   persist_dir DIR              one directory
#   persist_file FILE            one file
#   persistence_initialized      ${APP_DATA}/.initialized exists (install done)
#   persistence_mark_initialized VERSION   write ${APP_DATA}/.initialized
#
# IZPBX_ROOT (default empty) prefixes every path: the tests run the same code
# on a temporary tree.
# shellcheck source=common.sh
. /usr/local/lib/izpbx/common.sh

: "${IZPBX_ROOT:=}"
: "${APP_DATA:=}"

# 20.16 appDataDirs; Apache logs in the Debian path /var/log/apache2 (design
# C2: the old ${APP_DATA}/var/log/httpd stays as an archive)
PERSIST_DIRS=(
  /var/spool/cron /home/asterisk /etc/asterisk /var/lib/asterisk /var/spool/asterisk
  /var/www /var/log/apache2 /var/log/asterisk /var/log/fail2ban /var/lib/fail2ban
  /usr/local/fop2 /root /etc/dnsmasq.d /var/lib/dnsmasq /var/lib/tftpboot
)
PERSIST_FILES=(/etc/freepbx.conf /etc/amportal.conf)
# persisted directories that belong to the image, not to the user: equal to
# the image at every start (an image update, a migrated volume). Asterisk
# documentation (codec_opus does not load without its XML documentation),
# ARI specifications, static HTTP pages; 20.16 synced the documentation only.
PERSIST_SYNC_DIRS=(/var/lib/asterisk/documentation /var/lib/asterisk/rest-api /var/lib/asterisk/static-http)

_persist_stamp() { date +"%Y-%m-%dT%H:%M:%S%:z"; }
_dir_empty() { [ -z "$(ls -A "$1")" ]; }

persist_dir() {
  local sys="$IZPBX_ROOT$1" data="$IZPBX_ROOT$APP_DATA$1"
  mkdir -p "$data"
  # already linked: a restart, nothing to move
  if ! { [ -L "$sys" ] && [ "$(readlink "$sys")" == "$data" ]; }; then
    [ -L "$sys" ] && die "persistence: $1 is a symlink to $(readlink "$sys"), expected $data"
    if [ -e "$sys" ]; then
      [ -e "$sys.dist" ] && die "persistence: $1 and $1.dist both exist, refusing to nest"
      mv "$sys" "$sys.dist"
    fi
    mkdir -p "$(dirname "$sys")"
    ln -s "$data" "$sys"
    log_info "persistence: $1 -> $APP_DATA$1"
  fi
  # seed an empty target from the image (first start, or a directory new in
  # this release); a target with data is left as it is
  if _dir_empty "$data" && [ -d "$sys.dist" ] && ! _dir_empty "$sys.dist"; then
    cp -a "$sys.dist/." "$data/"
    chown --reference="$sys.dist" "$data"
    chmod --reference="$sys.dist" "$data"
    log_info "persistence: $APP_DATA$1 seeded from $1.dist"
  fi
  [ -e "$data/.initialized" ] || _persist_stamp > "$data/.initialized"
}

persist_file() {
  local sys="$IZPBX_ROOT$1" data="$IZPBX_ROOT$APP_DATA$1"
  # the link may dangle until FreePBX writes the file
  [ -L "$sys" ] && [ "$(readlink "$sys")" == "$data" ] && return 0
  [ -L "$sys" ] && die "persistence: $1 is a symlink to $(readlink "$sys"), expected $data"
  mkdir -p "$(dirname "$data")"
  if [ -e "$sys" ]; then
    [ -e "$data" ] || cp -a "$sys" "$data"
    [ -e "$sys.dist" ] && die "persistence: $1 and $1.dist both exist, refusing to overwrite"
    mv "$sys" "$sys.dist"
  fi
  ln -s "$data" "$sys"
  log_info "persistence: $1 -> $APP_DATA$1"
}

persistence_setup() {
  local d f
  if [ -z "$APP_DATA" ]; then
    log_warn "persistence: APP_DATA is empty, data is lost when the container is removed"
    return 0
  fi
  case "$APP_DATA" in
    /*) ;;
    *) die "persistence: APP_DATA must be an absolute path, got '$APP_DATA'" ;;
  esac
  for d in "${PERSIST_DIRS[@]}"; do persist_dir "$d"; done
  for f in "${PERSIST_FILES[@]}"; do persist_file "$f"; done
}

# persistence_sync_dist: each PERSIST_SYNC_DIRS under APP_DATA replaced by
# the copy of the image (<parent>.dist/<dir>, left by persist_dir) when they
# differ (content, missing or extra files, links: diff, as the rsync dry run
# of 20.16; rsync is not in the image)
persistence_sync_dist() {
  local d dist data
  [ -n "$APP_DATA" ] || return 0
  for d in "${PERSIST_SYNC_DIRS[@]}"; do
    dist="$IZPBX_ROOT$(dirname "$d").dist/$(basename "$d")" data="$IZPBX_ROOT$APP_DATA$d"
    [ -d "$dist" ] || continue
    [ -d "$data" ] && diff -rq --no-dereference "$dist" "$data" >/dev/null 2>&1 && continue
    rm -rf "${data:?}"
    cp -a "$dist" "$data"
    log_info "persistence: $APP_DATA$d updated from the image"
  done
}

persistence_initialized() { [ -n "$APP_DATA" ] && [ -e "$IZPBX_ROOT$APP_DATA/.initialized" ]; }

persistence_mark_initialized() {
  [ -n "$APP_DATA" ] || return 0
  printf '%s\n' "$1" > "$IZPBX_ROOT$APP_DATA/.initialized"
}
