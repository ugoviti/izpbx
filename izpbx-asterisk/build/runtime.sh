#!/bin/bash
# Stage "runtime": last step after the build results are copied in.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

ldconfig
# Asterisk runs as asterisk (1000:1000): the files copied from /staging are root's
for d in /etc/asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk /run/asterisk; do
  mkdir -p "$d"
  chown -R asterisk:asterisk "$d"
done
# no C/C++ toolchain in the runtime (P0-14): the UCP installer refuses to run
# unless "g++ --version" answers, although its node modules build nothing
install -m 755 "$here/g++-stub" /usr/local/bin/g++
# ... and it checks ICU with "pkg-config --modversion icu-i18n" (no .pc files
# without libicu-dev): a stub answers the version of the ICU runtime library
icu=$(dpkg-query -W -f '${Version}' 'libicu[0-9]*' | sed 's/-.*//')
[ -n "$icu" ] || build_die "ICU runtime library not installed"
sed "s/@ICU_VERSION@/$icu/" "$here/pkg-config-stub" > /usr/local/bin/pkg-config
chmod 755 /usr/local/bin/pkg-config
# Debian enables an sshd jail by default: izPBX has no sshd, and without its
# log file fail2ban refuses to start (the izPBX jails are written at start)
rm -f /etc/fail2ban/jail.d/defaults-debian.conf
# Apache logs are rotated by /etc/logrotate.d/httpd (rootfs, restart through
# izpbx-service); Debian's own file reloads through invoke-rc.d
rm -f /etc/logrotate.d/apache2
# /usr/sbin/sendmail is chosen at start (init.d/10-services.sh): msmtp, or
# Postfix's own, kept aside here (the diversion survives package upgrades)
dpkg-divert --local --rename --divert /usr/sbin/sendmail.postfix --add /usr/sbin/sendmail
# Postfix services not chrooted (as on Rocky in 20.16): Debian's chroot needs
# the copies of resolv.conf and friends made by its init script, unused here
postconf -F '*/*/chroot = n'
# Apache (Debian layout): the izPBX vhost and global conf are written at start
# by services/httpd.sh; Debian's default site is off
a2enmod -q rewrite ssl
# PHP through php-fpm (design H1): mpm_event + proxy_fcgi, no mod_php
a2dismod -q mpm_prefork 2>/dev/null || true
a2enmod -q mpm_event proxy_fcgi setenvif
a2enconf -q php8.2-fpm
# pool "asterisk" (rootfs) instead of Debian's www; master log on stderr (H2)
rm -f /etc/php/8.2/fpm/pool.d/www.conf
sed -i 's|^error_log = .*|error_log = /proc/self/fd/2|' /etc/php/8.2/fpm/php-fpm.conf
phpenmod -s ALL izpbx
php-fpm8.2 -t
a2dissite -q 000-default
: > /etc/apache2/sites-available/izpbx.conf
: > /etc/apache2/conf-available/izpbx.conf
a2ensite -q izpbx
a2enconf -q izpbx
# dnsmasq reads /etc/dnsmasq.d/*.conf (local.conf, written at start by
# services/dnsmasq.sh), as on Rocky in 20.16; Debian enables it only in its
# init script, unused here
sed -i 's|^#conf-dir=/etc/dnsmasq.d/,\*\.conf$|conf-dir=/etc/dnsmasq.d/,*.conf|' /etc/dnsmasq.conf
grep -qx 'conf-dir=/etc/dnsmasq.d/,\*\.conf' /etc/dnsmasq.conf
# phpMyAdmin (Debian package): off until PMA_ENABLED (services/pma.sh); php-fpm
# runs as asterisk; the cookie secret made at package install would be the
# same in every image: removed, a new one is written at start
a2disconf -q phpmyadmin
chgrp asterisk /etc/phpmyadmin/config-db.php
chown asterisk:asterisk /var/lib/phpmyadmin/tmp
rm -f /var/lib/phpmyadmin/blowfish_secret.inc.php
build_log "runtime ready"
