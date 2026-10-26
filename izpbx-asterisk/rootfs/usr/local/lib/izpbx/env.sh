#!/bin/bash
# izPBX environment: every default of the configuration variables, in one
# place (checklist P3-02). Sourced by izpbx-init and by the service scripts
# after common.sh:
#   . /usr/local/lib/izpbx/env.sh
#
# The defaults follow izpbx-asterisk/docs/env-contract.md (the 20.16.22 behaviour); the
# intended differences are in §13 of the design and in
# izpbx-asterisk/tests/expected/env-differences.txt. As in 20.16, ": ${VAR:=default}" gives
# the default also to a variable set but empty. A default that refers to
# another variable is in the last section, in dependency order.
#
# Values computed at start (PHONEBOOK_ADDRESS, FOP2_AMI_*, FOP2_LICENSE_IFACE,
# FREEPBX_VER_INSTALLED) are declared empty here and set by the module that
# computes them.

[ -n "${IZPBX_ENV_LOADED:-}" ] && return 0
IZPBX_ENV_LOADED=1

# versions of the components in the image (build/versions.env, copied to
# /usr/src/izpbx/versions.env): they are no longer build arguments in ENV
: "${IZPBX_VERSIONS_FILE:=/usr/src/izpbx/versions.env}"
_izpbx_version() { [ -r "$IZPBX_VERSIONS_FILE" ] && sed -n "s/^$1=//p" "$IZPBX_VERSIONS_FILE"; return 0; }
## 1. Image and build metadata
: "${APP_NAME:=izpbx-asterisk}"
: "${APP_DESCRIPTION:=izPBX Cloud Native Telephony System}"
: "${APP_VER:=${APP_VER:-dev}}"
: "${APP_VER_BUILD:=}"
: "${APP_BUILD_COMMIT:=}"
: "${APP_BUILD_DATE:=}"
: "${APP_CHART:=}"
: "${APP_RELEASE:=}"
: "${APP_NAMESPACE:=}"
: "${ASTERISK_VER:=$(_izpbx_version ASTERISK_VER)}"
: "${FREEPBX_VER:=$(_izpbx_version FREEPBX_VER)}"
: "${APP_UID:=1000}"
: "${APP_GID:=1000}"
: "${APP_USR:=asterisk}"
: "${APP_GRP:=asterisk}"
: "${FOP2_VER:=$(_izpbx_version FOP2_VER)}"
: "${FOP2_SHA256:=}"
: "${ZABBIX_VER:=$(_izpbx_version ZABBIX_VER)}"
: "${ZABBIX_REL:=}"

## 2. Paths, persistence and hooks
: "${APP_DATA:=}"
: "${APP_CONF:=}"
: "${APP_LOGS:=}"
: "${APP_TEMP:=}"
: "${APP_CUSTOM_SCRIPTS:=}"
: "${UMASK:=}"

## 3. System: timezone, hostname
: "${TZ:=UTC}"
: "${APP_FQDN:=}"

## 4. Database
: "${MYSQL_SERVER:=db}"
: "${APP_PORT_MYSQL:=3306}"
: "${MYSQL_DATABASE:=asterisk}"
: "${MYSQL_DATABASE_CDR:=asteriskcdrdb}"
: "${MYSQL_USER:=asterisk}"
: "${MYSQL_PASSWORD:=}"
: "${MYSQL_ROOT_USER:=root}"
: "${MYSQL_ROOT_PASSWORD:=}"
: "${IZPBX_MYSQL_PASSWORD_FILE:=}"
: "${IZPBX_MYSQL_ROOT_PASSWORD_FILE:=}"
: "${MYSQL_RANDOM_ROOT_PASSWORD:=}"
: "${MYSQL_ALLOW_EMPTY_ROOT_PASSWORD:=}"

# Docker secrets (20.16): the file is read only when the variable is empty
[ -z "$IZPBX_MYSQL_PASSWORD_FILE" ] || readfsecret IZPBX_MYSQL_PASSWORD_FILE MYSQL_PASSWORD || true
[ -z "$IZPBX_MYSQL_ROOT_PASSWORD_FILE" ] || readfsecret IZPBX_MYSQL_ROOT_PASSWORD_FILE MYSQL_ROOT_PASSWORD || true

## 5. Services (supervisord)
: "${IZPBX_ENABLED:=true}"
: "${ASTERISK_ENABLED:=false}"
: "${HTTPD_ENABLED:=true}"
: "${CRON_ENABLED:=true}"
: "${FAIL2BAN_ENABLED:=true}"
: "${MSMTP_ENABLED:=true}"
: "${POSTFIX_ENABLED:=false}"
: "${DNSMASQ_ENABLED:=false}"
: "${DHCP_ENABLED:=false}"
: "${TFTP_ENABLED:=false}"
: "${NTP_ENABLED:=false}"
: "${ZABBIX_ENABLED:=false}"
: "${FOP2_ENABLED:=false}"
: "${PMA_ENABLED:=false}"
: "${PHONEBOOK_ENABLED:=true}"

