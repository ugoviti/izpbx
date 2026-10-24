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
# Debian enables an sshd jail by default: izPBX has no sshd, and without its
# log file fail2ban refuses to start (the izPBX jails are written at start)
rm -f /etc/fail2ban/jail.d/defaults-debian.conf
# Apache logs are rotated by /etc/logrotate.d/httpd (rootfs, restart through
# izpbx-service); Debian's own file reloads through invoke-rc.d
rm -f /etc/logrotate.d/apache2
# /usr/sbin/sendmail is chosen at start (init.d/10-services.sh): msmtp, or
# Postfix's own, kept aside here (the diversion survives package upgrades)
dpkg-divert --local --rename --divert /usr/sbin/sendmail.postfix --add /usr/sbin/sendmail
# Apache (Debian layout): the izPBX vhost and global conf are written at start
# by services/httpd.sh; Debian's default site is off
a2enmod -q rewrite ssl
a2dissite -q 000-default
: > /etc/apache2/sites-available/izpbx.conf
: > /etc/apache2/conf-available/izpbx.conf
a2ensite -q izpbx
a2enconf -q izpbx
build_log "runtime ready"
