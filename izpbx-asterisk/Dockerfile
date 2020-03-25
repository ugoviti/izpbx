ARG IMAGE_FROM=centos:8

FROM ${IMAGE_FROM}

MAINTAINER Ugo Viti <ugo.viti@initzero.it>

# default app versions used during build step
ARG APP_VER_MAJOR=16
ARG APP_VER_MINOR=9
ARG APP_VER_PATCH=0
ARG APP_VER_BUILD

## app name
ENV APP_NAME              "izpbx-asterisk"
ENV APP_DESCRIPTION       "izPBX Cloud Native Telephony System"

## app ports
ENV APP_PORT_HTTP         80
ENV APP_PORT_HTTPS        443
ENV APP_PORT_IAX          4569
ENV APP_PORT_SIP          5060
ENV APP_PORT_PJSIP        5160
ENV APP_PORT_FOP          4445
ENV APP_PORT_RTP_START    10000
ENV APP_PORT_RTP_END      10200

## app users
ENV APP_UID               1000
ENV APP_GID               1000
ENV APP_USR               "asterisk"
ENV APP_GRP               "asterisk"

# full app version
ENV APP_VER=${APP_VER_MAJOR}.${APP_VER_MINOR}.${APP_VER_PATCH}
ENV APP_VER_BUILD=${APP_VER_BUILD}

## app componets
# https://downloads.asterisk.org/pub/telephony/asterisk/
ARG ASTERISK_VER=${APP_VER}

ARG FREEPBX_VER=15.0
#ARG FREEPBX_VER_FRAMEWORK=15.0.16.46

# http://sources.buildroot.net/spandsp/
ARG SPANDSP_VER=20180108

# https://github.com/BelledonneCommunications/bcg729/releases
ARG BCG729_VER=1.0.4

# https://www.fop2.com/download.php
ARG FOP2_VER=2.31.27

# https://github.com/irontec/sngrep/releases
ARG SNGREP_VER=1.4.6

## install
RUN set -xe && \
  # import system information vars
  . /etc/os-release && \
  \
  # install epel repository
  dnf -y install epel-release && \
  \
  # centos 7 specific (legacy)
  [[ $VERSION_ID -le 7 ]] && \
    ln -s /usr/bin/yum /usr/bin/dnf && \
    rpm -Uhv https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm && \
    rpm -Uvh https://rpms.remirepo.net/enterprise/remi-release-7.rpm && \
    yum-config-manager --enable remi 1>/dev/null && \
    yum-config-manager --enable remi-php73 1>/dev/null ; \
  \
  # centos 8 specific
  [[ $VERSION_ID -ge 8 ]] && \
    # repo for php 7.x
    rpm -Uvh https://rpms.remirepo.net/enterprise/remi-release-8.rpm && \
    # repo for ffmpeg
    rpm -Uhv https://download1.rpmfusion.org/free/el/rpmfusion-free-release-8.noarch.rpm && \
    # repo for lame command
    rpm -Uhv https://forensics.cert.org/cert-forensics-tools-release-el8.rpm && \
    # repo for posfix 3.5
    rpm -Uhv http://mirror.ghettoforge.org/distributions/gf/el/8/gf/x86_64/gf-release-8-11.gf.el8.noarch.rpm && \
    \
    # install dnf plugins
    dnf -y install dnf-plugins-core && \
    # enable extra repository
    dnf config-manager --set-enabled \
      PowerTools \
      remi \
      rpmfusion-free-updates \
      forensics \
      gf-plus \
      gf-testing \
    && \
    # install not upstream packages
    # postfix > 3.4.x needed for docker logging to stdout
    dnf -y install \
      lame \
      postfix3 \
    && \
    # FIXME: forensics repo make conflicts with certbot, so we used it only to install lame
    dnf config-manager --set-disabled forensics && \
    # enable php 7.3 module
    dnf module disable -y php && \
    dnf module enable -y php:remi-7.3 ; \
  \
  # upgrade the system
  dnf upgrade -y && \
  # install mandatory packages
  dnf -y install \
    ffmpeg \
    rsync \
    net-tools \
    iftop \
    lsof \
    strace \
    tcpdump \
    supervisor \
    curl \
    opus \
    whois \
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
    opus \
    libtool \
    ncurses \
    libtiff \
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
    certbot \
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
  && \
  \
  : "---------- generate selfsigned certificate for 100 years duration ----------" && \
  openssl req -subj '/CN=izpbx/O=InitZero/C=IT' -new -newkey rsa:2048 -sha256 -days 36500 -nodes -x509 -keyout /etc/pki/tls/private/localhost.key -out /etc/pki/tls/certs/localhost.crt && \
  : "---------- clean temporary files ----------" && \
  dnf clean all && \
  rm -rf /var/cache/yum

