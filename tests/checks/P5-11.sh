#!/usr/bin/env bash
# P5-11 (T12): UCP, backup upload, music on hold, through Apache + php-fpm.
# FreePBX installed; admin and UCP user created (tests/fixtures/pbx-setup/
# web-users.php); every request from inside the container with curl.
# - admin login: the backup page answers without the login form;
# - UCP login (token of the login page, ajax User/login): status true, the
#   dashboard has the logout link;
# - backup upload of 120 MB as the web UI sends it (Dropzone, 2 MB chunks to
#   ajax.php?module=backup&command=uploadrestore): the file assembled in
#   ASTSPOOLDIR/backup/uploads has the same size and sha256 (the backup dir
#   is made at start: the module mkdir is not recursive);
# - one request of 120 MB reaches PHP (200), one of 140 MB is refused by
#   Apache with 413 (LimitRequestBody, by Content-Length for php-fpm);
# - music on hold: a WAV uploaded to the default category is converted to
#   wav and ulaw, "moh show files" lists it, and a test call to 7300 plays
#   it (Started music on hold, class 'default').
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-11
assert_cmd "image builds" -- t_build_image "$image"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
c=$(t_run pbx "$image" --network "$net" -v "$(t_volume data):/data" -e APP_DATA=/data \
  -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw -v "$TESTS_DIR/fixtures/pbx-setup:/setup:ro")
assert_cmd "FreePBX installed: healthy" -- t_wait_healthy "$c" 1500
log "$(docker exec -u asterisk "$c" php /setup/web-users.php 2>&1)"
docker exec -u asterisk "$c" fwconsole reload >/dev/null 2>&1
pbxsh() { docker exec "$c" bash -c "$1"; }

# --- admin and UCP login
pbxsh 'curl -s -c /tmp/aj -b /tmp/aj -o /dev/null http://localhost/admin/config.php
    curl -s -c /tmp/aj -b /tmp/aj -o /dev/null -d "username=admin&password=AdminPass1" http://localhost/admin/config.php'
page=$(pbxsh 'curl -s -b /tmp/aj "http://localhost/admin/config.php?display=backup"')
assert_contains "$page" "Restore" "admin login: the backup page is shown"
assert_cmd_fails "admin login: no login form" -- grep -q loginform <<< "$page"
assert_cmd_fails "the backup page is not an error page (Whoops)" -- grep -qiE 'Whoops|ErrorException' <<< "$page"
ucp=$(pbxsh 'tok=$(curl -s -c /tmp/uj -b /tmp/uj http://localhost/ucp/ | grep -oE "name=\"token\" value=\"[^\"]*\"" | sed "s/.*value=\"//; s/\"$//")
  curl -s -c /tmp/uj -b /tmp/uj -d "username=ucpuser&password=UcpPass1&token=$tok&module=User&command=login" \
    -H "X-Requested-With: XMLHttpRequest" -H "Referer: http://localhost/ucp/" "http://localhost/ucp/ajax.php?module=User&command=login"')
assert_eq "true" "$(jq -r .status <<< "$ucp")" "UCP login: status true"
assert_contains "$(pbxsh 'curl -s -b /tmp/uj "http://localhost/ucp/?display=dashboard"')" "logout" "UCP login: the dashboard has the logout link"

# --- backup upload, 120 MB in 2 MB chunks as the web UI
pbxsh 'head -c 120M /dev/urandom > /tmp/b120.tar.gz && head -c 140M /dev/urandom > /tmp/b140.tar.gz
    rm -rf /tmp/chunks && mkdir /tmp/chunks && split -b 2M -d -a 3 /tmp/b120.tar.gz /tmp/chunks/c'
up=$(pbxsh 'n=$(ls /tmp/chunks | wc -l); i=0
  for f in /tmp/chunks/c*; do
    code=$(curl -s -b /tmp/aj -o /tmp/up.out -w "%{http_code}" -H "X-Requested-With: XMLHttpRequest" \
      -H "Referer: http://localhost/admin/config.php?display=backup" -F dzuuid=1b4e28ba-2fa1-41d2-883f-0016d3cca427 \
      -F dzchunkindex=$i -F dztotalchunkcount=$n -F "file=@$f;filename=b120.tar.gz;type=application/x-gzip" \
      "http://localhost/admin/ajax.php?module=backup&command=uploadrestore")
    case "$code" in 200|201) ;; *) echo "chunk $i: HTTP $code $(head -c 200 /tmp/up.out)"; exit 1 ;; esac
    i=$((i + 1))
  done; echo "chunks $i last $(cat /tmp/up.out)"')
log "backup upload: $up"
assert_contains "$up" '"status":true' "backup upload of 120 MB (2 MB chunks): status true"
assert_eq "$(pbxsh 'sha256sum < /tmp/b120.tar.gz')" "$(pbxsh 'sha256sum < /var/spool/asterisk/backup/uploads/b120.tar.gz' 2>/dev/null)" \
  "the assembled backup is the uploaded file (sha256)"
assert_eq 200 "$(pbxsh 'curl -s -o /dev/null -w "%{http_code}" --data-binary @/tmp/b120.tar.gz http://localhost/admin/config.php')" \
  "one request of 120 MB reaches PHP (200)"
assert_eq 413 "$(pbxsh 'curl -s -o /dev/null -w "%{http_code}" --data-binary @/tmp/b140.tar.gz http://localhost/admin/config.php')" \
  "one request of 140 MB to PHP is refused (413)"
assert_eq 413 "$(pbxsh 'curl -s -o /dev/null -w "%{http_code}" --data-binary @/tmp/b140.tar.gz http://localhost/robots.txt')" \
  "one request of 140 MB to a static file is refused (413)"
pbxsh 'rm -rf /tmp/b120.tar.gz /tmp/b140.tar.gz /tmp/chunks'

# --- music on hold
mohup=$(pbxsh 'sox -n -r 8000 -c 1 /tmp/izpbx-moh-test.wav synth 5 sine 440 2>/dev/null
  id=$(mysql -h db -uasterisk -pastpw asterisk -N -e "SELECT id FROM music WHERE category=\"default\"" 2>/dev/null)
  curl -s -b /tmp/aj -H "X-Requested-With: XMLHttpRequest" -H "Referer: http://localhost/admin/config.php?display=music" \
    -F "files[]=@/tmp/izpbx-moh-test.wav" -F id=$id -F "codec[]=wav" -F "codec[]=ulaw" \
    "http://localhost/admin/ajax.php?module=music&command=upload"')
assert_eq "true" "$(jq -r .status <<< "$mohup")" "music on hold upload: status true"
for e in wav ulaw; do
  assert_cmd "music on hold converted to $e" -- docker exec "$c" test -s "/var/lib/asterisk/moh/izpbx-moh-test.$e"
done
docker exec -u asterisk "$c" fwconsole reload >/dev/null 2>&1
assert_contains "$(docker exec "$c" asterisk -rx 'moh show files')" "moh/izpbx-moh-test" "moh show files lists it in class default"
n0=$(docker exec "$c" sh -c 'wc -l < /var/log/asterisk/full')
docker exec "$c" asterisk -rx 'channel originate Local/7300@from-internal application Wait 5' >/dev/null
assert_cmd "a test call plays it (music on hold, class default)" -- t_wait_for 20 -- \
  sh -c "docker exec $c sh -c \"tail -n +$((n0 + 1)) /var/log/asterisk/full\" | grep -q \"Started music on hold, class 'default'\""
finish
