#!/usr/bin/env bash
# P3-06 (design H1-H3): PHP through php-fpm. Apache runs mpm_event +
# proxy_fcgi without mod_php; the php-fpm pool "asterisk" runs its workers as
# asterisk; the 20.16.22 settings (99-local.ini, hardening included) apply to
# fpm and cli; date.timezone follows TZ in both.
# - php-fpm8.2 -t OK;
# - a test page served through FastCGI reports SAPI fpm-fcgi, user asterisk
#   and the expected allow_url_include, display_errors,
#   session.upload_progress.enabled, memory_limit, date.timezone; php -r
#   reports the same values for the cli;
# - negative checks: an invalid TZ falls back to UTC (and the page shows it),
#   and Apache has no php_module (mod_php would serve the page instead of fpm).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-06
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "php-fpm8.2 -t" -- docker run --rm --entrypoint "" "$image" php-fpm8.2 -t

PHP='$u = posix_getpwuid(posix_geteuid())["name"];
foreach (["sapi" => php_sapi_name(), "user" => $u,
  "allow_url_include" => ini_get("allow_url_include"), "display_errors" => ini_get("display_errors"),
  "session.upload_progress.enabled" => ini_get("session.upload_progress.enabled"),
  "memory_limit" => ini_get("memory_limit"), "date.timezone" => ini_get("date.timezone"),
  "opcache" => ini_get("opcache.enable")] as $k => $v) echo "$k=$v\n";'
# expected values: ini_get returns "" or "0" for Off
expect() { # output sapi user tz label
  local out=$1
  assert_contains "$out" "sapi=$2" "$5: SAPI $2"
  assert_contains "$out" "user=$3" "$5: runs as $3"
  assert_contains "$out" "allow_url_include=
" "$5: allow_url_include Off"
  grep -Eq '^display_errors=(0|)$' <<<"$out" && pass "$5: display_errors Off" || fail "$5: display_errors not Off ($(grep display_errors <<<"$out"))"
  assert_contains "$out" "session.upload_progress.enabled=0" "$5: session.upload_progress.enabled 0"
  assert_contains "$out" "memory_limit=512M" "$5: memory_limit 512M"
  assert_contains "$out" "date.timezone=$4" "$5: date.timezone $4"
}

start() { # name TZ -> container, page served
  local c
  c=$(t_run "$1" "$image" -e TZ="$2")
  t_wait_for 90 -- docker exec "$c" curl -fsS -o /dev/null http://localhost/ || log "httpd not answering"
  docker exec "$c" sh -c "printf '<?php %s' '$(printf '%s' "$PHP" | sed "s/'/'\\\\''/g")' > /var/www/html/izpbx-test.php"
  printf '%s\n' "$c"
}

c=$(start rome Europe/Rome)
page=$(docker exec "$c" curl -fsS http://localhost/izpbx-test.php 2>&1 || true)
expect "$page" fpm-fcgi asterisk Europe/Rome "fpm (page via FastCGI)"
cli=$(docker exec "$c" php -r "$PHP" 2>&1 || true)
expect "$cli" cli root Europe/Rome "cli"
workers=$(docker exec "$c" ps -o user=,args= -C php-fpm8.2 | grep 'pool asterisk' | awk '{print $1}' | sort -u)
assert_eq "asterisk" "$workers" "php-fpm workers run as asterisk"
mods=$(docker exec "$c" apache2ctl -M 2>/dev/null)
assert_contains "$mods" "mpm_event_module" "Apache uses mpm_event"
assert_contains "$mods" "proxy_fcgi_module" "Apache has proxy_fcgi"
assert_cmd_fails "control: no mod_php in Apache" -- grep -q php_module <<<"$mods"
assert_eq "Europe/Rome" "$(docker exec "$c" cat /etc/timezone)" "/etc/timezone follows TZ"

# negative check: an invalid TZ falls back to UTC
c=$(start badtz '../../etc/passwd')
page=$(docker exec "$c" curl -fsS http://localhost/izpbx-test.php 2>&1 || true)
assert_contains "$page" "date.timezone=UTC" "control: invalid TZ -> UTC in fpm"
assert_contains "$(docker logs "$c" 2>&1)" "invalid TZ" "control: invalid TZ logged"
finish
