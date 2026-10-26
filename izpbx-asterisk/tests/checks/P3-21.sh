#!/usr/bin/env bash
# P3-21: secrets (IZPBX_MYSQL_*_PASSWORD_FILE) and no password in the logs or
# in the process list.
# - MYSQL_PASSWORD 'a/b&c d\e|f' from a secret file (IZPBX_MYSQL_PASSWORD_FILE),
#   MYSQL_ROOT_PASSWORD with the same kind of characters: FreePBX installs,
#   the container becomes healthy, freepbx.conf gives the password back to PHP
#   unchanged; a restart (freepbx.conf rewritten from the environment) is
#   healthy again;
# - the command lines of every process, sampled every 0.2 s during the install
#   (izpbx-asterisk/tests/fixtures/secrets/sampler.sh), and docker logs hold neither password;
# - controls: the sampler sees the installer running; a process with a
#   password in its command line, and a password written to the logs, are
#   found by the same checks (the logs one on the logs plus a leaked line).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-21
pw='a/b&c d\e|f'
rootpw='R00t/p&w d\x|z'
sec=$(mktemp -d)
t_on_cleanup "t_rmtree '$sec'"
printf '%s' "$pw" > "$sec/mysql_password"
printf '%s\n%s\n' "$pw" "$rootpw" > "$sec/patterns"
cp "$TESTS_DIR/fixtures/secrets/sampler.sh" "$sec/sampler.sh"
chmod 644 "$sec"/*; chmod 755 "$sec" "$sec/sampler.sh"
assert_cmd "image builds" -- t_build_image "$image"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e "MARIADB_ROOT_PASSWORD=$rootpw" \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
vol=$(t_volume data)
c=$(t_run pbx "$image" --network "$net" -v "$vol:/data" -v "$sec:/secrets:ro" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e IZPBX_MYSQL_PASSWORD_FILE=/secrets/mysql_password -e "MYSQL_ROOT_PASSWORD=$rootpw" \
  --health-cmd "asterisk -rx 'core waitfullybooted' >/dev/null && curl -fsS -o /dev/null http://localhost/admin/config.php" \
  --health-interval 10s --health-timeout 10s --health-retries 3 --health-start-period 30m)
docker exec -d "$c" /secrets/sampler.sh

assert_cmd "install with the password from a secret file: healthy" -- t_wait_healthy "$c" 1500
hits=$(docker exec "$c" sh -c 'wc -l < /tmp/sampler.hits')
seen=$(docker exec "$c" sh -c 'wc -l < /tmp/sampler.seen')
samples=$(docker exec "$c" cat /tmp/sampler.count)
log "process list samples: $samples, with the installer running: $seen"
assert_cmd "control: the sampler saw the installer running" -- test "$seen" -gt 0
assert_eq 0 "$hits" "no password in the command line of any process during the install"
[ "$hits" -eq 0 ] || docker exec "$c" sort -u /tmp/sampler.hits | cut -c1-200 >&2
docker logs "$c" > "$sec/logs" 2>&1
assert_eq 0 "$(grep -c -F -f "$sec/patterns" "$sec/logs" || true)" "no password in docker logs"
grep -F -f "$sec/patterns" "$sec/logs" | sed -e "s|$(printf '%s' "$pw" | sed 's/[|&\\/]/\\&/g')|<pw>|g" \
  -e "s|$(printf '%s' "$rootpw" | sed 's/[|&\\/]/\\&/g')|<rootpw>|g" | head -5 | sed 's/^/    leak: /' >&2 || true
php_pw=$(docker exec "$c" php -r 'include "/etc/freepbx.conf"; echo $amp_conf["AMPDBPASS"];' 2>/dev/null | head -1)
[ "$php_pw" == "$pw" ] && pass "freepbx.conf gives the password back unchanged" || fail "freepbx.conf password differs"
assert_cmd "fwconsole reload with that password" -- docker exec -u asterisk "$c" fwconsole reload

docker restart "$c" >/dev/null
assert_cmd "after a restart (freepbx.conf from the environment): healthy" -- t_wait_healthy "$c" 300
docker exec -d "$c" /secrets/sampler.sh
docker exec -d "$c" sh -c 'P=$(cat /secrets/mysql_password); exec bash -c "sleep 6; true" "$P"'
assert_cmd "control: a password in a command line is found" -- \
  t_wait_for 20 -- docker exec "$c" sh -c 'test -s /tmp/sampler.hits'
docker exec "$c" touch /tmp/sampler.stop
{ cat "$sec/logs"; printf 'leak: %s\n' "$pw"; } > "$sec/logs-leak"
assert_cmd "control: a password in the logs is found by the same grep" -- grep -q -F -f "$sec/patterns" "$sec/logs-leak"
finish
