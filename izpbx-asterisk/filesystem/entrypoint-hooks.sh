#!/bin/bash
# written by Ugo Viti <ugo.viti@initzero.it>
# version: 20210313
#set -ex

## default root mail adrdess
: ${ROOT_MAILTO:="root@localhost"} # default root mail address

## app specific variables
: ${APP_DESCRIPTION:="izPBX Cloud Telephony System"}
: ${APP_CHART:=""}
: ${APP_RELEASE:=""}
: ${APP_NAMESPACE:=""}

: ${ASTERISK_VER:=""}
: ${FREEPBX_VER:=""}

# override default data directory used by container apps (used by stateful apps)
: ${APP_DATA:=""}

# default directory and config files paths arrays used for persistent data
declare -A appDataDirs=(
  [CRONDIR]=/var/spool/cron
  [ASTHOME]=/home/asterisk
  [ASTETCDIR]=/etc/asterisk
  [ASTVARLIBDIR]=/var/lib/asterisk
  [ASTSPOOLDIR]=/var/spool/asterisk
  [ASTRUNDIR]=/var/run/asterisk
  [HTTPDHOME]=/var/www
  [HTTPDLOGDIR]=/var/log/httpd
  [ASTLOGDIR]=/var/log/asterisk
  [F2BLOGDIR]=/var/log/fail2ban
  [F2BLIBDIR]=/var/lib/fail2ban
  [FOP2APPDIR]=/usr/local/fop2
  [SSLCRTDIR]=/etc/pki/izpbx
  [ROOTHOME]=/root
  [DNSMASQDIR]=/etc/dnsmasq.d
  [DNSMASQLEASEDIR]=/var/lib/dnsmasq
  [TFTPDIR]=/var/lib/tftpboot
)

declare -A appFilesConf=(
  [FPBXCFGFILE]=/etc/freepbx.conf
  [AMPCFGFILE]=/etc/amportal.conf
)

declare -A appCacheDirs=(
  [ASTRUNDIR]=/var/run/asterisk
  [PHPOPCACHEDIR]=/var/lib/php/opcache
  [PHPSESSDIR]=/var/lib/php/session
  [PHPWSDLDIR]=/var/lib/php/wsdlcache
)

declare -A fpbxDirs=(
  [AMPWEBROOT]=/var/www/html
  [ASTETCDIR]=/etc/asterisk
  [ASTVARLIBDIR]=/var/lib/asterisk
  [ASTAGIDIR]=/var/lib/asterisk/agi-bin
  [ASTSPOOLDIR]=/var/spool/asterisk
  [ASTRUNDIR]=/var/run/asterisk
  [ASTLOGDIR]=/var/log/asterisk
  [AMPBIN]=/var/lib/asterisk/bin
  [AMPSBIN]=/var/lib/asterisk/sbin
  [AMPCGIBIN]=/var/www/cgi-bin
  [AMPPLAYBACK]=/var/lib/asterisk/playback
  [CERTKEYLOC]=/etc/asterisk/keys               
)

declare -A fpbxDirsExtra=(
  [ASTMODDIR]=/usr/lib64/asterisk/modules
)

declare -A fpbxFilesLog=(
  [FPBXDBUGFILE]=/var/log/asterisk/freepbx-debug.log
  [FPBXLOGFILE]=/var/log/asterisk/freepbx.log
  [FPBXSECLOGFILE]=/var/log/asterisk/freepbx_security.log
)

declare -A fpbxSipSettings=(
  [rtpstart]=${APP_PORT_RTP_START}
  [rtpend]=${APP_PORT_RTP_END}
  [udpport-0.0.0.0]=${APP_PORT_PJSIP}
  [tcpport-0.0.0.0]=${APP_PORT_PJSIP}
  [bindport]=${APP_PORT_SIP}
)

# 20200318 still not used
#declare -A freepbxIaxSettings=(
#  [bindport]=${APP_PORT_IAX}
#)

## other variables

# hostname configuration
[ ! -z ${APP_FQDN} ] && HOSTNAME="${APP_FQDN}" # set hostname to APP_FQDN if defined
: ${SERVERNAME:=$HOSTNAME}      # (**$HOSTNAME**) default web server hostname

# mysql configuration
: ${MYSQL_SERVER:="db"}
: ${MYSQL_ROOT_PASSWORD:=""}
: ${MYSQL_DATABASE:="asterisk"}
: ${MYSQL_USER:="asterisk"}
: ${MYSQL_PASSWORD:=""}
: ${APP_PORT_MYSQL:="3306"}

# fop2 (automaticcally obtained quering freepbx settings)
#: ${FOP2_AMI_HOST:="localhost"}
#: ${FOP2_AMI_PORT:="5038"}
#: ${FOP2_AMI_USERNAME:="admin"}
#: ${FOP2_AMI_PASSWORD:="amp111"}

# apache httpd configuration
: ${HTTPD_HTTPS_ENABLED:="true"}
: ${HTTPD_REDIRECT_HTTP_TO_HTTPS:="false"}
: ${HTTPD_ALLOW_FROM:=""}

# phpMyAdmin configuration
: ${PMA_CONFIG:="/etc/phpMyAdmin/config.inc.php"}
: ${PMA_ALIAS:="/admin/pma"}
: ${PMA_ALLOW_FROM:="127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"}

## zabbix configuration
: ${ZABBIX_USR:="zabbix"}
: ${ZABBIX_GRP:="zabbix"}
: ${ZABBIX_SERVER:="127.0.0.1"}
: ${ZABBIX_SERVER_ACTIVE:="127.0.0.1"}
: ${ZABBIX_HOSTNAME:="${HOSTNAME}"}
: ${ZABBIX_HOSTMETADATA:="Linux"}

