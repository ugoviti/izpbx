ARG RHEL_VER=8
ARG IMAGE_FROM=rockylinux/rockylinux:${RHEL_VER}
FROM ${IMAGE_FROM}

LABEL maintainer="Ugo Viti <u.viti@wearequantico.it>"

### default app args used during build step
#ARG APP_VER_MAJOR=
#ARG APP_VER_MINOR=
#ARG APP_VER_PATCH=

## full app version
#ARG APP_VER=${APP_VER_MAJOR}.${APP_VER_MINOR}.${APP_VER_PATCH}
ARG APP_VER=dev
ENV APP_VER=${APP_VER}
ARG RHEL_VER=8
# PHP versions: FreePBX15 <= 7.2, FreePBX16 >= 7.4
ARG PHP_VER=7.4

# architecture dependent vars used in build stage
ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETVARIANT
ARG TARGETOS

### components app versions
## NOTE: every source tarball downloaded at build time is verified with the <NAME>_SHA256 below
##       (sha256 of the exact URL used by the build). Update it together with the version.
##       GitHub auto-generated archives (archive/<ref>.tar.gz) are not guaranteed byte-stable by GitHub:
##       if a checksum suddenly fails without a version change, re-download and re-check before updating it.

## https://downloads.asterisk.org/pub/telephony/asterisk/releases
## (official tarball, sha256 from asterisk-${ASTERISK_VER}.sha256 published next to it)
ARG ASTERISK_VER=20.21.0
ARG ASTERISK_SHA256=13fd6e8f1fbb19a3174af82a388dd72c87eb2c92d32fca83c4d51bfab03f686a

## https://github.com/FreePBX/core/tags
## (only major version)
ARG FREEPBX_VER=16

## https://www.fop2.com/download.php
## FOP2 is downloaded and installed at runtime by the entrypoint from
## https://download2.fop2.com/fop2-${FOP2_VER}-centos-x86_64.tgz and verified against FOP2_SHA256
## (x86_64 only: FOP2 ships aarch64 only as a Debian 12 package)
ARG FOP2_VER=2.31.53
ENV FOP2_SHA256=63b6a0ec011a41eaf7f70fda63282df501f27a67ac6ad8eec76e978f7025ace3

## https://sources.buildroot.net/spandsp
ARG SPANDSP_VER=3.0.0-6ec23e5a7e
ARG SPANDSP_SHA256=a11beed46b488a4cac3b0c42042ad28448bcee4c0027a82d5449180bbb178836

## https://github.com/holme-r/iksemel/releases
ARG IKSEMEL_VER=1.5.1.3
ARG IKSEMEL_SHA256=0043f710e1635bddcb67a6ee94472556a65cc5b404817bb8424837864d5fc589

## https://sourceforge.net/projects/xmlstar/files/xmlstarlet/
ARG XMLSTARLET_VER=1.6.1
ARG XMLSTARLET_SHA256=15d838c4f3375332fd95554619179b69e4ec91418a3a5296e7c631b7ed19e7ca

## https://github.com/BelledonneCommunications/bcg729/tags
ARG BCG729_VER=1.1.2
ARG BCG729_SHA256=9c22d98c2debc1e37163b8a703f05278ad5d9c03f1c6b373629d8a072092184a

## https://github.com/arkadijs/asterisk-g72x/commits/master
## (no releases: pinned to a master commit, 2026-09-07)
ARG ASTERISK_G72X_VER=5106838f3aabf8fe09fa3780a8e9d3ed4c2a0063
ARG ASTERISK_G72X_SHA256=2f0b21439f5b0f3bb83393b683cdc57876ebe94beb50da97a9b7730a31731c32

## https://github.com/wdoekes/asterisk-chan-dongle/commits/master
## (no releases: pinned to a master commit, 2026-09-19)
## fallback if it doesn't build: the previously used fork, pinned to its last commit (2022-07-12):
##   ASTERISK_CHAN_DONGLE_REPO=shalzz/asterisk-chan-dongle
##   ASTERISK_CHAN_DONGLE_VER=7268f64fa7438b10471a6e566cac834eda97815a
##   (and set ASTERISK_CHAN_DONGLE_SHA256 to the sha256 of its archive)
ARG ASTERISK_CHAN_DONGLE_REPO=wdoekes/asterisk-chan-dongle
ARG ASTERISK_CHAN_DONGLE_VER=7db8e75bc2b7c81b173e1bb465e376e64a70319a
ARG ASTERISK_CHAN_DONGLE_SHA256=2eeef1b3d1e7ffb1fbe1c36affef0c5a794ed2be5b477c1313f922871c005eab

