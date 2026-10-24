# shellcheck shell=bash
# Remote XML phonebook /pb (/usr/local/share/phonebook, with the security
# fixes of 20.16.22: vendor whitelist, escaped output, parameterized
# queries), as cfgService_phonebook of 20.16: the Apache configuration
# (20.16 conf.d/phonebook.conf, here conf-available/phonebook.conf, Debian
# layout) uses the access list of the web interface (HTTPD_ALLOW_FROM).
# shellcheck source=httpd.sh
. /usr/local/lib/izpbx/services/httpd.sh

: "${PHONEBOOK_APACHE:=/etc/apache2/conf-available/phonebook.conf}"

cfg_phonebook() {
  log_info "phonebook: enabled on /pb"
  echo "Alias /pb /usr/local/share/phonebook

<Directory /usr/local/share/phonebook>
    AllowOverride all
    AddDefaultCharset UTF-8
    DirectoryIndex index.php
$(_httpd_allow_from)
</Directory>
" > "$PHONEBOOK_APACHE"
  a2enconf -q phonebook >/dev/null
}

cfg_phonebook_disable() {
  log_info "phonebook: disabled"
  a2disconf -q phonebook >/dev/null 2>&1 || true
  rm -f "$PHONEBOOK_APACHE"
}
