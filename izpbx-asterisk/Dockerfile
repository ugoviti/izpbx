ARG IMAGE_FROM=centos:8

FROM ${IMAGE_FROM}

MAINTAINER Ugo Viti <ugo.viti@initzero.it>

# default app versions used during build step
ARG APP_VER_MAJOR=16
ARG APP_VER_MINOR=9
ARG APP_VER_PATCH=0

## app name
ENV APP_NAME              "izpbx-asterisk"
ENV APP_DESCRIPTION       "izPBX Cloud Native Telephony System"

## app ports
ENV APP_PORT_HTTP         80
ENV APP_PORT_HTTPS        443
ENV APP_PORT_SIP          5060
ENV APP_PORT_PJSIP        5160
ENV APP_PORT_FOP          4445
ENV APP_PORT_RPT_START    19000
ENV APP_PORT_RPT_END      20000

## app users
ENV APP_UID               1000
ENV APP_GID               1000
ENV APP_USR               "asterisk"
ENV APP_GRP               "asterisk"

# full app version
ARG APP_VER=${APP_VER_MAJOR}.${APP_VER_MINOR}.${APP_VER_PATCH}

## app componets
# https://downloads.asterisk.org/pub/telephony/asterisk/
ARG ASTERISK_VER=${APP_VER}

ARG FREEPBX_VER=15.0

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
  . /etc/os-release && \
  \
  dnf -y install epel-release && \
  \
  [[ $VERSION_ID -le 7 ]] && \
    ln -s /usr/bin/yum /usr/bin/dnf && \
    rpm -Uhv https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm && \
    rpm -Uvh https://rpms.remirepo.net/enterprise/remi-release-7.rpm && \
    yum-config-manager --enable remi 1>/dev/null && \
    yum-config-manager --enable remi-php72 1>/dev/null ; \
  \
  [[ $VERSION_ID -ge 8 ]] && \
    # install external repositories
    rpm -Uvh https://rpms.remirepo.net/enterprise/remi-release-8.rpm && \
    rpm -Uhv https://download1.rpmfusion.org/free/el/rpmfusion-free-release-8.noarch.rpm && \
    rpm -Uhv https://forensics.cert.org/cert-forensics-tools-release-el8.rpm && \
    \
    dnf -y install dnf-plugins-core && \
    dnf config-manager --set-enabled PowerTools remi && \
    dnf -y module disable php && \
    dnf -y module enable php:remi-7.3  && \
  \
  dnf upgrade -y && \
  dnf -y install \
    ffmpeg \
    lame \
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
    php \
    php-mysqlnd \
    php-process \
    php-pear \
    php-mbstring \
    php-xml \
    php-gd \
    php-curl \
    mariadb \
    postfix \
    diffutils \
    unzip \
    zip \
    uriparser \
  && \
  : "---------- clean temporary files ----------" && \
  echo TEST;
#  dnf clean all && \
#  rm -rf /var/cache/yum

## prep
RUN set -xe && \
  groupadd -g ${APP_GID} ${APP_GRP} && \
  useradd -u ${APP_UID} -c "${APP_DESCRIPTION} User" -g ${APP_GRP} -s /sbin/nologin ${APP_USR} && \
  usermod -aG wheel ${APP_USR}
  
## build
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
  echo TEST;

