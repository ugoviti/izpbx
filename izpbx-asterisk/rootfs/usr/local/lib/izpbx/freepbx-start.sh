#!/bin/bash
# s6 oneshot freepbx-start (after the asterisk service): the FreePBX
# post-start hooks, "fwconsole start --post", as 20.16 ran "fwconsole start"
# (startizpbx): the pm2 apps (core-fastagi, needed by ring groups and follow
# me through dialparties.agi with LAUNCH_AGI_AS_FASTAGI; the UCP node
# server; call transfer monitoring). Asterisk itself is the asterisk
# service. Only with FreePBX in use (IZPBX_ENABLED, mode normal or install),
# not in migration or dry-run. It never fails: a failed oneshot would stop
# the container (S6_BEHAVIOUR_IF_STAGE2_FAILS=2); the problem is logged.
# shellcheck source=services/freepbx.sh
. /usr/local/lib/izpbx/services/freepbx.sh
: "${IZPBX_FREEPBX_START_WAIT:=300}"

izpbx_dry_run && exit 0
[ "$IZPBX_ENABLED" == "true" ] || exit 0
case "$(izpbx_mode)" in normal|install) ;; *) log_info "freepbx-start: mode $(izpbx_mode), FreePBX post-start hooks skipped"; exit 0 ;; esac
freepbx_installed || exit 0

start=$SECONDS
until asterisk -rx 'core waitfullybooted' >/dev/null 2>&1; do
  if [ $((SECONDS - start)) -ge "$IZPBX_FREEPBX_START_WAIT" ]; then
    log_warn "freepbx-start: Asterisk not up after ${IZPBX_FREEPBX_START_WAIT}s, FreePBX post-start hooks not run"
    exit 0
  fi
  sleep 2
done
if fwconsole start --post --skipchown >/tmp/freepbx-start.log 2>&1; then
  log_info "freepbx-start: FreePBX post-start hooks done (pm2: $(fwconsole_as_asterisk pm2 --list 2>/dev/null | awk -F'|' 'NR > 3 && NF > 3 {gsub(/ /, "", $2); printf "%s ", $2}'))"
else
  log_warn "freepbx-start: fwconsole start --post failed, see /tmp/freepbx-start.log"
fi
exit 0
