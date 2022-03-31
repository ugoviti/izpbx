ARG IMAGE_FROM=rockylinux/rockylinux:8

FROM ${IMAGE_FROM}

MAINTAINER Ugo Viti <ugo.viti@initzero.it>

### default app args used during build step
#ARG APP_VER_MAJOR=
#ARG APP_VER_MINOR=
#ARG APP_VER_PATCH=

## full app version
#ARG APP_VER=${APP_VER_MAJOR}.${APP_VER_MINOR}.${APP_VER_PATCH}
ARG APP_VER=dev
ENV APP_VER=${APP_VER}

### components app versions
## https://downloads.asterisk.org/pub/telephony/asterisk/releases
ARG ASTERISK_VER=18.11.1

## https://github.com/FreePBX/core/tags (only major version)
ARG FREEPBX_VER=16

## https://www.fop2.com/download.php
ARG FOP2_VER=2.31.32

## http://sources.buildroot.net/spandsp
ARG SPANDSP_VER=3.0.0-6ec23e5a7e

## https://github.com/holme-r/iksemel
ARG IKSEMEL_VER=1.5.1.3

## https://github.com/BelledonneCommunications/bcg729/tags
ARG BCG729_VER=1.1.1

## https://bitbucket.org/arkadi/asterisk-g72x
ARG ASTERISK_G72X_VER=master

## https://github.com/ugoviti/izsynth
ARG IZSYNTH_VER=5.0

## https://github.com/ugoviti/zabbix-templates
ARG ZABBIX_TEMPLATE_VER=main

## https://github.com/irontec/sngrep/releases
ARG SNGREP_VER=1.4.10

### define variables for later container usage
ENV ASTERISK_VER=${ASTERISK_VER}
ENV FREEPBX_VER=${FREEPBX_VER}
ENV FOP2_VER=${FOP2_VER}

## app name
ENV APP_NAME              "izpbx-asterisk"
ENV APP_DESCRIPTION       "izPBX Cloud Native Telephony System"

## set default timezone
ENV TZ                    "UTC"

## app users
ENV APP_UID               1000
ENV APP_GID               1000
ENV APP_USR               "asterisk"
ENV APP_GRP               "asterisk"

## development debug mode (don't delete development and build dependencies on filesystem)
ARG APP_DEBUG=0

## install packages
ENV APP_INSTALL_DEPS=' \
    rsync \
    net-tools \
    procps-ng \
    iptables \
    libnetfilter_conntrack \
    libnfnetlink \
    conntrack-tools \
    libnetfilter_cthelper \
    libnetfilter_cttimeout \
    libnetfilter_queue \
    iftop \
    lsof \
    strace \
    tcpdump \
    supervisor \
    curl \
    opus \
    logrotate \
    fail2ban-server \
    fail2ban-mail \
    fail2ban-sendmail \
    libedit \
    unixODBC \
    sox \
    libxml2 \
    openssl \
    newt \
    sqlite \
    libuuid \
    jansson \
    binutils \
    libedit \
    libtool \
    ncurses \
    libtiff \
    libjpeg-turbo \
    audiofile \
    uuid \
    libtool-ltdl \
    libsndfile \
    wget \
    bzip2 \
    file \
    ilbc \
    mariadb-connector-odbc \
    mpg123 \
    nodejs \
    libtiff-tools \
    cronie \
    httpd \
    mod_ssl \
    php \
    php-mysqlnd \
    php-process \
    php-pear \
    php-mbstring \
    php-xml \
    php-json \
    php-gd \
    php-curl \
    php-ldap \
    mariadb \
    diffutils \
    unzip \
    zip \
    uriparser \
    jq \
    speex \
    speexdsp \
    portaudio \
    libsrtp \
    unbound-libs \
    freetds \
    freetds-libs \
    libevent \
    net-snmp-libs \
    codec2 \
    neon \
    pakchois \
    libmodman \
    libproxy \
    net-snmp-agent-libs \
    lm_sensors-libs \
    libical \
    libical-devel \
    icu \
    gcc-c++ \
    make \
    python2 \
    libnsl \
    which \
    fftw-libs \
    sudo \
    figlet \
    nc \
    dnsmasq \
    glibc-langpack-en \
    perl-DBI \
    perl-DBD-mysql \
    cyrus-sasl-plain \
    cyrus-sasl-md5 \
    libresample \
    incron \
    chrony \
    postfix \
    phpMyAdmin \
    zabbix-agent \
    zabbix-sender \
    ffmpeg \
    lame \
    libuv \
    patch \
    iproute \
  '
  
  # NOTE: postfix > 3.4.x is required for docker logging to stdout
  
