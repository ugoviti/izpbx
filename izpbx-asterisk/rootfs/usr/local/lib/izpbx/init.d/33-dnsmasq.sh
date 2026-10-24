# shellcheck shell=bash
# izpbx-init step: dnsmasq for DHCP/TFTP (services/dnsmasq.sh), when it runs
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/dnsmasq.sh
. /usr/local/lib/izpbx/services/dnsmasq.sh
if service_is_enabled dnsmasq; then cfg_dnsmasq; else log_info "dnsmasq: disabled, not configured"; fi
