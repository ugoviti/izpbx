# shellcheck shell=bash
# Zabbix agent 2, as cfgService_zabbix of 20.16: Server, ServerActive,
# Hostname and LogFile of the package configuration are commented and the
# values of the ZABBIX_* variables go to zabbix_agent2.d/local.conf;
# Hostname follows the system hostname (HostnameItem) unless ZABBIX_HOSTNAME
# differs from it. The Asterisk template queries Asterisk through
# "sudo -u asterisk asterisk -rx" (/etc/sudoers.d/zabbix: never as root).
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh

: "${ZABBIX_CONF:=/etc/zabbix/zabbix_agent2.conf}"
: "${ZABBIX_CONF_LOCAL:=/etc/zabbix/zabbix_agent2.d/local.conf}"

cfg_zabbix() {
  if [ -w "$ZABBIX_CONF" ]; then
    sed -i -e 's/^LogFile=/#LogFile=/' -e 's/^Hostname=/#Hostname=/' \
           -e 's/^Server=/#Server=/' -e 's/^ServerActive=/#ServerActive=/' "$ZABBIX_CONF"
  fi
  echo "#DebugLevel=4
#LogFileSize=1
#EnableRemoteCommands=1
Plugins.SystemRun.LogRemoteCommands=1
LogType=console

Server=${ZABBIX_SERVER}
ServerActive=${ZABBIX_SERVER_ACTIVE}

$(if [ "$ZABBIX_HOSTNAME" == "${HOSTNAME:-}" ]; then
    echo "HostnameItem=system.hostname"
  else
    echo "Hostname=${ZABBIX_HOSTNAME}"
  fi)

$([ -n "$ZABBIX_HOSTMETADATA" ] && echo "HostMetadata=${ZABBIX_HOSTMETADATA}")
" > "$ZABBIX_CONF_LOCAL"
  log_info "zabbix: server ${ZABBIX_SERVER}, hostname ${ZABBIX_HOSTNAME}"
}