RUN set -xe && \
  ## import system information vars
  . /etc/os-release && \
  \
  ## install epel repository
  dnf -y install epel-release && \
  \
  ## repo for phpMyAdmin
  rpm -Uvh https://rpms.remirepo.net/enterprise/remi-release-8.rpm && \
  ## repo for zabbix agent
  rpm -Uvh https://repo.zabbix.com/zabbix/5.4/rhel/8/x86_64/zabbix-release-5.4-1.el8.noarch.rpm && \
  ## repo for ffmpeg command
  rpm -Uhv https://download1.rpmfusion.org/free/el/rpmfusion-free-release-8.noarch.rpm && \
  rpm -Uhv https://download1.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-8.noarch.rpm && \
  ## repo for lame command
  rpm -Uhv http://repo.okay.com.mx/centos/8/x86_64/release/okay-release-1-5.el8.noarch.rpm && \
  ## fix wrong option
  sed '/^failovermethod/d' -i /etc/yum.repos.d/okay.repo && \
  \
  ## install dnf plugins
  dnf -y install dnf-plugins-core && \
  ## enable extra repository
  dnf config-manager --set-enabled \
    powertools \
    remi \
    rpmfusion-free-updates \
    rpmfusion-nonfree-updates \
    okay \
  && \
  ## enable module php 7.4 needed for FreePBX 16
  if [[ "${FREEPBX_VER}" = "16" ]]; then \
  : "---------- Enable PHP 7.4 ----------" && \
  dnf module reset php -y && \
  dnf module enable php:7.4 -y \
  ;fi && \
  \
  ## upgrade the system
  dnf upgrade -y && \
  ## install mandatory packages
  dnf install -y \
  $APP_INSTALL_DEPS \
  && \
  dnf mark install $APP_INSTALL_DEPS && \
  \
  if [[ ${APP_DEBUG} -eq 0 ]]; then \
  : "---------- Clean temporary files ----------" && \
  dnf clean all && \
  rm -rf /var/cache/{dnf,yum} ;fi && \
  : "---------- ALL install finished ----------" 

### prep users
RUN set -xe && \
  groupadd -g ${APP_GID} ${APP_GRP} && \
  useradd -u ${APP_UID} -c "${APP_DESCRIPTION} User" -g ${APP_GRP} -s /sbin/nologin ${APP_USR} && \
  ## add asterisk user to wheel and apache group
  usermod -aG wheel,apache ${APP_USR} && \
  ## fix phpMyAdmin apache group permissions
  chmod g+w /var/lib/phpMyAdmin/temp

### build stage

## copy external sources files
#ADD build/ /usr/src/

