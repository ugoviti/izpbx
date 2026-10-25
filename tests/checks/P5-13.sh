#!/usr/bin/env bash
# P5-13: commercial modules encoded with ionCube on a new installation.
# FreePBX installed; the commercial repo enabled and the commercial module
# sysadmin downloaded (not installed, no license needed to load its files;
# needs the FreePBX mirror). One of its files encoded with ionCube
# (header "@Ioncube"):
# - CLI: php includes it and ioncube_loader_version() answers;
# - php-fpm: a page that includes it answers through Apache with the loader
#   version and the fpm-fcgi SAPI;
# - negative check: "php -n" (no ini files, no loader) cannot run it (the
#   encoded file stops PHP, exit status not 0, nothing after the include).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-13
assert_cmd "image builds" -- t_build_image "$image"
net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
c=$(t_run pbx "$image" --network "$net" -v "$(t_volume data):/data" -e APP_DATA=/data \
  -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw)
assert_cmd "FreePBX installed: healthy" -- t_wait_healthy "$c" 1500

docker exec -u asterisk "$c" sh -c 'fwconsole ma enablerepo commercial && fwconsole ma download sysadmin' >/dev/null 2>&1
files=$(docker exec "$c" sh -c 'grep -rlE "^// 0 @Ioncube;" /var/www/html/admin/modules/sysadmin --include=*.php 2>/dev/null')
assert_cmd "sysadmin downloaded with ionCube encoded files ($(wc -w <<< "$files"))" -- test -n "$files"
# some encoded files call FreePBX functions at load time: the first one that
# loads on its own with the loader (the same file fails without it, below)
enc=
for f in $files; do
  if docker exec "$c" php -r "include '$f'; echo 'izpbx-loaded';" 2>/dev/null | grep -q izpbx-loaded; then enc=$f; break; fi
done
assert_cmd "an encoded file loads on its own" -- test -n "$enc"
log "encoded file: $enc ($(docker exec "$c" sed -n 4p "$enc" 2>/dev/null))"

assert_contains "$(docker exec "$c" php -r "include '$enc'; echo 'loaded, ioncube ', ioncube_loader_version(), PHP_EOL;" 2>&1)" \
  "loaded, ioncube 15." "CLI: the encoded file loads (ionCube loader)"
web=$(docker exec "$c" sh -c "printf '<?php include \"$enc\"; echo \"loaded, ioncube \", ioncube_loader_version(), \" sapi \", php_sapi_name();' > /var/www/html/izpbx-ioncube-test.php
  curl -s http://localhost/izpbx-ioncube-test.php; rm -f /var/www/html/izpbx-ioncube-test.php")
assert_contains "$web" "loaded, ioncube 15." "php-fpm: the encoded file loads (ionCube loader)"
assert_contains "$web" "sapi fpm-fcgi" "php-fpm: served by php-fpm"

out=$(docker exec "$c" php -n -r "include '$enc'; echo 'loaded', PHP_EOL;" 2>&1) && rc=0 || rc=$?
assert_ne 0 "$rc" "control: without the loader (php -n) PHP stops (exit $rc)"
assert_cmd_fails "control: without the loader nothing runs after the include" -- grep -q loaded <<< "$out"
finish