## https://github.com/ugoviti/izsynth
ARG IZSYNTH_VER=5.0
ARG IZSYNTH_SHA256=8c320d613c271ab768c75f12368dd1ec490e901c1547faa605a7d0e7d1b254bc

## https://www.zabbix.com/download_agents
ENV ZABBIX_VER=7.0
ENV ZABBIX_REL=${ZABBIX_VER}-1

## https://github.com/ugoviti/zabbix-templates/commits/main
## (pinned to a main commit, 2025-04-26)
ARG ZABBIX_TEMPLATE_VER=862da4c9f11d51509d1392bfe9fcf055b8d0d20b
ARG ZABBIX_TEMPLATE_SHA256=775b6cefe1596040703d9d83d5faf250ced1a924fb156d67a3828d8426b22b8f

## https://github.com/irontec/sngrep/releases
## (release asset sngrep-${SNGREP_VER}.tar.gz)
ARG SNGREP_VER=1.9.0
ARG SNGREP_SHA256=db1d45a27c5682a83ac9caedbca9a0af530c6da744b645d3f9b336d7ad2fc6a9
ARG SNGREP_XTRA_BUILDCONFIG=""

## https://www.ioncube.com/loaders.php
## versioned tarball (ioncube_loaders_lin_<arch>_<version>.tar.gz), one sha256 per architecture
ARG IONCUBE_VER=15.5.1
ARG IONCUBE_SHA256_X86_64=739962bd012e77ee82bf01f77a9641f050e4be057f0a5d1a95fe59ce11fd62ba
ARG IONCUBE_SHA256_AARCH64=b091974aa80a76bd798d71fd5209797d93749b0be13eaff978a3dbe0106b9e1f

## GPG keys of the third party repositories (full fingerprints, checked before rpm --import)
## remi: https://rpms.remirepo.net/RPM-GPG-KEY-remi2018
ARG REMI_GPG_FPR=6B38FEA7231F87F52B9CA9D8555097595F11735A
## zabbix: https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX-B5333005
ARG ZABBIX_GPG_FPR=4C3D6F2CC75F5146754FC374D913219AB5333005
## rpmfusion: https://download1.rpmfusion.org/{free,nonfree}/el/RPM-GPG-KEY-rpmfusion-{free,nonfree}-el-8
ARG RPMFUSION_FREE_GPG_FPR=837935CD19E123AA7F8A8E69979F0C69158B3811
ARG RPMFUSION_NONFREE_GPG_FPR=CF9FD59F61D6612146CDAC8E14B6792DBDDA8475

### define variables for later container usage
ENV ASTERISK_VER=${ASTERISK_VER}
ENV FREEPBX_VER=${FREEPBX_VER}
ENV FOP2_VER=${FOP2_VER}

## app name
ENV APP_NAME="izpbx-asterisk"
ENV APP_DESCRIPTION="izPBX Cloud Native Telephony System"

## set default timezone
ENV TZ="UTC"

## app users
ENV APP_UID=1000
ENV APP_GID=1000
ENV APP_USR="asterisk"
ENV APP_GRP="asterisk"

## development debug mode (don't delete development and build dependencies on filesystem)
ARG APP_DEBUG=0

## install ad hoc additional packages as defined via --build-arg next to regular dependencies
ARG APP_INSTALL_EXTRA=""

## OS updates cache buster: a new value (eg. the ISO week set by the weekly rebuild workflow)
## invalidates the STEP 1 layer, so "dnf upgrade" runs again instead of reusing the cached layer
ARG OS_UPDATE_STAMP=""

