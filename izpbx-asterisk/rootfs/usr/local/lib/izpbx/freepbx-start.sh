#!/bin/bash
# s6 oneshot freepbx-start (after the asterisk service): the FreePBX
# post-start hooks, "fwconsole start --post", as 20.16 ran "fwconsole start"
# (startizpbx): the pm2 apps (core-fastagi, needed by ring groups and follow
# me through dialparties.agi with LAUNCH_AGI_AS_FASTAGI; the UCP node
# server; call transfer monitoring). Asterisk itself is the asterisk
# service. Only with FreePBX in use (IZPBX_ENABLED, mode normal or install),
# not in migration or dry-run. It never fails: a failed oneshot would stop
# the container (S6_BEHAVIOUR_IF_STAGE2_FAILS=2); the problem is logged.
# Last, in every mode: the "ready" line (izpbx_ready).
# shellcheck source=services/freepbx.sh
. /usr/local/lib/izpbx/services/freepbx.sh
# shellcheck source=service.sh
. /usr/local/lib/izpbx/service.sh
: "${IZPBX_FREEPBX_START_WAIT:=300}"

# izpbx_ready: the end of the start, after the summary of izpbx-init (the
# services were still starting then): time since izpbx-init started, and
# with Asterisk its version, the PJSIP endpoints and the registrations of
# the trunks. Not in maintenance mode (izpbx-init said it, nothing runs).
izpbx_ready() {
  local t0 since='' ver endpoints regs reg_ok waited=$SECONDS
  [ ! -e "$IZPBX_MAINTENANCE_FLAG" ] || return 0
  if service_is_enabled asterisk; then
    until asterisk -rx 'core waitfullybooted' >/dev/null 2>&1; do
      if [ $((SECONDS - waited)) -ge "$IZPBX_FREEPBX_START_WAIT" ]; then
        log_warn "asterisk: not up after ${IZPBX_FREEPBX_START_WAIT}s"
        return 0
      fi
      sleep 2
    done
  fi
  t0=$(cat /run/izpbx/started 2>/dev/null || true)
  [[ "$t0" =~ ^[0-9]+$ ]] && since=" in $(( $(date +%s) - t0 ))s"
  log_section "$APP_DESCRIPTION $APP_VER ready$since"
  if service_is_enabled asterisk; then
    ver=$(asterisk -rx 'core show version' 2>/dev/null | awk 'NR == 1 {print $1, $2}')
    endpoints=$(asterisk -rx 'pjsip show endpoints' 2>/dev/null | awk '/^Objects found:/ {print $3}')
    regs=$(asterisk -rx 'pjsip show registrations' 2>/dev/null | awk '/^Objects found:/ {print $3}')
    reg_ok=$(asterisk -rx 'pjsip show registrations' 2>/dev/null | grep -cw 'Registered' || true)
    log_ok "asterisk: ${ver:-Asterisk} up, ${endpoints:-0} PJSIP endpoint(s), ${reg_ok:-0}/${regs:-0} trunk registration(s) registered"
    log_section ""
  fi
}

izpbx_dry_run && exit 0
trap izpbx_ready EXIT
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
  log_ok "freepbx-start: FreePBX post-start hooks done (pm2: $(fwconsole_as_asterisk pm2 --list 2>/dev/null | awk -F'|' 'NR > 3 && NF > 3 {gsub(/ /, "", $2); printf "%s%s", (n++ ? " " : ""), $2}'))"
else
  log_warn "freepbx-start: fwconsole start --post failed, see /tmp/freepbx-start.log"
fi
# the UCP node server stops after 15 failed restarts when its port is taken,
# and pm2 only says "errored" (P3-36: with network_mode host another program
# of the host may hold it). The owner of a listening socket is not visible
# here (no CAP_SYS_PTRACE), so the port is checked only when UCP failed.
# Wait until pm2 gives up (errored) or UCP is stable (online with the same
# restart count three times in a row), at most 30 seconds.
ucp_state() { fwconsole_as_asterisk pm2 --list 2>/dev/null | awk -F'|' '$2 ~ /^ ucp / {gsub(/ /, "", $4); gsub(/ /, "", $5); print $4, $5}'; }
prev='' same=0 state=''
for _ in $(seq 1 15); do
  state=$(ucp_state)
  case $state in errored*|'') break ;; esac
  if [ "$state" == "$prev" ]; then same=$((same + 1)); else same=0; fi
  [ "$same" -lt 2 ] || break
  prev=$state
  sleep 2
done
if [ "${state%% *}" == errored ]; then
  declare -A ucp_ports=([APP_PORT_UCP_HTTP]=${FREEPBX_NODEJSBINDPORT:-} [APP_PORT_UCP_HTTPS]=${FREEPBX_NODEJSHTTPSBINDPORT:-})
  busy=''
  for var in "${!ucp_ports[@]}"; do
    port=${ucp_ports[$var]}
    if [ -n "$port" ] && [ -n "$(ss -ltnH "sport = :$port" 2>/dev/null)" ]; then
      busy+=" port $port ($var) is already in use by another program (with network_mode host, a program of the host): set $var to a free port;"
    fi
  done
  log_warn "freepbx-start: the UCP node server does not start (pm2: errored):${busy:- see /home/asterisk/.pm2/logs and fwconsole pm2 --list}"
fi
# settings changed by izpbx-init (cfg_freepbx_settings): write the files of
# FreePBX again and reload Asterisk, as "Apply Config" (P3-37)
if [ -e "$IZPBX_FREEPBX_RELOAD_FLAG" ]; then
  rm -f "$IZPBX_FREEPBX_RELOAD_FLAG"
  if fwconsole_as_asterisk reload >/tmp/freepbx-reload.log 2>&1; then
    log_info "freepbx-start: FreePBX settings changed at start, applied (fwconsole reload)"
    # the reload copies the AGI scripts of the modules again with their own
    # modes (755): with FREEPBX_FIX_PERMISSION the state after this start is
    # the one of "fwconsole chown", as after a restart without reload (P3-26)
    if [ "$FREEPBX_FIX_PERMISSION" == true ]; then
      fwconsole chown >/dev/null 2>&1 || log_warn "freepbx-start: fwconsole chown after the reload failed"
    fi
  else
    log_warn "freepbx-start: fwconsole reload after the settings changed at start failed, see /tmp/freepbx-reload.log"
  fi
fi
exit 0
