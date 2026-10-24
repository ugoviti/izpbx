# shellcheck shell=bash
# Time zone of the container and of PHP (fpm and cli) from TZ, as 20.16: an
# invalid TZ (not a relative zoneinfo name, or no zoneinfo file) falls back
# to UTC. Writes /etc/localtime, /etc/timezone and
# /etc/php/8.2/{fpm,cli}/conf.d/99-izpbx-timezone.ini (20.16:
# /etc/php.d/99-timezone.ini, design C14).
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh

: "${PHP_CONF_DIR:=/etc/php/8.2}"
: "${ZONEINFO_DIR:=/usr/share/zoneinfo}"

cfg_timezone() {
  local sapi
  if [[ ! "$TZ" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] || [ ! -f "$ZONEINFO_DIR/$TZ" ]; then
    log_warn "timezone: invalid TZ='$TZ' (no $ZONEINFO_DIR/$TZ), using UTC"
    TZ=UTC
  fi
  export TZ
  ln -snf "$ZONEINFO_DIR/$TZ" /etc/localtime
  echo "$TZ" > /etc/timezone
  for sapi in fpm cli; do
    echo "date.timezone = \"${TZ}\"" > "$PHP_CONF_DIR/$sapi/conf.d/99-izpbx-timezone.ini"
  done
  log_info "timezone: $TZ"
}