### STEP 1: INSTALL BASE PACKAGES
RUN set -xe && \
  : "os update stamp: ${OS_UPDATE_STAMP}" && \
  ## import system information vars
  . /etc/os-release && export OSARCH=$(uname -m) && \
  \
  ## install packages
  APP_INSTALL_DEPS='\
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
    libproxy \
    net-snmp-agent-libs \
    lm_sensors-libs \
    libical \
    libical-devel \
    icu \
    gcc-c++ \
    make \
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
    chrony \
    postfix \
    phpMyAdmin \
    zabbix-agent2 \
    zabbix-sender \
    ffmpeg \
    libuv \
    patch \
    iproute \
    bc \
    chkconfig \
    libpcap \
    gmime \
    msmtp \
    mtr \
    vim-enhanced \
    lame-libs \
    libev \
    libwebsockets \
  ' && \
  # NOTE: postfix > 3.4.x is required for docker logging to stdout
  if [[ ${RHEL_VER} -le 8 ]]; then \
  # <= el8 (deprecated in el9)
  APP_INSTALL_DEPS_EXTRA='\
    libmodman \
    pakchois \
    incron \
    python2 \
  ' \
  ;fi && \
  \
  ## manage dnf rhel minimal image variant
  if command -v microdnf 1>/dev/null; then export RHEL_MINIMAL="true" ;else export RHEL_MINIMAL="false" ;fi && \
  if [[ "$RHEL_MINIMAL" = "true" && ! -e "/usr/bin/dnf" ]]; then ln -s /usr/bin/microdnf /usr/bin/dnf ;fi && \
  \
  ## dnf extra options
  export DNF_OPTS+=" -y --nodocs" && \
  echo "ip_resolve=4" >> /etc/dnf/dnf.conf && \
  ## enable epel repository (epel-release comes from the distro repo, signed with the Rocky key)
  dnf install ${DNF_OPTS} epel-release && \
  \
  ## third party repository release packages: import the repo GPG key (only if its fingerprint matches the pinned one),
  ## then download the release rpm and install it only if its signature is valid
  importGpgKey() { curl -fsSL --connect-timeout 30 -o /tmp/rpm-gpg-key.asc "$1" && gpg --with-colons --show-keys /tmp/rpm-gpg-key.asc | awk -F: '/^fpr/{print $10}' | grep -qx "$2" && rpm --import /tmp/rpm-gpg-key.asc && rm -f /tmp/rpm-gpg-key.asc; } && \
  installSignedRpm() { curl -fsSL --connect-timeout 30 -o /tmp/signed.rpm "$1" && rpm -K /tmp/signed.rpm | grep -q ': digests signatures OK$' && rpm -Uvh /tmp/signed.rpm && rm -f /tmp/signed.rpm; } && \
  importGpgKey https://rpms.remirepo.net/RPM-GPG-KEY-remi2018 ${REMI_GPG_FPR} && \
  importGpgKey https://repo.zabbix.com/RPM-GPG-KEY-ZABBIX-B5333005 ${ZABBIX_GPG_FPR} && \
  importGpgKey https://download1.rpmfusion.org/free/el/RPM-GPG-KEY-rpmfusion-free-el-${RHEL_VER} ${RPMFUSION_FREE_GPG_FPR} && \
  importGpgKey https://download1.rpmfusion.org/nonfree/el/RPM-GPG-KEY-rpmfusion-nonfree-el-${RHEL_VER} ${RPMFUSION_NONFREE_GPG_FPR} && \
  ## repo for phpMyAdmin
  installSignedRpm https://rpms.remirepo.net/enterprise/remi-release-${RHEL_VER}.rpm && \
  ## repo for zabbix agent
  installSignedRpm https://repo.zabbix.com/zabbix/${ZABBIX_VER}/rocky/${RHEL_VER}/x86_64/zabbix-release-${ZABBIX_REL}.el${RHEL_VER}.noarch.rpm && \
  ## repo for ffmpeg command
  installSignedRpm https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${RHEL_VER}.noarch.rpm && \
  installSignedRpm https://download1.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-${RHEL_VER}.noarch.rpm && \
  \
  ## enable extra repository via dnf command line
  export DNF_OPTS+=" --enablerepo=epel" && \
  export DNF_OPTS+=" --enablerepo=remi" && \
  export DNF_OPTS+=" --enablerepo=rpmfusion-free-updates" && \
  export DNF_OPTS+=" --enablerepo=rpmfusion-nonfree-updates" && \
  if [[ ${RHEL_VER} -le 8 ]]; then export DNF_OPTS+=" --enablerepo=powertools" ;fi && \
  if [[ ${RHEL_VER} -ge 9 ]]; then export DNF_OPTS+=" --enablerepo=crb" ;fi && \
  #if [[ ${RHEL_VER} -le 8 ]]; then export DNF_OPTS+=" --enablerepo=okay" ;fi && \
  \
  ## enable specific module php needed for FreePBX
  : "---------- Enable PHP ${PHP_VER} ----------" && \
  dnf module reset php -y && \
  dnf module enable php:${PHP_VER} -y && \
  \
  ## upgrade the system
  dnf upgrade ${DNF_OPTS} && \
  ## install mandatory packages
  dnf install ${DNF_OPTS} ${APP_INSTALL_DEPS} ${APP_INSTALL_DEPS_EXTRA} ${APP_INSTALL_EXTRA} \
  && \
  ## install extra packages (lame from the Rocky devel repo: signed with the Rocky key already in the image)
  installSignedRpm https://dl.rockylinux.org/pub/rocky/${RHEL_VER}/devel/${OSARCH}/os/Packages/l/lame-3.100-6.el${RHEL_VER}.${OSARCH}.rpm && \
  if [[ "$RHEL_MINIMAL" = "false" ]]; then \
    dnf mark install ${APP_INSTALL_DEPS} ${APP_INSTALL_DEPS_EXTRA} \
  ;fi && \
  \
  if [[ ${APP_DEBUG} -eq 0 ]]; then \
    : "---------- Clean temporary files ----------" && \
    dnf clean all && rm -rf /var/cache/{dnf,yum} \
  ;fi && \
  : "---------- ALL install finished ----------"

