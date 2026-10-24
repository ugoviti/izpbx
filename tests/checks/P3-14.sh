#!/usr/bin/env bash
# P3-14: phpMyAdmin (Debian package) enabled or disabled by izpbx-init
# (services/pma.sh), idempotent.
# - golden (pma case): conf-available/phpmyadmin_izpbx.conf equals the
#   20.16.22 phpMyAdmin_izpbx.conf with the Debian path (/usr/share/phpMyAdmin
#   -> /usr/share/phpmyadmin, design C11); the default alias is gone from the
#   package configuration (as in 20.16); the database host is MYSQL_SERVER;
#   apache2ctl -t OK;
# - HTTP: 200 on PMA_ALIAS from an allowed address (localhost), 403 from an
#   address not in PMA_ALLOW_FROM (another container), 404 on /phpmyadmin;
# - two restarts: one alias, the same Require lines, still 200;
# - enabled then disabled (init run twice): configuration off and removed;
# - the cookie secret is made per container (not the one of the image).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-14
golden="$TESTS_DIR/golden"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

docker run --rm --entrypoint "" --hostname izpbx-golden --env-file "$golden/cases/pma.env" "$image" bash -c \
  'izpbx-init --dry-run >/tmp/init.log 2>&1 || cat /tmp/init.log >&2
   . /etc/apache2/envvars; mkdir -p "$APACHE_RUN_DIR"; apache2ctl -t >/dev/null 2>&1 && echo "syntax ok" >&2
   grep -c "^Alias /phpmyadmin " /etc/phpmyadmin/apache.conf >&2 || true
   sed -n "s/^\$dbserver=//p" /etc/phpmyadmin/config-db.php >&2
   cat /etc/apache2/conf-available/phpmyadmin_izpbx.conf' > "$work/new.conf" 2> "$work/new.err"
old="$golden/20.16.22/pma/files/etc"
if diff -u <(sed 's|/usr/share/phpMyAdmin|/usr/share/phpmyadmin|' "$old/httpd/conf.d/phpMyAdmin_izpbx.conf") "$work/new.conf" > "$work/conf.diff"; then
  pass "phpmyadmin_izpbx.conf same as 20.16.22 (apart from the Debian path)"
else
  fail "phpmyadmin_izpbx.conf differs"; cat "$work/conf.diff" >&2
fi
err=$(cat "$work/new.err")
assert_contains "$err" "syntax ok" "apache2ctl -t"
assert_eq 0 "$(grep -c '^Alias /phpMyAdmin ' "$old/httpd/conf.d/phpMyAdmin.conf" || true)" "20.16.22: no default alias left (reference)"
assert_contains "$err" "0" "no default alias left in the package configuration"
old_host=$(sed -n "s/^\$cfg\['Servers'\]\[\$i\]\['host'\] = \(.*\);/\1/p" "$old/phpMyAdmin/config.inc.php")
assert_contains "$err" "${old_host};" "database host as 20.16.22 ($old_host)"

# --- HTTP access from allowed and not allowed addresses
net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
c=$(t_run pma "$image" --network "$net" --network-alias pbx -e PMA_ENABLED=true -e PMA_ALLOW_FROM=127.0.0.0/8 \
  -e ASTERISK_ENABLED=false -e IZPBX_ENABLED=false -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false)
code() { docker exec "$c" curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1$1"; }
t_wait_for 90 -- sh -c "[ \"\$(docker exec $c curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/admin/pma/)\" = 200 ]" || log "pma not answering"
assert_eq 200 "$(code /admin/pma/)" "HTTP 200 on /admin/pma/ from an allowed address"
assert_eq 404 "$(code /phpmyadmin/)" "HTTP 404 on the default alias /phpmyadmin"
other=$(docker run --rm --network "$net" --entrypoint "" "$image" curl -s -o /dev/null -w '%{http_code}' http://pbx/admin/pma/)
assert_eq 403 "$other" "HTTP 403 from an address not in PMA_ALLOW_FROM"
secret=$(docker exec "$c" cat /var/lib/phpmyadmin/blowfish_secret.inc.php 2>/dev/null)
assert_cmd "cookie secret made at start (64 hex chars)" -- grep -qE "blowfish_secret'\] = '[0-9a-f]{64}'" <<<"$secret"

# --- two restarts
for _ in 1 2; do docker restart "$c" >/dev/null; done
t_wait_for 90 -- sh -c "[ \"\$(docker exec $c curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/admin/pma/)\" = 200 ]" || log "pma not answering after restarts"
assert_eq 1 "$(docker exec "$c" sh -c 'cat /etc/apache2/conf-enabled/*.conf' | grep -c '^Alias /admin/pma ')" "after two restarts: one alias"
assert_eq 1 "$(docker exec "$c" grep -c 'Require ip' /etc/apache2/conf-available/phpmyadmin_izpbx.conf)" "after two restarts: Require lines not duplicated"
assert_eq 200 "$(code /admin/pma/)" "after two restarts: HTTP 200"
assert_eq "$secret" "$(docker exec "$c" cat /var/lib/phpmyadmin/blowfish_secret.inc.php)" "cookie secret kept across restarts"

# --- enabled then disabled
out=$(docker run --rm --entrypoint "" "$image" bash -c \
  'PMA_ENABLED=true izpbx-init --dry-run >/dev/null 2>&1; PMA_ENABLED=false izpbx-init --dry-run >/dev/null 2>&1
   ls /etc/apache2/conf-enabled; if test -e /etc/apache2/conf-available/phpmyadmin_izpbx.conf; then echo "LOCAL LEFT"; fi' 2>&1)
assert_cmd_fails "disabled: phpmyadmin confs off" -- grep -q 'phpmyadmin' <<<"$out"
assert_cmd_fails "disabled: izPBX configuration removed" -- grep -q 'LOCAL LEFT' <<<"$out"
finish