## build asterisk
RUN set -xe && \
  . /etc/os-release && \
  ASTERISK_BUILD_DEPS=' \
    dmidecode \
    autoconf \
    automake \
    ncurses-devel \
    libxml2-devel \
    openssl-devel \
    newt-devel \
    kernel-devel \
    sqlite-devel \
    libuuid-devel \
    jansson-devel \
    binutils-devel \
    libedit-devel \
    svn \
    opus-devel \
    opusfile-devel \
    unixODBC-devel \
    ncurses-devel \
    libtermcap-devel \
    libtiff-devel \
    libjpeg-turbo-devel \
    audiofile-devel \
    uuid-devel \
    libtool-ltdl-devel \
    libsamplerate-devel \
    patch \
    libsndfile-devel \
    doxygen \
    bison \
    fftw-devel \
    flex \
    graphviz \
    libpq-devel \
    libxslt-devel \
    net-snmp-devel \
    unbound-devel \
    libcurl-devel \
    openldap-devel \
    popt-devel \
    bluez-libs-devel \
    gsm-devel \
    libsrtp-devel \
    libvorbis-devel \
    lua-devel \
    neon-devel \
    speex-devel \
    speexdsp-devel \
    codec2-devel \
    freetds-devel \
    portaudio-devel \
    radcli-devel \
    uriparser-devel \
    uw-imap-devel \
    xmlstarlet \
    sox-devel \
    ilbc-devel \
    python2-devel \
    python3-devel \
    libtool \
    cmake \
    libresample-devel \
    mariadb-devel \
    libuv-devel \
  ' && \
  \
  dnf -y install $ASTERISK_BUILD_DEPS && \
  \
  : "---------- START build spandsp ----------" && \
  cd /usr/src && \
  mkdir spandsp && \
  curl -fSL --connect-timeout 30 http://sources.buildroot.net/spandsp/spandsp-${SPANDSP_VER}.tar.gz | tar xz --strip 1 -C spandsp && \
  cd spandsp && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END build ----------" && \
  \
  : "---------- START build iksemel ----------" && \
  cd /usr/src && \
  mkdir iksemel && \
  curl -fSL --connect-timeout 30 https://github.com/holme-r/iksemel/archive/${IKSEMEL_VER}.tar.gz | tar xz --strip 1 -C iksemel && \
  cd iksemel && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END build ----------" && \
  \
  : "---------- START build ASTERISK ----------" && \
  ## @20210408 unreachable asterisk url
  ## http://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VER}.tar.gz
  ## @20210408 unreachable asterisk url - disable get_mp3_source.sh because need internet connection
  #./contrib/scripts/get_mp3_source.sh
  ## @20210414 reneabled get_mp3_source.sh
  #tar zxvf /usr/src/asterisk-mp3.tar.gz -C addons
  cd /usr/src && \
  mkdir asterisk && \
  curl -fSL --connect-timeout 30 https://github.com/asterisk/asterisk/archive/refs/tags/${ASTERISK_VER}.tar.gz | tar xz --strip 1 -C asterisk && \
  cd asterisk && \
  \
  ./contrib/scripts/get_mp3_source.sh && \
  ./configure --prefix=/usr --libdir=/usr/lib64 --with-pjproject-bundled --with-jansson-bundled --with-resample --with-ssl=ssl --with-srtp && \
  \
  make menuselect/menuselect menuselect-tree menuselect.makeopts && \
  \
  menuselect/menuselect \
    --enable-category MENUSELECT_ADDONS \
    --enable-category MENUSELECT_CHANNELS \
    --enable-category MENUSELECT_APPS \
    --enable-category MENUSELECT_CDR \
    --enable-category MENUSELECT_FORMATS \
    --enable-category MENUSELECT_FUNCS \
    --enable-category MENUSELECT_PBX \
    --enable-category MENUSELECT_RES \
    --enable-category MENUSELECT_CEL \
  \
  menuselect/menuselect \
    --enable BETTER_BACKTRACES \
    --enable DONT_OPTIMIZE \
    --enable app_confbridge \
    --enable app_macro \
    --enable app_mysql \
    --enable app_page \
    --enable binaural_rendering_in_bridge_softmix \
    --enable chan_motif \
    --enable codec_silk \
    --enable codec_opus \
    --enable format_mp3 \
    --enable res_ari \
    --enable res_chan_stats \
    --enable res_calendar \
    --enable res_calendar_caldav \
    --enable res_calendar_icalendar \
    --enable res_endpoint_stats \
    --enable res_fax \
    --enable res_fax_spandsp \
    --enable res_pktccops \
    --enable res_snmp \
    --enable res_srtp \
    --enable res_xmpp \
    --disable-category MENUSELECT_CORE_SOUNDS \
    --disable-category MENUSELECT_EXTRA_SOUNDS \
    --disable-category MENUSELECT_MOH \
    --disable BUILD_NATIVE \
    --disable app_meetme \
    --disable app_ivrdemo \
    --disable app_saycounted \
    --disable app_skel \
    --disable app_voicemail_imap \
    --disable cdr_pgsql \
    --disable cel_pgsql \
    --disable cdr_sqlite3_custom \
    --disable cel_sqlite3_custom \
    --disable cdr_mysql \
    --disable cdr_tds \
    --disable cel_tds \
    --disable cdr_radius \
    --disable cel_radius \
    --disable cdr_syslog \
    --disable chan_alsa \
    --disable chan_console \
    --disable chan_oss \
    --disable chan_mgcp \
    --disable chan_skinny \
    --disable chan_ooh323 \
    --disable chan_mobile \
    --disable chan_unistim \
    --disable res_ari_mailboxes \
    --disable res_digium_phone \
    --disable res_calendar_ews \
    --disable res_calendar_exchange \
    --disable res_stasis_mailbox \
    --disable res_mwi_external \
    --disable res_mwi_external_ami \
    --disable res_config_pgsql \
    --disable res_config_mysql \
    --disable res_config_ldap \
    --disable res_config_sqlite3 \
    --disable res_phoneprov \
    --disable res_pjsip_phoneprov_provider \
  && \
  make && \
  make install && \
  make install-headers && \
  make config && \
  make samples && \
  ldconfig && \
  : "---------- END build ----------" && \
  \
  : "---------- START build bcg729 ----------" && \
  cd /usr/src && \
  mkdir bcg729 && \
  curl -fSL --connect-timeout 30 https://github.com/BelledonneCommunications/bcg729/archive/${BCG729_VER}.tar.gz | tar xz --strip 1 -C bcg729 && \
  cd bcg729 && \
  cmake . -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_PREFIX_PATH=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END build ----------" && \
  \
  if [[ ${ASTERISK_VER%%.*} -le 18 ]]; then \
  : "---------- START build asterisk-g72x ----------" && \
  cd /usr/src && \
  mkdir asterisk-g72x && \
  curl -fSL --connect-timeout 30 https://bitbucket.org/arkadi/asterisk-g72x/get/${ASTERISK_G72X_VER}.tar.gz | tar xz --strip 1 -C asterisk-g72x && \
  cd asterisk-g72x && \
  ./autogen.sh && \
  ./configure --prefix=/usr --with-bcg729 --enable-penryn && \
  make && \
  make install && \
  ldconfig ;fi && \
  : "---------- END build ----------" && \
  \
  : "---------- START build sngrep ----------" && \
  cd /usr/src && \
  mkdir sngrep && \
  curl -fSL --connect-timeout 30 https://github.com/irontec/sngrep/archive/v${SNGREP_VER}.tar.gz | tar xz --strip 1 -C sngrep && \
  cd sngrep && \
  dnf -y install libpcap libpcap-devel && \
  ./bootstrap.sh && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END build ----------" && \
  \
  if [[ ${APP_DEBUG} -eq 0 ]]; then \
  : "---------- Clean temporary files ----------" && \
  dnf remove -y $ASTERISK_BUILD_DEPS && \
  dnf clean all && \
  rm -rf /var/cache/yum /tmp /usr/src && \
  mkdir -p /usr/src /tmp && chmod 1777 /tmp ;fi && \
  : "---------- ALL builds finished ----------" 