### STEP 2: PREPARE SYSTEM USERS
## prep users
RUN set -xe && \
  groupadd -g ${APP_GID} ${APP_GRP} && \
  useradd -u ${APP_UID} -c "${APP_DESCRIPTION} User" -g ${APP_GRP} -s /sbin/nologin ${APP_USR} && \
  ## add asterisk user to wheel and apache group
  usermod -aG wheel,apache ${APP_USR} && \
  ## fix phpMyAdmin apache group permissions
  chmod g+w /var/lib/phpMyAdmin/temp

### STEP 3: BUILD STAGE
## build asterisk
RUN set -xe && \
  . /etc/os-release && export OSARCH=$(uname -m) && \
  \
  ## manage dnf rhel minimal image variant
  if command -v microdnf 1>/dev/null; then export RHEL_MINIMAL="true" ;else export RHEL_MINIMAL="false" ;fi && \
  if [[ "$RHEL_MINIMAL" = "true" && ! -e "/usr/bin/dnf" ]]; then ln -s /usr/bin/microdnf /usr/bin/dnf ;fi && \
  ## dnf extra options
  export DNF_OPTS+=" -y --nodocs" && \
  ## enable extra repository via dnf command line
  export DNF_OPTS+=" --enablerepo=epel" && \
  \
  ## 20261022 removed the --nogpgcheck workaround of 20221130: remi packages are verified with the key shipped by remi-release
  export DNF_OPTS+=" --enablerepo=remi" && \
  \
  export DNF_OPTS+=" --enablerepo=rpmfusion-free-updates" && \
  export DNF_OPTS+=" --enablerepo=rpmfusion-nonfree-updates" && \
  if [[ ${RHEL_VER} -le 8 ]]; then export DNF_OPTS+=" --enablerepo=powertools" ;fi && \
  #if [[ ${RHEL_VER} -le 8 ]]; then export DNF_OPTS+=" --enablerepo=okay" ;fi && \
  if [[ ${RHEL_VER} -ge 9 ]]; then export DNF_OPTS+=" --enablerepo=crb" ;fi && \
  \
  : "---------- START installing build packages ----------" && \
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
    libtiff-devel \
    libjpeg-turbo-devel \
    audiofile-devel \
    uuid-devel \
    libtool-ltdl-devel \
    libsamplerate-devel \
    libsndfile-devel \
    doxygen \
    bison \
    fftw-devel \
    flex \
    graphviz \
    libpq-devel \
    libxslt-devel \
    net-snmp-devel \
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
    sox-devel \
    ilbc-devel \
    python3-devel \
    libtool \
    cmake \
    libresample-devel \
    mariadb-devel \
    libuv-devel \
    xmlto \
    docbook5-schemas \
    gmime-devel \
    jack-audio-connection-kit-devel \
    libcap-devel \
    libpcap-devel \
    rpm-devel \
    mariadb-connector-c-devel \
    libogg-devel \
    cmake-data \
    libwebsockets-devel \
  ' && \
  #xmlstarlet \
  \
  # deprecated in el9
  if [[ ${RHEL_VER} -le 8 ]]; then \
  ASTERISK_BUILD_DEPS_EXTRA='\
    python2-devel \
    libtermcap-devel \
    unbound-devel \
  ' \
  ;fi && \
  \
  dnf install ${DNF_OPTS} ${ASTERISK_BUILD_DEPS} ${ASTERISK_BUILD_DEPS_EXTRA} && \
  \
  : "---------- END installing build packages ----------" && \
  \
  : "---------- START build spandsp ----------" && \
  cd /usr/src && \
  mkdir spandsp && \
  curl -fSL --connect-timeout 30 -o spandsp.tar.gz https://sources.buildroot.net/spandsp/spandsp-${SPANDSP_VER}.tar.gz && \
  echo "${SPANDSP_SHA256}  spandsp.tar.gz" | sha256sum -c - && \
  tar xzf spandsp.tar.gz --strip 1 -C spandsp && \
  cd spandsp && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END build ----------" && \
  \
  # not working with RHEL 9
  if [[ ${RHEL_VER} -le 8 ]]; then \
  : "---------- START build iksemel ----------" && \
  cd /usr/src && \
  mkdir iksemel && \
  curl -fSL --connect-timeout 30 -o iksemel.tar.gz https://github.com/holme-r/iksemel/archive/${IKSEMEL_VER}.tar.gz && \
  echo "${IKSEMEL_SHA256}  iksemel.tar.gz" | sha256sum -c - && \
  tar xzf iksemel.tar.gz --strip 1 -C iksemel && \
  cd iksemel && \
  ./configure --prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END build ----------" \
  ;fi && \
  \
  : "---------- START build xmlstarlet ----------" && \
  cd /usr/src && \
  mkdir xmlstarlet && \
  curl -fSL --connect-timeout 30 -o xmlstarlet.tar.gz https://sourceforge.net/projects/xmlstar/files/xmlstarlet/${XMLSTARLET_VER}/xmlstarlet-${XMLSTARLET_VER}.tar.gz && \
  echo "${XMLSTARLET_SHA256}  xmlstarlet.tar.gz" | sha256sum -c - && \
  tar xzf xmlstarlet.tar.gz --strip 1 -C xmlstarlet && \
  cd xmlstarlet && \
  ./configure --prefix=/usr --with-libxml-prefix=/usr && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END build ----------" && \
  \
  : "---------- START build ASTERISK ----------" && \
  ## @20261022 back to the official release tarball (verified with ASTERISK_SHA256)
  ## fallback (github auto-generated archive, different checksum): https://github.com/asterisk/asterisk/archive/refs/tags/${ASTERISK_VER}.tar.gz
  ## @20210408 unreachable asterisk url - disable get_mp3_source.sh because need internet connection
  #./contrib/scripts/get_mp3_source.sh
  ## @20210414 reneabled get_mp3_source.sh
  #tar zxvf /usr/src/asterisk-mp3.tar.gz -C addons
  cd /usr/src && \
  mkdir asterisk && \
  curl -fSL --connect-timeout 30 -o asterisk.tar.gz https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VER}.tar.gz && \
  echo "${ASTERISK_SHA256}  asterisk.tar.gz" | sha256sum -c - && \
  tar xzf asterisk.tar.gz --strip 1 -C asterisk && \
  cd asterisk && \
  # step debug to avoid reinstall every time the development packages during debug sessions (COMMENT BEFORE FINAL BUILD TO AVOID ANOTHER CONTAINER LAYER)
  #RUN set -xe && \
  cd /usr/src/asterisk && \
  ./contrib/scripts/get_mp3_source.sh && \
  ./configure --prefix=/usr --libdir=/usr/lib64 --with-pjproject-bundled --with-jansson-bundled --with-resample --with-ssl=ssl --with-srtp && \
  \
  # finalize configuration
  make menuselect/menuselect menuselect-tree menuselect.makeopts && \
  # configure default options by category
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
  && \
  # enable/disable default options by single resource
  if [[ ${ASTERISK_VER%%.*} -le 18 ]]; then \
  # asterisk <= 18
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
    --disable res_geolocation \
    --disable res_phoneprov \
    --disable res_pjsip_phoneprov_provider \
    ;else \
  # asterisk >= 20
  menuselect/menuselect \
    --enable BETTER_BACKTRACES \
    --enable DONT_OPTIMIZE \
    --enable G711_NEW_ALGORITHM \
    --enable app_confbridge \
    --enable app_macro \
    --enable app_page \
    --enable app_statsd \
    --enable app_saycounted \
    --enable binaural_rendering_in_bridge_softmix \
    --enable chan_motif \
    --enable chan_sip \
    --enable chan_pjsip \
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
    --enable res_config_sqlite3 \
    --enable res_phoneprov \
    --enable res_pjsip_phoneprov_provider \
    --disable-category MENUSELECT_CORE_SOUNDS \
    --disable-category MENUSELECT_EXTRA_SOUNDS \
    --disable-category MENUSELECT_MOH \
    --disable BUILD_NATIVE \
    --disable app_meetme \
    --disable app_ivrdemo \
    --disable app_jack \
    --disable app_saycounted \
    --disable app_skel \
    --disable app_voicemail_imap \
    --disable cdr_pgsql \
    --disable cel_pgsql \
    --disable cdr_sqlite3_custom \
    --disable cel_sqlite3_custom \
    --disable cdr_tds \
    --disable cel_tds \
    --disable cdr_radius \
    --disable cel_radius \
    --disable chan_alsa \
    --disable chan_console \
    --disable chan_mgcp \
    --disable chan_skinny \
    --disable chan_ooh323 \
    --disable chan_mobile \
    --disable chan_unistim \
    --disable res_digium_phone \
    --disable res_calendar_ews \
    --disable res_calendar_exchange \
    --disable res_mwi_external \
    --disable res_mwi_external_ami \
    --disable res_config_pgsql \
    --disable res_config_mysql \
    --disable res_config_ldap \
    --disable res_adsi \
    --disable res_monitor \
    --disable res_pktccops \
    --disable res_geolocation \
    ;fi && \
