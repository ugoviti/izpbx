#!/bin/bash
# Stage "base": Zabbix repository (pinned key), runtime packages, linker path,
# asterisk user.
#   build/base.sh   (run from the Dockerfile with versions.env and build/ in /usr/src/izpbx)
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
load_versions "$here/../versions.env"

# keep downloaded .deb files: /var/cache/apt is a BuildKit cache mount
rm -f /etc/apt/apt.conf.d/docker-clean
echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# bootstrap: what the repository setup below needs (debian slim has none of it)
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl gnupg

# Zabbix agent 2 repository: the published key file is a bundle of several
# keys, only the one with the pinned fingerprint goes into the keyring
key=$(mktemp)
curl -fsSL --proto '=https' --retry 5 -o "$key" https://repo.zabbix.com/zabbix-official-repo.key
gpg --show-keys --with-colons "$key" | awk -F: '$1=="fpr"{print $10}' | grep -qx "$ZABBIX_GPG_FPR" \
  || build_die "the Zabbix key file does not contain $ZABBIX_GPG_FPR"
gnupg_home=$(mktemp -d)
gpg --homedir "$gnupg_home" --quiet --import "$key"
gpg --homedir "$gnupg_home" --export "$ZABBIX_GPG_FPR" > /usr/share/keyrings/zabbix.gpg
rm -rf "$key" "$gnupg_home"
# Zabbix publishes amd64 under .../debian and arm64 under .../debian-arm64
# (same signing key): with the wrong one apt silently falls back to Debian's
# older zabbix-agent2 (6.0)
case "$(build_arch)" in
  x86_64) zabbix_repo=debian ;;
  aarch64) zabbix_repo=debian-arm64 ;;
esac
cat > /etc/apt/sources.list.d/zabbix.sources <<SRC
Types: deb
URIs: https://repo.zabbix.com/zabbix/$ZABBIX_VER/$zabbix_repo
Suites: bookworm
Components: main
Signed-By: /usr/share/keyrings/zabbix.gpg
SRC

apt-get update
# OS_UPDATE_STAMP (build arg) only changes the cache key of this step
build_log "upgrading the base system (stamp: ${OS_UPDATE_STAMP:-none})"
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
apt_install "$here/packages-runtime.txt"
zbx=$(dpkg-query -W -f '${Version}' zabbix-agent2)
[[ "$zbx" == 1:"$ZABBIX_VER".* ]] || build_die "zabbix-agent2 $zbx installed, expected $ZABBIX_VER.x from repo.zabbix.com"

# Asterisk is built with --libdir=/usr/lib64 (ASTMODDIR kept from 20.16)
echo /usr/lib64 > /etc/ld.so.conf.d/asterisk.conf
ldconfig

# asterisk user and group: 1000:1000 as in 20.16 (APP_UID/APP_GID)
getent group asterisk >/dev/null || groupadd -g 1000 asterisk
id asterisk >/dev/null 2>&1 || useradd -u 1000 -g asterisk -d /home/asterisk -m -s /bin/bash asterisk
build_log "base ready"
