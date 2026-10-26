#!/usr/bin/env bash
# P3-24: izpbx-healthcheck (design H5) as the health command of the container.
# - FreePBX installed: Docker reports healthy;
# - unhealthy (exit 1 with the reason) with Asterisk stopped, with httpd
#   stopped, with the database unreachable and in maintenance mode, healthy
#   again after each; in maintenance mode Docker reports unhealthy;
# - Asterisk alone (IZPBX_ENABLED=false, no database): healthy.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-24
assert_cmd "image builds" -- t_build_image "$image"
health=(--health-cmd izpbx-healthcheck --health-interval 5s --health-timeout 20s --health-retries 2 --health-start-period 30m)

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
vol=$(t_volume data)
c=$(t_run pbx "$image" --network "$net" -v "$vol:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw "${health[@]}")
a=$(t_run ast "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true "${health[@]}")

assert_cmd "FreePBX installed: Docker reports healthy" -- t_wait_healthy "$c" 1500
hc() { docker exec "$c" izpbx-healthcheck; }
assert_eq "healthy" "$(hc)" "izpbx-healthcheck: healthy"
svc() { docker exec "$c" /command/s6-svc "$1" -w"${1#-}" -T 60000 "/run/service/$2"; }
expect_unhealthy() { # what reason
  local out rc=0; out=$(hc) || rc=$?
  assert_eq 1 "$rc" "$1: exit 1"
  assert_contains "$out" "$2" "$1: reason '$2'"
}

svc -d asterisk
expect_unhealthy "Asterisk stopped" "Asterisk not answering"
svc -u asterisk
assert_cmd "Asterisk back: healthy" -- t_wait_for 120 -- hc

svc -d httpd
expect_unhealthy "httpd stopped" "HTTP"
svc -u httpd
assert_cmd "httpd back: healthy" -- t_wait_for 60 -- hc

docker network disconnect "$net" "$db"
expect_unhealthy "database unreachable" "database db:3306/asterisk not reachable"
docker network connect --alias db "$net" "$db"
assert_cmd "database back: healthy" -- t_wait_for 60 -- hc

docker exec "$c" sh -c 'echo "migration checks failed" > /run/izpbx/maintenance'
expect_unhealthy "maintenance mode" "maintenance mode (migration checks failed)"
assert_cmd "maintenance mode: Docker reports unhealthy" -- \
  t_wait_for 60 -- sh -c "[ \"\$(docker inspect -f '{{.State.Health.Status}}' $c)\" = unhealthy ]"
docker exec "$c" rm -f /run/izpbx/maintenance
assert_cmd "maintenance over: Docker reports healthy" -- t_wait_healthy "$c" 60

assert_cmd "Asterisk alone, no database: healthy" -- t_wait_healthy "$a" 120
finish
