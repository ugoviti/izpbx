#!/usr/bin/env bash
# Comparable view of one file of the golden matrix (P3-25), for each side:
#   map/files.sh old ROOT PATH    ROOT = tests/golden/20.16.22/<case>/files
#   map/files.sh new ROOT PATH    ROOT = root of a 22.17 tree after a dry-run
# PATH is the 20.16 path listed in "# expect:" of the case. The two views
# must be equal; the rules below are the intended differences of the items
# P3-05...P3-16 (Debian paths, design §6 C1-C14). Exit 3: no rule for PATH.
# Runs inside the 22.17 image (postconf of map/postfix.sh).
set -Eeuo pipefail
side=$1 root=$2 path=$3
here=$(cd "$(dirname "$0")" && pwd)
settings() { grep -Ev '^[[:space:]]*([#;]|$)' "$1"; }
pick() { if [ "$side" == old ]; then cat "$root$1"; else cat "$root$2"; fi; }

case "$path" in
  /etc/httpd/conf.d/virtual.conf|/etc/httpd/conf/httpd.conf)
    "$here/httpd.sh" "$side" "$root" ;;
  /etc/httpd/conf.d/phonebook.conf)
    pick /etc/httpd/conf.d/phonebook.conf /etc/apache2/conf-available/phonebook.conf ;;
  /etc/httpd/conf.d/phpMyAdmin_izpbx.conf)
    if [ "$side" == old ]; then sed 's|/usr/share/phpMyAdmin|/usr/share/phpmyadmin|' "$root$path"
    else cat "$root/etc/apache2/conf-available/phpmyadmin_izpbx.conf"; fi ;;
  /etc/httpd/conf.d/phpMyAdmin.conf)
    # the package's own aliases: removed on 20.16, conf disabled on Debian
    if [ "$side" == old ]; then n=$(grep -c '^Alias ' "$root$path" || true)
    else n=$(grep -hc '^Alias ' "$root"/etc/apache2/conf-enabled/phpmyadmin.conf 2>/dev/null || true); fi
    echo "package aliases enabled: ${n:-0}" ;;
  /etc/msmtprc)
    if [ "$side" == old ]; then sed 's|/etc/pki/tls/certs/ca-bundle.crt|/etc/ssl/certs/ca-certificates.crt|' "$root$path"
    else cat "$root$path"; fi ;;
  /etc/fail2ban/jail.d/99-local.conf)
    if [ "$side" == old ]; then sed 's|/var/log/httpd/|/var/log/apache2/|' "$root$path"; else cat "$root$path"; fi ;;
  /etc/fail2ban/fail2ban.conf|/etc/zabbix/zabbix_agent2.conf)
    settings "$root$path" ;;
  /etc/php.d/99-timezone.ini)
    pick /etc/php.d/99-timezone.ini /etc/php/8.2/fpm/conf.d/99-izpbx-timezone.ini ;;
  /etc/chrony.conf)
    if [ "$side" == old ]; then sed 's|^keyfile /etc/chrony.keys$|keyfile /etc/chrony/chrony.keys|' "$root$path"
    else cat "$root/etc/chrony/chrony.conf"; fi ;;
  /etc/izpbx/cron.env|/etc/timezone|/etc/dnsmasq.d/local.conf|/etc/zabbix/zabbix_agent2.d/local.conf)
    cat "$root$path" ;;
  /etc/aliases|/etc/postfix/*)
    "$here/postfix.sh" "postconf -c $root/etc/postfix -h" "$root" ;;
  *) echo "no rule for $path" >&2; exit 3 ;;
esac