RUN set -xe && \
  : "---------- START Build libresample ----------" && \
  cd /usr/src && \
  tar zxf libresample-0.1.3.tgz --strip 1 -C /usr/src/libresample/ && \
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
  curl -fSL --connect-timeout 30 http://sources.buildroot.net/spandsp/spandsp-${SPANDSP_VER}.tar.gz | tar xz --strip 1 -C /usr/src/spandsp/ && \
  cd spandsp && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END Build ----------" && \
  \
  : "---------- START Build ASTERISK ----------" && \
  cd /usr/src && \
  curl -fSL --connect-timeout 30 https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VER}.tar.gz | tar xz -C /usr/src/asterisk && \
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
  && \
  make && \
  \
  cd /usr/src/asterisk* && \
  make install && \
  make install-headers && \
  make config && \
  make samples && \
  ldconfig && \
  : "---------- END Build ----------" && \
  \
  : "---------- START Build bcg729 ----------" && \
  cd /usr/src && \
  curl -fSL --connect-timeout 30 https://github.com/BelledonneCommunications/bcg729/archive/${BCG729_VER}.tar.gz | tar xz --strip 1 -C /usr/src/bcg729 && \
  cd bcg729 && \
  ./autogen.sh && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END Build ----------" && \
  \
  : "---------- START Build asterisk-g72x ----------" && \
  [[ $APP_VER_MAJOR -le 17 ]] && \
  cd /usr/src && \
  curl -fSL --connect-timeout 30 https://bitbucket.org/arkadi/asterisk-g72x/get/master.tar.gz | tar xz --strip 1 -C /usr/src/asterisk-g72x && \
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
  curl -fSL --connect-timeout 30 https://github.com/irontec/sngrep/releases/download/v${SNGREP_VER}/sngrep-${SNGREP_VER}.tar.gz | tar xz --strip 1 -C /usr/src/sngrep && \
  cd sngrep && \
  dnf -y install libpcap libpcap-devel && \
  ./bootstrap.sh && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END Build ----------" && \
  \
#   : "---------- clean temporary files ----------" && \
#   rm -rf /usr/src && mkdir -p /usr/src && \
#   dnf -y remove $ASTERISK_BUILD_DEPS \
#     -x diffutils \
#     -x unzip \
#     -x zip \
#     -x uriparser \
#   && \
#   dnf clean all && \
#   rm -rf /var/cache/yum && \
  : "---------- ALL Builds Finished ----------"

# NOTE: asterisk build
# to get the options passed below: menuselect/menuselect --list-options

RUN set -xe && \
  : "---------- Install FOP2 ----------" && \
  cd /usr/src && \
  curl -fSL --connect-timeout 30 http://download2.fop2.com/fop2-${FOP2_VER}-centos-x86_64.tgz | tar xz --strip 1 -C /usr/src/fop2 && \
  cd fop2 && \
#  ./configure --prefix=/usr && \
#  make && \
#  make install && \
#  ldconfig && \
  : "---------- END Install ----------"

# set pemissions
RUN set -xe && \
  chown -R ${APP_USR}:${APP_GRP} \
    /etc/asterisk \
    /var/lib/asterisk \
    /var/spool/asterisk

# download freepbx
RUN set -xe && \
  cd /usr/src && \
  curl -fSL --connect-timeout 30 http://mirror.freepbx.org/modules/packages/freepbx/freepbx-${FREEPBX_VER}-latest.tgz | tar xz --strip 1 -C /usr/src/freepbx && \
  cd /usr/src/freepbx && \
  for MODULE in \
      announcement \
      asteriskinfo \
      backup \
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
      queues \
      timeconditions \
      ; do \
  mkdir -p /usr/src/freepbx/amp_conf/htdocs/admin/modules/$MODULE/ && \
  echo "---> PreDownloading module for offline install: $MODULE" && \
  curl -sfSL --connect-timeout 30 https://github.com/FreePBX/$MODULE/archive/release/${FREEPBX_VER}.tar.gz | tar xz -C /usr/src/freepbx/amp_conf/htdocs/admin/modules/$MODULE/ --strip-components=1 \
  ; done

# exposed ports
EXPOSE ${APP_PORT_HTTP}/tcp ${APP_PORT_HTTPS}/tcp ${APP_PORT_SIP}/tcp ${APP_PORT_PJSIP}/tcp ${APP_PORT_FOP}/tcp ${APP_PORT_RPT_START}/tcp ${APP_PORT_RPT_END}/tcp

# define volumes
#VOLUME [ "/var/spool/cron", "/var/www", "/etc/asterisk", "/var/lib/asterisk/sounds/custom" ]

# add files to container
ADD Dockerfile filesystem VERSION README.md /

# start the container process
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