## 6. Web server, HTTPS, phpMyAdmin, phonebook
: "${APP_PORT_HTTP:=80}"
: "${APP_PORT_HTTPS:=443}"
: "${HTTPD_ALLOW_FROM:=}"
: "${HTTPD_REDIRECT_HTTP_TO_HTTPS:=false}"
: "${HTTPD_HTTPS_ENABLED:=false}"
: "${HTTPD_HTTPS_CERT_FILE:=/etc/asterisk/keys/default.crt}"
: "${HTTPD_HTTPS_KEY_FILE:=/etc/asterisk/keys/default.key}"
: "${HTTPD_HTTPS_CHAIN_FILE:=}"
: "${LETSENCRYPT_ENABLED:=}"
: "${LETSENCRYPT_COUNTRY_CODE:=}"
: "${LETSENCRYPT_COUNTRY_STATE:=}"
: "${PMA_ALIAS:=/admin/pma}"
: "${PMA_ALLOW_FROM:=127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16}"
: "${PMA_CONFIG:=/etc/phpmyadmin/config.inc.php}"
: "${PHONEBOOK_ADDRESS:=}"
: "${APP_PORT_AMI:=8088}"

## 7. Mail: msmtp, Postfix, root alias
: "${SMTP_MAIL_FROM:=izpbx@localhost.localdomain}"
: "${SMTP_RELAYHOST:=}"
: "${SMTP_RELAYHOST_PORT:=}"
: "${SMTP_RELAYHOST_USERNAME:=}"
: "${SMTP_RELAYHOST_PASSWORD:=}"
: "${SMTP_STARTTLS:=true}"
: "${SMTP_ALLOWED_SENDER_DOMAINS:=}"
: "${SMTP_MESSAGE_SIZE_LIMIT:=0}"
: "${SMTP_MYNETWORKS:=}"

## 8. fail2ban
: "${FAIL2BAN_DEFAULT_BANACTION:=}"
: "${FAIL2BAN_DEFAULT_IGNOREIP:=}"
: "${FAIL2BAN_DEFAULT_BANTIME:=}"
: "${FAIL2BAN_DEFAULT_FINDTIME:=}"
: "${FAIL2BAN_DEFAULT_MAXRETRY:=}"
: "${FAIL2BAN_ASTERISK_ENABLED:=}"
: "${FAIL2BAN_ASTERISK_LOGPATH:=}"
: "${FAIL2BAN_RECIDIVE_ENABLED:=}"
: "${FAIL2BAN_RECIDIVE_BANTIME:=}"
: "${FAIL2BAN_RECIDIVE_FINDTIME:=}"
: "${FAIL2BAN_RECIDIVE_MAXRETRY:=}"

## 9. FreePBX
: "${FREEPBX_MODULES_CORE:=framework core dashboard sipsettings voicemail}"
: "${FREEPBX_MODULES_PRE:=userman pm2}"
: "${FREEPBX_MODULES_EXTRA:=soundlang callrecording cdr conferences customappsreg featurecodeadmin infoservices logfiles music manager arimanager filestore recordings announcement asteriskinfo backup callforward callwaiting daynight calendar certman cidlookup contactmanager donotdisturb fax findmefollow iaxsettings miscapps miscdests ivr parking presencestate printextensions queues cel timeconditions bulkhandler weakpasswords ucp}"
: "${FREEPBX_MODULES_DISABLED:=}"
: "${FREEPBX_AUTOUPDATE_MODULES_FIRSTDEPLOY:=}"
: "${FREEPBX_AUTOUPGRADE_CORE:=}"
: "${FREEPBX_AUTOUPGRADE_MODULES:=}"
: "${FREEPBX_FIX_PERMISSION:=true}"
: "${FREEPBX_VER_INSTALLED:=}"
: "${FREEPBX_FREEPBX_SYSTEM_IDENT:=}"
: "${FREEPBX_AS_DISPLAY_READONLY_SETTINGS:=}"
: "${FREEPBX_AS_OVERRIDE_READONLY:=}"
: "${FREEPBX_ENABLECW:=}"
: "${FREEPBX_TONEZONE:=}"
: "${FREEPBX_PHPTIMEZONE:=}"
: "${FREEPBX_BRAND_IMAGE_TANGO_LEFT:=}"
: "${FREEPBX_BRAND_IMAGE_FREEPBX_FOOT:=}"
: "${FREEPBX_BRAND_IMAGE_SPONSOR_FOOT:=}"
: "${FREEPBX_BRAND_FREEPBX_ALT_LEFT:=}"
: "${FREEPBX_BRAND_FREEPBX_ALT_FOOT:=}"
: "${FREEPBX_BRAND_SPONSOR_ALT_FOOT:=}"
: "${FREEPBX_BRAND_IMAGE_FREEPBX_LINK_LEFT:=}"
: "${FREEPBX_BRAND_IMAGE_FREEPBX_LINK_FOOT:=}"
: "${FREEPBX_BRAND_IMAGE_SPONSOR_LINK_FOOT:=}"
: "${FREEPBX_RSSFEEDS:=}"
: "${FREEPBX_SIGNATURECHECK:=}"
: "${APP_PORT_PJSIP:=5060}"
: "${APP_PORT_SIP:=5160}"
: "${APP_PORT_RTP_START:=10000}"
: "${APP_PORT_RTP_END:=10200}"
: "${APP_PORT_IAX:=4569}"
: "${APP_PORT_WEBRTC:=8089}"
: "${APP_PORT_UCP_HTTP:=8001}"
: "${APP_PORT_UCP_HTTPS:=8003}"
: "${APP_PORT_DHCP:=67}"
: "${APP_PORT_TFTP:=69}"
: "${APP_PORT_NTP:=123}"
: "${APP_PORT_FOP2:=4445}"
: "${APP_PORT_ZABBIX:=10050}"
: "${HEP_ENABLED:=}"

