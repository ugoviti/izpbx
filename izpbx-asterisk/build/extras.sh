#!/bin/bash
# Stage "runtime": ionCube loader for PHP 8.2 (every SAPI: cli, fpm),
# npm, izsynth, the Asterisk templates for zabbix-agent2. Every download is pinned
# by sha256 in versions.env.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
load_versions "$here/../versions.env"
cache=/usr/src/download-cache
arch=$(build_arch)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- ionCube: the loader of this PHP version, loaded first (priority 00)
php_ver=$(php -r 'echo PHP_MAJOR_VERSION, ".", PHP_MINOR_VERSION;')
ext_dir=$(php -r 'echo ini_get("extension_dir");')
loader="ioncube_loader_lin_$php_ver.so"
fetch_verified "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_${arch//_/-}_$IONCUBE_VER.tar.gz" \
  "$(arch_var IONCUBE_SHA256)" "$cache/ioncube-$arch-$IONCUBE_VER.tar.gz"
tar -xzf "$cache/ioncube-$arch-$IONCUBE_VER.tar.gz" -C "$tmp" "ioncube/$loader"
install -m 644 "$tmp/ioncube/$loader" "$ext_dir/$loader"
printf '; priority=00\nzend_extension=%s\n' "$loader" > "/etc/php/$php_ver/mods-available/ioncube.ini"
phpenmod -v "$php_ver" -s ALL ioncube
got=$(php -v | grep -oE 'ionCube PHP Loader v[0-9.]+' | grep -oE '[0-9.]+$' || true)
[ "$got" == "$IONCUBE_VER" ] || build_die "ionCube: php -v reports '${got:-no loader}', expected $IONCUBE_VER"

# --- npm (pure JavaScript; Node.js comes from Debian)
fetch_verified "https://registry.npmjs.org/npm/-/npm-$NPM_VER.tgz" "$NPM_SHA256" "$cache/npm-$NPM_VER.tgz"
rm -rf /usr/local/lib/node_modules/npm && mkdir -p /usr/local/lib/node_modules/npm
tar -xzf "$cache/npm-$NPM_VER.tgz" -C /usr/local/lib/node_modules/npm --strip-components=1 --no-same-owner
ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
[ "$(npm --version)" == "$NPM_VER" ] || build_die "npm: $(npm --version) installed, expected $NPM_VER"

# --- izsynth
fetch_verified "https://github.com/ugoviti/izsynth/archive/$IZSYNTH_VER.tar.gz" "$IZSYNTH_SHA256" "$cache/izsynth-$IZSYNTH_VER.tar.gz"
tar -xzf "$cache/izsynth-$IZSYNTH_VER.tar.gz" -C "$tmp" "izsynth-$IZSYNTH_VER/izsynth"
install -m 755 "$tmp/izsynth-$IZSYNTH_VER/izsynth" /usr/local/bin/izsynth

# --- Asterisk templates for zabbix-agent2 (asterisk.conf + scripts/asterisk.sh)
fetch_verified "https://github.com/ugoviti/zabbix-templates/archive/$ZABBIX_TEMPLATE_VER.tar.gz" "$ZABBIX_TEMPLATE_SHA256" \
  "$cache/zabbix-templates-$ZABBIX_TEMPLATE_VER.tar.gz"
tar -xzf "$cache/zabbix-templates-$ZABBIX_TEMPLATE_VER.tar.gz" -C /etc/zabbix/zabbix_agent2.d --strip-components=3 --no-same-owner --no-same-permissions \
  "zabbix-templates-$ZABBIX_TEMPLATE_VER/asterisk/zabbix_agent2.d"
chmod 755 /etc/zabbix/zabbix_agent2.d/scripts/asterisk.sh

build_log "extras: ionCube $IONCUBE_VER (PHP $php_ver), npm $NPM_VER, izsynth $IZSYNTH_VER, zabbix templates ${ZABBIX_TEMPLATE_VER:0:12}"