## default supervisord services status
#: ${SYSLOG_ENABLED:="true"}
#: ${POSTFIX_ENABLED:="true"}
: ${CRON_ENABLED:="true"}
: ${HTTPD_ENABLED:="true"}
: ${ASTERISK_ENABLED:="false"}
: ${IZPBX_ENABLED:="true"}
: ${FAIL2BAN_ENABLED:="true"}
: ${POSTFIX_ENABLED:="true"}
: ${DNSMASQ_ENABLED:="false"}
: ${DHCP_ENABLED:="false"}
: ${TFTP_ENABLED:="false"}
: ${ZABBIX_ENABLED:="false"}
: ${FOP2_ENABLED:="false"}
: ${PMA_ENABLED:="false"}

## daemons configs

# postfix
: ${SMTP_RELAYHOST:=""}
: ${SMTP_RELAYHOST_USERNAME:=""}
: ${SMTP_RELAYHOST_PASSWORD:=""}
: ${SMTP_STARTTLS:="true"}
: ${SMTP_ALLOWED_SENDER_DOMAINS:=""}
: ${SMTP_MESSAGE_SIZE_LIMIT:="0"}
: ${SMTP_MAIL_FROM:=""}

: ${RELAYHOST:="$SMTP_RELAYHOST"}
: ${RELAYHOST_USERNAME:="$SMTP_RELAYHOST_USERNAME"}
: ${RELAYHOST_PASSWORD:="$SMTP_RELAYHOST_PASSWORD"}
: ${ALLOWED_SENDER_DOMAINS:="$SMTP_ALLOWED_SENDER_DOMAINS"}
: ${MESSAGE_SIZE_LIMIT:="$SMTP_MESSAGE_SIZE_LIMIT"}

# operating system specific variables
## detect current operating system
: ${OS_RELEASE:="$(cat /etc/os-release | grep ^"ID=" | sed 's/"//g' | awk -F"=" '{print $2}')"}

# debian paths
if   [ "$OS_RELEASE" = "debian" ]; then
: ${SUPERVISOR_DIR:="/etc/supervisor/conf.d/"}
: ${PMA_DIR:="/var/www/html/admin/pma"}
: ${PMA_CONF:="$PMA_DIR/config.inc.php"}
#: ${PMA_CONF:="/etc/phpmyadmin/config.inc.php"}
: ${PMA_CONF_APACHE:="/etc/phpmyadmin/apache.conf"}
: ${PHP_CONF:="/etc/php/7.3/apache2/php.ini"}
: ${NRPE_CONF:="/etc/nagios/nrpe.cfg"}
: ${NRPE_CONF_LOCAL:="/etc/nagios/nrpe_local.cfg"}
: ${ZABBIX_CONF:="/etc/zabbix/zabbix_agentd.conf"}
: ${ZABBIX_CONF_LOCAL:="/etc/zabbix/zabbix_agentd.conf.d/local.conf"}
# alpine paths
elif [ "$OS_RELEASE" = "alpine" ]; then
: ${SUPERVISOR_DIR:="/etc/supervisor.d"}
: ${PMA_CONF:="/etc/phpmyadmin/config.inc.php"}
: ${PMA_CONF_APACHE:="/etc/apache2/conf.d/phpmyadmin.conf"}
: ${PHP_CONF:="/etc/php/php.ini"}
: ${ZABBIX_CONF_LOCAL:="/etc/zabbix/zabbix_agentd.conf.d/local.conf"}
# centos paths
elif [ "$OS_RELEASE" = "centos" ]; then
: ${SUPERVISOR_DIR:="/etc/supervisord.d"}
: ${HTTPD_CONF_DIR:="/etc/httpd"} # apache config dir
: ${PMA_CONF_APACHE:="/etc/httpd/conf.d/phpMyAdmin.conf"}
: ${ZABBIX_CONF:="/etc/zabbix/zabbix_agentd.conf"}
: ${ZABBIX_CONF_LOCAL:="/etc/zabbix/zabbix_agentd.d/local.conf"}
fi


## misc functions
check_version() { printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' '); }

print_path() {
  echo ${@%/*}
}

print_fullname() {
  echo ${@##*/}
}

print_name() {
  print_fullname $(echo ${@%.*})
}