## 10. DHCP and TFTP (dnsmasq)
: "${DHCP_POOL_START:=}"
: "${DHCP_POOL_END:=}"
: "${DHCP_POOL_LEASE:=72h}"
: "${DHCP_DOMAIN:=}"
: "${DHCP_DNS:=}"
: "${DHCP_GW:=}"
: "${DHCP_NTP:=}"

## 11. NTP (chronyd)
: "${NTP_SERVERS:=}"
: "${NTP_ALLOW_FROM:=}"

## 12. Zabbix agent 2
: "${ZABBIX_SERVER:=127.0.0.1}"
: "${ZABBIX_HOSTMETADATA:=izPBX}"
: "${ZABBIX_USR:=zabbix}"
: "${ZABBIX_GRP:=zabbix}"

## 13. FOP2
: "${FOP2_AMI_HOST:=}"
: "${FOP2_AMI_PORT:=}"
: "${FOP2_AMI_USERNAME:=}"
: "${FOP2_AMI_PASSWORD:=}"
: "${FOP2_LICENSE_NAME:=}"
: "${FOP2_LICENSE_CODE:=}"
: "${FOP2_LICENSE_IFACE:=}"
: "${FOP2_AUTOUPGRADE:=false}"
: "${FOP2_AUTOACTIVATION:=false}"

## 14. Legacy entrypoint (`entrypoint.sh`)
# APP_RUNAS, MULTISERVICE, CMD_OVERRIDE and ENTRYPOINT_TINI are gone in 22.17
# (design D22): init.d/01-legacy.sh warns when one is set. UMASK stays: the
# umask of izpbx-init and of every service (their run scripts source this
# file), as 20.16 set it for supervisord and its children.
if [[ "$UMASK" =~ ^0?[0-7]{3}$ ]]; then umask "$UMASK"; fi

## defaults derived from other variables (after the variables they use)
: "${SMTP_MAIL_TO:=${ROOT_MAILTO:-root@localhost.localdomain}}"
: "${ROOT_MAILTO:=${SMTP_MAIL_TO}}"
: "${LETSENCRYPT_EMAIL:=${SMTP_MAIL_TO}}"
: "${RELAYHOST:=${SMTP_RELAYHOST}}"
: "${RELAYHOST_PORT:=${SMTP_RELAYHOST_PORT:-25}}"
: "${RELAYHOST_USERNAME:=${SMTP_RELAYHOST_USERNAME}}"
: "${RELAYHOST_PASSWORD:=${SMTP_RELAYHOST_PASSWORD}}"
: "${ALLOWED_SENDER_DOMAINS:=${SMTP_ALLOWED_SENDER_DOMAINS}}"
: "${MESSAGE_SIZE_LIMIT:=${SMTP_MESSAGE_SIZE_LIMIT}}"
: "${FAIL2BAN_DEFAULT_SENDER:=${SMTP_MAIL_FROM}}"
: "${FAIL2BAN_DEFAULT_DESTEMAIL:=${SMTP_MAIL_TO}}"
: "${FREEPBX_HTTPBINDPORT:=${APP_PORT_AMI}}"
# the UCP node server ports (P3-36: 20.16 published them but never applied them)
: "${FREEPBX_NODEJSBINDPORT:=${APP_PORT_UCP_HTTP}}"
: "${FREEPBX_NODEJSHTTPSBINDPORT:=${APP_PORT_UCP_HTTPS}}"
: "${ZABBIX_SERVER_ACTIVE:=${ZABBIX_SERVER}}"
# APP_FQDN is the hostname of the services (20.16: hostname + export HOSTNAME)
[ -n "$APP_FQDN" ] && export HOSTNAME="$APP_FQDN"
: "${SERVERNAME:=${HOSTNAME:-}}"
: "${ZABBIX_HOSTNAME:=${HOSTNAME:-}}"

## migration from 20.16 (new in 22.17, design §7 and §13)
: "${IZPBX_MIGRATE_FREEPBX:=false}"
: "${IZPBX_MIGRATE_IGNORE_MODULES:=}"
: "${IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN:=false}"
# maintenance mode (design S10): written by izpbx-init, read by service_gate
# and izpbx-healthcheck (in /run: it does not survive a restart)
: "${IZPBX_MAINTENANCE_FLAG:=/run/izpbx/maintenance}"
