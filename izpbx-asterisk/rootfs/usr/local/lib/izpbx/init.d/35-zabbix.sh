# shellcheck shell=bash
# izpbx-init step: Zabbix agent 2 configuration (services/zabbix.sh), when it runs
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/zabbix.sh
. /usr/local/lib/izpbx/services/zabbix.sh
if service_is_enabled zabbix; then cfg_zabbix; else log_info "zabbix: disabled, not configured"; fi
