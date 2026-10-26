#!/usr/bin/env bash
# P3-18: ODBC for the CDR (services/odbc.sh) against a MariaDB:
# - odbcinst.ini: driver MySQL = libmaodbc.so of this architecture; odbc.ini:
#   DSN MySQL-asteriskcdrdb on MYSQL_SERVER/APP_PORT_MYSQL/MYSQL_DATABASE_CDR,
#   as 20.16; a second start leaves one [MySQL] section;
# - isql MySQL-asteriskcdrdb connects and reads the CDR database;
# - Asterisk with the res_odbc connection of FreePBX (fixture): "odbc show"
#   reports it connected;
# - negative checks: a wrong MYSQL_SERVER makes isql fail; a driver path not
#   of this architecture makes isql fail.
# arm64: same code, checked with the deferred arm64 run (P1-11).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-18
assert_cmd "image builds" -- t_build_image "$image"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias cdrdb \
  -e MARIADB_ROOT_PASSWORD=rootpw -e MARIADB_DATABASE=asteriskcdrdb -e MARIADB_USER=asterisk \
  -e MARIADB_PASSWORD=astpw --health-cmd 'healthcheck.sh --connect --innodb_initialized' \
  --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
docker exec "$db" mariadb -uroot -prootpw asteriskcdrdb -e 'CREATE TABLE cdr (uniqueid VARCHAR(32)); INSERT INTO cdr VALUES ("p3-18-row")'

c=$(t_run pbx "$image" --network "$net" -e MYSQL_SERVER=cdrdb -e ASTERISK_ENABLED=true -e HTTPD_ENABLED=false \
  -e IZPBX_ENABLED=false -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false -e POSTFIX_ENABLED=false \
  -v "$TESTS_DIR/fixtures/odbc/res_odbc.conf:/etc/asterisk/res_odbc.conf:ro")
assert_cmd "Asterisk starts" -- t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted'

drv=$(docker exec "$c" sh -c 'ls /usr/lib/*/odbc/libmaodbc.so')
assert_contains "$(docker exec "$c" cat /etc/odbcinst.ini)" "Driver=$drv" "odbcinst.ini: driver MySQL = $drv"
case "$(docker exec "$c" uname -m)" in
  x86_64) multiarch=x86_64-linux-gnu ;;
  aarch64) multiarch=aarch64-linux-gnu ;;
  *) multiarch=unknown ;;
esac
assert_eq "/usr/lib/$multiarch/odbc/libmaodbc.so" "$drv" "the driver path is the one of this architecture"
ini=$(docker exec "$c" cat /etc/odbc.ini)
assert_contains "$ini" "[MySQL-asteriskcdrdb]" "odbc.ini: DSN MySQL-asteriskcdrdb"
assert_contains "$ini" "server = cdrdb" "odbc.ini: server from MYSQL_SERVER"
assert_contains "$ini" "database = asteriskcdrdb" "odbc.ini: database from MYSQL_DATABASE_CDR"
assert_contains "$ini" "Port = 3306" "odbc.ini: port from APP_PORT_MYSQL"

isql() { docker exec "$1" sh -c 'echo "SELECT uniqueid FROM cdr" | isql -b MySQL-asteriskcdrdb asterisk astpw'; }
assert_contains "$(isql "$c" 2>&1)" "p3-18-row" "isql MySQL-asteriskcdrdb connects and reads the CDR table"
assert_cmd "odbc show: connection asteriskcdrdb active" -- t_wait_for 30 -- \
  sh -c "docker exec '$c' asterisk -rx 'odbc show asteriskcdrdb' | grep -q 'Number of active connections: [1-9]'"

docker restart "$c" >/dev/null
assert_cmd "after a restart Asterisk starts" -- t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted'
assert_eq 1 "$(docker exec "$c" grep -c '^\[MySQL\]' /etc/odbcinst.ini)" "after a restart: one [MySQL] section"

# --- negative checks
bad=$(t_run bad "$image" --network "$net" -e MYSQL_SERVER=nodb.invalid -e ASTERISK_ENABLED=false -e HTTPD_ENABLED=false \
  -e IZPBX_ENABLED=false -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false -e POSTFIX_ENABLED=false)
t_wait_for 60 -- docker exec "$bad" test -s /etc/odbc.ini || true
sleep 2
assert_cmd_fails "control: a wrong MYSQL_SERVER makes isql fail" -- sh -c "docker exec '$bad' sh -c 'echo SELECT 1 | isql -b MySQL-asteriskcdrdb asterisk astpw' | grep -q '^| 1'"
docker exec "$c" sed -i 's|^Driver=/usr/lib/[^/]*/|Driver=/usr/lib/aarch64-linux-gnu/|' /etc/odbcinst.ini
[ "$(uname -m)" == "aarch64" ] && docker exec "$c" sed -i 's|aarch64-linux-gnu|x86_64-linux-gnu|' /etc/odbcinst.ini
assert_cmd_fails "control: a driver of another architecture makes isql fail" -- sh -c "isql '$c' 2>&1 | grep -q p3-18-row"
finish
