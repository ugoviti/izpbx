#!/bin/bash
# Stage "base": runtime packages, linker path, asterisk user.
#   build/base.sh   (run from the Dockerfile with versions.env and build/ in /usr/src/izpbx)
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

# keep downloaded .deb files: /var/cache/apt is a BuildKit cache mount
rm -f /etc/apt/apt.conf.d/docker-clean
echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

apt-get update
# OS_UPDATE_STAMP (build arg) only changes the cache key of this step
build_log "upgrading the base system (stamp: ${OS_UPDATE_STAMP:-none})"
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
apt_install "$here/packages-runtime.txt"

# Asterisk is built with --libdir=/usr/lib64 (ASTMODDIR kept from 20.16)
echo /usr/lib64 > /etc/ld.so.conf.d/asterisk.conf
ldconfig

# asterisk user and group: 1000:1000 as in 20.16 (APP_UID/APP_GID)
getent group asterisk >/dev/null || groupadd -g 1000 asterisk
id asterisk >/dev/null 2>&1 || useradd -u 1000 -g asterisk -d /home/asterisk -m -s /bin/bash asterisk
build_log "base ready"
