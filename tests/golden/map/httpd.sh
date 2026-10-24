#!/usr/bin/env bash
# Path mapping 20.16 (Rocky) -> 22.17 (Debian) for the Apache files (design
# C1, C2, P3-05). Prints a comparable view of one side:
#   map/httpd.sh old DIR   DIR = tests/golden/20.16.22/<case>/files
#   map/httpd.sh new DIR   DIR = files copied from a 22.17 dry-run
# The views of the two sides must be equal. Allowed differences:
# - virtual.conf is sites-available/izpbx.conf;
# - httpd.conf directives (ServerName, Listen, User, Group) are in
#   conf-available/izpbx.conf, ports.conf and envvars (APACHE_RUN_USER/GROUP);
# - no Debian equivalent: log paths (logs/ -> ${APACHE_LOG_DIR}/), passphrase
#   helper and SSL session cache paths, cipher list (RHEL crypto policy
#   PROFILE=SYSTEM -> Debian ssl.conf HIGH:!aNULL).
set -Eeuo pipefail
side=$1 dir=$2
if [ "$side" == old ]; then
  echo "== directives"
  grep -E '^(ServerName|Listen|User|Group) ' "$dir/etc/httpd/conf/httpd.conf" | sort
  echo "== vhost"
  sed -e 's|logs/ssl_error_log|${APACHE_LOG_DIR}/ssl_error_log|' \
      -e 's|logs/ssl_access_log|${APACHE_LOG_DIR}/ssl_access_log|' \
      -e 's|exec:/usr/libexec/httpd-ssl-pass-dialog|exec:/usr/share/apache2/ask-for-passphrase|' \
      -e 's|shmcb:/run/httpd/sslcache(|shmcb:${APACHE_RUN_DIR}/ssl_scache(|' \
      -e 's|PROFILE=SYSTEM|HIGH:!aNULL|' "$dir/etc/httpd/conf.d/virtual.conf"
else
  echo "== directives"
  {
    grep -E '^ServerName ' "$dir/etc/apache2/conf-available/izpbx.conf"
    grep -E '^Listen ' "$dir/etc/apache2/ports.conf"
    sed -n 's/^export APACHE_RUN_USER=/User /p; s/^export APACHE_RUN_GROUP=/Group /p' "$dir/etc/apache2/envvars"
  } | sort
  echo "== vhost"
  cat "$dir/etc/apache2/sites-available/izpbx.conf"
fi
