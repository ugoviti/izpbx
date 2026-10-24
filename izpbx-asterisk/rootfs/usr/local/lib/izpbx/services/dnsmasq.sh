# shellcheck shell=bash
# dnsmasq for DHCP and TFTP, as cfgService_dhcp/cfgService_tftp of 20.16:
# the template /etc/dnsmasq.d/local.conf (rootfs, persisted under APP_DATA)
# is edited in place, so the changes also apply to an existing file on a
# restart. Values are escaped for sed (hostile DHCP_DOMAIN, R1).
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh

: "${DNSMASQ_CONF:=/etc/dnsmasq.d/local.conf}"
: "${TFTP_DIR:=/var/lib/tftpboot}"

cfg_dhcp() {
  local f=$DNSMASQ_CONF
  log_info "dnsmasq: DHCP"
  if [ -n "$DHCP_POOL_START" ] && [ -n "$DHCP_POOL_END" ]; then
    # also an already enabled dhcp-range, so a restart applies the new pool
    sed "s|^#\?dhcp-range=.*|dhcp-range=$(sedEscape "$DHCP_POOL_START,$DHCP_POOL_END,${DHCP_POOL_LEASE:-72h}")|" -i "$f"
  else
    log_warn "dnsmasq: DHCP enabled without a pool: set DHCP_POOL_START and DHCP_POOL_END (DHCP_POOL_LEASE optional)"
  fi
  if [ -n "$DHCP_DOMAIN" ]; then
    sed "s|^local=.*|local=/$(sedEscape "$DHCP_DOMAIN")/|" -i "$f"
    sed "s|^domain=.*|domain=$(sedEscape "$DHCP_DOMAIN")|" -i "$f"
    sed "s|^#dhcp-option=option:domain-name,.*|dhcp-option=option:domain-name,$(sedEscape "$DHCP_DOMAIN")|" -i "$f"
  fi
  if [ -n "$DHCP_DNS" ]; then
    sed "s|^#\?dhcp-option=6,.*|dhcp-option=6,$(sedEscape "$DHCP_DNS")|" -i "$f"
  fi
  if [ -n "$DHCP_GW" ]; then
    sed "s|^#\?dhcp-option=3,.*|dhcp-option=3,$(sedEscape "$DHCP_GW")|" -i "$f"
  fi
  if [ -n "$DHCP_NTP" ]; then
    sed "s|^#dhcp-option=option:ntp-server,.*|dhcp-option=option:ntp-server,$(sedEscape "$DHCP_NTP")|" -i "$f"
  fi
}

cfg_tftp() {
  local f=$DNSMASQ_CONF
  log_info "dnsmasq: TFTP from $TFTP_DIR"
  sed "s|^#dhcp-option=66|dhcp-option=66|" -i "$f"
  sed "s|^#enable-tftp|enable-tftp|" -i "$f"
  sed "s|^#tftp-root=.*|tftp-root=$(sedEscape "$TFTP_DIR")|" -i "$f"
  mkdir -p "$TFTP_DIR"
  chown "$APP_USR:$APP_GRP" "$TFTP_DIR"
  # 20.16: phones configured with the /tftpboot path
  [ -e /tftpboot ] || ln -s "$TFTP_DIR" /tftpboot
}

cfg_dnsmasq() {
  [ "$DHCP_ENABLED" == "true" ] && cfg_dhcp
  [ "$TFTP_ENABLED" == "true" ] && cfg_tftp
  return 0
}
