#!/bin/bash
# written by Ugo Viti <ugo.viti@initzero.it>
# version: 20240113
#set -ex

## app specific variables
: ${APP_DESCRIPTION:="izPBX Cloud Telephony System"}
: ${APP_CHART:=""}
: ${APP_RELEASE:=""}
: ${APP_NAMESPACE:=""}

: ${ASTERISK_VER:=""}
: ${FREEPBX_VER:=""}

# override default data directory used by this apps (used for stateful and persistent data)
: ${APP_CONF:=""}
: ${APP_DATA:=""}
: ${APP_LOGS:=""}
: ${APP_TEMP:=""}

# array of custom data directory
declare -A appDataDirsCustom=(
  [APP_CONF]="${APP_CONF}"
  [APP_DATA]="${APP_DATA}"
  [APP_LOGS]="${APP_LOGS}"
  [APP_TEMP]="${APP_TEMP}"
)

# array of default data directory paths used by this app
declare -A appDataDirsDefault=(
  [APP_CONF]="${APP_CONF}"
  [APP_DATA]="${APP_DATA}"
  [APP_LOGS]="${APP_LOGS}"
  [APP_TEMP]="${APP_TEMP}"
)

# timezone management workaround
: ${TZ:="UTC"}
[ -e "/etc/localtime" ] && rm -f /etc/localtime
[ -e "/etc/timezone" ] && rm -f /etc/timezone
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
echo "$TZ" > /etc/timezone

# default directory and config files paths arrays used for persistent data
declare -A appDataDirs=(
  [CRONDIR]="/var/spool/cron"
  [ASTHOME]="/home/asterisk"
  [ASTETCDIR]="/etc/asterisk"
  [ASTVARLIBDIR]="/var/lib/asterisk"
  [ASTSPOOLDIR]="/var/spool/asterisk"
  [HTTPDHOME]="/var/www"
  [HTTPDLOGDIR]="/var/log/httpd"
  [ASTLOGDIR]="/var/log/asterisk"
  [F2BLOGDIR]="/var/log/fail2ban"
  [F2BLIBDIR]="/var/lib/fail2ban"
  [FOP2APPDIR]="/usr/local/fop2"
  [ROOTHOME]="/root"
  [DNSMASQDIR]="/etc/dnsmasq.d"
  [DNSMASQLEASEDIR]="/var/lib/dnsmasq"
  [TFTPDIR]="/var/lib/tftpboot"
)

# configuration files
declare -A appFilesConf=(
  [FPBXCFGFILE]="/etc/freepbx.conf"
  [AMPCFGFILE]="/etc/amportal.conf"
)

# log files
declare -A appFilesLog=(
  [FPBXLOGFILE]="/var/log/asterisk/freepbx.log"
  [FPBXSECLOGFILE]="/var/log/asterisk/freepbx_security.log"
  [F2BLOGFILE]="/var/log/fail2ban/fail2ban.log"
)

# cache directories
declare -A appCacheDirs=(
  [ASTRUNDIR]="/var/run/asterisk"
  [PHPOPCACHEDIR]="/var/lib/php/opcache"
  [PHPSESSDIR]="/var/lib/php/session"
  [PHPWSDLDIR]="/var/lib/php/wsdlcache"
)

# FreePBX directories
declare -A fpbxDirs=(
  [AMPWEBROOT]="/var/www/html"
  [ASTETCDIR]="/etc/asterisk"
  [ASTVARLIBDIR]="/var/lib/asterisk"
  [ASTAGIDIR]="/var/lib/asterisk/agi-bin"
  [ASTSPOOLDIR]="/var/spool/asterisk"
  [ASTLOGDIR]="/var/log/asterisk"
  [AMPBIN]="/var/lib/asterisk/bin"
  [AMPSBIN]="/var/lib/asterisk/sbin"
  [AMPCGIBIN]="/var/www/cgi-bin"
  [AMPPLAYBACK]="/var/lib/asterisk/playback"
  [CERTKEYLOC]="/etc/asterisk/keys"
)

# asterisk extra directories
declare -A fpbxDirsExtra=(
  [ASTMODDIR]="/usr/lib64/asterisk/modules"
)

# FreePBX log files
declare -A fpbxFilesLog=(
  [FPBXDBUGFILE]="/var/log/asterisk/freepbx_debug.log"
)

# FreePBX customizable settings
: ${FREEPBX_FIX_PERMISSION:="true"}
: ${FREEPBX_HTTPBINDPORT:="$APP_PORT_AMI"}

# FreePBX customizable SIP settings
declare -A fpbxSipSettings=(
  [rtpstart]=${APP_PORT_RTP_START}
  [rtpend]=${APP_PORT_RTP_END}
  [udpport-0.0.0.0]=${APP_PORT_PJSIP}
  [tcpport-0.0.0.0]=${APP_PORT_PJSIP}
  [bindport]=${APP_PORT_SIP}
)

# 20200318 still can't be changed
#declare -A freepbxIaxSettings=(
#  [bindport]=${APP_PORT_IAX}
#)

## other variables

# hostname configuration
[ ! -z ${APP_FQDN} ] && hostname "${APP_FQDN}" && export HOSTNAME=${HOSTNAME} # set hostname to APP_FQDN if defined
: ${SERVERNAME:=$HOSTNAME}      # (**$HOSTNAME**) default web server hostname

# define PHONEBOOK_ADDRESS used in phonebook menu.xml.
: ${PHONEBOOK_ADDRESS:=""}
if [ -z "$PHONEBOOK_ADDRESS" ]; then
  [ "$HTTPD_HTTPS_ENABLED" = "true" ] && PHONEBOOK_PROTO=https || PHONEBOOK_PROTO=http

  if [ -z ${APP_FQDN} ]; then
      PHONEBOOK_ADDRESS="$PHONEBOOK_PROTO://$(hostname -I | awk '{print $1}')"
    else
      PHONEBOOK_ADDRESS="$PHONEBOOK_PROTO://${APP_FQDN}"
  fi
fi

# mysql configuration (see bellow for other variables after help functions section)
: ${MYSQL_SERVER:="db"}
: ${MYSQL_DATABASE:="asterisk"}
: ${MYSQL_DATABASE_CDR:="asteriskcdrdb"}
: ${MYSQL_USER:="asterisk"}
: ${MYSQL_PASSWORD:=""}
: ${MYSQL_ROOT_USER:="root"}
: ${MYSQL_ROOT_PASSWORD:=""}
: ${APP_PORT_MYSQL:="3306"}

# fop2 (automaticcally obtained quering freepbx settings)
#: ${FOP2_AMI_HOST:="localhost"}
#: ${FOP2_AMI_PORT:="5038"}
#: ${FOP2_AMI_USERNAME:="admin"}
#: ${FOP2_AMI_PASSWORD:="amp111"}
: ${FOP2_AUTOUPGRADE:="false"}
: ${FOP2_AUTOACTIVATION:="false"}

# apache httpd configuration
: ${HTTPD_HTTPS_ENABLED:="false"}
: ${HTTPD_REDIRECT_HTTP_TO_HTTPS:="false"}
: ${HTTPD_ALLOW_FROM:=""}

: ${HTTPD_HTTPS_CERT_FILE:="${fpbxDirs[CERTKEYLOC]}/default.crt"}
: ${HTTPD_HTTPS_KEY_FILE:="${fpbxDirs[CERTKEYLOC]}/default.key"}
#: ${HTTPD_HTTPS_CHAIN_FILE:="${fpbxDirs[CERTKEYLOC]}/default.chain.crt"}

# phpMyAdmin configuration
: ${PMA_CONFIG:="/etc/phpMyAdmin/config.inc.php"}
: ${PMA_ALIAS:="/admin/pma"}
: ${PMA_ALLOW_FROM:="127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"}

## zabbix configuration
: ${ZABBIX_USR:="zabbix"}
: ${ZABBIX_GRP:="zabbix"}
: ${ZABBIX_SERVER:="127.0.0.1"}
: ${ZABBIX_SERVER_ACTIVE:="${ZABBIX_SERVER}"}
: ${ZABBIX_HOSTNAME:="$HOSTNAME"}
: ${ZABBIX_HOSTMETADATA:="izPBX"}

## default supervisord services status
: ${CRON_ENABLED:="true"}
: ${HTTPD_ENABLED:="true"}
: ${ASTERISK_ENABLED:="false"}
: ${IZPBX_ENABLED:="true"}
: ${FAIL2BAN_ENABLED:="true"}
: ${MSMTP_ENABLED:="true"}
: ${POSTFIX_ENABLED:="false"}
: ${DNSMASQ_ENABLED:="false"}
: ${DHCP_ENABLED:="false"}
: ${TFTP_ENABLED:="false"}
: ${NTP_ENABLED:="false"}
: ${ZABBIX_ENABLED:="false"}
: ${FOP2_ENABLED:="false"}
: ${PMA_ENABLED:="false"}
: ${PHONEBOOK_ENABLED:="true"}

## daemons configs
# legacy config: if ROOT_MAILTO is defined then set SMTP_MAIL_TO=$ROOT_MAILTO
: ${SMTP_MAIL_TO:="$ROOT_MAILTO"}
## default cron mail adrdess
: ${ROOT_MAILTO:="$SMTP_MAIL_TO"} # default root mail address

# postfix
: ${SMTP_RELAYHOST:=""}
#: ${SMTP_RELAYHOST_PORT:="25"}
: ${SMTP_RELAYHOST_USERNAME:=""}
: ${SMTP_RELAYHOST_PASSWORD:=""}
: ${SMTP_STARTTLS:="true"}
: ${SMTP_ALLOWED_SENDER_DOMAINS:=""}
: ${SMTP_MESSAGE_SIZE_LIMIT:="0"}
: ${SMTP_MAIL_FROM:="izpbx@localhost.localdomain"}
: ${SMTP_MAIL_TO:="root@localhost.localdomain"}
# smarthost config
: ${RELAYHOST:="$SMTP_RELAYHOST"}
#: ${RELAYHOST_PORT:="$SMTP_RELAYHOST_PORT"}
: ${RELAYHOST_USERNAME:="$SMTP_RELAYHOST_USERNAME"}
: ${RELAYHOST_PASSWORD:="$SMTP_RELAYHOST_PASSWORD"}
: ${ALLOWED_SENDER_DOMAINS:="$SMTP_ALLOWED_SENDER_DOMAINS"}
: ${MESSAGE_SIZE_LIMIT:="$SMTP_MESSAGE_SIZE_LIMIT"}

# fail2ban
: ${FAIL2BAN_DEFAULT_SENDER:="$SMTP_MAIL_FROM"}
: ${FAIL2BAN_DEFAULT_DESTEMAIL:="$SMTP_MAIL_TO"}

