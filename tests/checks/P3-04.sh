#!/usr/bin/env bash
# P3-04: dry-run mode. izpbx-init --dry-run (or IZPBX_DRY_RUN=true) generates
# the files, records database writes, "fwconsole setting" and commands in
# IZPBX_DRY_RUN_LOG instead of running them, and no service starts.
# A test init step uses every helper of actions.sh against a MariaDB with the
# general log on:
# - izpbx-init --dry-run: 0 write queries in the general log (the read query
#   reaches the DB), every action recorded, files still generated;
# - the container started normally (/init) with IZPBX_DRY_RUN=true: the init
#   completes, every s6 service is down and no service process runs, 0 writes;
# - negative check: the same step without dry-run writes to the DB and the
#   general log shows it.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-04
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db \
  -e MARIADB_ROOT_PASSWORD=rootpw -e MARIADB_DATABASE=asterisk -e MARIADB_USER=asterisk \
  -e MARIADB_PASSWORD=astpw --health-cmd 'healthcheck.sh --connect --innodb_initialized' \
  --health-interval 2s --health-retries 60 -- --general-log=1 --general-log-file=/tmp/general.log)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
docker exec "$db" mariadb -uroot -prootpw asterisk -e 'CREATE TABLE t (v INT)'

cat > "$work/50-test-actions.sh" <<'EOF'
# shellcheck shell=bash
. /usr/local/lib/izpbx/actions.sh
izpbx_sql "INSERT INTO t VALUES (42)"
izpbx_sql "UPDATE t SET v = 43"
fpbx_setting AMPWEBROOT /var/www/html
izpbx_do touch /tmp/izpbx-test-action
log_info "test step: read $(izpbx_sql_query 'SELECT 7 AS izpbx_test_read')"
EOF
chmod 644 "$work/50-test-actions.sh"
common=(--network "$net" -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw
        -v "$work/50-test-actions.sh:/usr/local/lib/izpbx/init.d/50-test-actions.sh:ro")
writes() { docker exec "$db" grep -Eic 'Query[[:space:]]+(INSERT|UPDATE|DELETE|REPLACE|CREATE|ALTER|DROP|TRUNCATE|GRANT)' /tmp/general.log || true; }
reads() { docker exec "$db" grep -c 'izpbx_test_read' /tmp/general.log || true; }
w0=$(writes)

# --- izpbx-init --dry-run
out=$(docker run --rm --entrypoint "" "${common[@]}" "$image" \
  bash -c 'izpbx-init --dry-run && echo "--- log" && cat /run/izpbx/dry-run.log &&
           { [ -e /tmp/izpbx-test-action ] && echo "action ran" || echo "action not run"; } &&
           [ -L /usr/sbin/sendmail ] && echo "files generated"' 2>&1) || true
assert_eq "$w0" "$(writes)" "dry-run: no write query in the general log"
assert_ne 0 "$(reads)" "dry-run: the read query reached the DB"
assert_contains "$out" "sql: INSERT INTO t VALUES (42)" "dry-run: INSERT recorded"
assert_contains "$out" "sql: UPDATE t SET v = 43" "dry-run: UPDATE recorded"
assert_contains "$out" "fwconsole setting AMPWEBROOT /var/www/html" "dry-run: fwconsole setting recorded"
assert_contains "$out" "touch /tmp/izpbx-test-action" "dry-run: command recorded"
assert_contains "$out" "action not run" "dry-run: command not run"
assert_contains "$out" "files generated" "dry-run: files still generated"
assert_contains "$out" "izpbx-init: done" "dry-run: init completes"
assert_cmd_fails "unknown option refused" -- docker run --rm --entrypoint "" "$image" izpbx-init --bogus

# --- full start with IZPBX_DRY_RUN=true
c=$(t_run full "$image" "${common[@]}" -e IZPBX_DRY_RUN=true)
assert_cmd "full start: init completes" -- t_wait_for 90 -- sh -c "docker logs $c 2>&1 | grep -q 'izpbx-init: done'"
sleep 5
up=$(docker exec "$c" sh -c 'for s in /run/service/*; do case ${s##*/} in s6rc-*|s6-*) continue;; esac; /command/s6-svstat -o up "$s" | grep -q true && echo "${s##*/}"; done' || true)
assert_eq "" "$up" "full start: every service down"
procs=$(docker exec "$c" sh -c 'for p in asterisk apache2 php-fpm8.2 cron fail2ban-server master dnsmasq chronyd zabbix_agent2 fop2_server; do pgrep -x "$p" >/dev/null && echo "$p"; done' || true)
assert_eq "" "$procs" "full start: no service process"
assert_eq "$w0" "$(writes)" "full start: no write query"

# --- negative check: without dry-run the step writes
docker run --rm --entrypoint "" "${common[@]}" "$image" izpbx-init >/dev/null 2>&1 || true
assert_ne "$w0" "$(writes)" "control: without dry-run the writes show in the general log"
assert_eq 43 "$(docker exec "$db" mariadb -uroot -prootpw -N asterisk -e 'SELECT v FROM t')" "control: the row was written"
finish
