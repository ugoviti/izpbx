#!/bin/bash
# Helpers for the s6 run scripts (/etc/s6-overlay/s6-rc.d/<service>/run):
#   service_gate NAME             stay down unless NAME is enabled (*_ENABLED)
#   service_is_enabled NAME       NAME enabled? (SERVICE_VARS, after the rules)
#   service_off NAME              the service is disabled: stay down, no restart
#   service_run NAME CMD...       run CMD, reliable stop (see below)
# The run scripts start with "#!/command/with-contenv bash" so they see the
# container environment.
# shellcheck source=common.sh
. /usr/local/lib/izpbx/common.sh
# shellcheck source=env.sh
. /usr/local/lib/izpbx/env.sh

# rules kept from 20.16 (docs/env-contract.md §5): Postfix replaces msmtp,
# DHCP and TFTP are served by dnsmasq
services_resolve() {
  [ "$POSTFIX_ENABLED" == "true" ] && MSMTP_ENABLED=false
  if [ "$DHCP_ENABLED" == "true" ] || [ "$TFTP_ENABLED" == "true" ]; then DNSMASQ_ENABLED=true; fi
  return 0
}
services_resolve

# s6 service -> variables that enable it (design S12; any "true" is enough)
declare -A SERVICE_VARS=(
  [asterisk]="IZPBX_ENABLED ASTERISK_ENABLED" [php-fpm]=HTTPD_ENABLED [httpd]=HTTPD_ENABLED
  [cron]=CRON_ENABLED [fail2ban]=FAIL2BAN_ENABLED [postfix]=POSTFIX_ENABLED [dnsmasq]=DNSMASQ_ENABLED
  [ntp]=NTP_ENABLED [zabbix]=ZABBIX_ENABLED [fop2]=FOP2_ENABLED
)

# service_is_enabled NAME: one of its variables is "true"
service_is_enabled() {
  local v
  [ -n "${SERVICE_VARS[$1]:-}" ] || { log_error "service $1 is not in SERVICE_VARS"; return 1; }
  for v in ${SERVICE_VARS[$1]}; do [ "${!v:-}" == "true" ] && return 0; done
  return 1
}

# service_gate NAME: in a run script, stay down unless the service is enabled;
# in dry-run (IZPBX_DRY_RUN=true) every service stays down
service_gate() {
  if [ "${IZPBX_DRY_RUN:-false}" == "true" ]; then
    log_info "$1: dry-run, not started"
    exec /command/s6-svc -O .
  fi
  service_is_enabled "$1" || service_off "$1"
}

# s6-svc -O: run at most once, so the exit below leaves the service down
service_off() {
  log_info "$1: disabled"
  exec /command/s6-svc -O .
}

# service_run NAME CMD...: run CMD as a child of the run script. Some daemons
# drop a SIGTERM received while they are still starting (Asterisk, fail2ban)
# or do not stop on it at all (FOP2 without a configuration), and s6 would
# wait for them: on TERM keep sending it every second, and after
# SERVICE_STOP_GRACE seconds (default 20) send KILL. A requested stop ends
# by SIGTERM (also when the TERM killed CMD during its start); otherwise CMD's
# own exit status, so "finish" still sees crashes and kills as failures.
service_run() {
  _svc_name=$1; shift
  _svc_stop=
  "$@" &
  _svc_child=$!
  trap _service_stop TERM
  wait "$_svc_child"
  local rc=$?
  # a requested stop ends with the TERM itself: "finish" sees signal 15 and s6
  # keeps the state it was asked for (up again on "s6-svc -r", down on -d)
  if [ -n "$_svc_stop" ]; then trap - TERM; kill -TERM "$BASHPID"; exit 0; fi
  exit "$rc"
}
_service_stop() {
  local waited=0 grace=${SERVICE_STOP_GRACE:-20}
  _svc_stop=1
  log_info "$_svc_name: stopping (pid $_svc_child)"
  while kill -0 "$_svc_child" 2>/dev/null; do
    if [ "$waited" -ge "$grace" ]; then
      log_warn "$_svc_name: still running after ${grace}s, killing it"
      kill -KILL "$_svc_child" 2>/dev/null
      break
    fi
    kill -TERM "$_svc_child" 2>/dev/null
    sleep 1
    waited=$((waited + 1))
  done
}