# operating system specific variables
## detect current operating system
: ${OS_RELEASE:="$(cat /etc/os-release | grep ^"ID=" | sed 's/"//g' | awk -F"=" '{print $2}')"}

# operating system specific paths
if   [ "$OS_RELEASE" = "debian" ]; then
# debian paths
: ${SUPERVISOR_DIR:="/etc/supervisor/conf.d/"}
: ${PMA_DIR:="/var/www/html/admin/pma"}
: ${PMA_CONF:="$PMA_DIR/config.inc.php"}
#: ${PMA_CONF:="/etc/phpmyadmin/config.inc.php"}
: ${PMA_CONF_APACHE:="/etc/phpmyadmin/apache.conf"}
: ${PHP_CONF:="/etc/php/7.3/apache2/php.ini"}
: ${NRPE_CONF:="/etc/nagios/nrpe.cfg"}
: ${NRPE_CONF_LOCAL:="/etc/nagios/nrpe_local.cfg"}
: ${ZABBIX_CONF:="/etc/zabbix/zabbix_agent2.conf"}
: ${ZABBIX_CONF_LOCAL:="/etc/zabbix/zabbix_agent2.d/local.conf"}
elif [ "$OS_RELEASE" = "alpine" ]; then
# alpine paths
: ${SUPERVISOR_DIR:="/etc/supervisor.d"}
: ${PMA_CONF:="/etc/phpmyadmin/config.inc.php"}
: ${PMA_CONF_APACHE:="/etc/apache2/conf.d/phpmyadmin.conf"}
: ${PHP_CONF:="/etc/php/php.ini"}
: ${ZABBIX_CONF_LOCAL:="/etc/zabbix/zabbix_agent2.d/local.conf"}
else
# failback to RHEL based distro
: ${SUPERVISOR_DIR:="/etc/supervisord.d"}
: ${HTTPD_CONF_DIR:="/etc/httpd"} # apache config dir
: ${PMA_CONF_APACHE:="/etc/httpd/conf.d/phpMyAdmin.conf"}
: ${ZABBIX_CONF:="/etc/zabbix/zabbix_agent2.conf"}
: ${ZABBIX_CONF_LOCAL:="/etc/zabbix/zabbix_agent2.d/local.conf"}
fi


## helper functions
function check_version() { printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' '); }
function print_path() { echo ${@%/*}; }
function print_fullname() { echo ${@##*/}; }
function print_name() { print_fullname $(echo ${@%.*}); }
function print_ext() { echo ${@##*.}; }
function dirEmpty() { [ -z "$(ls -A "$1"/)" ]; } # return true if specified directory is empty, false if contains files
function readfsecret() {
  # parameters:
  #
  #  $1 : name of variable that stores path to password file
  #  $2 : name of variable that stores retrieved password
  #

  if [ $# -lt 2 ] ; then
    echo "syntax error: not enough parameters" >&2
    return 1
  elif [ ! ${!1} ] ; then
    echo "info/warning: param#1 / value referenced by '$1' (expected: file path to secret file) is empty. abort." >&2
    return 128
  elif [ ${!2} ] ; then
    # password string  in target var if present has presedence
    echo "info/warning: param#2 / target var '$2' is not empty. we refuse to overwrite present value of '$2'. abort." >&2
    return 129
  elif [ -r "${!1}" ] ; then
    # check if password file is accessible
    # if yes, read file content and store it in $2 var
    local rvalue="$(<${!1})"
    local -n rvref=$2
    rvref=$rvalue
  else
    echo "error: can not access/read passwort file '${!1}'. abort." >&2
    return 1
  fi

  if [ ! ${!2} ] ; then
    # issue a warning if content of secret file is empty
    echo "warning: param#2 / passwort var '${2}' has been set to empty string." >&2
  fi

  # TODO: export retrieved password to environment if necessary
}

# mysql secrets from docker secrets
[ ! -z "$IZPBX_MYSQL_PASSWORD_FILE" ]      && readfsecret IZPBX_MYSQL_PASSWORD_FILE      MYSQL_PASSWORD
[ ! -z "$IZPBX_MYSQL_ROOT_PASSWORD_FILE" ] && readfsecret IZPBX_MYSQL_ROOT_PASSWORD_FILE MYSQL_ROOT_PASSWORD


## main functions
function initizializeDir() {
  local dirDefault="$1"
  shift
  local dirCustom="$1"
  shift
  local prefixLog="$1"
  shift
  local syncForce="$1"

  if [ -z "$prefixLog" ];then
    local prefix="--> "
    local prefixIndent="--> "
  else
    local prefix="--> $prefixLog "
    local prefixIndent="$(echo $prefixLog | sed 's/[][\/a-zA-Z0-9]/-/g')---> "
  fi

  # verify if $dirDefault and $dirCustom are not the same directory
  if [[ "$dirDefault" != "$dirCustom" && -e "$dirDefault" && ! -z "$dirCustom" ]]; then
    if dirEmpty "$dirCustom" && ! dirEmpty "${dirDefault}"; then
      # copy data files form default directory if destination is empty
      echo -e "${prefixIndent}INFO: [$dirDefault] empty dir '${dirCustom}' detected... copying default files from '${dirDefault}' to '${dirCustom}'"
      cp -af "$dirDefault"/. "$dirCustom"/
      #echo -e "${prefixIndent}INFO: [$dirDefault] setting owner with user '${APP_USR}' (UID:${APP_UID}) and group '${APP_GRP}' (GID:${APP_GID}) on '${dirCustom}'"
      #chown -R ${APP_USR}:${APP_GRP} "$dirCustom"/
    elif [[ ! -f "${dirCustom}/.initialized" && "$syncForce" = "force" ]]; then
      # copy data files form default directory only if destination is not initialized and is empty
      echo -e "${prefixIndent}INFO: [$dirDefault] missing '${dirCustom}/.initialized' file... copying default files from '${dirDefault}' to '${dirCustom}'"
      cp -af "$dirDefault"/. "$dirCustom"/
    else
      echo -e "${prefixIndent}INFO: [$dirDefault] data dir '$dirCustom' is already initialized... skipping data initialization"
    fi
  fi

  # make the dirCustom initialized unsing ISO 8601:2004 extended time format: https://en.wikipedia.org/wiki/ISO_8601
  if [[ -e "${dirCustom}" && ! -f "${dirCustom}/.initialized" ]]; then
    echo -e "${prefixIndent}INFO: [$dirDefault] directory '$dirCustom' successfully initialized"
    echo "$(date +"%Y-%m-%dT%H:%M:%S%:z")" > "${dirCustom}/.initialized";
  fi
}

# if required move default confgurations to custom directory
function symlinkDir() {
  local dirDefault="$1"
  shift
  local dirCustom="$1"
  shift
  local prefixLog="$1"

  if [ -z "$prefixLog" ];then
    local prefix="--> "
    local prefixIndent="--> "
  else
    local prefix="--> $prefixLog "
    local prefixIndent="$(echo $prefixLog | sed 's/[][\/a-zA-Z0-9]/-/g')---> "
  fi

  if [ ! -z "$dirCustom" ]; then
    echo -e "${prefix}INFO: [$dirDefault] detected directory data override path: '$dirCustom'"

    if [ ! -e "$dirCustom" ]; then
      # make destination dir if not exist
      echo -e "${prefixIndent}WARN: [$dirDefault] custom directory '$dirCustom' doesn't exist... creating empty directory '$dirCustom'"
      mkdir -p "$dirCustom"
    fi

    if [ ! -e "$dirDefault" ]; then
      # make default dir if not exist
      echo -e "${prefixIndent}WARN: [$dirDefault] default directory doesn't exist... creating empty directory '$dirDefault'"
      mkdir -p "$dirDefault"
    fi

    # rename default directory
    if [ -e "$dirDefault" ]; then
      echo -e "${prefixIndent}INFO: [$dirDefault] renaming '$dirDefault' to '${dirDefault}.dist'"
      mv "$dirDefault" "$dirDefault".dist
    fi

    # symlink default directory to custom directory
    echo -e "${prefixIndent}INFO: [$dirDefault] symlinking '$dirDefault' to '$dirCustom'"
    ln -s "$dirCustom" "$dirDefault"
  else
    echo "${prefix}WARN: [$dirDefault] no custom persistent storage path defined... all data placed into '$dirDefault' will be lost on container restart"
  fi
}

function symlinkFile() {
  local fileDefault="$1"
  shift
  local fileCustom="$1"
  shift
  local prefixLog="$1"

  if [ -z "$prefixLog" ];then
    local prefix="--> "
    local prefixIndent="--> "
  else
    local prefix="--> $prefixLog "
    local prefixIndent="$(echo $prefixLog | sed 's/[][\/a-zA-Z0-9]/-/g')---> "
  fi

  echo -e "${prefix}INFO: [$fileDefault] file data override detected: default:[$fileDefault] custom:[$fileCustom]"

  if [ -e "$fileDefault" ]; then
      # copy data files form default directory if destination is empty
      if [ ! -e "$fileCustom" ]; then
        echo -e "${prefixIndent}INFO: [$fileDefault] detected not existing file '$fileCustom'. copying '$fileDefault' to '$fileCustom'..."
        cp -a -f "$fileDefault" "$fileCustom"
      fi
      echo -e "${prefixIndent}INFO: [$fileDefault] renaming to '${fileDefault}.dist'... "
      mv "$fileDefault" "$fileDefault".dist
    else
      echo -e "${prefixIndent}WARN: [$fileDefault] default file doesn't exist... creating symlink from a not existing source file"
      #touch "$fileDefault"
  fi

  echo -e "${prefixIndent}INFO: [$fileDefault] symlinking '$fileDefault' to '$fileCustom'"
  # create parent dir if not exist
  [ ! -e "$(dirname "$fileCustom")" ] && mkdir -p "$(dirname "$fileCustom")"
  # link custom file over orinal path
  ln -s "$fileCustom" "$fileDefault"
}

function fixOwner() {
  usr=$1
  shift
  grp=$1
  shift
  file="$@"
  if [ -e "${file}" ]; then
      if [ "$(stat -c "%U %G" "${file}")" != "${usr} ${grp}" ];then
          echo "---> fixing owner: '${file}'"
          chown ${usr}:${grp} "${file}"
      fi
    else
      echo "---> WARNING: file or directory doesn't exist: '${file}'"
  fi
}

function fixPermission() {
  usr=$1
  shift
  grp=$1
  shift
  file="$@"
  if [ -e "${file}" ]; then
      if [ "$(stat -c "%a" "${file}")" != "770" ];then
          echo "---> fixing permission: '${file}'"
          chmod 0770 "${file}"
      fi
    else
      echo "---> WARNING: file or directory doesn't exist: '${file}'"
  fi
}

# enable/disable and configure services
function chkService() {
  local SERVICE_VAR="$1"
  eval local SERVICE_ENABLED="\$$(echo $SERVICE_VAR)"
  eval local SERVICE_DAEMON="\$$(echo $SERVICE_VAR | sed 's/_.*//')_DAEMON"
  local SERVICE="$(echo $SERVICE_VAR | sed 's/_.*//' | sed -e 's/\(.*\)/\L\1/')"
  [ -z "$SERVICE_DAEMON" ] && local SERVICE_DAEMON="$SERVICE"
  if [ "$SERVICE_ENABLED" = "true" ]; then
    autostart=true
    echo "=> Enabling $SERVICE_DAEMON service... because $SERVICE_VAR=$SERVICE_ENABLED"
    echo "--> configuring $SERVICE_DAEMON service..."
    cfgService_$SERVICE
   else
    autostart=false
    echo "=> Disabling $SERVICE_DAEMON service... because $SERVICE_VAR=$SERVICE_ENABLED"
  fi
  sed "s/autostart=.*/autostart=$autostart/" -i ${SUPERVISOR_DIR}/$SERVICE_DAEMON.ini
}

## postfix service
function cfgService_postfix() {
# fix inet_protocols ipv6 problem
postconf -e inet_protocols=ipv4

# Set up host name
if [ ! -z "$HOSTNAME" ]; then
  postconf -e myhostname="$HOSTNAME"
else
  postconf -# myhostname
fi

# Set up a relay host, if needed
if [ ! -z "$RELAYHOST" ]; then
    echo -n "- Forwarding all emails to [$RELAYHOST]:$RELAYHOST_PORT"
    postconf -e "relayhost=[$RELAYHOST]:$RELAYHOST_PORT"

    if [ -n "$RELAYHOST_USERNAME" ] && [ -n "$RELAYHOST_PASSWORD" ]; then
      echo " using username $RELAYHOST_USERNAME."
      echo "$RELAYHOST $RELAYHOST_USERNAME:$RELAYHOST_PASSWORD" >> /etc/postfix/sasl_passwd
      postmap hash:/etc/postfix/sasl_passwd
      postconf -e "smtp_sasl_auth_enable=yes"
      postconf -e "smtp_sasl_password_maps=hash:/etc/postfix/sasl_passwd"
      postconf -e "smtp_sasl_security_options=noanonymous"
    else
      echo " without any authentication. Make sure your server is configured to accept emails coming from this IP."
    fi
else
    echo "---> postfix will try to deliver emails directly to the final server. make sure your DNS is setup properly!"
    postconf -# relayhost
    postconf -# smtp_sasl_auth_enable
    postconf -# smtp_sasl_password_maps
    postconf -# smtp_sasl_security_options
fi

# Set up my networks to list only networks in the local loopback range
#network_table=/etc/postfix/network_table
#touch $network_table
#echo "127.0.0.0/8    any_value" >  $network_table
#echo "10.0.0.0/8     any_value" >> $network_table
#echo "172.16.0.0/12  any_value" >> $network_table
#echo "192.168.0.0/16 any_value" >> $network_table
## Ignore IPv6 for now
##echo "fd00::/8" >> $network_table
#postmap $network_table
#postconf -e mynetworks=hash:$network_table

if [ ! -z "$SMTP_MYNETWORKS" ]; then
  echo "---> enabling mynetworks: $SMTP_MYNETWORKS"
  postconf -e mynetworks=$SMTP_MYNETWORKS
else
  postconf -e "mynetworks=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
fi

if [ "$SMTP_STARTTLS" = "true" ]; then
  echo "---> enabling TLS support as smtp client"
  postconf -e smtp_use_tls=yes
fi

# split with space
if [ ! -z "$ALLOWED_SENDER_DOMAINS" ]; then
	echo -n "---> Setting up allowed SENDER domains: $ALLOWED_SENDER_DOMAINS"
	allowed_senders=/etc/postfix/allowed_senders
	rm -f $allowed_senders $allowed_senders.db > /dev/null
	touch $allowed_senders
	for i in $ALLOWED_SENDER_DOMAINS; do
		echo -n " $i"
		echo -e "$i\tOK" >> $allowed_senders
	done
	echo
	postmap $allowed_senders

	postconf -e "smtpd_restriction_classes=allowed_domains_only"
	postconf -e "allowed_domains_only=permit_mynetworks, reject_non_fqdn_sender reject"
	postconf -e "smtpd_recipient_restrictions=reject_non_fqdn_recipient, reject_unknown_recipient_domain, reject_unverified_recipient, check_sender_access hash:$allowed_senders, reject"
else
	postconf -# "smtpd_restriction_classes"
	postconf -e "smtpd_recipient_restrictions=reject_non_fqdn_recipient,reject_unknown_recipient_domain,reject_unverified_recipient"
fi

# Use 587 (submission)
echo "---> enabling submission protocol on port 587"
sed -i -r -e 's/^#submission/submission/' /etc/postfix/master.cf

# configure /etc/aliases
[ ! -f /etc/aliases ] && echo "postmaster: root" > /etc/aliases

if   ! grep ^"root:" /etc/aliases 2>&1 >/dev/null; then 
  echo "root: ${SMTP_MAIL_TO}" >> /etc/aliases
  newaliases
elif ! grep ^"root:.*${SMTP_MAIL_TO}" /etc/aliases 2>&1 >/dev/null; then 
  echo sed "s/^root:.*/root: ${SMTP_MAIL_TO}/" -i /etc/aliases
  newaliases
fi

# enable logging to stdout
postconf -e "maillog_file = /dev/stdout"

# fix for send-mail: fatal: parameter inet_interfaces: no local interface found for ::1
postconf -e "inet_protocols = ipv4"

# set max message size limit
postconf -e "mailbox_size_limit = 0"
postconf -e "message_size_limit = ${MESSAGE_SIZE_LIMIT}"

# set from email address
if [ ! -z "$SMTP_MAIL_FROM" ]; then
  echo "/.+/ $SMTP_MAIL_FROM" > /etc/postfix/sender_canonical_maps
  echo "/From:.*/ REPLACE From: $SMTP_MAIL_FROM" > /etc/postfix/header_checks
  postconf -e "sender_canonical_maps = regexp:/etc/postfix/sender_canonical_maps"
  postconf -e "smtp_header_checks = regexp:/etc/postfix/header_checks"
fi
}

## cron service
function cfgService_cron() {
  if   [ "$OS_RELEASE" = "debian" ]; then
    cronDir="/var/spool/cron/ing supervisord config fbs"
  else
    cronDir="/var/spool/cron"
  fi
  
  if [ -e "$cronDir" ]; then
    if [ "$(stat -c "%U %G %a" "$cronDir")" != "root root 0700" ];then
      echo "---> fixing permissions: '$cronDir'"
      chown root:root "$cronDir"
      chmod u=rwx,g=wx,o=t "$cronDir"
    fi
  fi
}

## parse and edit ini config files based on SECTION and KEY=VALUE

# input stream format: SECTION KEY=VALUE
#   echo RECIDIVE ENABLED=false | iniParser /etc/fail2ban/jail.d/99-local.conf

# FIXME: match all files sections right now
# example for multple values using global env and parsing it before send to iniParser:
#  set FAIL2BAN_DEFAULT_FINDTIME=3600
#  set FAIL2BAN_DEFAULT_MAXRETRY=10
#  set FAIL2BAN_RECIDIVE_ENABLED=false
#  set FAIL2BAN_RECIDIVE_BANTIME=1814400
#  set | grep ^"FAIL2BAN_" | sed -e 's/^FAIL2BAN_//' | sed -e 's/_/ /' | iniParser /etc/fail2ban/jail.d/99-local.conf
function iniParser() {
  ini="$@"
  while read setting ; do
    section="$(echo $setting | cut -d" " -f1)"
    k=$(echo $setting | sed -e "s/^${section} //" | cut -d"=" -f-1 | tr '[:upper:]' '[:lower:]')
    v=$(echo $setting | sed -e "s/'//g" | cut -d"=" -f2-)
    sed -e "/^\[${section}\]$/I,/^\(\|;\|#\)\[/ s/^\(;\|#\)${k}/${k}/" -e "/^\[${section}\]$/I,/^\[/ s|^${k}.*=.*|${k}=${v}|I" -i "${ini}"
  done
}

## fail2ban service
function cfgService_fail2ban() {
  echo "--> reconfiguring Fail2ban settings..."
  # ini config file parse function
  # fix default log path
  echo "DEFAULT LOGTARGET=${appFilesLog[F2BLOGFILE]}" | iniParser "/etc/fail2ban/fail2ban.conf"
  # configure all settings
  set | grep ^"FAIL2BAN_" | sed -e 's/^FAIL2BAN_//' | sed -e 's/_/ /' | iniParser "/etc/fail2ban/jail.d/99-local.conf"
}

## apache service
function cfgService_httpd() {

  # local functions
  function print_ApacheAllowFrom() {
    if [ ! -z "${HTTPD_ALLOW_FROM}" ]; then 
        for IP in $(echo ${HTTPD_ALLOW_FROM} | sed -e "s/'//g") ; do
          echo "    Require ip ${IP}"
        done
    else
        echo "    Require all granted"
    fi
  }

echo "--> setting Apache ServerName to ${SERVERNAME}"
sed "s/#LoadModule mpm_prefork_module/LoadModule mpm_prefork_module/" -i "${HTTPD_CONF_DIR}/conf.modules.d/00-mpm.conf"
sed "s/LoadModule mpm_event_module/#LoadModule mpm_event_module/"     -i "${HTTPD_CONF_DIR}/conf.modules.d/00-mpm.conf"
sed "s/^#ServerName.*/ServerName ${SERVERNAME}/" -i "${HTTPD_CONF_DIR}/conf/httpd.conf"
sed "s/^User .*/User ${APP_USR}/"               -i "${HTTPD_CONF_DIR}/conf/httpd.conf"
sed "s/^Group .*/Group ${APP_GRP}/"             -i "${HTTPD_CONF_DIR}/conf/httpd.conf"
sed "s/^Listen .*/Listen ${APP_PORT_HTTP}/"       -i "${HTTPD_CONF_DIR}/conf/httpd.conf"

# disable default ssl.conf and use virtual.conf
[ -e "${HTTPD_CONF_DIR}/conf.d/ssl.conf" ] && mv "${HTTPD_CONF_DIR}/conf.d/ssl.conf" "${HTTPD_CONF_DIR}/conf.d/ssl.conf-dist"

echo "--> configuring Apache VirtualHosting and creating empty ${HTTPD_CONF_DIR}/conf.d/virtual.conf file"
echo "" > "${HTTPD_CONF_DIR}/conf.d/virtual.conf"

echo "# default virtualhost

<VirtualHost *:${APP_PORT_HTTP}>
  DocumentRoot /var/www/html" >> "${HTTPD_CONF_DIR}/conf.d/virtual.conf"
  
if [ "${HTTPD_REDIRECT_HTTP_TO_HTTPS}" = "true" ]; then
echo "--> setting automatic redirect from http to https for default virtualhost"
echo "  <IfModule mod_rewrite.c>
    RewriteEngine on
    RewriteCond %{REQUEST_URI} !\.well-known/acme-challenge
    RewriteCond %{REQUEST_URI} !\.freepbx-known
    RewriteCond %{HTTPS} off
    #RewriteCond %{HTTP_HOST} ^www\.(.*)$ [NC]
    RewriteRule .? https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
  </IfModule>" >> "${HTTPD_CONF_DIR}/conf.d/virtual.conf"
fi

echo "
  <Directory /var/www/html>
    Options Includes FollowSymLinks
    AllowOverride All
$(print_ApacheAllowFrom)
  </Directory>
</VirtualHost>
" >> "${HTTPD_CONF_DIR}/conf.d/virtual.conf"

if [ ! -z "${APP_FQDN}" ]; then
  echo "--> setting Apache VirtualHosting to: ${APP_FQDN} on port ${APP_PORT_HTTP}"
  echo "# ${APP_FQDN} virtualhost
  <VirtualHost *:${APP_PORT_HTTP}>
    ServerName ${APP_FQDN}" >> "${HTTPD_CONF_DIR}/conf.d/virtual.conf"
    
  if [ "${HTTPD_REDIRECT_HTTP_TO_HTTPS}" = "true" ]; then
  echo "--> setting automatic redirect from http to https for ${APP_FQDN} virtualhost"
  echo "# enable http to https automatic rewrite
<IfModule mod_rewrite.c>
  RewriteEngine on
  RewriteCond %{REQUEST_URI} !\.well-known/acme-challenge
  RewriteCond %{REQUEST_URI} !\.freepbx-known
  RewriteCond %{HTTPS} off
  #RewriteCond %{HTTP_HOST} ^www\.(.*)$ [NC]
  RewriteRule .? https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</IfModule>
" >> "${HTTPD_CONF_DIR}/conf.d/virtual.conf"
  fi
  
  # close virtualhost directive
  echo "<Directory /var/www/html>
    Options Includes FollowSymLinks
    AllowOverride All
$(print_ApacheAllowFrom)
  </Directory>
</VirtualHost>
" >> "${HTTPD_CONF_DIR}/conf.d/virtual.conf"
fi

if [ "${HTTPD_HTTPS_ENABLED}" = "true" ]; then
  echo "--> enabling Apache SSL engine"
  
  ## recreate self-signed cert if needed
  # detect CN of specified cert
  [ -e "${HTTPD_HTTPS_CERT_FILE}" ] && local CERT_CN=$(openssl x509 -noout -subject -in ${HTTPD_HTTPS_CERT_FILE} | sed 's/.*CN = //;s/, .*//')
  
  # define cert subject
  [ -z "$APP_FQDN" ] && local CERT_SUBJ="/CN=izpbx" || CERT_SUBJ="/CN=$APP_FQDN"

  if [[ ! -e "${HTTPD_HTTPS_CERT_FILE}" && ! -e "${HTTPD_HTTPS_KEY_FILE}" ]]; then
    echo "---> WARNING: the SSL certificate files (HTTPD_HTTPS_CERT_FILE=${HTTPD_HTTPS_CERT_FILE} HTTPD_HTTPS_KEY_FILE=${HTTPD_HTTPS_KEY_FILE}) doesn't exist"
    echo "----> generating new self-signed certificate (with 10 years duration) to avoid web server crashing"
    # make dirs if not exists
    [ ! -e "$(dirname "${HTTPD_HTTPS_CERT_FILE}")" ] && mkdir "$(dirname "${HTTPD_HTTPS_CERT_FILE}")"
    [ ! -e "$(dirname "${HTTPD_HTTPS_KEY_FILE}")" ]  && mkdir "$(dirname "${HTTPD_HTTPS_KEY_FILE}")"
    openssl req -subj "$CERT_SUBJ" -new -newkey rsa:2048 -sha256 -days 3650 -nodes -x509 -keyout "${HTTPD_HTTPS_KEY_FILE}" -out "${HTTPD_HTTPS_CERT_FILE}"
  elif [[ ! -z "$APP_FQDN" && "$CERT_CN" = "izpbx" ]]; then
    echo "---> WARNING: current SSL certificate CN '$CERT_CN' (${HTTPD_HTTPS_CERT_FILE}) doesn't match configured APP_FQDN '$APP_FQDN' variable"
    echo "----> generating new self-signed certificate (with 10 years duration)"
    openssl req -subj "$CERT_SUBJ" -new -newkey rsa:2048 -sha256 -days 3650 -nodes -x509 -keyout "${HTTPD_HTTPS_KEY_FILE}" -out "${HTTPD_HTTPS_CERT_FILE}"
  elif [[ ! -z "$APP_FQDN" && "$APP_FQDN" != "$CERT_CN" ]]; then
    echo "---> WARNING: current SSL certificate CN '$CERT_CN' (${HTTPD_HTTPS_CERT_FILE}) doesn't match configured APP_FQDN '$APP_FQDN' variable"
    echo "----> NOTE: FIX IT BY REPLACING THE WRONG CERTIFICATES"
  fi

  echo "
# enable HTTPS listening
Listen ${APP_PORT_HTTPS} https
SSLPassPhraseDialog    exec:/usr/libexec/httpd-ssl-pass-dialog
SSLSessionCache        shmcb:/run/httpd/sslcache(512000)
SSLSessionCacheTimeout 300
SSLCryptoDevice        builtin
" >> "${HTTPD_CONF_DIR}/conf.d/virtual.conf"

  if [[ -z "${APP_FQDN}" && "${LETSENCRYPT_ENABLED}" = "true" ]]; then
    echo "--> WARNING: LETSENCRYPT_ENABLED=${LETSENCRYPT_ENABLED} but not APP_FQDN defined, please set APP_FQDN to a valid Internet FQDN domain name and retry... enabling self signed certificate instead"
  fi

  if [[ ! -z "${APP_FQDN}" && "${LETSENCRYPT_ENABLED}" = "true" ]]; then
    echo "# enable ssl virtualhost using Let's Encrypt certificates
<VirtualHost *:${APP_PORT_HTTPS}>
  ServerName ${APP_FQDN}

  ErrorLog                 logs/ssl_error_log
  TransferLog              logs/ssl_access_log
  LogLevel                 warn
  
  SSLEngine               on
  SSLHonorCipherOrder     on
  SSLCipherSuite          PROFILE=SYSTEM
  SSLProxyCipherSuite     PROFILE=SYSTEM
  SSLCertificateFile      ${fpbxDirs[CERTKEYLOC]}/integration/webserver.crt
  SSLCertificateKeyFile   ${fpbxDirs[CERTKEYLOC]}/integration/webserver.key
  SSLCertificateChainFile ${fpbxDirs[CERTKEYLOC]}/integration/certificate.pem
  
  <Directory /var/www/html>
    Options Includes FollowSymLinks
    AllowOverride All
$(print_ApacheAllowFrom)
  </Directory>
</VirtualHost>
" >> "${HTTPD_CONF_DIR}/conf.d/virtual.conf"
  else
    echo "# enable default ssl virtualhost with self signed certificate
<VirtualHost _default_:${APP_PORT_HTTPS}>
  ErrorLog                 logs/ssl_error_log
  TransferLog              logs/ssl_access_log
  LogLevel                 warn
  
  SSLEngine                on
  SSLHonorCipherOrder      on
  SSLCipherSuite           PROFILE=SYSTEM
  SSLProxyCipherSuite      PROFILE=SYSTEM
  SSLCertificateFile       ${HTTPD_HTTPS_CERT_FILE}
  SSLCertificateKeyFile    ${HTTPD_HTTPS_KEY_FILE}
  $([ ! -z "${HTTPD_HTTPS_CHAIN_FILE}" ] && echo "SSLCertificateChainFile  ${HTTPD_HTTPS_CHAIN_FILE}")

  <Directory /var/www/html>
    Options Includes FollowSymLinks
    AllowOverride All
$(print_ApacheAllowFrom)
  </Directory>
</VirtualHost>
" >> "${HTTPD_CONF_DIR}/conf.d/virtual.conf"
  fi
fi
}

function cfgService_asterisk() {
  echo "=> Starting Asterisk"
}

## freepbx+asterisk service
function cfgService_izpbx() {

  function freepbxReload() {
    echo "---> reloading FreePBX..."
    su - ${APP_USR} -s /bin/bash -c "fwconsole reload"
  }
  
  function freepbxChown() {
    echo "---> setting FreePBX Permission..."
    fwconsole chown
  }
  
  function freepbxSettingsFix() {
    # reload freepbx config 
    echo "---> FIXME: applying workarounds for FreePBX broken modules and configs..."

    # make missing log files
    [ ! -e "${fpbxDirs[ASTLOGDIR]}/full" ] && touch "${fpbxDirs[ASTLOGDIR]}/full" && chown ${APP_USR}:${APP_GRP} "${file}" "${fpbxDirs[ASTLOGDIR]}/full"
    
    # fix paths and relink fwconsole and amportal if not exist
    [ ! -e "/usr/sbin/fwconsole" ] && ln -s ${fpbxDirs[AMPBIN]}/fwconsole /usr/sbin/fwconsole
    [ ! -e "/usr/sbin/amportal" ]  && ln -s ${fpbxDirs[AMPBIN]}/amportal  /usr/sbin/amportal

    # reset FreePBX config file permissions
    for file in ${appFilesConf[@]}; do
      chown ${APP_USR}:${APP_GRP} "${file}"
    done

    # fix freepbx directory paths
    if [ ! -z "${APP_DATA}" ]; then
      echo "---> fixing directory system paths in db configuration..."
      for k in ${!fpbxDirs[@]}; do
        [ "$(fwconsole setting ${k} | awk -F"[][{}]" '{print $2}')" != "${fpbxDirs[$k]}" ] && fwconsole setting ${k} ${fpbxDirs[$k]}
      done
      for k in ${!fpbxFilesLog[@]}; do
        [ "$(fwconsole setting ${k} | awk -F"[][{}]" '{print $2}')" != "${fpbxFilesLog[$k]}" ] && fwconsole setting ${k} ${fpbxFilesLog[$k]}
      done
    fi
    
    # fixing missing documentation that prevent loading extra codecs (like codec_opus)
    if [ -n "${APP_DATA}" ]; then
      echo "---> checking asterisk documentation directory..."
      rsync -avc --delete "${appDataDirs[ASTVARLIBDIR]}.dist/documentation/" "${APP_DATA}${appDataDirs[ASTVARLIBDIR]}/documentation/" --dry-run | grep -q '^' && {
        echo "---> fixing asterisk documentation directory... ${DST}"
        rsync -avc --delete "${appDataDirs[ASTVARLIBDIR]}.dist/documentation/" "${APP_DATA}${appDataDirs[ASTVARLIBDIR]}/documentation/"
      }
    fi
    
    # FIXME @20200318 freepbx 15.x warnings workaround
    sed 's/^preload = chan_local.so/;preload = chan_local.so/' -i ${fpbxDirs[ASTETCDIR]}/modules.conf
    sed 's/^enabled =.*/enabled = yes/' -i ${fpbxDirs[ASTETCDIR]}/hep.conf
    
    # FIXME @20200322 https://issues.freepbx.org/browse/FREEPBX-21317 (NOT MORE NEEDED)
    #[ $(fwconsole ma list | grep backup | awk '{print $4}' | sed 's/\.//g') -lt 150893 ] && su - ${APP_USR} -s /bin/bash -c "fwconsole ma downloadinstall backup --edge"
    
    # FIXME @20210321 FreePBX doesn't configure into configuration DB the non default 'asteriskcdrdb' DB
    [ "$(fwconsole setting CDRDBNAME | awk -F"[][{}]" '{print $2}')" != "${MYSQL_DATABASE_CDR}" ] && fwconsole setting CDRDBNAME ${MYSQL_DATABASE_CDR}
    
    # FIXME FreePBX by default include many non existant context, adding these as blank fixe the startup and reload warnings
    grep "include => .*-custom" ${fpbxDirs[ASTETCDIR]}/extensions.conf ${fpbxDirs[ASTETCDIR]}/extensions_additional.conf | awk '{print $3}' | sort -u | while read context ; do echo -e "[$context]\n"; done > ${fpbxDirs[ASTETCDIR]}/freepbx_custom_fix_missing_contexts.conf
    echo -e "[ext-meetme]\n\n[ext-queues]\n\n[app-recordings]" >> ${fpbxDirs[ASTETCDIR]}/freepbx_custom_fix_missing_contexts.conf
    if ! grep "#include freepbx_custom_fix_missing_contexts.conf" ${fpbxDirs[ASTETCDIR]}/extensions_custom.conf >/dev/null 2>&1; then echo "#include freepbx_custom_fix_missing_contexts.conf" >> ${fpbxDirs[ASTETCDIR]}/extensions_custom.conf ; fi

    ## fix Asterisk/FreePBX file permissions
    [ "$FREEPBX_FIX_PERMISSION" = "true" ] && freepbxChown
  }
  
  echo "---> verifing FreePBX configurations"

  # legend of freepbx install script:
  #    --webroot=WEBROOT            Filesystem location from which FreePBX files will be served [default: "/var/www/html"]
  #    --astetcdir=ASTETCDIR        Filesystem location from which Asterisk configuration files will be served [default: "/etc/asterisk"]
  #    --astmoddir=ASTMODDIR        Filesystem location for Asterisk modules [default: "/usr/lib64/asterisk/modules"]
  #    --astvarlibdir=ASTVARLIBDIR  Filesystem location for Asterisk lib files [default: "/var/lib/asterisk"]
  #    --astagidir=ASTAGIDIR        Filesystem location for Asterisk agi files [default: "/var/lib/asterisk/agi-bin"]
  #    --astspooldir=ASTSPOOLDIR    Location of the Asterisk spool directory [default: "/var/spool/asterisk"]
  #    --astrundir=ASTRUNDIR        Location of the Asterisk run directory [default: "/var/run/asterisk"]
  #    --astlogdir=ASTLOGDIR        Location of the Asterisk log files [default: "/var/log/asterisk"]
  #    --ampbin=AMPBIN              Location of the FreePBX command line scripts [default: "/var/lib/asterisk/bin"]
  #    --ampsbin=AMPSBIN            Location of the FreePBX (root) command line scripts [default: "/usr/sbin"]
  #    --ampcgibin=AMPCGIBIN        Location of the Apache cgi-bin executables [default: "/var/www/cgi-bin"]
  #    --ampplayback=AMPPLAYBACK    Directory for FreePBX html5 playback files [default: "/var/lib/asterisk/playback"]

  # transform associative array to variable=paths, ex. AMPWEBROOT=/var/www/html (not needed anymore)
  #for k in ${!fpbxDirs[@]}      ; do eval $k=${fpbxDirs[$k]}      ;done
  #for k in ${!fpbxDirsExtra[@]} ; do eval $k=${fpbxDirsExtra[$k]} ;done
  #for k in ${!fpbxFilesLog[@]}  ; do eval $k=${fpbxFilesLog[$k]}  ;done    

  ## enable PERSISTENCE and rebase directory paths, based on APP_DATA and create/chown missing directories
  # process directories
  if [ ! -z "${APP_DATA}" ]; then
    echo "---> using '${APP_DATA}' as basedir for FreePBX install"
    # process directories
    for k in ${!fpbxDirs[@]}; do
      v="${fpbxDirs[$k]}"
      eval fpbxDirs[$k]=${APP_DATA}$v
      [ ! -e "$v" ] && mkdir -p "$v"
      if [ "$(stat -c "%U %G" "$v" 2>/dev/null)" != "${APP_USR} ${APP_GRP}" ];then
      echo "---> fixing permissions for: $k=$v"
      chown ${APP_USR}:${APP_GRP} "$v"
      fi
    done
    
    # process app logs files
    for k in ${!appFilesLog[@]}; do
      v="${appFilesLog[$k]}"
      eval appFilesLog[$k]=${APP_DATA}$v
      [ ! -e "$v" ] && touch "$v"
      if [ "$(stat -c "%U %G" "$v" 2>/dev/null)" != "${APP_USR} ${APP_GRP}" ];then
      echo "---> fixing permissions for: $k=$v"
      chown ${APP_USR}:${APP_GRP} "$v"
      fi
    done

    # process freepbx logs files
    for k in ${!fpbxFilesLog[@]}; do
      v="${fpbxFilesLog[$k]}"
      eval fpbxFilesLog[$k]=${APP_DATA}$v
      [ ! -e "$v" ] && touch "$v"
      if [ "$(stat -c "%U %G" "$v" 2>/dev/null)" != "${APP_USR} ${APP_GRP}" ];then
      echo "---> fixing permissions for: $k=$v"
      chown ${APP_USR}:${APP_GRP} "$v"
      fi
    done
  fi

  # configure CDR ODBC
  echo "---> configuring FreePBX ODBC"
  # fix mysql odbc inst file path
  sed -i 's/\/lib64\/libmyodbc5.so/\/lib64\/libmaodbc.so/' /etc/odbcinst.ini
  # create mysql odbc
  echo "[MySQL-asteriskcdrdb]
Description = MariaDB connection to '${MYSQL_DATABASE_CDR}' CDR database
driver = MySQL
server = ${MYSQL_SERVER}
database = ${MYSQL_DATABASE_CDR}
Port = ${APP_PORT_MYSQL}
option = 3
Charset=utf8" > /etc/odbc.ini

  # LEGACY: workaround for missing ${APP_DATA}/.initialized file but already initialized izpbx deploy
  if [[ -e "${appFilesConf[FPBXCFGFILE]}" && ! -e ${APP_DATA}/.initialized ]]; then
    echo "---> INFO: found '${appFilesConf[FPBXCFGFILE]}' configuration file but missing '${APP_DATA}/.initialized'... creating it right now"
    echo "---> NOTE: if you want deploy izPBX from scratch, remove '${appFilesConf[FPBXCFGFILE]}' and '${APP_DATA}/.initialized' file"
    # make this deploy initialized and save the configuration status for later usage if using persistent data
    initizializeDir "${appDataDirsCustom[APP_DATA]}" "${appDataDirsCustom[APP_DATA]}" "$(printf '[%02d/%d]' $n $t)"
  fi
  
  # initialize izpbx if not already deployed
  if [ ! -e ${APP_DATA}/.initialized ]; then
      # first run detected initialize izpbx
      cfgService_freepbx_install
      [ "$INSTALL_STATUS" = "KO" ] && echo "=> ERROR: FreePBX not installed... exiting in 60 seconds" && sleep 60 && exit 1
      # save the current installed freepbx version
      FREEPBX_VER_INSTALLED="$(${fpbxDirs[AMPBIN]}/fwconsole -V | awk '{print $NF}' | awk -F'.' '{print $1}')"
    else
      # save the current installed freepbx version
      FREEPBX_VER_INSTALLED="$(${fpbxDirs[AMPBIN]}/fwconsole -V | awk '{print $NF}' | awk -F'.' '{print $1}')"
      
      # 'fwconsole -V' is not always reliable, reading current installed version directly from database
      if [ -z "${FREEPBX_VER_INSTALLED##*[!0-9]*}" ]; then
        FREEPBX_VER_INSTALLED="$(mysql -h ${MYSQL_SERVER} -P ${APP_PORT_MYSQL} -u ${MYSQL_USER} --password=${MYSQL_PASSWORD} ${MYSQL_DATABASE} --batch --skip-column-names --raw --execute="SELECT value FROM admin WHERE variable = 'version';" | awk '{print $NF}' | awk -F'.' '{print $1}')"
      fi
      
      # save version into .initialized file if empty
      #[ -z "$(cat "${APP_DATA}/.initialized")" ] && ${fpbxDirs[AMPBIN]}/fwconsole -V > "${APP_DATA}/.initialized"
      
      echo "---> INFO: found '${APP_DATA}/.initialized' file - Detected installed FreePBX version: $FREEPBX_VER_INSTALLED"
      [ ! -e "${appFilesConf[FPBXCFGFILE]}" ] && echo "---> WARNING: missing configuration file: ${appFilesConf[FPBXCFGFILE]}"
      
      # izpbx is already initialized, update configuration files
      echo "---> reconfiguring '${appFilesConf[FPBXCFGFILE]}'"
      sed "s/^\$amp_conf\['AMPDBHOST'\] =.*/\$amp_conf\['AMPDBHOST'\] = '${MYSQL_SERVER}';/"   -i "${appFilesConf[FPBXCFGFILE]}"
      sed "s/^\$amp_conf\['AMPDBPORT'\] =.*/\$amp_conf\['AMPDBPORT'\] = '${APP_PORT_MYSQL}';/" -i "${appFilesConf[FPBXCFGFILE]}"
      sed "s/^\$amp_conf\['AMPDBNAME'\] =.*/\$amp_conf\['AMPDBNAME'\] = '${MYSQL_DATABASE}';/" -i "${appFilesConf[FPBXCFGFILE]}"
      sed "s/^\$amp_conf\['AMPDBUSER'\] =.*/\$amp_conf\['AMPDBUSER'\] = '${MYSQL_USER}';/"     -i "${appFilesConf[FPBXCFGFILE]}"
      sed "s/^\$amp_conf\['AMPDBPASS'\] =.*/\$amp_conf\['AMPDBPASS'\] = '${MYSQL_PASSWORD}';/" -i "${appFilesConf[FPBXCFGFILE]}"
  fi

  # apply workarounds and fixes for FreePBX bugs
  freepbxSettingsFix
  
  # reconfigure freepbx from env variables
  echo "---> reconfiguring FreePBX Advanced Settings if needed..."
  set | grep ^"FREEPBX_" | grep -v -e ^"FREEPBX_MODULES_" -e ^"FREEPBX_AUTOUPGRADE_" -e ^"FREEPBX_FIX_PERMISSION" -e ^"FREEPBX_VER" | sed -e 's/^FREEPBX_//' -e 's/=/ /' | while read setting ; do
    k="$(echo $setting | awk '{print $1}')"
    v="$(echo $setting | awk '{print $2}')"
    currentVal=$(fwconsole setting $k | awk -F"[][{}]" '{print $2}')
    [ "$currentVal" = "true" ] && currentVal="1"
    [ "$currentVal" = "false" ] && currentVal="0"
    if [ "$currentVal" != "$v" ]; then
      echo "---> reconfiguring advanced setting: ${k}=${v}"
      fwconsole setting $k $v
    fi
  done

  # reconfigure freepbx settings based on docker variables content using FreePBX API bootstrap
  echo "---> reconfiguring FreePBX SIP Settings if needed..."
  for k in ${!fpbxSipSettings[@]}; do
    v="${fpbxSipSettings[$k]}"
    cVal=$(echo "<?php include '/etc/freepbx.conf'; \$FreePBX = FreePBX::Create(); echo \$FreePBX->sipsettings->getConfig('${k}');?>" | php)
    if [ "$cVal" != "${v}" ];then
      echo "---> reconfiguring sip setting: ${k}=${v}"
      echo "<?php include '/etc/freepbx.conf'; \$FreePBX = FreePBX::Create(); \$FreePBX->sipsettings->setConfig('${k}',${v}); needreload();?>" | php
    fi
  done

  # FIXME: 20200315 iaxsettings doesn't works right now
  #echo "---> reconfiguring FreePBX IAX2 settings if needed..."
  #for k in ${!freepbxIaxSettings[@]}; do
  #  v="${freepbxIaxSettings[$k]}"
  #  echo "<?php include '/etc/freepbx.conf'; \$FreePBX = FreePBX::Create(); \$FreePBX->iaxsettings->setConfig('${k}',${v}); needreload();?>" | php
  #done
  
  # check if we need to upgrade FreePBX to a major version
  cfgService_freepbx_upgrade_check
}

function cfgService_freepbx_upgrade_check() {
  #set -x
  if [ -e "${APP_DATA}/.initialized" ]; then
    if [ $FREEPBX_VER_INSTALLED -lt $FREEPBX_VER ];then
      echo
      echo "=========================================================================================="
      echo "==> !!! UPGRADABLE FreePBX installation detetected !!!"
      echo "=========================================================================================="
      echo "==> Installed FreePBX version: ${FREEPBX_VER_INSTALLED}"
      echo "==> Available FreePBX version: ${FREEPBX_VER}"
      echo "=========================================================================================="
      if [ "$FREEPBX_AUTOUPGRADE_CORE" = "true" ]; then
        echo "==> INFO: FreePBX automatic upgrade ENABLED"
        echo "==> ATTENTION: make sure to have backed up your installation before upgrading"
        let UPGRADABLE=${FREEPBX_VER}-${FREEPBX_VER_INSTALLED}
        if [ $UPGRADABLE = 1 ]; then
            cfgService_freepbx_upgrade
          else
            echo
            echo "==> WARNING: Unable to upgrade FreePBX directly from ${FREEPBX_VER_INSTALLED} to ${FREEPBX_VER} release"
            echo "==>          You must upgrade to the previous major version before going to ${FREEPBX_VER} release"
            echo
        fi
        else
          echo "==> INFO: FreePBX automatic upgrade DISABLED"
          echo
      fi
    fi
  fi
}

function cfgService_freepbx_upgrade() {
  echo "=========================================================================================="
  echo "==> START UPGRADING FreePBX from '${FREEPBX_VER_INSTALLED}' to '${FREEPBX_VER}'"
  # FIXME: @20211128 workaround
  [ -e "/tmp/cron.error" ] && rm -f /tmp/cron.error
  
  # FIXME: @20211130 check on future version if this is still needed
  echo "--> step:[1] FIXME: patching 'Encoding.php' for issue: https://issues.freepbx.org/browse/FREEPBX-21703"
  patch "${fpbxDirs[AMPWEBROOT]}/admin/libraries/Composer/vendor/neitanod/forceutf8/src/ForceUTF8/Encoding.php" "/usr/src/php74.patch"
  echo "--> step:[2] starting freepbx services"
  fwconsole start
  echo "--> step:[3] upgrading all modules"
  fwconsole ma upgradeall
  echo "--> step:[4] installing versionupgrade modules"
  fwconsole ma downloadinstall versionupgrade
  fwconsole chown
  fwconsole reload
  echo "--> step:[5] upgrading from FreePBX $FREEPBX_VER_INSTALLED to $FREEPBX_VER"
  #fwconsole versionupgrade --check
  fwconsole versionupgrade --upgrade
  if [ $? != 0 ]; then
    # FIXME: @20211130 check on future version if this is still needed
    echo "--> step:[5-b] FIXME: applying workaround for issue: https://issues.freepbx.org/browse/FREEPBX-22983"
    # refs: https://community.freepbx.org/t/2021-09-17-security-fixes-release-update/78054
    fwconsole ma downloadinstall framework --tag=16.0.10.42
    echo "--> step:[5-c] upgradind all modules again"
    fwconsole ma upgradeall
  fi
  echo "--> step:[6] finalizing upgrade"
  fwconsole chown
  fwconsole reload
  fwconsole stop
  echo "==> END UPGRADING FreePBX from '${FREEPBX_VER_INSTALLED}' to '${FREEPBX_VER}'"
  echo "=========================================================================================="
  echo
}

# install FreePBX if not installed
function cfgService_freepbx_install() {
  function mysqlQuery() {
    mysql -h ${MYSQL_SERVER} -P ${APP_PORT_MYSQL} -u ${MYSQL_ROOT_USER} --password=${MYSQL_ROOT_PASSWORD} -N -B -e "$@"
  }
  
  function checkMysql() {
    mysqlQuery "SELECT 1;" >/dev/null
  }
  
  # counter for global attempts
  try=1 ; trymax=5
  
  until [ $try -eq $trymax ]; do
  cd /usr/src/freepbx
  echo
  echo "====================================================================="
  echo "=> !!! NEW INSTALLATION DETECTED :: FreePBX IS NOT INITIALIZED !!! <="
  echo "====================================================================="
  echo "--> missing '${APP_DATA}/.initialized' file... initializing FreePBX... try:[$try/$trymax]"

  # use mysql user if MYSQL_ROOT_PASSWORD is not defined and skip initial MySQL deploy
  if [ -z "${MYSQL_ROOT_PASSWORD}" ]; then
    echo "--> NOTE: skipping MySQL init because not root user password defined"
    MYSQL_ROOT_USER="${MYSQL_USER}"
    MYSQL_ROOT_PASSWORD="${MYSQL_PASSWORD}"
    SKIP_MYSQL_INIT="true"
  fi
  
  # start asterisk if it's not running
  if ! asterisk -r -x "core show version" 2>/dev/null ; then ./start_asterisk start ; fi
  
  # counter for connecting to MySQL database
  myn=1 ; myt=10
  
  until [ $myn -eq $myt ]; do
    # wait 10 seconds for mysql to come run
    sleep 10
    checkMysql
    RETVAL=$?
    if [ $RETVAL = 0 ]; then
        myn=$myt
      else
        let myn+=1
        echo "--> WARNING: cannot connect to MySQL database '${MYSQL_SERVER}'... waiting database to become ready... retrying in 10 seconds... try:[$myn/$myt]"
    fi
  done
  
  # latest check if MySQL is reachable otherwhise exit and don't try to install FreePBX
  checkMysql && [ $? != 0 ] && "=> ERROR: UNABLE TO CONNECT TO THE MYSQL DATABASE AFTER $myt ATTEMPTS. Check the db connection, username, password and permissions... exiting" && exit 1
  
  echo "--> installing FreePBX in '${fpbxDirs[AMPWEBROOT]}'"
  echo "---> START install FreePBX @ $(date)"
  # https://github.com/FreePBX/announcement/archive/release/15.0.zip
  
  # set default freepbx install options
  FPBX_OPTS+=" --webroot=${fpbxDirs[AMPWEBROOT]}"
  FPBX_OPTS+=" --astetcdir=${fpbxDirs[ASTETCDIR]}"
  FPBX_OPTS+=" --astvarlibdir=${fpbxDirs[ASTVARLIBDIR]}"
  FPBX_OPTS+=" --astagidir=${fpbxDirs[ASTAGIDIR]}"
  FPBX_OPTS+=" --astspooldir=${fpbxDirs[ASTSPOOLDIR]}"
  FPBX_OPTS+=" --astrundir=${appCacheDirs[ASTRUNDIR]}"
  FPBX_OPTS+=" --astlogdir=${fpbxDirs[ASTLOGDIR]}"
  FPBX_OPTS+=" --ampbin=${fpbxDirs[AMPBIN]}"
  FPBX_OPTS+=" --ampsbin=${fpbxDirs[AMPSBIN]}"
  FPBX_OPTS+=" --ampcgibin=${fpbxDirs[AMPCGIBIN]}"
  FPBX_OPTS+=" --ampplayback=${fpbxDirs[AMPPLAYBACK]}"
  FPBX_OPTS+=" --astmoddir=${fpbxDirsExtra[ASTMODDIR]}"

  #set -x
  
  ## create mysql users and databases if not exists
  if [ "$SKIP_MYSQL_INIT" != "true" ]; then
    echo "---> creating and grantig access to FreePBX databases: ${MYSQL_DATABASE}, ${MYSQL_DATABASE_CDR}"
    # freepbx mysql user
    mysqlQuery "CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    # freepbx asterisk config db
    mysqlQuery "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE}"
    mysqlQuery "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%' WITH GRANT OPTION;"
    # freepbx asterisk cdr db
    mysqlQuery "CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE_CDR}"
    mysqlQuery "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE_CDR}.* TO '${MYSQL_USER}'@'%' WITH GRANT OPTION;"
  fi
  
  # veirfy if databases exist and we can access
  mysqlQuery "USE ${MYSQL_DATABASE};"     ; [ $? != 0 ] && echo "---> WARNING: unable to access ${MYSQL_DATABASE} database. Please check if exist and the permissions... exiting" && exit 1
  mysqlQuery "USE ${MYSQL_DATABASE_CDR};" ; [ $? != 0 ] && echo "---> WARNING: unable to access ${MYSQL_DATABASE_CDR} database. Please check if exist and the permissions... exiting" && exit 1
  
  # install freepbx
  set -x
  ./install -n --skip-install --no-ansi --dbhost=${MYSQL_SERVER} --dbport=${APP_PORT_MYSQL} --dbuser=${MYSQL_USER} --dbpass=${MYSQL_PASSWORD} --dbname=${MYSQL_DATABASE} --cdrdbname=${MYSQL_DATABASE_CDR} ${FPBX_OPTS}
  RETVAL=$?
  set +x
  echo "---> END install FreePBX @ $(date)"
  unset FPBX_OPTS
 
  # if the install success exec continue with specific ordered modules install
  if [ $RETVAL = 0 ]; then
    # core modules
    : ${FREEPBX_MODULES_CORE:="
      framework
      core
      dashboard
      sipsettings
      voicemail
    "}

    # prerequisite extra modules
    : ${FREEPBX_MODULES_PRE:="
      userman
      pm2
    "}

    # extra modules
    : ${FREEPBX_MODULES_EXTRA:="
      soundlang
      callrecording
      cdr
      conferences
      customappsreg
      featurecodeadmin
      infoservices
      logfiles
      music
      manager
      arimanager
      filestore
      recordings
      announcement
      asteriskinfo
      backup
      callforward
      callwaiting
      daynight
      calendar
      certman
      cidlookup
      contactmanager
      donotdisturb
      fax
      findmefollow
      iaxsettings
      miscapps
      miscdests
      ivr
      parking
      phonebook
      presencestate
      printextensions
      queues
      cel
      timeconditions
      bulkhandler
      weakpasswords
      ucp
    "}

      ## deprecated:
      #speeddial

    # disabled modules
    : ${FREEPBX_MODULES_DISABLED:="
    "}
    
    # apply workarounds and fix for FreePBX unresolved issues
    freepbxSettingsFix

    # FIXME @20251014 framework 16.0.41 issue preventing initial setup completion
    FRAMEWORK_VERSION=$(fwconsole ma list --format=json | jq -s -r '.[] | select(.data | type=="array") | .data[] | select(.[0]=="framework") | .[1]')
    [[ $FRAMEWORK_VERSION =~ ^16\.0\.41($|\.) ]] && fwconsole ma downloadinstall framework --tag=16.0.40

    # fix permissions before installing FreePBX modules
    freepbxChown

    echo "--> enabling EXTENDED FreePBX repo..."
    su - ${APP_USR} -s /bin/bash -c "fwconsole ma enablerepo extended"
    su - ${APP_USR} -s /bin/bash -c "fwconsole ma enablerepo unsupported"
    
    echo "--> installing Prerequisite FreePBX modules from local repo into '${fpbxDirs[AMPWEBROOT]}/admin/modules'"
    mod_cnt=1 ; mod_tot=$(echo ${FREEPBX_MODULES_PRE} ${FREEPBX_MODULES_EXTRA} | wc -w)
    for module in ${FREEPBX_MODULES_PRE}; do
      #echo "---> [$mod_cnt/$mod_tot] installing module: ${module}"
      printf -- '---> [%02d/%d] installing module: %s\n' $mod_cnt $mod_tot "${module}"
      # the pre-modules need be installed as root
      su - ${APP_USR} -s /bin/bash -c "fwconsole ma install ${module}"
      # enabling modules after install is not needed
      #su - ${APP_USR} -s /bin/bash -c "fwconsole ma enable ${module}"
      let mod_cnt+=1
    done
    
    echo "--> installing Extra FreePBX modules from local repo into '${fpbxDirs[AMPWEBROOT]}/admin/modules'"
    for module in ${FREEPBX_MODULES_EXTRA}; do
      #echo "---> [$mod_cnt/$mod_tot] installing module: ${module}"
      printf -- '---> [%02d/%d] installing module: %s\n' $mod_cnt $mod_tot "${module}"
      su - ${APP_USR} -s /bin/bash -c "fwconsole ma install ${module}"
      let mod_cnt+=1
    done

    if [ "${FREEPBX_AUTOUPDATE_MODULES_FIRSTDEPLOY}" = "true" ]; then
      echo "--> auto upgrading FreePBX modules"
      su - ${APP_USR} -s /bin/bash -c "fwconsole ma upgradeall"
    fi
    
    # reload freePBX
    freepbxReload
    
    # make this deploy initialized and save the configuration status for later usage if using persistent data
    initizializeDir "${appDataDirsCustom[APP_DATA]}" "${appDataDirsCustom[APP_DATA]}" "$(printf '[%02d/%d]' $n $t)"
    # save current FreePBX version number
    [ -z "$(cat "${APP_DATA}/.initialized")" ] && ${fpbxDirs[AMPBIN]}/fwconsole -V > "${APP_DATA}/.initialized"
    
    # DEBUG: pause here
    #sleep 300
  fi

  if [ $RETVAL = 0 ]; then
      try=$trymax
    else
      let try+=1
      echo "--> WARNING: unable to install FreePBX ${FREEPBX_VER}... restarting in 10 seconds... try:[$try/$trymax]"
      # check if reached the end of the loop
      [ $try -eq $trymax ] && INSTALL_STATUS="KO" || sleep 10
  fi
  done

  #echo DEBUG: try=$try trymax=$trymax INSTALL_STATUS=$INSTALL_STATUS
  
  # stop asterisk
  if asterisk -r -x "core show version" 2>/dev/null ; then 
    echo "--> stopping Asterisk"
    asterisk -r -x "core stop now"
    echo "=> Finished installing FreePBX"
  fi
  echo "======================================================================"
}

## dnsmasq service
function cfgService_dnsmasq() {
  [ "$DHCP_ENABLED" = "true" ] && cfgService_dhcp
  [ "$TFTP_ENABLED" = "true" ] && cfgService_tftp
}

## chronyd service (ntp server)
function cfgService_ntp() {
  # disable default ntp pools addresses if NTP_SERVERS var is set
  echo "# chronyd ntp server configuration
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
keyfile /etc/chrony.keys
leapsectz right/UTC
logdir /var/log/chrony

bindcmdaddress 0.0.0.0
$([ -z "$NTP_SERVERS" ] && echo "pool 2.pool.ntp.org iburst" || for server in $NTP_SERVERS ; do echo "pool $server iburst"; done)

$(for subnet in $NTP_ALLOW_FROM ; do echo "allow $subnet"; done)
" > /etc/chrony.conf
}

## dhcp service
function cfgService_dhcp() {
  echo "--> configuring DHCP service"
  if [[ ! -z "$DHCP_POOL_START" || ! -z "$DHCP_POOL_END" || ! -z "$DHCP_POOL_LEASE" ]]; then
    sed "s|^#dhcp-range=.*|dhcp-range=$DHCP_POOL_START,$DHCP_POOL_END,$DHCP_POOL_LEASE|" -i "${appDataDirs[DNSMASQDIR]}/local.conf"
  else
    echo "--> WARNING: DHCP server enabled but specify DHCP_POOL_START:[$DHCP_POOL_START] DHCP_POOL_END:[$DHCP_POOL_END] DHCP_POOL_LEASE:[$DHCP_POOL_LEASE]"
  fi
  
  if [ ! -z "$DHCP_DOMAIN" ]; then
    sed "s|^local=.*|local=/$DHCP_DOMAIN/|"   -i "${appDataDirs[DNSMASQDIR]}/local.conf"
    sed "s|^domain=.*|domain=/$DHCP_DOMAIN/|" -i "${appDataDirs[DNSMASQDIR]}/local.conf"
    sed "s|^#dhcp-option=option:domain-name,.*|dhcp-option=option:domain-name,$DHCP_DOMAIN|" -i "${appDataDirs[DNSMASQDIR]}/local.conf"
  fi

  [ ! -z "$DHCP_DNS" ] && sed "s|^#dhcp-option=6,.*|dhcp-option=6,$DHCP_DNS|" -i "${appDataDirs[DNSMASQDIR]}/local.conf"
  [ ! -z "$DHCP_DNS" ] && sed "s|^dhcp-option=6,.*|dhcp-option=6,$DHCP_DNS|" -i "${appDataDirs[DNSMASQDIR]}/local.conf"
  
  [ ! -z "$DHCP_GW" ] && sed "s|^#dhcp-option=3,.*|dhcp-option=3,$DHCP_GW|" -i "${appDataDirs[DNSMASQDIR]}/local.conf"
  [ ! -z "$DHCP_GW" ] && sed "s|^dhcp-option=3,.*|dhcp-option=3,$DHCP_GW|" -i "${appDataDirs[DNSMASQDIR]}/local.conf"
  
  [ ! -z "$DHCP_NTP" ] && sed "s|^#dhcp-option=option:ntp-server,.*|dhcp-option=option:ntp-server,$DHCP_NTP|" -i "${appDataDirs[DNSMASQDIR]}/local.conf"
}

## tftp service
function cfgService_tftp() {
  echo "--> configuring TFTP service"
  sed "s|^#dhcp-option=66|dhcp-option=66|"                  -i "${appDataDirs[DNSMASQDIR]}/local.conf"
  sed "s|^#enable-tftp|enable-tftp|"                        -i "${appDataDirs[DNSMASQDIR]}/local.conf"
  sed "s|^#tftp-root=.*|tftp-root=${appDataDirs[TFTPDIR]}|" -i "${appDataDirs[DNSMASQDIR]}/local.conf"
}

## zabbix service
function cfgService_zabbix() {
  # comment zabbix global config
  if [ -w "$ZABBIX_CONF" ]; then
    sed 's/^LogFile=/#LogFile=/g' -i $ZABBIX_CONF
    sed 's/^Hostname=/#Hostname=/g' -i $ZABBIX_CONF
    sed 's/^Server=/#Server=/g' -i $ZABBIX_CONF
    sed 's/^ServerActive=/#ServerActive=/g' -i $ZABBIX_CONF
  fi
  # zabbix user defined local config
  echo "#DebugLevel=4
#LogFileSize=1
#EnableRemoteCommands=1
Plugins.SystemRun.LogRemoteCommands=1
LogType=console

Server=${ZABBIX_SERVER}
ServerActive=${ZABBIX_SERVER_ACTIVE}

$(if [ "${ZABBIX_HOSTNAME}" = "${HOSTNAME}" ]; then
    echo "HostnameItem=system.hostname"
  else
    echo "Hostname=${ZABBIX_HOSTNAME}"
fi)

$(if [ ! -z "${ZABBIX_HOSTMETADATA}" ]; then
  #echo "HostMetadataItem=system.uname"
  echo "HostMetadata=${ZABBIX_HOSTMETADATA}"
fi)
" > "$ZABBIX_CONF_LOCAL"
}

function cfgService_fop2 () {
  [ ! -e "${appDataDirs[FOP2APPDIR]}/fop2.cfg" ] && cfgService_fop2_install

  if [ -e "${appDataDirs[FOP2APPDIR]}/fop2.cfg" ]; then
    # obtain asterisk manager configs from freepbx
    : ${FOP2_AMI_HOST:="$(fwconsole setting ASTMANAGERHOST | awk -F"[][{}]" '{print $2}')"}
    : ${FOP2_AMI_PORT:="$(fwconsole setting ASTMANAGERPORT | awk -F"[][{}]" '{print $2}')"}
    : ${FOP2_AMI_USERNAME:="$(fwconsole setting AMPMGRUSER | awk -F"[][{}]" '{print $2}')"}
    : ${FOP2_AMI_PASSWORD:="$(fwconsole setting AMPMGRPASS | awk -F"[][{}]" '{print $2}')"}
  
    # reconfigure fop2.cfg
    sed "s|^manager_host.*=.*|manager_host=${FOP2_AMI_HOST}|" -i "${appDataDirs[FOP2APPDIR]}/fop2.cfg"
    sed "s|^manager_port.*=.*|manager_port=${FOP2_AMI_PORT}|" -i "${appDataDirs[FOP2APPDIR]}/fop2.cfg"
    sed "s|^manager_user.*=.*|manager_user=${FOP2_AMI_USERNAME}|" -i "${appDataDirs[FOP2APPDIR]}/fop2.cfg"
    sed "s|^manager_secret.*=.*|manager_secret=${FOP2_AMI_PASSWORD}|" -i "${appDataDirs[FOP2APPDIR]}/fop2.cfg"
   
    # configure fop2 certificates if https is enabled
    if [ "$HTTPD_HTTPS_ENABLED" = "true" ]; then
      sed "s|^ssl_certificate_file.*=.*|ssl_certificate_file=${HTTPD_HTTPS_CERT_FILE}|"        -i "${appDataDirs[FOP2APPDIR]}/fop2.cfg"
      sed "s|^ssl_certificate_key_file.*=.*|ssl_certificate_key_file=${HTTPD_HTTPS_KEY_FILE}|" -i "${appDataDirs[FOP2APPDIR]}/fop2.cfg"
    fi
   
    # FOP2 License Code Management
    # licensing method
    FOP2_LICENSE_OPTS+=" --rp=http"
    # licensed interface
    [ -z "${FOP2_LICENSE_IFACE}" ] && FOP2_LICENSE_IFACE=$(ip link show | grep ^"[0-9].*:" | awk -F': ' '{print $2}' | grep -v -e lo | head -n1)
    # save interface name into /etc/sysconfig/fop2 file
    [ ! -z "${FOP2_LICENSE_IFACE}" ] && echo "OPTIONS=\"-d -i ${FOP2_LICENSE_IFACE}\"" > /etc/sysconfig/fop2
    # use interface name in the command line
    [ ! -z "${FOP2_LICENSE_IFACE}" ] && FOP2_LICENSE_OPTS+=" --iface ${FOP2_LICENSE_IFACE}"
    # modify fop2 command if interface name is specified
    [ ! -z "${FOP2_LICENSE_IFACE}" ] && sed "s|^command.*=.*|command=/usr/local/fop2/fop2_server -i ${FOP2_LICENSE_IFACE}|" -i "${SUPERVISOR_DIR}/fop2.ini"
    
    # fop2 version upgrade check
    if [ "$FOP2_AUTOUPGRADE" = "true" ]; then
      [ -e "${appDataDirs[FOP2APPDIR]}/fop2_server" ] && FOP2_VER_CUR=$("${appDataDirs[FOP2APPDIR]}/fop2_server" -v 2>/dev/null | awk '{print $3}')
      if   [ $(check_version $FOP2_VER_CUR) -lt $(check_version $FOP2_VER) ]; then
        echo "=> INFO: FOP2 update detected... upgrading from $FOP2_VER_CUR to $FOP2_VER"
        cfgService_fop2_upgrade
      elif [ $(check_version $FOP2_VER_CUR) -gt $(check_version $FOP2_VER) ]; then
        echo "=> WARNING: Specified FOP2_VER=$FOP2_VER is older than installed version: $FOP2_VER_CUR"
      else
        echo "=> INFO: Specified FOP2_VER=$FOP2_VER, installed version: $FOP2_VER_CUR"
      fi
    fi
    
    if [ ! -e "${appDataDirs[FOP2APPDIR]}/fop2.lic" ]; then
      if [ -z "${FOP2_LICENSE_CODE}" ]; then
          echo "--> INFO: FOP2 is not licensed and no 'FOP2_LICENSE_CODE' variable defined... running in Demo Mode"
        else
          echo "--> INFO: Registering FOP2"
          echo "---> NAME: ${FOP2_LICENSE_NAME}"
          echo "---> CODE: ${FOP2_LICENSE_CODE}"
          echo "---> IFACE: ${FOP2_LICENSE_IFACE} ($(ip a show dev ${FOP2_LICENSE_IFACE} | grep 'link/ether' | awk '{print $2}'))"
          set -x
          ${appDataDirs[FOP2APPDIR]}/fop2_server --register --name "${FOP2_LICENSE_NAME}" --code "${FOP2_LICENSE_CODE}" $FOP2_LICENSE_OPTS
          set +x
          echo "--> INFO: FOP2 license code info:"
          ${appDataDirs[FOP2APPDIR]}/fop2_server --getinfo $FOP2_LICENSE_OPTS
          echo "--> INFO: FOP2 license code status:"
          ${appDataDirs[FOP2APPDIR]}/fop2_server --test $FOP2_LICENSE_OPTS
      fi
    elif [ "${FOP2_AUTOACTIVATION}" = "true" ]; then
      FOP2_LICENSE_STATUS="$(${appDataDirs[FOP2APPDIR]}/fop2_server --getinfo $FOP2_LICENSE_OPTS | grep ^"Not Found")"
      if [ ! -z "$FOP2_LICENSE_STATUS" ]; then
        echo "--> WARNING: Reactivating FOP2 license because:"
        echo $FOP2_LICENSE_STATUS
        set -x
        ${appDataDirs[FOP2APPDIR]}/fop2_server --reactivate $FOP2_LICENSE_OPTS
        set +x
        FOP2_LICENSE_STATUS="$(${appDataDirs[FOP2APPDIR]}/fop2_server --getinfo $FOP2_LICENSE_OPTS | grep ^"Not Found")"
        if [ ! -z "$FOP2_LICENSE_STATUS" ]; then
          echo "echo --> ERROR: Failed to reactivating the license... trying to revoke and register it again:"
          set -x
          ${appDataDirs[FOP2APPDIR]}/fop2_server --revoke   --name "${FOP2_LICENSE_NAME}" --code "${FOP2_LICENSE_CODE}" $FOP2_LICENSE_OPTS
          ${appDataDirs[FOP2APPDIR]}/fop2_server --register --name "${FOP2_LICENSE_NAME}" --code "${FOP2_LICENSE_CODE}" $FOP2_LICENSE_OPTS
          set +x
        fi
      fi
      echo "--> INFO: FOP2 info:"
      ${appDataDirs[FOP2APPDIR]}/fop2_server --getinfo $FOP2_LICENSE_OPTS
      echo "--> INFO: FOP2 test:"
      ${appDataDirs[FOP2APPDIR]}/fop2_server --test $FOP2_LICENSE_OPTS
    fi
  fi
}

function cfgService_pma() {
    echo "=> Enabling and Configuring phpMyAdmin"
    # remove unused http alias
    sed "/^Alias \/phpMyAdmin \/usr\/share\/phpMyAdmin/d" -i "${PMA_CONF_APACHE}"
    # reconfigure the http alias
    sed "s|^Alias /phpmyadmin /usr/share/phpMyAdmin|Alias ${PMA_ALIAS} /usr/share/phpMyAdmin|" -i "${PMA_CONF_APACHE}"
    # allow connection from internal networks
    #sed "s|Require local|Require ip ${PMA_ALLOW_FROM}|" -i "${PMA_CONF_APACHE}"
    cat <<EOF >> "${PMA_CONF_APACHE}"
<Directory /usr/share/phpMyAdmin/>
  AddDefaultCharset UTF-8
$(for FROM in ${PMA_ALLOW_FROM}; do echo "    Require ip $FROM"; done)
</Directory>
EOF
    # configure database access
    sed "s|'localhost';|'${MYSQL_SERVER}';|" -i "${PMA_CONFIG}"
}

function cfgService_phonebook() {
    echo "=> Enabling Remote XML PhoneBook support"
    
    echo "Alias /pb /usr/local/share/phonebook

<Directory /usr/local/share/phonebook>
    AllowOverride all
    AddDefaultCharset UTF-8
    DirectoryIndex index.php
$(print_ApacheAllowFrom)
</Directory>
" > "${HTTPD_CONF_DIR}/conf.d/phonebook.conf"
}

function cfgService_letsencrypt() {
  echo "=> Generating Let's Encrypt certificates for '$APP_FQDN'"
  if   [ -z "$APP_FQDN" ]; then
    echo "--> WARNING: skipping let's encrypt certificates request because APP_FQDN is not defined"
  elif [ -z "$LETSENCRYPT_COUNTRY_CODE" ]; then
    echo "--> WARNING: skipping let's encrypt certificates request because LETSENCRYPT_COUNTRY_CODE is not defined"
  elif [ -z "$LETSENCRYPT_COUNTRY_STATE" ]; then
    echo "--> WARNING: skipping let's encrypt certificates request because LETSENCRYPT_COUNTRY_STATE is not defined"
  elif [ -z "$SMTP_MAIL_TO" ]; then
    echo "--> WARNING: skipping let's encrypt certificates request because SMTP_MAIL_TO is not defined"
  else
    # generate let's encrypt certificates
    # NOTE: apache web server must be running to complete the certbot handshake
    # FIXME: if the FQDN address is different than outgoing address making the request, the certification process will fail with:
    #        Error 'Requested host 'APP_FQDN' does not resolve to 'EXTERNAL OUTGOING IP' (Resolved to 'APP_FQDN RESOLVING IP' instead)' when requesting ....
    CERTOK=1
    
    # renew existing certificate
    if [ -e "${fpbxDirs[CERTKEYLOC]}/$APP_FQDN.pem" ]; then
      echo "--> Let's Encrypt certificates for '$APP_FQDN' already exists... Check and update all certificates"
      httpd -k start
      fwconsole certificates --updateall
      [ $? -eq 0 ] && CERTOK=0
      [ $CERTOK -eq 0 ] && fwconsole certificates --default=$APP_FQDN
      [ $CERTOK -eq 0 ] && echo "--> default FreePBX certificate configured to ${fpbxDirs[CERTKEYLOC]}/$APP_FQDN.pem"
      httpd -k stop
    fi

    # request new certificate
    if [ $CERTOK -eq 1 ]; then
      httpd -k start
      set -x
      fwconsole certificates -n --generate --type=le --hostname=$APP_FQDN --country-code=$LETSENCRYPT_COUNTRY_CODE --state=$LETSENCRYPT_COUNTRY_STATE --email=$SMTP_MAIL_FROM
      set +x
      [ $? -eq 0 ] && CERTOK=0
      [ $CERTOK -eq 0 ] && fwconsole certificates --default=$APP_FQDN
      [ $CERTOK -eq 0 ] && echo "--> default FreePBX certificate configured to ${fpbxDirs[CERTKEYLOC]}/$APP_FQDN.pem"
      httpd -k stop
    fi
  fi
}

function cfgService_fop2_install() {
  echo
  echo "=> !!! FOP2 IS NOT INITIALIZED :: NEW INSTALLATION DETECTED !!! Downloading and Installing FOP2..."
  echo
  fwconsole start
  if [ -z "$FOP2_VER" ]; then
    # automatic installation of latest version
    wget -O - http://download.fop2.com/install_fop2.sh | bash
   else
    curl -fSL --connect-timeout 30 http://download2.fop2.com/fop2-$FOP2_VER-centos-x86_64.tgz | tar xz -C /usr/src
    cd /usr/src/fop2 && make install && /usr/local/fop2/generate_override_contexts.pl -write
  fi
  
  pkill fop2_server
  fwconsole stop
}

function cfgService_fop2_upgrade() {
  #:${FOP2_VER:=$1}
  #[ -z "${FOP2_VER}" ] && echo "--> ERROR: No FOP2 upgrade version defined... define FOP2_VER var or give it as argument... exiting" && return
  
  # container workarounds
  export TERM=linux
  
  curl -fSL --connect-timeout 30 http://download2.fop2.com/fop2-$FOP2_VER-centos-x86_64.tgz | tar xz -C /usr/src
  cd /usr/src/fop2 && make install
}

function cfgBashEnv() {
  echo '. /etc/os-release
  APP="izPBX"
  DOMAIN="$(hostname | cut -d'.' -f2)"
  if [ ! -z "$DOMAIN" ];then DOMAIN=".${DOMAIN}" ; fi
  
  if [ -t 1 ]; then
    export PS1="(${APP})\e[1;34m[\e[1;33m\u@\e[1;32m\h\e[2m$DOMAIN\e[0m: \e[1;37m\w\[\e[1;34m]\e[1;36m\\$ \e[0m"
  fi

  # aliases
  alias d="ls -lAsh --color"
  alias cp="cp -ip"
  alias rm="rm -i"
  alias mv="mv -i"

  echo -e -n "\E[1;34m"
  figlet -w 120 "${APP}"

  : ${APP_VER:="unknown"}
  : ${APP_VER_BUILD:="unknown"}
  : ${APP_BUILD_COMMIT:="unknown"}
  : ${APP_BUILD_DATE:="unknown"}
  
  [ "${APP_BUILD_DATE}" != "unknown" ] && APP_BUILD_DATE=$(date -d @${APP_BUILD_DATE} +"%Y-%m-%d")
  
  echo -e "\E[1;36m${APP} \E[1;32m${APP_VER}\E[1;36m (build: \E[1;32m${APP_VER_BUILD}\E[1;36m commit: \E[1;32m${APP_BUILD_COMMIT}\E[1;36m date: \E[1;32m${APP_BUILD_DATE}\E[1;36m), Asterisk \E[1;32m${ASTERISK_VER:-unknown}\E[1;36m, FreePBX \E[1;32m${FREEPBX_VER:-unknown}\E[1;36m, ${NAME} \E[1;32m${VERSION_ID:-unknown}\E[1;36m, Kernel \E[1;32m$(uname -r)\E[0m"
  echo'
}

function cfgService_msmtp() {
    echo "=> Setting up MSMTP as (default) sendmail replacement"

    # set alternative for mta to 'msmtp' thereby updating symlinks in rootfs
    alternatives --set mta /usr/bin/msmtp

    # check if configuration file already exists in $APP_USR home directory, if not, create default configuration
    USR_HOME="$(getent passwd "$APP_USR" | cut -d: -f6)"

    echo "defaults
$([ "${SMTP_STARTTLS}" = "true" ] && echo "tls      on" || echo "tls      off")
$([ "${SMTP_STARTTLS}" = "true" ] && echo "tls_starttls   on" || echo "tls_starttls   off")
$([ "${SMTP_STARTTLS}" = "true" ] && echo "tls_trust_file /etc/pki/tls/certs/ca-bundle.crt")
logfile  ${USR_HOME}/msmtp.log
account  default

$([ ! -z "${SMTP_RELAYHOST}" ]          && echo "host     ${SMTP_RELAYHOST}")
$([ ! -z "${SMTP_RELAYHOST_PORT}" ]     && echo "port     ${SMTP_RELAYHOST_PORT}")
$([ ! -z "${SMTP_MAIL_FROM}" ]          && echo "from     ${SMTP_MAIL_FROM}")

$([ ! -z "${SMTP_RELAYHOST_USERNAME}" ] && echo "auth     on" || echo "auth     off")
$([ ! -z "${SMTP_RELAYHOST_USERNAME}" ] && echo "user     ${SMTP_RELAYHOST_USERNAME}")
$([ ! -z "${SMTP_RELAYHOST_PASSWORD}" ] && echo "password ${SMTP_RELAYHOST_PASSWORD}")
" > "/etc/msmtprc"

echo "--> forwarding all emails to: ${SMTP_RELAYHOST}"
[ -n "${SMTP_RELAYHOST_USERNAME}" ] && echo "---> using username: ${SMTP_RELAYHOST_USERNAME}"
}

function runHooks() {
  # configure supervisord
  echo "--> fixing supervisord config file..."
  if   [ "$OS_RELEASE" = "debian" ]; then
    echo "---> Debian Linux detected"
    sed 's|^files = .*|files = /etc/supervisor/conf.d/*.ini|' -i /etc/supervisor/supervisord.conf
    mkdir -p /var/log/supervisor /var/log/proftpd /var/log/dbconfig-common /var/log/apt/ /var/log/apache2/ /var/run/nagios/
    touch /var/log/wtmp /var/log/lastlog
    [ ! -e /sbin/nologin ] && ln -s /usr/sbin/nologin /sbin/nologin
  else
    echo "---> RHEL Linux based distro detected"
    mkdir -p /run/supervisor
    sed 's/\[supervisord\]/\[supervisord\]\nuser=root/' -i /etc/supervisord.conf
    sed 's|^file=.*|file=/run/supervisor/supervisor.sock|' -i /etc/supervisord.conf
    sed 's|^pidfile=.*|pidfile=/run/supervisor/supervisord.pid|' -i /etc/supervisord.conf
    sed 's|^nodaemon=.*|nodaemon=true|' -i /etc/supervisord.conf
    # configure webserver security
    #echo unix_http_server username=admin | iniParser /etc/supervisord.conf
    #echo unix_http_server password=izpbx | iniParser /etc/supervisord.conf
    
#     echo "
# [eventlistener:processes]
# command=stop-supervisor.sh
# events=PROCESS_STATE_STOPPED, PROCESS_STATE_EXITED, PROCESS_STATE_FATAL" >> /etc/supervisord.conf
    
  fi

  # check and create missing container directory
  if [ ! -z "${APP_DATA}" ]; then  
    echo "=> Persistent storage path detected... relocating and reconfiguring system data and configuration files using basedir: '${APP_DATA}'"

    # link to custom data directory if required
    local n=1 ; local t=$(echo ${#appDataDirs[@]} + ${#appFilesConf[@]} | bc)
    for dir in ${appDataDirs[@]}; do
      symlinkDir "${dir}" "${APP_DATA}${dir}" "$(printf '[%02d/%d]' $n $t)"
      initizializeDir "${dir}".dist "${APP_DATA}${dir}" "$(printf '[%02d/%d]' $n $t)"
      let n+=1
    done
    
    # link default configuration files to custom location
    for file in ${appFilesConf[@]}; do
      symlinkFile "${file}" "${APP_DATA}${file}" "$(printf '[%02d/%d]' $n $t)"
      let n+=1
    done
   else
    echo "=> WARNING: No Persistent storage path detected... the configurations will be lost on container restart"
  fi

  # check files and directory permissions
  echo "--> verifying files permissions"
  
  # TFTPDIR permission and path fix
  fixOwner "${APP_USR}" "${APP_GRP}" "${appDataDirs[TFTPDIR]}"
  [ ! -e "/tftpboot" ] && ln -s "${appDataDirs[TFTPDIR]}" "/tftpboot"

#   for dir in ${appDataDirs[@]}; do
#     [ ! -z "${APP_DATA}" ] && dir="${APP_DATA}${dir}"
#     fixOwner "${APP_USR}" "${APP_GRP}" "${dir}"
#   done
#   for dir in ${appCacheDirs[@]}; do
#     [ ! -e "${dir}" ] && mkdir -p "${dir}"
#     fixOwner "${APP_USR}" "${APP_GRP}" "${dir}"
#   done
#   for file in ${appFilesConf[@]}; do
#     [ ! -z "${APP_DATA}" ] && file="${APP_DATA}${file}"
#     fixOwner "${APP_USR}" "${APP_GRP}" "${file}"
#   done

  # customize bash env
  cfgBashEnv > /root/.bashrc
  
  # enable/disable and configure services
  [[ "$POSTFIX_ENABLED" = "true" && "$MSMTP_ENABLED" = "true" ]] && MSMTP_ENABLED=false # make POSTFIX service override MSMTP if both enabled
  [[ "$MSMTP_ENABLED" = "true" ]] && cfgService_msmtp

  chkService POSTFIX_ENABLED
  chkService CRON_ENABLED
  chkService FAIL2BAN_ENABLED
  chkService HTTPD_ENABLED
  chkService ASTERISK_ENABLED
  chkService IZPBX_ENABLED
  chkService ZABBIX_ENABLED
  chkService FOP2_ENABLED
  chkService NTP_ENABLED

  # dnsmasq management
  [[ "$DHCP_ENABLED" = "true" || "$TFTP_ENABLED" = "true" ]] && DNSMASQ_ENABLED=true
  chkService DNSMASQ_ENABLED
   
  # phpMyAdmin configuration
  [ "${PMA_ENABLED}" = "true" ] && cfgService_pma || mv "${PMA_CONF_APACHE}" "${PMA_CONF_APACHE}-disabled"

  # remote XML phonebook support
  [ ${PHONEBOOK_ENABLED} = "true" ] && cfgService_phonebook
  
  # Lets Encrypt certificate generation
  [[ "${HTTPD_HTTPS_ENABLED}" = "true" && "${LETSENCRYPT_ENABLED}" = "true" ]] && cfgService_letsencrypt
}

function runHooksCustom() {
  HOOK=${1:-""}
  HOOKDIR=${APP_CUSTOM_SCRIPTS}/${HOOK}
  
  [ -z "${APP_CUSTOM_SCRIPTS}" ] && { echo "--> Custom Script Hooks: OFF" ; return ; }

  echo "--> Looking for custom scripts ('${HOOK}' hook stage) in '${APP_CUSTOM_SCRIPTS}/${HOOK}='${HOOKDIR}'"
  
  if [ -d "${HOOKDIR}" ] ; then
     for inc in ${HOOKDIR}/*.custom-inc ; do
      if [ -r ${inc} ] ; then
        echo "---> Found and source '${inc}' ..."
        source ${inc}
      fi
     done
    else
      echo "---> WARNING: Custom scripts dir '${HOOKDIR}' doesn't exist..."
  fi
}

runHooksCustom pre-init
runHooks
runHooksCustom post-init
