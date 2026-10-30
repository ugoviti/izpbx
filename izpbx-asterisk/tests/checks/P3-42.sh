#!/usr/bin/env bash
# P3-42: fail2ban 1.0.2 of Debian 12 warned at every start "'allowipv6' not
# defined in 'Definition'. Using default one: 'auto'" (seen in the log of a
# migrated production PBX): /etc/fail2ban/fail2ban.d/izpbx.local sets it to
# its default. fail2ban.conf stays the one of the package (golden P3-25).
# - in a started container (izpbx-init, jails): fail2ban-client -t OK, no
#   allowipv6 warning there nor in the container log;
# - negative: without izpbx.local the warning is back;
# - MariaDB with the command of compose.yml: no "Aborted connection" note for a
#   client that exits without closing (as every fwconsole run does, hundreds
#   during a migration) and no warning about expire_logs_days of the image;
#   negative: without --log-warnings=1 --expire-logs-days=0 both are there.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-42
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "fail2ban.conf of the package untouched" -- docker run --rm --entrypoint "" "$image" grep -qx '#allowipv6 = auto' /etc/fail2ban/fail2ban.conf
c=$(t_run f2b "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=false -e FAIL2BAN_ENABLED=true)
t_wait_for 120 -- sh -c "docker logs '$c' 2>&1 | grep -q 'izpbx-init: done'" || die "izpbx-init did not finish"
out=$(docker exec "$c" fail2ban-client -t 2>&1) || true
assert_contains "$out" "OK: configuration test is successful" "fail2ban configuration OK"
assert_cmd_fails "no allowipv6 warning" -- grep -q allowipv6 <<< "$out"
assert_cmd_fails "no allowipv6 warning in the container log" -- sh -c "docker logs '$c' 2>&1 | grep -q allowipv6"
docker exec "$c" mv /etc/fail2ban/fail2ban.d/izpbx.local /tmp/
assert_contains "$(docker exec "$c" fail2ban-client -t 2>&1 || true)" "'allowipv6' not defined" "negative: without izpbx.local the warning is back"

dbcmd=$(sed -n 's/^    command: //p' "$DEPLOY_FILES/compose.yml" | head -n 1)
assert_contains "$dbcmd" "--log-warnings=1 --expire-logs-days=0" "compose.yml: MariaDB options"
mdb() { # name options -> log of a MariaDB with two clients killed
  local m opts
  read -r -a opts <<< "$2"
  m=$(t_run "$1" docker.io/mariadb:10.11.19 -e MARIADB_ROOT_PASSWORD=x -- "${opts[@]}")
  t_wait_for 120 -- sh -c "docker logs '$m' 2>&1 | grep -q 'Version: .*port: 3306'" || die "MariaDB $1 did not start"
  # TCP clients killed during a query: the server notices when the query ends
  docker exec "$m" sh -c 'for i in 1 2; do timeout -s KILL 1 mariadb -h127.0.0.1 -uroot -px -e "SELECT SLEEP(2)"; done' >/dev/null 2>&1 || true
  sleep 4
  docker logs "$m" 2>&1
}
out=$(mdb mdb "$dbcmd")
assert_cmd_fails "MariaDB: no Aborted connection note" -- grep -q 'Aborted connection' <<< "$out"
assert_cmd_fails "MariaDB: no expire_logs_days warning" -- grep -q 'expire-logs-days or --binlog-expire-logs-seconds' <<< "$out"
out=$(mdb mdbneg "${dbcmd%% --log-warnings*}")
assert_contains "$out" "Aborted connection" "negative: without the options the Aborted connection notes are there"
assert_contains "$out" "expire-logs-days or --binlog-expire-logs-seconds" "negative: and the expire_logs_days warning"
finish
