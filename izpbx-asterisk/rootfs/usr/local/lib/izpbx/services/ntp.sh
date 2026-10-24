# shellcheck shell=bash
# chronyd as NTP server, as cfgService_ntp of 20.16: pools from NTP_SERVERS
# (default 2.pool.ntp.org), "allow" for each NTP_ALLOW_FROM subnet, chronyc
# commands only from localhost (bindcmdaddress 127.0.0.1). Debian paths
# (design C10): /etc/chrony/chrony.conf and /etc/chrony/chrony.keys.
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh

: "${CHRONY_CONF:=/etc/chrony/chrony.conf}"

cfg_ntp() {
  local server subnet
  {
    echo "# chronyd ntp server configuration
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
keyfile /etc/chrony/chrony.keys
leapsectz right/UTC
logdir /var/log/chrony

bindcmdaddress 127.0.0.1"
    if [ -z "$NTP_SERVERS" ]; then
      echo "pool 2.pool.ntp.org iburst"
    else
      # shellcheck disable=SC2086 # space separated list
      for server in $NTP_SERVERS; do echo "pool $server iburst"; done
    fi
    echo
    # shellcheck disable=SC2086 # space separated list
    for subnet in $NTP_ALLOW_FROM; do echo "allow $subnet"; done
    echo
  } > "$CHRONY_CONF"
  mkdir -p /var/log/chrony
  log_info "ntp: servers ${NTP_SERVERS:-2.pool.ntp.org}, clients ${NTP_ALLOW_FROM:-none}"
}