# not supported anymore in asterisk 20
#    --enable app_mysql \
#    --disable cdr_syslog \
#    --disable cdr_mysql \
#    --disable chan_oss \
  \
  # build and install Asterisk PBX
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
  curl -fSL --connect-timeout 30 -o bcg729.tar.gz https://github.com/BelledonneCommunications/bcg729/archive/${BCG729_VER}.tar.gz && \
  echo "${BCG729_SHA256}  bcg729.tar.gz" | sha256sum -c - && \
  tar xzf bcg729.tar.gz --strip 1 -C bcg729 && \
  cd bcg729 && \
  cmake . -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_PREFIX_PATH=/usr -DBUILD_SHARED_LIBS=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END build ----------" && \
  \
  # not working with RHEL 9
  if [[ ${RHEL_VER} -le 8 ]]; then \
  : "---------- START build asterisk-g72x ----------" && \
  cd /usr/src && \
  mkdir asterisk-g72x && \
  curl -fSL --connect-timeout 30 -o asterisk-g72x.tar.gz https://github.com/arkadijs/asterisk-g72x/archive/${ASTERISK_G72X_VER}.tar.gz && \
  echo "${ASTERISK_G72X_SHA256}  asterisk-g72x.tar.gz" | sha256sum -c - && \
  tar xzf asterisk-g72x.tar.gz --strip 1 -C asterisk-g72x && \
  cd asterisk-g72x && \
  ./autogen.sh && \
  if [[ "${OSARCH}" = "x86_64" ]]; then \
    ./configure --prefix=/usr --with-bcg729 --disable-penryn \
  ;else \
    ./configure --prefix=/usr --with-bcg729 \
  ;fi && \
  make && \
  make install && \
  ldconfig \
  ;fi && \
  : "---------- END build ----------" && \
  \
  : "---------- START build asterisk-chan-dongle ----------" && \
  cd /usr/src && \
  mkdir asterisk-chan-dongle && \
  curl -fSL --connect-timeout 30 -o asterisk-chan-dongle.tar.gz https://github.com/${ASTERISK_CHAN_DONGLE_REPO}/archive/${ASTERISK_CHAN_DONGLE_VER}.tar.gz && \
  echo "${ASTERISK_CHAN_DONGLE_SHA256}  asterisk-chan-dongle.tar.gz" | sha256sum -c - && \
  tar xzf asterisk-chan-dongle.tar.gz --strip 1 -C asterisk-chan-dongle && \
  cd asterisk-chan-dongle && \
  ./bootstrap && \
  ./configure --with-astversion=${ASTERISK_VER} && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END build ----------" && \
  \
  : "---------- START build sngrep ----------" && \
  cd /usr/src && \
  mkdir sngrep && \
  curl -fSL --connect-timeout 30 -o sngrep.tar.gz https://github.com/irontec/sngrep/releases/download/v${SNGREP_VER}/sngrep-${SNGREP_VER}.tar.gz && \
  echo "${SNGREP_SHA256}  sngrep.tar.gz" | sha256sum -c - && \
  tar xzf sngrep.tar.gz --strip 1 -C sngrep && \
  cd sngrep && \
  ./bootstrap.sh && \
  ./configure --prefix=/usr ${SNGREP_XTRA_BUILDCONFIG} && \
  make && \
  make install && \
  ldconfig && \
  : "---------- END build ----------" && \
  \
  if [[ ${APP_DEBUG} -eq 0 ]]; then \
  : "---------- Clean temporary files ----------" && \
  dnf remove ${DNF_OPTS} ${ASTERISK_BUILD_DEPS} ${ASTERISK_BUILD_DEPS_EXTRA} && \
  dnf clean all && \
  rm -rf /var/cache/yum /tmp /usr/src && \
  mkdir -p /usr/src /tmp && chmod 1777 /tmp \
  ;fi && \
  : "---------- ALL builds finished ----------" 

