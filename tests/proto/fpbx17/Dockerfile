# syntax=docker/dockerfile:1
# Prototype FreePBX 17 + Asterisk 22 on Debian 12, used by P0-10/P0-11 to test
# the restore of a 20.16.x backup. Not the izPBX 22.17 image (that is P1).
FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ASTERISK_VER=22.11.0
ARG ASTERISK_SHA256=3bd5ee040509a3d3cd9b1ba9520c18e6ec0a7e7981ca68c457dcd36ba3c54d94
ARG FREEPBX_SHA256=57bfe353de693cd9f0f03b4e6cda68da69fd39c4beb9506fc06c8814ec40e538
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl wget bzip2 patch xz-utils file \
      build-essential pkg-config autoconf automake libtool \
      libssl-dev libncurses-dev libnewt-dev libxml2-dev libsqlite3-dev uuid-dev \
      libedit-dev libjansson-dev libcurl4-openssl-dev libsrtp2-dev libspeex-dev \
      libspeexdsp-dev libopus-dev libvorbis-dev libogg-dev libgsm1-dev libical-dev \
      libspandsp-dev libtiff-dev unixodbc-dev odbc-mariadb libldap2-dev libpq-dev \
      apache2 php8.2 libapache2-mod-php8.2 php8.2-cli php8.2-common php8.2-curl \
      php8.2-gd php8.2-mbstring php8.2-mysql php8.2-xml php8.2-zip php8.2-intl \
      php8.2-bcmath php8.2-soap php8.2-ldap php8.2-sqlite3 php-pear \
      mariadb-client sox lame ffmpeg mpg123 nodejs npm cron sudo git unzip \
      procps iproute2 net-tools gnupg less vim-tiny \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src
RUN curl -fsSLo asterisk.tgz "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-${ASTERISK_VER}.tar.gz" \
 && echo "${ASTERISK_SHA256}  asterisk.tgz" | sha256sum -c - \
 && mkdir asterisk && tar -xzf asterisk.tgz -C asterisk --strip-components=1 && rm asterisk.tgz
WORKDIR /usr/src/asterisk
RUN ./configure --libdir=/usr/lib64 --with-pjproject-bundled --with-jansson-bundled >/dev/null \
 && make menuselect.makeopts \
 && menuselect/menuselect --enable res_config_mysql --disable BUILD_NATIVE menuselect.makeopts \
 && make -j"$(nproc)" >/dev/null \
 && make install >/dev/null && make samples >/dev/null \
 && { make config >/dev/null 2>&1 || true; } \
 && ldconfig

# --libdir=/usr/lib64 is not a default linker path on Debian
RUN echo /usr/lib64 > /etc/ld.so.conf.d/asterisk.conf && ldconfig

RUN useradd -r -d /home/asterisk -m -s /bin/bash asterisk \
 && chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk /usr/lib64/asterisk \
 && sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf \
 && sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
 && sed -i 's/^\(upload_max_filesize\|post_max_size\) = .*/\1 = 256M/; s/^memory_limit = .*/memory_limit = 512M/' /etc/php/8.2/apache2/php.ini /etc/php/8.2/cli/php.ini \
 && a2enmod rewrite >/dev/null && rm -f /var/www/html/index.html

WORKDIR /usr/src
RUN curl -fsSLo freepbx.tgz https://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz \
 && echo "${FREEPBX_SHA256}  freepbx.tgz" | sha256sum -c - \
 && tar -xzf freepbx.tgz && rm freepbx.tgz

COPY proto-install.sh /usr/local/bin/proto-install.sh
CMD ["sleep", "infinity"]