### NOTE: asterisk build
## to get the options passed above: menuselect/menuselect --list-options

## download freepbx and modules for offline install:
## php -r 'echo json_encode(simplexml_load_file("http://mirror1.freepbx.org/modules-15.0.xml"));' | jq
## curl -fSL --connect-timeout 30 http://mirror.freepbx.org/modules/packages/freepbx/freepbx-${FREEPBX_VER}.0-latest.tgz | tar xz --strip 1 -C freepbx
## curl -fSL https://github.com/FreePBX/framework/archive/release/${FREEPBX_VER_FRAMEWORK}.tar.gz| tar xfz - --strip 1 -C freepbx

## copy external sources files again
ADD build/ /usr/src/

## deploy freepbx
RUN set -xe && \
  \
  cd /usr/src && \
  mkdir freepbx && \
  curl -fSL --connect-timeout 30 http://mirror.freepbx.org/modules/packages/freepbx/freepbx-${FREEPBX_VER}.0-latest.tgz | tar xz --strip 1 -C freepbx && \
  cd freepbx && \
  ## download modules-*.xml file if not exist in local build dir
  if [[ -e "/usr/src/modules-${FREEPBX_VER}.0.xml" ]]; then cp "/usr/src/modules-${FREEPBX_VER}.0.xml" "/usr/src/freepbx/modules-${FREEPBX_VER}.0.xml"; else \
    curl -fSL --connect-timeout 30 http://mirror1.freepbx.org/modules-${FREEPBX_VER}.0.xml -o modules-${FREEPBX_VER}.0.xml \
  ;fi && \
  mkdir -p amp_conf/htdocs/admin/modules/_cache && \
  for MODULE in \
      announcement \
      arimanager \
      asteriskinfo \
      backup \
      calendar \
      callforward \
      callwaiting \
      cel \
      certman \
      cidlookup \
      contactmanager \
      daynight \
      donotdisturb \
      fax \
      filestore \
      findmefollow \
      iaxsettings \
      ivr \
      manager \
      miscapps \
      miscdests \
      parking \
      phonebook \
      presencestate \
      printextensions \
      queues \
      soundlang \
      timeconditions \
      userman \
      ucp \
      bulkhandler \
      speeddial \
      weakpasswords \
      pm2 \
      ; do \
  echo "---------- PreDownloading module for offline install: $MODULE ----------" && \
  mkdir -p amp_conf/htdocs/admin/modules/$MODULE && \
  MODULE_VER=$(php -r "echo json_encode(simplexml_load_file('modules-${FREEPBX_VER}.0.xml'));" | jq -r ".module[] | select(.rawname == \"${MODULE}\") | {version}".version) && \
  curl -sfSL --connect-timeout 30 http://mirror.freepbx.org/modules/packages/$MODULE/$MODULE-${MODULE_VER}.tgz | tar xz --strip 1 -C amp_conf/htdocs/admin/modules/$MODULE/ && \
  curl -sfSL --connect-timeout 30 http://mirror.freepbx.org/modules/packages/$MODULE/$MODULE-${MODULE_VER}.tgz.gpg -o amp_conf/htdocs/admin/modules/_cache/$MODULE-${MODULE_VER}.tgz.gpg \
  ; done && \
  su - asterisk -s /bin/bash -c "gpg --refresh-keys --keyserver hkp://keyserver.ubuntu.com:80" && \
  su - asterisk -s /bin/bash -c "gpg --import /usr/src/freepbx/amp_conf/htdocs/admin/libraries/BMO/1588A7366BD35B34.key" && \
  su - asterisk -s /bin/bash -c "gpg --import /usr/src/freepbx/amp_conf/htdocs/admin/libraries/BMO/3DDB2122FE6D84F7.key" && \
  su - asterisk -s /bin/bash -c "gpg --import /usr/src/freepbx/amp_conf/htdocs/admin/libraries/BMO/86CE877469D2EAD9.key" && \
  su - asterisk -s /bin/bash -c "gpg --import /usr/src/freepbx/amp_conf/htdocs/admin/libraries/BMO/9F9169F4B33B4659.key"