## prep
RUN set -xe && \
  groupadd -g ${APP_GID} ${APP_GRP} && \
  useradd -u ${APP_UID} -c "${APP_DESCRIPTION} User" -g ${APP_GRP} -s /sbin/nologin ${APP_USR} && \
  usermod -aG wheel ${APP_USR}
  
## build

# Development Debug mode
ARG APP_DEBUG=0

# copy external sources files
ADD build/ /usr/src/

RUN set -xe && \
  . /etc/os-release && \
  ASTERISK_BUILD_DEPS=' \
    dmidecode \
    gcc-c++ \
    autoconf \
    automake \
    ncurses-devel \
    libxml2-devel \
    make \
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
    unixODBC-devel \
    ncurses-devel \
    libtermcap-devel \
    libtiff-devel \
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
    libical-devel \
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
    python3-devel \
  ' ; \
  [[ $VERSION_ID -le 7 ]] && ASTERISK_BUILD_DEPS+="mysql-devel" ; \
  [[ $VERSION_ID -ge 8 ]] && ASTERISK_BUILD_DEPS+="mariadb-devel" ; \  
  \
  dnf -y install $ASTERISK_BUILD_DEPS && \
  : "---------- START Build libresample ----------" && \
  cd /usr/src && \
  mkdir libresample && \
  tar zxf libresample-0.1.3.tgz --strip 1 -C libresample && \
  cd libresample && \
  patch -s --fuzz=0 --no-backup-if-mismatch < ../libresample_shared-libs.patch && \
  mkdir pkgconfig && \
  cp ../libresample.pc pkgconfig/ && \
  ./configure --prefix=/usr && \
  make VERBOSE=1 && \
  cp tests/resample-sndfile /usr/bin/ && \
  cp libresample.so.0 /usr/lib64/ && \
  cp include/libresample.h /usr/include/ && \
  cp libresample.so /usr/lib64/ && \
  cp pkgconfig/libresample.pc /usr/lib64/pkgconfig/ && \
  ldconfig && \
  : "---------- END Build ----------" && \
  \
  : "---------- START Build spandsp ----------" && \
  cd /usr/src && \
  mkdir spandsp && \
  curl -fSL --connect-timeout 30 http://sources.buildroot.net/spandsp/spandsp-${SPANDSP_VER}.tar.gz | tar xz --strip 1 -C spandsp && \
  cd spandsp && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END Build ----------" && \
  \
  : "---------- START Build ASTERISK ----------" && \
  cd /usr/src && \
  mkdir asterisk && \
  curl -fSL --connect-timeout 30 https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VER}.tar.gz | tar xz --strip 1 -C asterisk && \
  cd asterisk && \
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
    --enable app_meetme \
    --enable app_page \
    --enable chan_mgcp \
    --enable chan_motif \
    --enable res_ari \
    --enable res_snmp \
    --enable res_srtp \
    --enable res_endpoint_stats \
    --enable res_chan_stats \
    --enable res_calendar \
    --enable res_calendar_caldav \
    --enable res_calendar_icalendar \
    --enable res_pktccops \
    --enable codec_silk \
    --enable codec_opus \
    --enable app_confbridge \
    --enable res_fax \
    --enable res_fax_spandsp \
    --enable app_macro \
    --enable format_mp3 \
    --enable res_phoneprov \
    --disable-category MENUSELECT_CORE_SOUNDS \
    --disable-category MENUSELECT_EXTRA_SOUNDS \
    --disable-category MENUSELECT_MOH \
    --disable BUILD_NATIVE \
    --disable app_ivrdemo \
    --disable app_saycounted \
    --disable app_skel \
    --disable cdr_pgsql \
    --disable cel_pgsql \
    --disable cel_sqlite3_custom \
    --disable cel_tds \
    --disable cel_radius \
    --disable cdr_syslog \
    --disable chan_alsa \
    --disable chan_oss \
    --disable chan_skinny \
    --disable chan_ooh323 \
    --disable chan_mobile \
    --disable chan_unistim \
    --disable res_digium_phone \
    --disable res_calendar_ews \
    --disable res_calendar_exchange \
    --disable res_stasis_mailbox \
    --disable res_mwi_external \
    --disable res_mwi_external_ami \
    --disable res_config_pgsql \
    --disable res_config_mysql \
    --disable res_phoneprov \
    --disable res_pjsip_phoneprov_provider \
  && \
  make && \
  make install && \
  make install-headers && \
  make config && \
  make samples && \
  ldconfig && \
  : "---------- END Build ----------" && \
  \
  : "---------- START Build bcg729 ----------" && \
  cd /usr/src && \
  mkdir bcg729 && \
  curl -fSL --connect-timeout 30 https://github.com/BelledonneCommunications/bcg729/archive/${BCG729_VER}.tar.gz | tar xz --strip 1 -C bcg729 && \
  cd bcg729 && \
  ./autogen.sh && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END Build ----------" && \
  \
  [[ $APP_VER_MAJOR -le 17 ]] && \
  : "---------- START Build asterisk-g72x ----------" && \
  cd /usr/src && \
  mkdir asterisk-g72x && \
  curl -fSL --connect-timeout 30 https://bitbucket.org/arkadi/asterisk-g72x/get/master.tar.gz | tar xz --strip 1 -C asterisk-g72x && \
  cd asterisk-g72x && \
  ./autogen.sh && \
  ./configure --prefix=/usr --with-bcg729 --enable-penryn && \
  make && \
  make install && \
  ldconfig ; \
  : "---------- END Build ----------" && \
  \
  : "---------- START Build sngrep ----------" && \
  cd /usr/src && \
  mkdir sngrep && \
  curl -fSL --connect-timeout 30 https://github.com/irontec/sngrep/releases/download/v${SNGREP_VER}/sngrep-${SNGREP_VER}.tar.gz | tar xz --strip 1 -C sngrep && \
  cd sngrep && \
  dnf -y install libpcap libpcap-devel && \
  ./bootstrap.sh && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END Build ----------" && \
  \
  [[ $APP_DEBUG -eq 0 ]] && \
  : "---------- Clean temporary files ----------" && \
  dnf -y remove $ASTERISK_BUILD_DEPS \
    -x diffutils \
    -x unzip \
    -x zip \
    -x uriparser \
   && \
   dnf clean all && \
   rm -rf /var/cache/yum /tmp /usr/src && \
   mkdir -p /usr/src /tmp && chmod 1777 /tmp ; \
   : "---------- ALL builds finished ----------" 