### NOTE: asterisk build
## to get the options passed above: menuselect/menuselect --list-options

## download freepbx and modules for offline install:
## php -r 'echo json_encode(simplexml_load_file("https://mirror1.freepbx.org/modules-15.0.xml"));' | jq
## curl -fSL --connect-timeout 30 https://mirror.freepbx.org/modules/packages/freepbx/freepbx-${FREEPBX_VER}.0-latest.tgz | tar xz --strip 1 -C freepbx
## curl -fSL https://github.com/FreePBX/framework/archive/release/${FREEPBX_VER_FRAMEWORK}.tar.gz| tar xfz - --strip 1 -C freepbx

## copy external sources files again
ADD build/ /usr/src/

## deploy freepbx
# NOTE: pipefail: a failed curl into 'curl | tar' pipes must fail the build
RUN set -xe -o pipefail && \
  \
  cd /usr/src && \
  mkdir freepbx && \
  # deprecated download (because this is not the latest version)
  #curl -fSL --connect-timeout 30 https://mirror.freepbx.org/modules/packages/freepbx/freepbx-${FREEPBX_VER}.0-latest.tgz | tar xz --strip 1 -C freepbx && \
  cd freepbx && \
  ## download modules-*.xml file if not exist in local build dir
  if [[ -e "/usr/src/modules-${FREEPBX_VER}.0.xml" ]]; then \
    cp "/usr/src/modules-${FREEPBX_VER}.0.xml" "/usr/src/freepbx/modules-${FREEPBX_VER}.0.xml" \
  ;else \
    # NOTE: query the mirror like FreePBX Module Admin does (POST to all-X.0.xml): the static modules-X.0.xml
    #       file is not updated anymore and lists older module releases (ex. contactmanager without security fixes)
    curl -fSL --connect-timeout 30 -X POST -d "phpver=${PHP_VER}" -d "astver=${ASTERISK_VER}" https://mirror.freepbx.org/all-${FREEPBX_VER}.0.xml -o modules-${FREEPBX_VER}.0.xml \
  ;fi && \
  \
  # download latest framework release
  MODULE="framework" && \
  MODULE_VER=$(php -r "echo json_encode(simplexml_load_file('modules-${FREEPBX_VER}.0.xml'));" | jq -r ".module[] | select(.rawname == \"${MODULE}\") | {version}".version) && \
  [ -n "${MODULE_VER}" ] && \
  echo "---------- Predownloading freepbx framework latest release: ${MODULE_VER} ----------" && \
  curl -fSL --connect-timeout 30 https://mirror.freepbx.org/modules/packages/$MODULE/$MODULE-${MODULE_VER}.tgz | tar xz --strip 1 -C ./ && \
  \
  # make the modules cache
  mkdir -p amp_conf/htdocs/admin/modules/_cache && \
  # predownload the following modules for faster install (need to skip 'framework' module)
  for MODULE in \
      core \
      featurecodeadmin \
      customappsreg \
      recordings \
      callrecording \
      conferences \
      dashboard \
      logfiles \
      cdr \
      sipsettings \
      voicemail \
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
      music \
      infoservices \
      weakpasswords \
      pm2 \
      ; do \
  # download loop
  MODULE_VER=$(php -r "echo json_encode(simplexml_load_file('modules-${FREEPBX_VER}.0.xml'));" | jq -r ".module[] | select(.rawname == \"${MODULE}\") | {version}".version) && \
  # stop the build if the module is not listed or a download fails (errors inside the loop are not caught by 'set -e')
  { [ -n "${MODULE_VER}" ] || { echo "ERROR: module '$MODULE' not found into modules-${FREEPBX_VER}.0.xml"; exit 1; } ; } && \
  mkdir -p amp_conf/htdocs/admin/modules/$MODULE && \
  echo "---------- Predownloading module for offline install: $MODULE ${MODULE_VER} ----------" && \
  curl -fSL --connect-timeout 30 https://mirror.freepbx.org/modules/packages/$MODULE/$MODULE-${MODULE_VER}.tgz | tar xz --strip 1 -C amp_conf/htdocs/admin/modules/$MODULE/ && \
  curl -fSL --connect-timeout 30 https://mirror.freepbx.org/modules/packages/$MODULE/$MODULE-${MODULE_VER}.tgz.gpg -o amp_conf/htdocs/admin/modules/_cache/$MODULE-${MODULE_VER}.tgz.gpg \
  || exit 1 \
  ; done
  