## install other components
RUN set -xe && \
  : "---------- START install izsynth by InitZero ----------" && \
  cd /usr/src && \
  mkdir -p izsynth && \
  curl -fSL --connect-timeout 30 https://github.com/ugoviti/izsynth/archive/${IZSYNTH_VER}.tar.gz | tar xz --strip 1 -C izsynth && \
  cp -a izsynth/izsynth /usr/local/bin/izsynth && \
  chmod 755 /usr/local/bin/izsynth && \
  : "---------- END install ----------" && \
  : "---------- START install Asterisk Zabbix Agents by InitZero ----------" && \
  cd /etc/zabbix/zabbix_agentd.d && \
  curl -fSL --connect-timeout 30 https://github.com/ugoviti/zabbix-templates/archive/${ZABBIX_TEMPLATE_VER}.tar.gz | tar xz --strip 3 zabbix-templates-${ZABBIX_TEMPLATE_VER}/asterisk/zabbix_agentd.d && \
  : "---------- END install ----------" && \
  ## enable module php 7.4 needed for FreePBX 16
  if [[ "${FREEPBX_VER}" = "16" ]]; then \
  : "---------- START install PHP IonCube Loader ----------" && \
  curl -fSL --connect-timeout 30 https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz | tar xz --strip 1 -C /usr/lib64/php/modules/ ioncube/ioncube_loader_lin_7.4.so && \
  echo "zend_extension=ioncube_loader_lin_7.4.so" >> /etc/php.ini && \
  : "---------- END install ----------" \
  ;fi

