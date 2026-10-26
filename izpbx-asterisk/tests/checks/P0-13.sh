#!/usr/bin/env bash
# P0-13 (H4): FreePBX 17 .htaccess files with php-fpm.
# - 0 php_value/php_flag directives active under fpm in the .htaccess files of
#   the image (framework + the 45 default modules) and of an installed
#   FreePBX 17 (the only one, admin/.htaccess max_input_vars 5000, sits in
#   <IfModule php7_module>: inert, so the value goes into the fpm pool);
# - prototype served by apache mpm_event + proxy_fcgi + php8.2-fpm: login and
#   HTTP 200 on the main admin pages, no FreePBX error page, SAPI fpm-fcgi
#   with max_input_vars 5000.
# Negative: the scanner reports active directives in a synthetic .htaccess;
# a wrong password does not log in; an active php_value gives HTTP 500.
source "$(dirname "$0")/../lib.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
proto_image=izpbx-proto/fpbx17-fpm:17.0.33
proto_dir="$TESTS_DIR/proto/fpbx17-fpm"
# shellcheck source=../proto/proto.sh
source "$TESTS_DIR/proto/proto.sh"
scan="$TESTS_DIR/proto/htaccess-active-php.awk"
image=izpbx-asterisk:p0-13

# --- static scan: scanner self-test, then the image tree
printf 'php_value a 1\n<IfModule php7_module>\nphp_value b 2\n</IfModule>\n<IfModule !php_module>\nphp_flag c on\n</IfModule>\n' > "$work/htaccess"
assert_eq "2" "$(awk -f "$scan" "$work/htaccess" | wc -l)" "control: the scanner reports the 2 active directives of a synthetic .htaccess"
assert_cmd "image builds" -- t_build_image "$image"
found=$(docker run --rm --entrypoint "" -v "$scan:/scan.awk:ro" "$image" bash -c 'find /usr/src/freepbx -name .htaccess -exec awk -f /scan.awk {} +')
assert_eq "" "$found" "image: no php_value/php_flag active under fpm in the .htaccess files"
n=$(docker run --rm --entrypoint "" "$image" bash -c 'find /usr/src/freepbx -name .htaccess | wc -l')
[ "$n" -ge 3 ] || die "only $n .htaccess files in the image: scan would be meaningless"
docker rmi "$image" >/dev/null 2>&1 || true

# --- prototype with php-fpm
assert_cmd "base prototype image builds" -- docker build -q -t izpbx-proto/fpbx17:17.0.33 "$TESTS_DIR/proto/fpbx17"
assert_cmd "FreePBX 17 installs on the php-fpm prototype" -- proto_up
mods=$(docker exec "$pbx" apachectl -M 2>/dev/null)
assert_contains "$mods" "proxy_fcgi_module" "apache uses proxy_fcgi"
assert_eq "0" "$(grep -c 'php_module' <<< "$mods" || true)" "no PHP apache module loaded"
docker cp "$scan" "$pbx:/tmp/scan.awk"
found=$(docker exec "$pbx" bash -c 'find -L /var/www/html -name .htaccess -exec awk -f /tmp/scan.awk {} +')
assert_eq "" "$found" "installed FreePBX 17: no php_value/php_flag active under fpm"

# admin user, first-run wizard done, and the asterisk ssh key the backup page reads
proto_sql "INSERT INTO ampusers (username,password_sha1,extension_low,extension_high,deptname,sections) VALUES ('admin',SHA1('proto-admin'),'','','','*')"
docker exec -u asterisk "$pbx" php -r 'include "/etc/freepbx.conf"; $o=FreePBX::OOBE(); $c=[]; foreach(array_keys($o->getOOBEModules()) as $m) $c[$m]=$m; $o->setConfig("completed",$c);' >/dev/null 2>&1
docker exec "$pbx" bash -c 'mkdir -p /home/asterisk/.ssh && echo "ecdsa-sha2-nistp256 AAAAproto asterisk@proto" > /home/asterisk/.ssh/id_ecdsa.pub && chown -R asterisk: /home/asterisk/.ssh'

login() { # password -> 0 if logged in
  docker exec "$pbx" bash -c "rm -f /tmp/jar; curl -s -c /tmp/jar -b /tmp/jar -o /dev/null http://localhost/admin/config.php
    curl -s -c /tmp/jar -b /tmp/jar -o /tmp/login.html -d 'username=admin&password=$1' http://localhost/admin/config.php
    grep -c '>Logout<' /tmp/login.html" >/dev/null
}
assert_cmd_fails "control: a wrong password does not log in" -- login wrong-password
assert_cmd "admin logs in" -- login proto-admin
page() { # display -> "code errors wizard"
  docker exec "$pbx" bash -c "curl -s -b /tmp/jar -o /tmp/p.html -w '%{http_code}' 'http://localhost/admin/config.php?display=$1'
    echo \" \$(grep -c 'There was an error' /tmp/p.html) \$(grep -c 'default locales' /tmp/p.html) \$(grep -c '>Logout<' /tmp/p.html)\""
}
for d in index extensions trunks routing did ivr queues ringgroups timeconditions modules advancedsettings backup userman sipsettings asteriskinfo; do
  assert_eq "200 0 0 1" "$(page "$d")" "display=$d: HTTP 200, logged in, no error page"
done
docker exec "$pbx" bash -c 'echo "<?php echo php_sapi_name(),\" \",ini_get(\"max_input_vars\");" > /var/www/html/p013.php'
assert_eq "fpm-fcgi 5000" "$(docker exec "$pbx" curl -s http://localhost/p013.php)" "PHP runs as fpm with max_input_vars 5000"

# negative: an active php_value in admin/.htaccess -> 500 with fpm
docker exec "$pbx" sed -i '1i php_value max_input_vars 6000' /var/www/html/admin/.htaccess
assert_eq "500" "$(page extensions | cut -d' ' -f1)" "control: an active php_value gives HTTP 500"
found=$(docker exec "$pbx" bash -c 'find -L /var/www/html -name .htaccess -exec awk -f /tmp/scan.awk {} +')
assert_contains "$found" "admin/.htaccess:1: php_value max_input_vars 6000" "control: the scanner reports it"

finish