## install other components
RUN set -xe && \
  . /etc/os-release && export OSARCH=$(uname -m) && \
  : "---------- START install izsynth by InitZero ----------" && \
  cd /usr/src && \
  mkdir -p izsynth && \
  curl -fSL --connect-timeout 30 -o izsynth.tar.gz https://github.com/ugoviti/izsynth/archive/${IZSYNTH_VER}.tar.gz && \
  echo "${IZSYNTH_SHA256}  izsynth.tar.gz" | sha256sum -c - && \
  tar xzf izsynth.tar.gz --strip 1 -C izsynth && \
  rm -f izsynth.tar.gz && \
  cp -a izsynth/izsynth /usr/local/bin/izsynth && \
  chmod 755 /usr/local/bin/izsynth && \
  : "---------- END install ----------" && \
  \
  : "---------- START install Asterisk Zabbix Agents by InitZero ----------" && \
  curl -fSL --connect-timeout 30 -o /tmp/zabbix-templates.tar.gz https://github.com/ugoviti/zabbix-templates/archive/${ZABBIX_TEMPLATE_VER}.tar.gz && \
  echo "${ZABBIX_TEMPLATE_SHA256}  /tmp/zabbix-templates.tar.gz" | sha256sum -c - && \
  cd /etc/zabbix/zabbix_agent2.d && \
  tar xzf /tmp/zabbix-templates.tar.gz --strip 3 zabbix-templates-${ZABBIX_TEMPLATE_VER}/asterisk/zabbix_agent2.d && \
  rm -f /tmp/zabbix-templates.tar.gz && \
  : "---------- END install ----------" && \
  \
  : "---------- START install PHP ionCube Loader ----------" && \
  case "${OSARCH}" in \
    x86_64)  IONCUBE_SHA256="${IONCUBE_SHA256_X86_64}" ;; \
    aarch64) IONCUBE_SHA256="${IONCUBE_SHA256_AARCH64}" ;; \
    *) echo "ionCube: no pinned sha256 for ${OSARCH}" && exit 1 ;; \
  esac && \
  curl -fSL --connect-timeout 30 -o /tmp/ioncube.tar.gz https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_${OSARCH//_/-}_${IONCUBE_VER}.tar.gz && \
  echo "${IONCUBE_SHA256}  /tmp/ioncube.tar.gz" | sha256sum -c - && \
  tar xzf /tmp/ioncube.tar.gz --strip 1 -C /usr/lib64/php/modules/ ioncube/ioncube_loader_lin_"${PHP_VER}".so && \
  rm -f /tmp/ioncube.tar.gz && \
  echo "zend_extension=ioncube_loader_lin_${PHP_VER}.so" >> /etc/php.ini && \
  : "---------- END install ----------"

### STEP 4: FINISH SYSTEM SETUP  
## set pemissions and sudo
RUN set -xe && \
  chown -R ${APP_USR}:${APP_GRP} \
    /etc/asterisk \
    /var/lib/asterisk \
    /var/spool/asterisk

### fixes and workarounds
## gpg management
RUN set -xe && \
  # fix gpg keys
  su - asterisk -s /bin/bash -c 'for key in /usr/src/freepbx/amp_conf/htdocs/admin/libraries/BMO/*.key ; do gpg --import "$key" ; done' && \
  su - asterisk -s /bin/bash -c 'gpg --refresh-keys --keyserver keys.openpgp.org'

## copy external sources files
ADD patch/ /usr/src/

## FIXME: fix for FreePBX 16 upgrade error (20211121: MUST be removed in a future release for better security)
## other problem when upgrading to FreePBX 16: https://issues.freepbx.org/browse/FREEPBX-22842
## references: https://wiki.freepbx.org/display/FOP/Non+Distro+-+Upgrade+to+FreePBX+16
RUN sed 's/@SECLEVEL=2/@SECLEVEL=1/' -i /etc/crypto-policies/back-ends/opensslcnf.config

### app ports
ENV APP_PORT_HTTP=80
ENV APP_PORT_HTTPS=443
ENV APP_PORT_IAX=4569
ENV APP_PORT_PJSIP=5060
ENV APP_PORT_SIP=5160
ENV APP_PORT_WEBRTC=8089
ENV APP_PORT_UCP_HTTP=8001
ENV APP_PORT_UCP_HTTPS=8003
ENV APP_PORT_AMI=8088
ENV APP_PORT_RTP_START=10000
ENV APP_PORT_RTP_END=10200
ENV APP_PORT_DHCP=67
ENV APP_PORT_TFTP=69
ENV APP_PORT_NTP=123
ENV APP_PORT_FOP2=4445
ENV APP_PORT_ZABBIX=10050

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

## CI envs for later usage
ENV APP_FQDN=""
ENV APP_VER_BUILD="${APP_VER_BUILD}"
ENV APP_BUILD_COMMIT="${APP_BUILD_COMMIT}"
ENV APP_BUILD_DATE="${APP_BUILD_DATE}"

## add files to container
ADD rootfs Dockerfile README.md /

## start the container process
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