print_ext() {
  echo ${@##*.}
}

# return true if specified directory is empty
dirEmpty() {
    [ -z "$(ls -A "$1/")" ]
}

fixOwner() {
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

fixPermission() {
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

# if required move default confgurations to custom directory
symlinkDir() {
  local dirOriginal="$1"
  local dirCustom="$2"

  echo "--> directory data override detected: original:[$dirOriginal] custom:[$dirCustom]"

  # copy data files form original directory if destination is empty
  if [ -e "$dirOriginal" ] && dirEmpty "$dirCustom"; then
    echo "---> empty dir '$dirCustom' detected copying '$dirOriginal' contents to '$dirCustom'..."
    rsync -a -q "$dirOriginal/" "$dirCustom/"
  fi

  # make directory if not exist
  if [ ! -e "$dirOriginal" ]; then
      # make destination dir if not exist
      echo "---> WARNING: original data directory doesn't exist... creating empty directory: '$dirOriginal'"
      mkdir -p "$dirOriginal"
  fi
  
  # rename directory
  if [ -e "$dirOriginal" ]; then
      echo -e "---> renaming '${dirOriginal}' to '${dirOriginal}.dist'"
      mv "$dirOriginal" "$dirOriginal".dist
  fi
  
  # symlink directory
  echo "---> symlinking '$dirCustom' to '$dirOriginal'"
  ln -s "$dirCustom" "$dirOriginal"
}

symlinkFile() {
  local fileOriginal="$1"
  local fileCustom="$2"

  echo "--> file data override detected: original:[$fileOriginal] custom:[$fileCustom]"

  if [ -e "$fileOriginal" ]; then
      # copy data files form original directory if destination is empty
      if [ ! -e "$fileCustom" ]; then
        echo "---> INFO: detected not existing file '$fileCustom'. copying '$fileOriginal' to '$fileCustom'..."
        rsync -a -q "$fileOriginal" "$fileCustom"
      fi
      echo -e "---> renaming '${fileOriginal}' to '${fileOriginal}.dist'... "
      mv "$fileOriginal" "$fileOriginal".dist
    else
      echo "---> WARNING: original data file doesn't exist... creating symlink from a not existing source: '$fileOriginal'"
      #touch "$fileOriginal"
  fi

  echo "---> symlinking '$fileCustom' to '$fileOriginal'"
  # create parent dir if not exist
  [ ! -e "$(dirname "$fileCustom")" ] && mkdir -p "$(dirname "$fileCustom")"
  ln -s "$fileCustom" "$fileOriginal"

}

# enable/disable and configure services
chkService() {
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
cfgService_postfix() {
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
	echo -n "- Forwarding all emails to $RELAYHOST"
	postconf -e relayhost=$RELAYHOST

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
  echo -n "- enabling mynetworks: $SMTP_MYNETWORKS"
  postconf -e mynetworks=$SMTP_MYNETWORKS
else
  postconf -e "mynetworks=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
fi

if [ "$SMTP_STARTTLS" = "true" ]; then
  echo -n "- enabling TLS support as smtp client"
  postconf -e smtp_use_tls=yes
fi

# split with space
if [ ! -z "$ALLOWED_SENDER_DOMAINS" ]; then
	echo -n "- Setting up allowed SENDER domains: $ALLOWED_SENDER_DOMAINS"
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
echo -n "- enabling submission protocol on port 587"
sed -i -r -e 's/^#submission/submission/' /etc/postfix/master.cf

# configure /etc/aliases
[ ! -f /etc/aliases ] && echo "postmaster: root" > /etc/aliases
[ ${ROOT_MAILTO} ] && echo "root: ${ROOT_MAILTO}" >> /etc/aliases && newaliases

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
cfgService_cron() {
  if   [ "$OS_RELEASE" = "debian" ]; then
    cronDir="/var/spool/cron/ing supervisord config fbs"
  elif [ "$OS_RELEASE" = "centos" ]; then
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
iniParser() {
  ini="$@"
  while read setting ; do
    section="$(echo $setting | awk -F" " '{print $1}')"
    k=$(echo $setting | sed -e "s/^${section} //" | awk -F"=" '{print $1}' | tr '[:upper:]' '[:lower:]')
    v=$(echo $setting | sed -e "s/'//g" | awk -F"=" '{print $2}')
    sed -e "/^\[${section}\]$/I,/^\(\|;\|#\)\[/ s/^\(;\|#\)${k}/${k}/" -e "/^\[${section}\]$/I,/^\[/ s|^${k}.*=.*|${k}=${v}|I" -i "${ini}"
  done
}

## fail2ban service
cfgService_fail2ban() {
  echo "--> reconfiguring Fail2ban settings..."
  # ini config file parse function
  # fix default log path
  echo "DEFAULT LOGTARGET=/var/log/fail2ban/fail2ban.log" | iniParser /etc/fail2ban/fail2ban.conf
  touch /var/log/fail2ban/fail2ban.log
  # configure all settings
  set | grep ^"FAIL2BAN_" | sed -e 's/^FAIL2BAN_//' | sed -e 's/_/ /' | iniParser "/etc/fail2ban/jail.d/99-local.conf"
}

## apache service
cfgService_httpd() {
  echo "--> setting Apache ServerName to ${SERVERNAME}"
  if   [ "$OS_RELEASE" = "debian" ]; then
    sed "s/#ServerName .*/ServerName ${SERVERNAME}/" -i "${HTTPD_CONF_DIR}/sites-enabled/000-default.conf"
    echo "ServerName ${SERVERNAME}" >> "${HTTPD_CONF_DIR}/apache2.conf"
  elif [ "$OS_RELEASE" = "alpine" ]; then
    sed "s/^#ServerName.*/ServerName ${SERVERNAME}/" -i "${HTTPD_CONF_DIR}/httpd.conf"
  elif [ "$OS_RELEASE" = "centos" ]; then
    sed "s/#LoadModule mpm_prefork_module/LoadModule mpm_prefork_module/" -i "${HTTPD_CONF_DIR}/conf.modules.d/00-mpm.conf"
    sed "s/LoadModule mpm_event_module/#LoadModule mpm_event_module/"     -i "${HTTPD_CONF_DIR}/conf.modules.d/00-mpm.conf"
    sed "s/^#ServerName.*/ServerName ${SERVERNAME}/" -i "${HTTPD_CONF_DIR}/conf/httpd.conf"
    sed "s/User apache/User ${APP_USR}/"               -i "${HTTPD_CONF_DIR}/conf/httpd.conf"
    sed "s/Group apache/Group ${APP_GRP}/"             -i "${HTTPD_CONF_DIR}/conf/httpd.conf"
    sed "s/Listen 80/Listen ${APP_PORT_HTTP}/"       -i "${HTTPD_CONF_DIR}/conf/httpd.conf"
    
    # disable default ssl.conf and use virtual.conf instead if HTTPD_HTTPS_ENABLED=false
    mv "${HTTPD_CONF_DIR}/conf.d/ssl.conf" "${HTTPD_CONF_DIR}/conf.d/ssl.conf-dist"


print_AllowFrom() {
  if [ ! -z "${HTTPD_ALLOW_FROM}" ]; then 
      for IP in $(echo ${HTTPD_ALLOW_FROM} | sed -e "s/'//g") ; do
        echo "    Require ip ${IP}"
      done
  else
      echo "    Require all granted"
  fi
}

    echo "# default HTTP virtualhost
<VirtualHost *:${APP_PORT_HTTP}>
  DocumentRoot /var/www/html
$(if [ "${HTTPD_REDIRECT_HTTP_TO_HTTPS}" = "true" ]; then
echo "  <IfModule mod_rewrite.c>
    RewriteEngine on
    RewriteCond %{REQUEST_URI} !\.well-known/acme-challenge
    RewriteCond %{HTTPS} off
    #RewriteCond %{HTTP_HOST} ^www\.(.*)$ [NC]
    RewriteRule .? https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
  </IfModule>"
fi)
  <Directory /var/www/html>
    Options Includes FollowSymLinks MultiViews
    AllowOverride All
$(print_AllowFrom)
  </Directory>
</VirtualHost>

$(if [ ! -z "${APP_FQDN}" ]; then
echo "# HTTP virtualhost
<VirtualHost *:${APP_PORT_HTTP}>
  ServerName ${APP_FQDN}
$(if [ "${HTTPD_REDIRECT_HTTP_TO_HTTPS}" = "true" ]; then
echo "# enable http to https automatic rewrite
<IfModule mod_rewrite.c>
  RewriteEngine on
  RewriteCond %{REQUEST_URI} !\.well-known/acme-challenge
  RewriteCond %{HTTPS} off
  #RewriteCond %{HTTP_HOST} ^www\.(.*)$ [NC]
  RewriteRule .? https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
</IfModule>"
fi)
  <Directory /var/www/html>
    Options Includes FollowSymLinks MultiViews
    AllowOverride All
$(print_AllowFrom)
  </Directory>
</VirtualHost>"
fi)

$(if [ "${HTTPD_HTTPS_ENABLED}" = "true" ]; then
echo "# Enable HTTPS listening
Listen ${APP_PORT_HTTPS} https
SSLPassPhraseDialog    exec:/usr/libexec/httpd-ssl-pass-dialog
SSLSessionCache        shmcb:/run/httpd/sslcache(512000)
SSLSessionCacheTimeout 300
SSLCryptoDevice        builtin"
fi)

$(if [[ "${HTTPD_HTTPS_ENABLED}" = "true" && "${LETSENCRYPT_ENABLED}" != "true" ]]; then
echo "# enable default ssl virtualhost with self signed certificate
<VirtualHost _default_:${APP_PORT_HTTPS}>
  ErrorLog                 logs/ssl_error_log
  TransferLog              logs/ssl_access_log
  LogLevel                 warn
  SSLEngine                on
  SSLHonorCipherOrder      on
  SSLCipherSuite           PROFILE=SYSTEM
  SSLProxyCipherSuite      PROFILE=SYSTEM
  SSLCertificateFile       ${appDataDirs[SSLCRTDIR]}/izpbx.crt
  SSLCertificateKeyFile    ${appDataDirs[SSLCRTDIR]}/izpbx.key
  #SSLCertificateChainFile ${appDataDirs[SSLCRTDIR]}/chain.crt

  <Directory /var/www/html>
    Options Includes FollowSymLinks MultiViews
    AllowOverride All
$(print_AllowFrom)
  </Directory>
</VirtualHost>"
fi)

$(if [[ ! -z "${APP_FQDN}" && "${LETSENCRYPT_ENABLED}" = "true" ]]; then
echo "# HTTPS virtualhost
<VirtualHost *:${APP_PORT_HTTPS}>
  ServerName ${APP_FQDN}

  SSLEngine               on
  SSLHonorCipherOrder     on
  SSLCipherSuite          PROFILE=SYSTEM
  SSLProxyCipherSuite     PROFILE=SYSTEM
  SSLCertificateFile      ${appDataDirs[ASTETCDIR]}/keys/integration/webserver.crt
  SSLCertificateKeyFile   ${appDataDirs[ASTETCDIR]}/keys/integration/webserver.key

  <Directory /var/www/html>
    Options Includes FollowSymLinks MultiViews
    AllowOverride All
$(print_AllowFrom)
  </Directory>
</VirtualHost>"
fi)

" > "${HTTPD_CONF_DIR}/conf.d/virtual.conf"
  fi
}

cfgService_asterisk() {
  echo "=> Starting Asterisk"
}

## freepbx+asterisk service
cfgService_izpbx() {

  freepbx_reload() {
    # reload freepbx config
    echo "---> reloading FreePBX..."
    su - ${APP_USR} -s /bin/bash -c "fwconsole reload"
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

  ## rebase directory paths, based on APP_DATA and create/chown missing directories
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
    
    # process logs files
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

  echo "--> configuring FreePBX ODBC"
  # fix mysql odbc inst file path
  sed -i 's/\/lib64\/libmyodbc5.so/\/lib64\/libmaodbc.so/' /etc/odbcinst.ini
  # create mysql odbc
  echo "[MySQL-asteriskcdrdb]
Description = MariaDB connection to 'asteriskcdrdb' database
driver = MySQL
server = ${MYSQL_SERVER}
database = asteriskcdrdb
Port = ${APP_PORT_MYSQL}
option = 3
Charset=utf8" > /etc/odbc.ini

  # workaround for legacy missing ${APP_DATA}/.initialized file nut already initialized izpbx deploy
  if [[ -e "${appFilesConf[FPBXCFGFILE]}" && ! -e ${APP_DATA}/.initialized ]]; then
    echo "--> INFO: found '${appFilesConf[FPBXCFGFILE]}' configuration file but missing '${APP_DATA}/.initialized'... creating it right now"
    echo "--> NOTE: if you want make an initial install, remove '${appFilesConf[FPBXCFGFILE]}' and '${APP_DATA}/.initialized' file"
    touch "${APP_DATA}/.initialized"
  fi
  
  # initialize izpbx if not already deployed
  if [ ! -e ${APP_DATA}/.initialized ]; then
      # first run detected initialize izpbx
      cfgService_freepbx_install
    else
      echo "--> INFO: FreePBX installation DETECTED! found '${APP_DATA}/.initialized' file"
      [ ! -e "${appFilesConf[FPBXCFGFILE]}" ] && echo "---> WARNING: missing configuration file: ${appFilesConf[FPBXCFGFILE]}"
      # izpbx is already initialized, update configuration files
      echo "---> reconfiguring '${appFilesConf[FPBXCFGFILE]}'..."
      [[ ! -z "${APP_PORT_MYSQL}" && ${APP_PORT_MYSQL} -ne 3306 ]] && export MYSQL_SERVER="${MYSQL_SERVER}:${APP_PORT_MYSQL}"
      sed "s/^\$amp_conf\['AMPDBUSER'\] =.*/\$amp_conf\['AMPDBUSER'\] = '${MYSQL_USER}';/"     -i "${appFilesConf[FPBXCFGFILE]}"
      sed "s/^\$amp_conf\['AMPDBPASS'\] =.*/\$amp_conf\['AMPDBPASS'\] = '${MYSQL_PASSWORD}';/" -i "${appFilesConf[FPBXCFGFILE]}"
      sed "s/^\$amp_conf\['AMPDBHOST'\] =.*/\$amp_conf\['AMPDBHOST'\] = '${MYSQL_SERVER}';/"   -i "${appFilesConf[FPBXCFGFILE]}"
      sed "s/^\$amp_conf\['AMPDBNAME'\] =.*/\$amp_conf\['AMPDBNAME'\] = '${MYSQL_DATABASE}';/" -i "${appFilesConf[FPBXCFGFILE]}"
  fi

  echo "---> applying workarounds for FreePBX and Asterisk..."
  # make missing log files
  [ ! -e "${fpbxDirs[ASTLOGDIR]}/full" ] && touch "${fpbxDirs[ASTLOGDIR]}/full" && chown ${APP_USR}:${APP_GRP} "${file}" "${fpbxDirs[ASTLOGDIR]}/full"
  
  # relink fwconsole and amportal if not exist
  [ ! -e "/usr/sbin/fwconsole" ] && ln -s ${fpbxDirs[AMPBIN]}/fwconsole /usr/sbin/fwconsole
  [ ! -e "/usr/sbin/amportal" ]  && ln -s ${fpbxDirs[AMPBIN]}/amportal  /usr/sbin/amportal
  
  # reconfigure freepbx from env variables
  echo "---> reconfiguring FreePBX Advanced Settings if needed..."
  set | grep ^"FREEPBX_" | grep -v -e ^"FREEPBX_MODULES_" -e ^"FREEPBX_VER=" | sed -e 's/^FREEPBX_//' -e 's/=/ /' | while read setting ; do
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
  #for k in ${!freepbxIaxSettings[@]}; do
  #  v="${freepbxIaxSettings[$k]}"
  #  echo "<?php include '/etc/freepbx.conf'; \$FreePBX = FreePBX::Create(); \$FreePBX->iaxsettings->setConfig('${k}',${v}); needreload();?>" | php
  #done

  echo "---> FIXME: temporary workarounds for FreePBX broken modules and configs..."
  # FIXME: 20200318 freepbx 15.x warnings workaround
  sed 's/^preload = chan_local.so/;preload = chan_local.so/' -i ${fpbxDirs[ASTETCDIR]}/modules.conf
  sed 's/^enabled =.*/enabled = yes/' -i ${fpbxDirs[ASTETCDIR]}/hep.conf
  # FIXME: 20200322 https://issues.freepbx.org/browse/FREEPBX-21317 (NOT MORE NEEDED)
  #[ $(fwconsole ma list | grep backup | awk '{print $4}' | sed 's/\.//g') -lt 150893 ] && su - ${APP_USR} -s /bin/bash -c "fwconsole ma downloadinstall backup --edge"
}

cfgService_freepbx_install() {
  n=1 ; t=5

  until [ $n -eq $t ]; do
  echo
  echo "====================================================================="
  echo "=> !!! FreePBX IS NOT INITIALIZED :: NEW INSTALLATION DETECTED !!! <="
  echo "====================================================================="
  echo
  echo "--> missing '${APP_DATA}/.initialized' file... initializing FreePBX right now... try:[$n/$t]"
  cd /usr/src/freepbx
  
  # start asterisk if it's not running
  if ! asterisk -r -x "core show version" 2>/dev/null ; then ./start_asterisk start ; fi
  
  # verify and wait if mysql is ready
  myn=1 ; myt=10
  until [ $myn -eq $myt ]; do
    mysql -h ${MYSQL_SERVER} -P ${APP_PORT_MYSQL} -u root --password=${MYSQL_ROOT_PASSWORD} -B -e "SELECT 1;" >/dev/null
    RETVAL=$?
    if [ $RETVAL = 0 ]; then
        myn=$myt
      else
        let myn+=1
        echo "--> WARNING: cannot connect to MySQL database '${MYSQL_SERVER}'... waiting database to become ready... retrying in 10 seconds... try:[$myn/$myt]"
        sleep 10
    fi
  done
  
  # FIXME: allow asterisk user to manage asteriskcdrdb database
  mysql -h ${MYSQL_SERVER} -P ${APP_PORT_MYSQL} -u root --password=${MYSQL_ROOT_PASSWORD} -B -e "CREATE DATABASE IF NOT EXISTS asteriskcdrdb"
  mysql -h ${MYSQL_SERVER} -P ${APP_PORT_MYSQL} -u root --password=${MYSQL_ROOT_PASSWORD} -B -e "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'asterisk'@'%' WITH GRANT OPTION;"

  # set default freepbx install options
  FPBX_OPTS+=" --webroot=${fpbxDirs[AMPWEBROOT]}"
  FPBX_OPTS+=" --astetcdir=${fpbxDirs[ASTETCDIR]}"
  FPBX_OPTS+=" --astmoddir=${fpbxDirs[ASTMODDIR]}"
  FPBX_OPTS+=" --astvarlibdir=${fpbxDirs[ASTVARLIBDIR]}"
  FPBX_OPTS+=" --astagidir=${fpbxDirs[ASTAGIDIR]}"
  FPBX_OPTS+=" --astspooldir=${fpbxDirs[ASTSPOOLDIR]}"
  FPBX_OPTS+=" --astrundir=${fpbxDirs[ASTRUNDIR]}"
  FPBX_OPTS+=" --astlogdir=${fpbxDirs[ASTLOGDIR]}"
  FPBX_OPTS+=" --ampbin=${fpbxDirs[AMPBIN]}"
  FPBX_OPTS+=" --ampsbin=${fpbxDirs[AMPSBIN]}"
  FPBX_OPTS+=" --ampcgibin=${fpbxDirs[AMPCGIBIN]}"
  FPBX_OPTS+=" --ampplayback=${fpbxDirs[AMPPLAYBACK]}"

  echo "--> installing FreePBX in '${fpbxDirs[AMPWEBROOT]}'"
  echo "---> START install FreePBX @ $(date)"
  # https://github.com/FreePBX/announcement/archive/release/15.0.zip
  # if mysql run in a non standard port change the mysql server address
  [[ ! -z "${APP_PORT_MYSQL}" && ${APP_PORT_MYSQL} -ne 3306 ]] && export MYSQL_SERVER="${MYSQL_SERVER}:${APP_PORT_MYSQL}"
  set -x
  ./install -n --skip-install --no-ansi --dbhost=${MYSQL_SERVER} --dbuser=${MYSQL_USER} --dbpass=${MYSQL_PASSWORD} ${FPBX_OPTS}
  RETVAL=$?
  set +x
  echo "---> END install FreePBX @ $(date)"
  unset FPBX_OPTS
 
  # if the install success exec
  if [ $RETVAL = 0 ]; then
    # fix paths and relink fwconsole and amportal if not exist
    [ ! -e "/usr/sbin/fwconsole" ] && ln -s ${fpbxDirs[ASTVARLIBDIR]}/bin/fwconsole /usr/sbin/fwconsole
    [ ! -e "/usr/sbin/amportal" ]  && ln -s ${fpbxDirs[ASTVARLIBDIR]}/bin/amportal  /usr/sbin/amportal
      
    # fix freepbx config file permissions
    if [ ! -z "${APP_DATA}" ]; then
      for file in ${appFilesConf[@]}; do
        chown ${APP_USR}:${APP_GRP} "${file}"
      done
      echo "--> fixing directory system paths in db configuration..."
      for k in ${!fpbxDirs[@]} ${!fpbxFilesLog[@]}; do
        fwconsole setting ${k} ${fpbxDirs[$k]}
      done
    fi
   
    : ${FREEPBX_MODULES_CORE:="
      framework
      core
      dashboard
      sipsettings
      voicemail
    "}

    # ordered modules install
    : ${FREEPBX_MODULES_PRE:="
      userman
      pm2
    "}
    
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
    "}

    # disabled modules
    : ${FREEPBX_MODULES_DISABLED:="
      bulkhandler
      speeddial
      weakpasswords
      ucp
    "}
    echo "--> enabling EXTENDED FreePBX repo..."
    su - ${APP_USR} -s /bin/bash -c "fwconsole ma enablerepo extended"
    su - ${APP_USR} -s /bin/bash -c "fwconsole ma enablerepo unsupported"
    
    echo "--> installing Prerequisite FreePBX modules from local install into '${fpbxDirs[AMPWEBROOT]}/admin/modules'"
    for module in ${FREEPBX_MODULES_PRE}; do
      su - ${APP_USR} -s /bin/bash -c "echo \"---> installing module: ${module}\" && fwconsole ma install ${module}"
    done
    
    # fix freepbx and asterisk permissions
    echo "--> fixing FreePBX permissions..."
    fwconsole chown
    freepbx_reload
    
    echo "--> installing Extra FreePBX modules from local install into '${fpbxDirs[AMPWEBROOT]}/admin/modules'"
    for module in ${FREEPBX_MODULES_EXTRA}; do
      su - ${APP_USR} -s /bin/bash -c "echo \"---> installing module: ${module}\" && fwconsole ma install ${module}"
    done
    
    # fix freepbx and asterisk permissions
    echo "--> fixing FreePBX permissions..."
    fwconsole chown
    freepbx_reload
    
    # make this installation initialized
    touch "${APP_DATA}/.initialized"

    # DEBUG: pause forever here
    #while true ; do sleep 10 ; done
  fi

  if [ $RETVAL = 0 ]; then
      n=$t
    else
      let n+=1
      echo "--> problem detected... restarting in 10 seconds... try:[$n/$t]"
      sleep 10
  fi
  done
  
  # stop asterisk
  if asterisk -r -x "core show version" 2>/dev/null ; then 
    echo "--> stopping Asterisk"
    asterisk -r -x "core stop now"
    echo "=> Finished installing FreePBX"
  fi
}

## dnsmasq service
cfgService_dnsmasq() {
  [ "$DHCP_ENABLED" = "true" ] && cfgService_dhcp
  [ "$TFTP_ENABLED" = "true" ] && cfgService_tftp
}

## dhcp service
cfgService_dhcp() {
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
cfgService_tftp() {
  echo "--> configuring TFTP service"
  sed "s|^#dhcp-option=66|dhcp-option=66|"                  -i "${appDataDirs[DNSMASQDIR]}/local.conf"
  sed "s|^#enable-tftp|enable-tftp|"                        -i "${appDataDirs[DNSMASQDIR]}/local.conf"
  sed "s|^#tftp-root=.*|tftp-root=${appDataDirs[TFTPDIR]}|" -i "${appDataDirs[DNSMASQDIR]}/local.conf"
}

## zabbix service
cfgService_zabbix() {
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
LogRemoteCommands=1
LogType=console

#Hostname=${ZABBIX_HOSTNAME}
HostnameItem=system.hostname

Server=${ZABBIX_SERVER}
#ServerActive=${ZABBIX_SERVER_ACTIVE}

#HostMetadataItem=system.uname
#HostMetadata=${ZABBIX_HOSTMETADATA}
" > "$ZABBIX_CONF_LOCAL"
}

cfgService_fop2 () {
  [ ! -e "${appDataDirs[FOP2APPDIR]}/fop2.cfg" ] && cfgService_fop2_install

  if [ -e "${appDataDirs[FOP2APPDIR]}/fop2.cfg" ]; then
  
    # fop2 version upgrade check
    [ -e "${appDataDirs[FOP2APPDIR]}/fop2_server" ] && FOP2_VER_CUR=$("${appDataDirs[FOP2APPDIR]}/fop2_server" -v 2>/dev/null | awk '{print $3}')
    if   [ $(check_version $FOP2_VER_CUR) -lt $(check_version $FOP2_VER) ]; then
      echo "=> INFO: FOP2 update detected... upgrading from $FOP2_VER_CUR to $FOP2_VER"
      cfgService_fop2_upgrade
    elif [ $(check_version $FOP2_VER_CUR) -gt $(check_version $FOP2_VER) ]; then
      echo "=> WARNING: Specified FOP2_VER=$FOP2_VER is older than installed version: $FOP2_VER_CUR"
     else
      echo "=> INFO: Specified FOP2_VER=$FOP2_VER, installed version: $FOP2_VER_CUR"
    fi
     
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
   
    # FOP2 License Code Management
    
    # license interface management
    [ -z "${FOP2_LICENSE_IFACE}" ] && FOP2_LICENSE_IFACE=eth0
    FOP2_LICENSE_OPTS+=" --iface ${FOP2_LICENSE_IFACE}"
    
    # modify fop2 command if interface name is specified
    [ ! -z "${FOP2_LICENSE_IFACE}" ] && sed "s|^command.*=.*|command=/usr/local/fop2/fop2_server -i ${FOP2_LICENSE_IFACE}|" -i "${SUPERVISOR_DIR}/fop2.ini"
    
    if [ ! -e "${appDataDirs[FOP2APPDIR]}/fop2.lic" ]; then
      if [ -z "${FOP2_LICENSE_CODE}" ]; then
          echo "--> INFO: FOP2 is not licensed and no 'FOP2_LICENSE_CODE' variable defined... running in trial mode"
      elif [ -z "${FOP2_LICENSE_NAME}" ] ; then
          echo "--> INFO: FOP2 is not licensed and no 'FOP2_LICENSE_NAME' variable defined... running in trial mode"
        else
          echo "--> INFO: Registering FOP2"
          echo "---> NAME: ${FOP2_LICENSE_NAME}"
          echo "---> CODE: ${FOP2_LICENSE_CODE}"
          echo "---> IFACE: ${FOP2_LICENSE_IFACE} ($(ip a show dev ${FOP2_LICENSE_IFACE} | grep 'link/ether' | awk '{print $2}'))"
          set -x
          ${appDataDirs[FOP2APPDIR]}/fop2_server --register --name "${FOP2_LICENSE_NAME}" --code "${FOP2_LICENSE_CODE}" $FOP2_LICENSE_OPTS
          set +x
          echo "--> INFO: FOP2 license code status:"
          ${appDataDirs[FOP2APPDIR]}/fop2_server --getinfo $FOP2_LICENSE_OPTS
      fi
      else
        FOP2_LICENSE_STATUS="$(${appDataDirs[FOP2APPDIR]}/fop2_server --getinfo $FOP2_LICENSE_OPTS)"
        if [ ! -z "$(echo $FOP2_LICENSE_STATUS | grep "Not Found")" ]; then
          echo "--> WARNING: Reactivating FOP2 license because:"
          echo $FOP2_LICENSE_STATUS
          set -x
          ${appDataDirs[FOP2APPDIR]}/fop2_server --reactivate $FOP2_LICENSE_OPTS
          set +x
        fi
        echo "--> INFO: FOP2 license code status:"
        ${appDataDirs[FOP2APPDIR]}/fop2_server --getinfo $FOP2_LICENSE_OPTS
    fi
  fi
}

cfgService_pma() {
  if [ "${PMA_ENABLED}" = "true" ]; then
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
   Require ip ${PMA_ALLOW_FROM}
</Directory>
EOF
    # configure database access
    sed "s|'localhost';|'${MYSQL_SERVER}';|" -i "${PMA_CONFIG}"
  else
    # disable phpMyAdmin
    mv "${HTTPD_CONF_DIR}/conf.d/phpMyAdmin.conf" "${HTTPD_CONF_DIR}/conf.d/phpMyAdmin.conf-disabled"
  fi
}

cfgService_fop2_install() {
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

cfgService_fop2_upgrade() {
  curl -fSL --connect-timeout 30 http://download2.fop2.com/fop2-$FOP2_VER-centos-x86_64.tgz | tar xz -C /usr/src
  cd /usr/src/fop2 && make install
}

cfgBashEnv() {
  echo '. /etc/os-release
  
  if [ -t 1 ]; then
    export PS1="\e[1;34m[\e[1;33m\u@\e[1;32mdocker-\h\e[1;37m:\w\[\e[1;34m]\e[1;36m\\$ \e[0m"
  fi

  # aliases
  alias d="ls -lAsh --color"
  alias cp="cp -ip"
  alias rm="rm -i"
  alias mv="mv -i"

  echo -e -n "\E[1;34m"
  figlet -w 120 "izPBX"

  : ${APP_VER:="unknown"}
  : ${APP_VER_BUILD:="unknown"}
  : ${APP_BUILD_COMMIT:="unknown"}
  : ${APP_BUILD_DATE:="unknown"}
  
  [ "${APP_BUILD_DATE}" != "unknown" ] && APP_BUILD_DATE=$(date -d @${APP_BUILD_DATE} +"%Y-%m-%d")
  
  echo -e "\E[1;36mizPBX \E[1;32m${APP_VER}\E[1;36m (build: \E[1;32m${APP_VER_BUILD}\E[1;36m commit: \E[1;32m${APP_BUILD_COMMIT}\E[1;36m date: \E[1;32m${APP_BUILD_DATE}\E[1;36m), Asterisk \E[1;32m${ASTERISK_VER:-unknown}\E[1;36m, FreePBX \E[1;32m${FREEPBX_VER:-unknown}\E[1;36m, ${NAME} \E[1;32m${VERSION_ID:-unknown}\E[1;36m, Kernel \E[1;32m$(uname -r)\E[0m"
  echo'
}

runHooks() {
  # configure supervisord
  echo "--> fixing supervisord config file..."
  if   [ "$OS_RELEASE" = "debian" ]; then
    echo "---> Debian Linux detected"
    sed 's|^files = .*|files = /etc/supervisor/conf.d/*.ini|' -i /etc/supervisor/supervisord.conf
    mkdir -p /var/log/supervisor /var/log/proftpd /var/log/dbconfig-common /var/log/apt/ /var/log/apache2/ /var/run/nagios/
    touch /var/log/wtmp /var/log/lastlog
    [ ! -e /sbin/nologin ] && ln -s /usr/sbin/nologin /sbin/nologin
  elif [ "$OS_RELEASE" = "centos" ]; then
    echo "---> CentOS Linux detected"
    mkdir -p /run/supervisor
    sed 's/\[supervisord\]/\[supervisord\]\nuser=root/' -i /etc/supervisord.conf
    sed 's|^file=.*|file=/run/supervisor/supervisor.sock|' -i /etc/supervisord.conf
    sed 's|^pidfile=.*|pidfile=/run/supervisor/supervisord.pid|' -i /etc/supervisord.conf
    sed 's|^nodaemon=.*|nodaemon=true|' -i /etc/supervisord.conf
    # configure webserver security
    #echo unix_http_server username=admin | iniParser /etc/supervisord.conf
    #echo unix_http_server password=izpbx | iniParser /etc/supervisord.conf
  fi

  # check and create missing container directory
  if [ ! -z "${APP_DATA}" ]; then  
    echo "=> Persistent storage path detected... relocating and reconfiguring system data and configuration files using basedir: ${APP_DATA}"
    for dir in ${appDataDirs[@]}
      do
        dir="${APP_DATA}${dir}"
        if [ ! -e "${dir}" ];then
          echo "--> creating missing dir: '$dir'"
          mkdir -p "${dir}"
        fi
      done

    # link to custom data directory if required
    for dir in ${appDataDirs[@]}; do
      symlinkDir "${dir}" "${APP_DATA}${dir}"
    done
    
    for file in ${appFilesConf[@]}; do
      # echo FILE=$file
      symlinkFile "${file}" "${APP_DATA}${file}"
    done
   else
    echo "=> WARNING: No Persistent storage path detected... the configurations will be lost on container restart"
  fi

  # check files and directory permissions
#  echo "--> verifying files permissions"
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
  cfgBashEnv > /etc/profile.d/iz.sh
  
  # enable/disable and configure services
  #chkService SYSLOG_ENABLED
  chkService POSTFIX_ENABLED
  chkService CRON_ENABLED
  chkService FAIL2BAN_ENABLED
  chkService HTTPD_ENABLED
  chkService ASTERISK_ENABLED
  chkService IZPBX_ENABLED
  chkService ZABBIX_ENABLED
  chkService FOP2_ENABLED

  # dnsmasq management
  [[ "$DHCP_ENABLED" = "true" || "$TFTP_ENABLED" = "true" ]] && DNSMASQ_ENABLED=true
  chkService DNSMASQ_ENABLED
   
  # phpMyAdmin configuration
  cfgService_pma

  # Lets Encrypt certificate generation
  if [[ ! -z "$APP_FQDN" && "$LETSENCRYPT_ENABLED" == "true" ]]; then
    echo "--> Let's Encrypt $APP_FQDN"
    if [ -e "/etc/asterisk/keys/$APP_FQDN.pem" ]; then
      echo "----> certificate already exists..."
    else
      echo "----> generating HTTPS certificate"
      # apache web server must be running to complete the certbot handshake
      httpd -k start
      fwconsole certificates --generate --type=le --hostname=$APP_FQDN --country-code=$LETSENCRYPT_COUNTRY_CODE --state=$LETSENCRYPT_COUNTRY_STATE --email=$ROOT_MAILTO
      result=$?
      if [[ $result -eq 0 ]]; then
        fwconsole certificates --default=$APP_FQDN
        result=$?
      fi
      httpd -k stop
    fi
  fi
}

runHooks
