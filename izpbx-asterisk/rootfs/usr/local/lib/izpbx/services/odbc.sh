# shellcheck shell=bash
# ODBC for the Asterisk CDR, as the "configure CDR ODBC" step of 20.16:
# - /etc/odbcinst.ini: driver "MySQL" (the name the 20.16 DSN uses) pointing
#   to the MariaDB Connector/ODBC of the Debian package for this architecture
#   (/usr/lib/<multiarch>/odbc/libmaodbc.so; 20.16 rewrote /lib64/libmyodbc5.so);
# - /etc/odbc.ini: DSN MySQL-asteriskcdrdb on MYSQL_SERVER:APP_PORT_MYSQL,
#   database MYSQL_DATABASE_CDR (FreePBX gives the credentials in
#   res_odbc_additional.conf).
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh

: "${ODBC_INST:=/etc/odbcinst.ini}"
: "${ODBC_INI:=/etc/odbc.ini}"

odbc_driver_path() {
  local f
  for f in /usr/lib/*/odbc/libmaodbc.so; do [ -e "$f" ] && { echo "$f"; return 0; }; done
  return 1
}

cfg_odbc() {
  local drv
  if ! drv=$(odbc_driver_path); then
    log_error "odbc: MariaDB Connector/ODBC (libmaodbc.so) not found, CDR ODBC not configured"
    return 0
  fi
  # replace the [MySQL] section, keep the others (the package's [MariaDB Unicode])
  touch "$ODBC_INST"
  awk '/^\[/ {skip = ($0 == "[MySQL]")} !skip' "$ODBC_INST" > "$ODBC_INST.tmp"
  printf '[MySQL]\nDescription=MariaDB Connector/ODBC\nDriver=%s\nThreading=0\n' "$drv" >> "$ODBC_INST.tmp"
  mv "$ODBC_INST.tmp" "$ODBC_INST"
  chmod 0644 "$ODBC_INST"

  cat > "$ODBC_INI" <<ODBC
[MySQL-asteriskcdrdb]
Description = MariaDB connection to '${MYSQL_DATABASE_CDR}' CDR database
driver = MySQL
server = ${MYSQL_SERVER}
database = ${MYSQL_DATABASE_CDR}
Port = ${APP_PORT_MYSQL}
option = 3
Charset=utf8
ODBC
  log_info "odbc: DSN MySQL-asteriskcdrdb -> ${MYSQL_SERVER}:${APP_PORT_MYSQL}/${MYSQL_DATABASE_CDR} (driver $drv)"
}
