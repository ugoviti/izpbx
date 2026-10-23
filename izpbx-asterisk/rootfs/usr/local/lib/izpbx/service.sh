#!/bin/bash
# Helpers for the s6 run scripts (/etc/s6-overlay/s6-rc.d/<service>/run):
#   service_enabled VAR DEFAULT   true when ${VAR:-DEFAULT} is "true"
#   service_off NAME              the service is disabled: stay down, no restart
# The run scripts start with "#!/command/with-contenv bash" so they see the
# container environment.
# shellcheck source=common.sh
. /usr/local/lib/izpbx/common.sh

service_enabled() { [ "${!1:-$2}" == "true" ]; }

# s6-svc -O: run at most once, so the exit below leaves the service down
service_off() {
  log_info "$1: disabled"
  exec /command/s6-svc -O .
}

# service_run NAME CMD...: run CMD as a child of the run script. Some daemons
# drop a SIGTERM received while they are still starting (Asterisk, fail2ban)
# or do not stop on it at all (FOP2 without a configuration), and s6 would
# wait for them: on TERM keep sending it every second, and after
# SERVICE_STOP_GRACE seconds (default 20) send KILL. A requested stop exits 0
# (also when the TERM killed CMD during its start); otherwise CMD's own exit
# status, so "finish" still sees crashes and kills as failures.
service_run() {
  _svc_name=$1; shift
  _svc_stop=
  "$@" &
  _svc_child=$!
  trap _service_stop TERM
  wait "$_svc_child"
  local rc=$?
  [ -n "$_svc_stop" ] && exit 0
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
