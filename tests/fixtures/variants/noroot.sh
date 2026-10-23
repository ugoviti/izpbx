# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # sourced by make-fixture.sh: shares its variables
# noroot (P0-08c): no MYSQL_ROOT_PASSWORD for izPBX. The databases and the
# user are created by hand beforehand, with grants on the two databases only.
NO_ROOT=1
variant_pre_pbx() {
  log "variant noroot: creating databases and user by hand"
  db_sql <<SQL
CREATE DATABASE asterisk;
CREATE DATABASE asteriskcdrdb;
CREATE USER 'asterisk'@'%' IDENTIFIED BY '$DB_PW';
GRANT ALL PRIVILEGES ON asterisk.* TO 'asterisk'@'%';
GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'asterisk'@'%';
SQL
}
variant_manifest() { echo "anomaly=no MYSQL_ROOT_PASSWORD, user with grants on the two databases only"; }