# NOTE: asterisk build
# to get the options passed below: menuselect/menuselect --list-options

RUN set -xe && \
  : "---------- Install FOP2 ----------" && \
  cd /usr/src && \
  mkdir fop2 && \
  curl -fSL --connect-timeout 30 http://download2.fop2.com/fop2-${FOP2_VER}-centos-x86_64.tgz | tar xz --strip 1 -C fop2 && \
  cd fop2 && \
#  ./configure --prefix=/usr && \
#  make && \
#  make install && \
#  ldconfig && \
  : "---------- END Install ----------"

## download freepbx and modules for offline install
# modules xml url: http://mirror1.freepbx.org/modules-15.0.xml
# php -r 'echo json_encode(simplexml_load_file("modules-15.0.xml"));' | jq
# curl -fSL --connect-timeout 30 http://mirror.freepbx.org/modules/packages/freepbx/freepbx-${FREEPBX_VER}-latest.tgz | tar xz --strip 1 -C freepbx
# curl -fSL https://github.com/FreePBX/framework/archive/release/${FREEPBX_VER_FRAMEWORK}.tar.gz| tar xfz - --strip 1 -C freepbx

RUN set -xe && \
  cd /usr/src && \
  mkdir freepbx && \
  curl -fSL --connect-timeout 30 http://mirror.freepbx.org/modules/packages/freepbx/freepbx-${FREEPBX_VER}-latest.tgz | tar xz --strip 1 -C freepbx && \
  cd freepbx && \
  curl -fSL --connect-timeout 30 http://mirror1.freepbx.org/modules-${FREEPBX_VER}.xml -o modules-${FREEPBX_VER}.xml && \
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
      ; do \
  echo "---------- PreDownloading module for offline install: $MODULE ----------" && \
  mkdir -p amp_conf/htdocs/admin/modules/$MODULE && \
  MODULE_VER=$(php -r "echo json_encode(simplexml_load_file('modules-${FREEPBX_VER}.xml'));" | jq -r ".module[] | select(.rawname == \"${MODULE}\") | {version}".version) && \
  curl -sfSL --connect-timeout 30 http://mirror.freepbx.org/modules/packages/$MODULE/$MODULE-${MODULE_VER}.tgz | tar xz --strip 1 -C amp_conf/htdocs/admin/modules/$MODULE/ && \
  curl -sfSL --connect-timeout 30 http://mirror.freepbx.org/modules/packages/$MODULE/$MODULE-${MODULE_VER}.tgz.gpg -o amp_conf/htdocs/admin/modules/_cache/$MODULE-${MODULE_VER}.tgz.gpg \
  ; done && \
  su - asterisk -s /bin/bash -c "gpg --refresh-keys --keyserver hkp://keyserver.ubuntu.com:80" && \
  su - asterisk -s /bin/bash -c "gpg --import /usr/src/freepbx/amp_conf/htdocs/admin/libraries/BMO/1588A7366BD35B34.key" && \
  su - asterisk -s /bin/bash -c "gpg --import /usr/src/freepbx/amp_conf/htdocs/admin/libraries/BMO/3DDB2122FE6D84F7.key" && \
  su - asterisk -s /bin/bash -c "gpg --import /usr/src/freepbx/amp_conf/htdocs/admin/libraries/BMO/86CE877469D2EAD9.key" && \
  su - asterisk -s /bin/bash -c "gpg --import /usr/src/freepbx/amp_conf/htdocs/admin/libraries/BMO/9F9169F4B33B4659.key"

# set pemissions
RUN set -xe && \
  chown -R ${APP_USR}:${APP_GRP} \
    /etc/asterisk \
    /var/lib/asterisk \
    /var/spool/asterisk
  
# exposed ports
EXPOSE \
  ${APP_PORT_HTTP}/tcp \
  ${APP_PORT_HTTPS}/tcp \
  ${APP_PORT_FOP}/tcp \
  ${APP_PORT_IAX}/tcp \
  ${APP_PORT_SIP}/tcp \
  ${APP_PORT_PJSIP}/tcp \
  ${APP_PORT_IAX}/udp \
  ${APP_PORT_SIP}/udp \
  ${APP_PORT_PJSIP}/udp \
  ${APP_PORT_RTP_START}-${APP_PORT_RTP_END}/udp

# define volumes
#VOLUME [ "/var/spool/cron", "/var/www", "/etc/asterisk", "/var/lib/asterisk/sounds/custom" ]

# add files to container
ADD Dockerfile filesystem README.md /

# other variables
ENV APP_FQDN ""

# start the container process
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
