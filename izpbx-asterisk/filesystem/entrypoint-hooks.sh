#!/bin/bash
# written by Ugo Viti <ugo.viti@initzero.it>
# version: 20200315
#set -ex

## default root mail adrdess
: ${ROOT_MAILTO:="root@localhost"} # default root mail address

## app specific variables
: ${APP_DESCRIPTION:="izPBX Cloud Telephony System"}
: ${APP_CHART:=""}
: ${APP_RELEASE:=""}
: ${APP_NAMESPACE:=""}

# override default data directory used by container apps (used for statefll aps)
: ${APP_DATA:=""}

# default directory and config files paths arrays
declare -A appDataDirs=(
  [CRONDIR]=/var/spool/cron
  [USERSHOME]=/home
  [ASTETCDIR]=/etc/asterisk
  [ASTVARLIBDIR]=/var/lib/asterisk
  [ASTSPOOLDIR]=/var/spool/asterisk
  [ASTLOGDIR]=/var/log/asterisk
  [F2BLOGDIR]=/var/log/fail2ban
  [HTTPDHOME]=/var/www
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

declare -A freepbxDirs=(
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

declare -A freepbxDirsExtra=(
  [ASTMODDIR]=/usr/lib64/asterisk/modules
)

declare -A freepbxFilesLog=(
  [FPBXDBUGFILE]=/var/log/asterisk/freepbx-debug.log
  [FPBX_LOG_FILE]=/var/log/asterisk/freepbx.log
)

## other variables
# mysql configuration
: ${MYSQL_SERVER:="db"}
: ${MYSQL_ROOT_PASSWORD:=""}
: ${MYSQL_DATABASE:="asterisk"}
: ${MYSQL_USER:="asterisk"}
: ${MYSQL_PASSWORD:=""}

## hostname configuration
: ${SERVERNAME:=$HOSTNAME}      # (**$HOSTNAME**) default web server hostname

## supervisord services
#: ${SYSLOG_ENABLED:="true"}
#: ${POSTFIX_ENABLED:="true"}
: ${CRON_ENABLED:="true"}
: ${HTTPD_ENABLED:="true"}
: ${ASTERISK_ENABLED:="true"}

## daemons configs
: ${RELAYHOST:=""}
: ${RELAYHOST_USERNAME:=""}
: ${RELAYHOST_PASSWORD:=""}
: ${ALLOWED_SENDER_DOMAINS:=""}

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
: ${NRPE_CONF:="/etc/nrpe.cfg"}
# centos paths
elif [ "$OS_RELEASE" = "centos" ]; then
: ${SUPERVISOR_DIR:="/etc/supervisord.d"}
: ${HTTPD_CONF_DIR:="/etc/httpd"} # apache config dir
: ${PMA_CONF_APACHE:="/etc/httpd/conf.d/phpMyadmin.conf"}
fi


## misc functions
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

# if required move default confgurations to custom directory
symlinkDir() {
  local dirOriginal="$1"
  local dirCustom="$2"

  echo "=> DIRECTORY data override detected: original:[$dirOriginal] custom:[$dirCustom]"

  # copy data files form original directory if destination is empty
  if [ -e "$dirOriginal" ] && dirEmpty "$dirCustom"; then
    echo "--> INFO: Detected empty dir '$dirCustom'. Copying '$dirOriginal' to '$dirCustom'..."
    rsync -a -q "$dirOriginal/" "$dirCustom/"
  fi

  if [ -e "$dirOriginal" ]; then
      echo "--> renaming '${dirOriginal}' to '${dirOriginal}.dist'... "
      mv "$dirOriginal" "$dirOriginal".dist
    else
      # make destination dir if not exist
      echo "--> WARNING: original data directory '$dirOriginal' doesn't exist... creating empty directory"
      mkdir -p "$dirOriginal"
  fi
  
  echo "--> symlinking '$dirCustom' to '$dirOriginal'"
  ln -s "$dirCustom" "$dirOriginal"
}

symlinkFile() {
  local fileOriginal="$1"
  local fileCustom="$2"

  echo "=> FILE data override detected: original:[$fileOriginal] custom:[$fileCustom]"

  if [ -e "$fileOriginal" ]; then
      # copy data files form original directory if destination is empty
      if [ ! -e "$fileCustom" ]; then
        echo "--> INFO: Detected not existing file '$fileCustom'. Copying '$fileOriginal' to '$fileCustom'..."
        rsync -a -q "$fileOriginal" "$fileCustom"
      fi
      echo "--> renaming '${fileOriginal}' to '${fileOriginal}.dist'... "
      mv "$fileOriginal" "$fileOriginal".dist
    else
      echo "--> WARNING: original data file '$fileOriginal' doesn't exist... creating symlink from a not existing source"
      #touch "$fileOriginal"
  fi

  echo "--> symlinking '$fileCustom' to '$fileOriginal'"
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
    echo "--> Configuring $SERVICE_DAEMON service..."
    cfgService_$SERVICE
   else
    autostart=false
    echo "=> Disabling $SERVICE_DAEMON service... because $SERVICE_VAR=$SERVICE_ENABLED"
  fi
  sed "s/autostart=.*/autostart=$autostart/" -i ${SUPERVISOR_DIR}/$SERVICE_DAEMON.ini
}

## exec entrypoint hooks

## postfix service
cfgService_postfix() {
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
	echo "- Will try to deliver emails directly to the final server. Make sure your DNS is setup properly!"
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

if [ ! -z "$MYNETWORKS" ]; then
	postconf -e mynetworks=$MYNETWORKS
else
	postconf -e "mynetworks=127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
fi

# split with space
if [ ! -z "$ALLOWED_SENDER_DOMAINS" ]; then
	echo -n "- Setting up allowed SENDER domains:"
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
sed -i -r -e 's/^#submission/submission/' /etc/postfix/master.cf
}

## cron service
cfgService_cron() {
  echo "---> Configuring Cron service"
  if   [ "$OS_RELEASE" = "debian" ]; then
    cronDir="/var/spool/cron/ing supervisord config fbs"
  elif [ "$OS_RELEASE" = "centos" ]; then
    cronDir="/var/spool/cron"
  fi
  
  if [ -e "$cronDir" ]; then
    if [ "$(stat -c "%U %G %a" "$cronDir")" != "root root 0700" ];then
      echo "---> Fixing "$cronDir" permissions..."
      chown root:root "$cronDir"
      chmod u=rwx,g=wx,o=t "$cronDir"
    fi
  fi
}

## apache service
cfgService_httpd() {
  echo "---> Setting Apache ServerName to ${SERVERNAME}"
  if   [ "$OS_RELEASE" = "debian" ]; then
    sed "s/#ServerName .*/ServerName ${SERVERNAME}/" -i "${HTTPD_CONF_DIR}/sites-enabled/000-default.conf"
    echo "ServerName ${SERVERNAME}" >> "${HTTPD_CONF_DIR}/apache2.conf"
  elif [ "$OS_RELEASE" = "alpine" ]; then
    sed "s/^#ServerName.*/ServerName ${SERVERNAME}/" -i "${HTTPD_CONF_DIR}/httpd.conf"
  elif [ "$OS_RELEASE" = "centos" ]; then
    sed 's/#LoadModule mpm_prefork_module/LoadModule mpm_prefork_module/' -i "${HTTPD_CONF_DIR}/conf.modules.d/00-mpm.conf"
    sed 's/LoadModule mpm_event_module/#LoadModule mpm_event_module/'     -i "${HTTPD_CONF_DIR}/conf.modules.d/00-mpm.conf"
    sed "s/^#ServerName.*/ServerName ${SERVERNAME}/" -i "${HTTPD_CONF_DIR}/conf/httpd.conf"
    sed 's/User apache/User asterisk/'               -i "${HTTPD_CONF_DIR}/conf/httpd.conf"
    sed 's/Group apache/Group asterisk/'             -i "${HTTPD_CONF_DIR}/conf/httpd.conf"
    
    echo "
    <VirtualHost *:80>
    <Directory /var/www/html>
      AllowOverride All
    </Directory>
    </VirtualHost>
    " > "${HTTPD_CONF_DIR}/conf.d/virtual.conf"
  fi
}

## asterisk service
cfgService_asterisk() {
  fixOwner() {
    dir="$1"
    if [ "$(stat -c "%U %G" "$dir")" != "${APP_USR} ${APP_GRP}" ];then
        echo "---> Fixing '$dir' owner..."
        chown ${APP_USR}:${APP_GRP} "$dir"
        #chmod 0770 "$dir"
    fi
  }

  fixPermission() {
    dir="$1"
    if [ "$(stat -c "%a" "$dir")" != "770" ];then
        echo "---> Fixing '$dir' permission..."
        chmod 0770 "$dir"
    fi
  }
  
  # check and create missing container directory
  if [ ! -z "${APP_DATA}" ]; then  
    for dir in ${appDataDirs[@]}
      do
        dir="${APP_DATA}${dir}"
        if [ ! -e "${dir}" ];then
          echo "---> Creating missing dir: '$dir'..."
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
  fi

  # check files and directory permissions
  echo "---> Verifing files permissions"
  for dir in ${appDataDirs[@]}; do
    [ ! -z "${APP_DATA}" ] && dir="${APP_DATA}${dir}"
    [ -e "${dir}" ] && fixOwner "${dir}" || echo "WARNING: the directory '${dir}' doesn't exist"
  done
  for dir in ${appCacheDirs[@]}; do
    fixOwner "${dir}"
  done
  for file in ${appFilesConf[@]}; do
    [ ! -z "${APP_DATA}" ] && file="${APP_DATA}${file}"
    [ -e "${file}" ] && fixOwner "${file}" || echo "WARNING: the file '${file}' doesn't exist"
  done
  
  # configure FreePBX
  cfgService_freepbx
}

## asterisk service
cfgService_freepbx() {
  echo "=> Verifing FreePBX configurations"

  echo "--> Configuring FreePBX ODBC"
  # fix mysql odbc inst file path
  sed -i 's/\/lib64\/libmyodbc5.so/\/lib64\/libmaodbc.so/' /etc/odbcinst.ini
  # create mysql odbc
  echo "[MySQL-asteriskcdrdb]
Description = MariaDB connection to 'asteriskcdrdb' database
driver = MySQL
server = ${MYSQL_SERVER}
database = asteriskcdrdb
Port = 3306
option = 3
Charset=utf8" > /etc/odbc.ini

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

  ## rebase directory paths, based on APP_DATA and create/chown missing directories
  if [ ! -z "${APP_DATA}" ]; then
    echo "--> Using '${APP_DATA}' as basedir for FreePBX install"
    # process directories
    for k in ${!freepbxDirs[@]}; do
      v="${freepbxDirs[$k]}"
      eval freepbxDirs[$k]=${APP_DATA}$v
      [ ! -e "$v" ] && mkdir -p "$v"
      if [ "$(stat -c "%U %G" "$v" 2>/dev/null)" != "${APP_USR} ${APP_GRP}" ];then
      echo "---> Fixing permissions for: $k=$v"
      chown ${APP_USR}:${APP_GRP} "$v"
      fi
    done
    
    # process logs files
    for k in ${!freepbxFilesLog[@]}; do
      v="${freepbxFilesLog[$k]}"
      eval freepbxFilesLog[$k]=${APP_DATA}$v
      [ ! -e "$v" ] && mkdir -p "$v"
      if [ "$(stat -c "%U %G" "$v" 2>/dev/null)" != "${APP_USR} ${APP_GRP}" ];then
      echo "---> Fixing permissions for: $k=$v"
      chown ${APP_USR}:${APP_GRP} "$v"
      fi
    done
  fi

  # transform associative array to variable=paths, ex. AMPWEBROOT=/var/www/html
  for k in ${!freepbxDirs[@]}      ; do eval $k=${freepbxDirs[$k]}     ;done
  for k in ${!freepbxDirsExtra[@]} ; do eval $k=${freepbxDirsExtra[$k]}     ;done
  for k in ${!freepbxFilesLog[@]}  ; do eval $k=${freepbxFilesLog[$k]} ;done    

  # OneTime: install freepbx if this is the first time we initialize the container
  [ ! -e "${appFilesConf[FPBXCFGFILE]}" ] && cfgService_freepbx_install

  echo "--> Applying Workarounds for FreePBX and Asterisk..."
  # relink fwconsole and amportal if not exist
  [ ! -e "/usr/sbin/fwconsole" ] && ln -s /var/lib/asterisk/bin/fwconsole /usr/sbin/fwconsole
  [ ! -e "/usr/sbin/amportal" ] && ln -s /var/lib/asterisk/bin/amportal /usr/sbin/amportal

  # freepbx warnings workaround
  sed 's/^preload = chan_local.so/;preload = chan_local.so/' -i /etc/asterisk/modules.conf
  sed 's/^enabled =.*/enabled = yes/' -i /etc/asterisk/hep.conf

  # reconfigure freepbx from env variables
  echo "--> Reconfiguring FreePBX Advanced Settings..."
  set | grep ^IZPBX_ | sed -e 's/^IZPBX_//' -e 's/=/ /' | while read setting ; do fwconsole setting $setting ; done
}

cfgService_freepbx_install() {
  n=1 ; t=5

  until [ $n -eq $t ]; do
  echo "=> INFO: New installation detected! installing FreePBX in 20 seconds... try:[$n/$t]"
  
  cd /usr/src/freepbx
  
  # start asterisk if it's not running
  if ! asterisk -r -x "core show version" 2>/dev/null ; then ./start_asterisk start ; fi
  
  sleep 20
  
  # FIXME: allow asterisk user to manage asteriskcdrdb database
  mysql -h ${MYSQL_SERVER} -u root --password=${MYSQL_ROOT_PASSWORD} -B -e "CREATE DATABASE IF NOT EXISTS asteriskcdrdb"
  mysql -h ${MYSQL_SERVER} -u root --password=${MYSQL_ROOT_PASSWORD} -B -e "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'asterisk'@'%' WITH GRANT OPTION;"

  # set default freepbx install options
  FPBX_OPTS+=" --webroot=${AMPWEBROOT}"
  FPBX_OPTS+=" --astetcdir=${ASTETCDIR}"
  FPBX_OPTS+=" --astmoddir=${ASTMODDIR}"
  FPBX_OPTS+=" --astvarlibdir=${ASTVARLIBDIR}"
  FPBX_OPTS+=" --astagidir=${ASTAGIDIR}"
  FPBX_OPTS+=" --astspooldir=${ASTSPOOLDIR}"
  FPBX_OPTS+=" --astrundir=${ASTRUNDIR}"
  FPBX_OPTS+=" --astlogdir=${ASTLOGDIR}"
  FPBX_OPTS+=" --ampbin=${AMPBIN}"
  FPBX_OPTS+=" --ampsbin=${AMPSBIN}"
  FPBX_OPTS+=" --ampcgibin=${AMPCGIBIN}"
  FPBX_OPTS+=" --ampplayback=${AMPPLAYBACK}"

  echo "--> Installing FreePBX in '${AMPWEBROOT}'"
  set -x
  ./install -n --dbhost=${MYSQL_SERVER} --dbuser=${MYSQL_USER} --dbpass=${MYSQL_PASSWORD} ${FPBX_OPTS}
  RETVAL=$?
  set +x
  unset FPBX_OPTS
  
  # TEST:
  #[ $RETVAL != 0 ] && fwconsole ma install pm2 && ./install -n --dbhost=${MYSQL_SERVER} --dbuser=${MYSQL_USER} --dbpass=${MYSQL_PASSWORD}
  #RETVAL=$?
  
  if [ $RETVAL = 0 ]; then
    # fix paths and relink fwconsole and amportal if not exist
    [ ! -e "/usr/sbin/fwconsole" ] && ln -s /var/lib/asterisk/bin/fwconsole /usr/sbin/fwconsole
    [ ! -e "/usr/sbin/amportal" ]  && ln -s /var/lib/asterisk/bin/amportal  /usr/sbin/amportal
    
    # fix freepbx config file permissions
    if [ ! -z "${APP_DATA}" ]; then
      for file in ${appFilesConf[@]}; do
        chown ${APP_USR}:${APP_GRP} "${file}"
      done
      echo "--> Fixing directory system paths in db configuration..."
      for k in ${!freepbxDirs[@]} ${!freepbxFilesLog[@]}; do
        fwconsole setting ${k} ${freepbxDirs[$k]}
      done
    fi
   
    echo "--> Installing core FreePBX modules..."
    su - ${APP_USR} -c "fwconsole ma install \
      framework \
      core \
      voicemail \
      sipsettings \
      infoservices \
      featurecodeadmin \
      logfiles \
      callrecording \
      cdr \
      dashboard \
      music \
      soundlang \
      recordings \
      conferences \
      "
 
    echo "--> Enabling extended FreePBX repo..."
    su - ${APP_USR} -c "fwconsole ma enablerepo extended"
    su - ${APP_USR} -c "fwconsole ma enablerepo unsupported"
    
    echo "--> Installing extra FreePBX modules..."
    su - ${APP_USR} -c "fwconsole ma downloadinstall \
      announcement \
      asteriskinfo \
      backup \
      bulkhandler \
      callforward \
      callwaiting \
      daynight \
      calendar \
      certman \
      cidlookup \
      contactmanager \
      donotdisturb \
      fax \
      findmefollow \
      iaxsettings \
      miscapps \
      miscdests \
      userman \
      ivr \
      parking \
      phonebook \
      presencestate \
      printextensions \
      queues \
      speeddial \
      timeconditions \
      weakpasswords \
      "

    # fix freepbx permissions
    fwconsole chown

    # reload asterisk
    echo "--> Reloading FreePBX..."
    su - ${APP_USR} -c "fwconsole reload"
  fi

  if [ $RETVAL = 0 ]; then
      n=$t
    else
      let n+=1
      echo "--> Problem detected... restarting in 10 seconds... try:[$n/$t]"
      sleep 10
  fi
  done
  
  # stop asterisk
  if asterisk -r -x "core show version" 2>/dev/null ; then 
    echo "--> Stopping Asterisk"
    asterisk -r -x "core stop now"
    echo "=> Finished installing FreePBX"
  fi
}

runHooks() {
  echo "=> Executing $APP_DESCRIPTION container hooks..."
  # configure supervisord
  echo "--> Fixing supervisord config file..."
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
  fi

  # configure /etc/aliases
  [ ! -f /etc/aliases ] && echo "postmaster: root" > /etc/aliases
  [ ${ROOT_MAILTO} ] && echo "root: ${ROOT_MAILTO}" >> /etc/aliases && newaliases

  # enable/disable and configure services
  #chkService SYSLOG_ENABLED
  #chkService POSTFIX_ENABLED
  chkService CRON_ENABLED
  chkService HTTPD_ENABLED
  chkService ASTERISK_ENABLED
}

runHooks
