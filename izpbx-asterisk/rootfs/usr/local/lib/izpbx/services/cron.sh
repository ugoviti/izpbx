# shellcheck shell=bash
# cron spool, as cfgService_cron of 20.16 with the Debian layout (design C4):
# /var/spool/cron/crontabs root:crontab 1730 (the setgid crontab command
# writes there, cron reads it) and each crontab <user>:crontab 0600, the
# owner cron requires ("WRONG FILE OWNER" otherwise). 20.16 set the directory
# root:root 0700, which on Debian blocks "crontab -e" of non-root users. The
# spool is persisted under APP_DATA (persistence.sh), so the permissions are
# fixed at every start.
# shellcheck source=../common.sh
. /usr/local/lib/izpbx/common.sh

: "${CRON_SPOOL:=/var/spool/cron/crontabs}"

cfg_cron() {
  local f user
  mkdir -p "$CRON_SPOOL"
  if [ "$(stat -L -c '%U %G %a' "$CRON_SPOOL")" != "root crontab 1730" ]; then
    log_info "cron: fixing permissions of $CRON_SPOOL"
    chown root:crontab "$CRON_SPOOL"
    chmod 1730 "$CRON_SPOOL"
  fi
  for f in "$CRON_SPOOL"/*; do
    [ -f "$f" ] || continue
    user=${f##*/}
    if ! id -u "$user" >/dev/null 2>&1; then
      log_warn "cron: $f belongs to no user, ignored by cron"
      continue
    fi
    if [ "$(stat -c '%U %G %a' "$f")" != "$user crontab 600" ]; then
      log_info "cron: fixing permissions of the crontab of $user"
      chown "$user:crontab" "$f"
      chmod 0600 "$f"
    fi
  done
  log_info "cron: spool $CRON_SPOOL ready"
}
