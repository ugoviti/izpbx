#!/bin/bash
# Install FreePBX 17 on the prototype container (DB in another container).
#   MYSQL_SERVER MYSQL_USER MYSQL_PASSWORD MYSQL_ROOT_PASSWORD
#   PROTO_MODULES   extra modules to download (izPBX 20.16 default list)
set -Eeuo pipefail
trap 'echo "proto-install: error at line $LINENO: $BASH_COMMAND" >&2' ERR
: "${MYSQL_SERVER:=db}" "${MYSQL_USER:=asterisk}" "${MYSQL_PASSWORD:?}" "${MYSQL_ROOT_PASSWORD:?}"
# izPBX 20.16 default modules missing from the FreePBX 17 tarball (phonebook has no 17 release)
: "${PROTO_MODULES:=arimanager asteriskinfo callforward callwaiting cidlookup contactmanager daynight donotdisturb iaxsettings manager miscapps miscdests presencestate printextensions timeconditions weakpasswords}"

q() { MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -h "$MYSQL_SERVER" -uroot -e "$1"; }
step() { echo "proto-install: $*" >&2; }

# FreePBX reads /etc/machine-id (shell_exec returns null without it and
# PHP 8.2 turns the preg_replace deprecation into an exception)
[ -s /etc/machine-id ] || tr -d - < /proc/sys/kernel/random/uuid > /etc/machine-id

# izPBX keeps everything under /data and a restore brings back the 20.16
# path settings (AMPWEBROOT=/data/var/www/html, ...): same layout via symlinks
mkdir -p /data/var/lib /data/var/spool /data/var/log /data/etc /var/lib/asterisk/sbin
for p in var/www var/lib/asterisk var/spool/asterisk var/log/asterisk etc/asterisk; do
  [ -e "/data/$p" ] || ln -s "/$p" "/data/$p"
done

step "databases"
q "CREATE USER IF NOT EXISTS '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD';
   CREATE DATABASE IF NOT EXISTS asterisk; CREATE DATABASE IF NOT EXISTS asteriskcdrdb;
   GRANT ALL ON asterisk.* TO '$MYSQL_USER'@'%'; GRANT ALL ON asteriskcdrdb.* TO '$MYSQL_USER'@'%';"
cat > /etc/odbc.ini <<ODBC
[MySQL-asteriskcdrdb]
Description = MariaDB connection to 'asteriskcdrdb' CDR database
driver = MariaDB Unicode
server = $MYSQL_SERVER
database = asteriskcdrdb
Port = 3306
option = 3
Charset=utf8
ODBC

step "FreePBX installer"
apachectl start
cd /usr/src/freepbx
./start_asterisk start
# NOTE: the 17.0.33 installer exits non-zero even when it reports success
./install -n --dbhost="$MYSQL_SERVER" --dbuser="$MYSQL_USER" --dbpass="$MYSQL_PASSWORD" --dbname=asterisk --cdrdbname=asteriskcdrdb \
  2>&1 | tee /tmp/freepbx-install.log || true
grep -q 'You have successfully installed FreePBX' /tmp/freepbx-install.log || { echo "proto-install: FreePBX installer failed" >&2; exit 1; }
ln -sf /var/lib/asterisk/bin/fwconsole /var/lib/asterisk/sbin/fwconsole

step "modules: $PROTO_MODULES"
# NOTE: run as asterisk; as root fwconsole exits 1 (PKCS destructor) even on success
for m in $PROTO_MODULES; do
  su -s /bin/bash asterisk -c "fwconsole ma downloadinstall $m" >/dev/null 2>&1 || true
done
fwconsole chown >/dev/null 2>&1 || true
missing=()
for m in $PROTO_MODULES; do
  fwconsole ma list | grep -qE "^\| $m +\| [0-9.]+ +\| Enabled" || missing+=("$m")
done
[ ${#missing[@]} -eq 0 ] || { echo "proto-install: modules not enabled: ${missing[*]}" >&2; exit 1; }
fwconsole reload >/dev/null
echo "proto-install: FreePBX $(fwconsole -V | awk '{print $NF}') ready, $(fwconsole ma list | grep -c Enabled) modules enabled"
