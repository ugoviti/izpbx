#!/usr/bin/env bash
# P4-04: maintenance mode without the opt-in (D4, S10). A FreePBX 16 /data
# (20.16.22 fixture) without IZPBX_MIGRATE_FREEPBX:
# - the init completes, the container stays up without restarts (restart
#   policy unless-stopped), no service runs (Asterisk, httpd, php-fpm, cron),
#   the image healthcheck reports unhealthy "maintenance mode";
# - /data (outside .izpbx-migration, where the preflight report goes) and
#   the databases are unchanged;
# - with the opt-in but a blocking check (macro fixture): maintenance mode
#   too, the reason names the blocking checks;
# - control: without the maintenance flag the same services do start
#   (s6-svc -u asterisk brings Asterisk up).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-04
fx="$TESTS_DIR/fixtures/out"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -o "$fx" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
assert_cmd "macro variant derives" -- "$TESTS_DIR/fixtures/derive-variant.sh" "$fx/20.16.22" macro

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/20.16.22/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
  docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot

fixture_data() { # volume fixture
  docker run --rm --entrypoint "" -v "$1:/data" -v "$fx/$2:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
}
datasum() { # volume -> checksum of /data outside .izpbx-migration: every entry
  # (type, mode, owner, symlink target) and the content of the regular files
  docker run --rm --entrypoint "" -v "$1:/data:ro" "$image" sh -c 'cd /data && {
    find . -path ./.izpbx-migration -prune -o -printf "%y %m %U:%G %p %l\n" | LC_ALL=C sort
    find . -path ./.izpbx-migration -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum; } | sha256sum'
}
dbsum() { docker exec -e MYSQL_PWD=rootpw "$db" sh -c 'for s in asterisk asteriskcdrdb; do
  mariadb -uroot -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema=\"$s\" ORDER BY 1" |
  while read -r t; do mariadb -uroot -N "$s" -e "CHECKSUM TABLE \`$t\`"; done; done | md5sum'; }
pbx() { # name volume [args]: the image healthcheck, with a short start period
  local n=$1 v=$2; shift 2
  t_run "$n" "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw \
    --restart unless-stopped --health-start-period 1s --health-interval 5s --health-retries 2 "$@"
}
init_done() { docker logs "$1" 2>&1 | grep 'izpbx-init: done' >/dev/null; }
health() { docker inspect -f '{{.State.Health.Status}}' "$1"; }
running() { docker exec "$1" sh -c "pgrep -f '^asterisk -f' || pgrep -x apache2 || pgrep -x php-fpm8.2 || pgrep -x cron" >/dev/null 2>&1; }

# --- FreePBX 16 without the opt-in
vb=$(t_volume base); fixture_data "$vb" 20.16.22
db_before=$(dbsum) files_before=$(datasum "$vb")
c=$(pbx m "$vb")
assert_cmd "the init completes" -- t_wait_for 180 -- init_done "$c"
assert_contains "$(docker logs "$c" 2>&1)" "MAINTENANCE MODE: FreePBX 16 data found and the migration to FreePBX 17 is not enabled" \
  "maintenance mode reported with the reason"
assert_contains "$(docker logs "$c" 2>&1)" "set IZPBX_MIGRATE_FREEPBX=true" "instructions to migrate in the log"
assert_cmd "the healthcheck reports unhealthy" -- t_wait_for 60 -- sh -c "[ \"\$(docker inspect -f '{{.State.Health.Status}}' $c)\" = unhealthy ]"
assert_contains "$(docker exec "$c" izpbx-healthcheck)" "unhealthy: maintenance mode" "the healthcheck names maintenance mode"
sleep 30
assert_eq "true 0" "$(docker inspect -f '{{.State.Running}} {{.RestartCount}}' "$c")" "after 30 s: still running, no restart"
assert_cmd_fails "no Asterisk, httpd, php-fpm or cron running" -- running "$c"
assert_contains "$(docker logs "$c" 2>&1)" "asterisk: maintenance mode, not started" "Asterisk kept down by the maintenance flag"
docker stop "$c" >/dev/null
assert_eq "$db_before" "$(dbsum)" "the databases are unchanged"
assert_eq "$files_before" "$(datasum "$vb")" "/data is unchanged outside .izpbx-migration"

# --- opt-in, but a blocking check
vm=$(t_volume macro); fixture_data "$vm" 20.16.22-macro
c2=$(pbx mm "$vm" -e IZPBX_MIGRATE_FREEPBX=true)
assert_cmd "opt-in + blocking check: the init completes" -- t_wait_for 180 -- init_done "$c2"
assert_contains "$(docker logs "$c2" 2>&1)" "MAINTENANCE MODE: the migration checks found blocking problems" \
  "opt-in + blocking check: maintenance mode, the reason names the checks"
assert_cmd_fails "opt-in + blocking check: no service running" -- running "$c2"

# --- control: without the flag the services do start
docker exec "$c2" rm -f /run/izpbx/maintenance
docker exec "$c2" sh -c 'rm -f /run/service/asterisk/down; /command/s6-svc -u /run/service/asterisk'
assert_cmd "control: without the maintenance flag Asterisk starts" -- \
  t_wait_for 60 -- docker exec "$c2" pgrep -f '^asterisk -f'
finish