## set pemissions and sudo
RUN set -xe && \
  chown -R ${APP_USR}:${APP_GRP} \
    /etc/asterisk \
    /var/lib/asterisk \
    /var/spool/asterisk

### fixes and workarounds

## copy external sources files
ADD patch/ /usr/src/

## FIXME: fix for FreePBX 16 upgrade error (20211121: MUST be removed in a future release for better security)
## other problem when upgrading to FreePBX 16: https://issues.freepbx.org/browse/FREEPBX-22842
## references: https://wiki.freepbx.org/display/FOP/Non+Distro+-+Upgrade+to+FreePBX+16
RUN sed 's/@SECLEVEL=2/@SECLEVEL=1/' -i /etc/crypto-policies/back-ends/opensslcnf.config

### app ports
ENV APP_PORT_HTTP         80
ENV APP_PORT_HTTPS        443
ENV APP_PORT_IAX          4569
ENV APP_PORT_PJSIP        5060
ENV APP_PORT_SIP          5160
ENV APP_PORT_WEBRTC       8089
ENV APP_PORT_UCP_HTTP     8001
ENV APP_PORT_UCP_HTTPS    8003
ENV APP_PORT_AMI          8088
ENV APP_PORT_RTP_START    10000
ENV APP_PORT_RTP_END      10200
ENV APP_PORT_DHCP         67
ENV APP_PORT_TFTP         69
ENV APP_PORT_NTP          123
ENV APP_PORT_FOP2         4445
ENV APP_PORT_ZABBIX       10050

### exposed ports
EXPOSE \
  ${APP_PORT_HTTP}/tcp \
  ${APP_PORT_HTTPS}/tcp \
  ${APP_PORT_IAX}/tcp \
  ${APP_PORT_IAX}/udp \
  ${APP_PORT_PJSIP}/tcp \
  ${APP_PORT_PJSIP}/udp \
  ${APP_PORT_SIP}/tcp \
  ${APP_PORT_SIP}/udp \
  ${APP_PORT_WEBRTC}/tcp \
  ${APP_PORT_UCP_HTTP}/tcp \
  ${APP_PORT_UCP_HTTPS}/tcp \
  ${APP_PORT_AMI}/tcp \
  ${APP_PORT_RTP_START}-${APP_PORT_RTP_END}/tcp \
  ${APP_PORT_RTP_START}-${APP_PORT_RTP_END}/udp \
  ${APP_PORT_DHCP}/udp \
  ${APP_PORT_TFTP}/tcp \
  ${APP_PORT_TFTP}/udp \
  ${APP_PORT_NTP}/udp \
  ${APP_PORT_FOP2}/tcp \
  ${APP_PORT_ZABBIX}/tcp

### define volumes
#VOLUME [ "/var/spool/cron", "/var/www", "/etc/asterisk", "/var/lib/asterisk/sounds/custom" ]

## CI args
ARG APP_VER_BUILD
ARG APP_BUILD_COMMIT
ARG APP_BUILD_DATE

## CI envs
ENV APP_FQDN=""
ENV APP_VER_BUILD="${APP_VER_BUILD}"
ENV APP_BUILD_COMMIT="${APP_BUILD_COMMIT}"
ENV APP_BUILD_DATE="${APP_BUILD_DATE}"

## add files to container
ADD rootfs Dockerfile README.md /

## start the container process
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
