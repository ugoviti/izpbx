# shellcheck shell=bash
# phpMyAdmin (Debian package, design C11), as cfgService_pma and
# cfgService_pma_disable of 20.16, rewritten at every start (idempotent):
# - enabled: the default alias /phpmyadmin of the package configuration is
#   removed, conf-available/phpmyadmin_izpbx.conf sets PMA_ALIAS and one
#   "Require ip" per PMA_ALLOW_FROM (it sorts after phpmyadmin.conf, so its
#   Require rules win), the database host is MYSQL_SERVER, the cookie secret
#   is made once per container;
# - disabled: both configurations off, the izPBX one removed.
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh

: "${PMA_DIR:=/usr/share/phpmyadmin}"
: "${PMA_APACHE_PKG:=/etc/phpmyadmin/apache.conf}"
: "${PMA_APACHE_LOCAL:=/etc/apache2/conf-available/phpmyadmin_izpbx.conf}"
: "${PMA_CONFIG_DB:=/etc/phpmyadmin/config-db.php}"
: "${PMA_SECRET:=/var/lib/phpmyadmin/blowfish_secret.inc.php}"

cfg_pma() {
  local from
  log_info "phpMyAdmin: enabled on ${PMA_ALIAS} for ${PMA_ALLOW_FROM}"
  sed -i '/^Alias \/phpmyadmin /d' "$PMA_APACHE_PKG"
  {
    echo "# phpMyAdmin izPBX configuration (automatically generated at container startup: don't edit)"
    echo "Alias ${PMA_ALIAS} ${PMA_DIR}"
    echo
    echo "<Directory ${PMA_DIR}/>"
    echo "  AddDefaultCharset UTF-8"
    # shellcheck disable=SC2086 # space separated list
    for from in $PMA_ALLOW_FROM; do echo "    Require ip $from"; done
    echo "</Directory>"
  } > "$PMA_APACHE_LOCAL"
  a2enconf -q phpmyadmin phpmyadmin_izpbx >/dev/null
  sed -i "s|^\$dbserver=.*|\$dbserver='$(sedEscape "$(phpSquote "$MYSQL_SERVER")")';|" "$PMA_CONFIG_DB"
  if [ ! -s "$PMA_SECRET" ]; then
    ( umask 027
      printf "<?php\n\$cfg['blowfish_secret'] = '%s';\n" "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$PMA_SECRET" )
    chgrp "$APP_GRP" "$PMA_SECRET"
  fi
}

cfg_pma_disable() {
  log_info "phpMyAdmin: disabled"
  a2disconf -q phpmyadmin phpmyadmin_izpbx >/dev/null 2>&1 || true
  rm -f "$PMA_APACHE_LOCAL"
}
