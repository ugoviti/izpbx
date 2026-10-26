#!/usr/bin/env bash
# P3-27: the Debian default page must not hide FreePBX (regression found by
# the user on a dev instance): the apache2 postinst copies its index.html to
# /var/www/html, persistence seeds it into /data and DirectoryIndex serves it
# before index.php of FreePBX. The build removes it; cfg_httpd removes it from
# the webroot under APP_DATA at every start only when it is the page of the
# package (/usr/share/apache2/default-site/index.html).
# - the image has no /var/www/html/index.html;
# - GET / on a new installation and after the migration of the 20.16.22
#   fixture: redirect to /admin, no "Apache2 Debian Default Page";
# - a volume with the Debian page in its webroot heals at the next start;
# - control: an index.html of the user stays and is served.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-27
fx="$TESTS_DIR/fixtures/out/20.16.22"
debian_title="Apache2 Debian Default Page"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
assert_cmd_fails "the image has no /var/www/html/index.html" -- docker run --rm --entrypoint "" "$image" test -e /var/www/html/index.html
assert_cmd "the package keeps its copy (the reference of cfg_httpd)" -- \
  docker run --rm --entrypoint "" "$image" grep -q "$debian_title" /usr/share/apache2/default-site/index.html

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db() { # alias
  local d
  d=$(t_run "$1" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$1" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || die "MariaDB did not start"
  printf '%s\n' "$d"
}
root() { # container -> "<code> <redirect>" and the body in $work/body
  docker exec "$1" curl -s -o /tmp/p3-27-body -w '%{http_code} %{redirect_url}' http://localhost/
}
body() { docker exec "$1" cat /tmp/p3-27-body 2>/dev/null; }

# --- the migration of the fixture, started first (the longest)
mdb=$(db mdb)
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$mdb" mariadb -uroot || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
  docker exec -i -e MYSQL_PWD=rootpw "$mdb" mariadb -uroot
mv=$(t_volume mig)
docker run --rm --entrypoint "" -v "$mv:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
mig=$(t_run mig "$image" --network "$net" -v "$mv:/data" -e APP_DATA=/data -e MYSQL_SERVER=mdb -e MYSQL_PASSWORD=fixture-pw \
  -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)

# --- new installation
db ndb >/dev/null
nv=$(t_volume new)
new=$(t_run new "$image" --network "$net" -v "$nv:/data" -e APP_DATA=/data -e MYSQL_SERVER=ndb -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw)
assert_cmd "new installation: healthy" -- t_wait_healthy "$new" 2400
r=$(root "$new")
log "new installation: GET / -> $r"
assert_cmd "new installation: GET / redirects to /admin" -- grep -qE '^30[12] http://localhost/admin/?$' <<< "$r"
assert_cmd_fails "new installation: no Debian page" -- grep -q "$debian_title" <<< "$(body "$new")"

# --- a volume with the Debian page in the webroot heals at the next start
docker exec "$new" cp /usr/share/apache2/default-site/index.html /var/www/html/index.html
assert_cmd "the Debian page is served when it is there (precondition)" -- sh -c "docker exec '$new' curl -s http://localhost/ | grep -q '$debian_title'"
docker restart "$new" >/dev/null
assert_cmd "after the restart: healthy" -- t_wait_healthy "$new" 600
assert_cmd_fails "the Debian page was removed from the webroot under /data" -- docker exec "$new" test -e /data/var/www/html/index.html
assert_cmd "GET / redirects to /admin again" -- grep -qE '^30[12] http://localhost/admin/?$' <<< "$(root "$new")"
assert_cmd "the log says so" -- sh -c "docker logs '$new' 2>&1 | grep 'httpd: Debian default page removed' >/dev/null"

# --- control: an index.html of the user stays
echo '<html><body>izpbx custom landing page</body></html>' | docker exec -i "$new" sh -c 'cat > /var/www/html/index.html'
docker restart "$new" >/dev/null
assert_cmd "after the restart: healthy" -- t_wait_healthy "$new" 600
assert_cmd "control: the index.html of the user stays" -- docker exec "$new" grep -q 'izpbx custom landing page' /data/var/www/html/index.html
assert_cmd "control: and it is served on /" -- sh -c "docker exec '$new' curl -s http://localhost/ | grep -q 'izpbx custom landing page'"

# --- after the migration
assert_cmd "migration: healthy" -- t_wait_healthy "$mig" 2400
assert_cmd "migration completed (verify=done)" -- docker exec "$mig" grep -qx 'verify=done' /data/.izpbx-migration/state
r=$(root "$mig")
log "after the migration: GET / -> $r"
assert_cmd "after the migration: GET / redirects to /admin" -- grep -qE '^30[12] http://localhost/admin/?$' <<< "$r"
assert_cmd_fails "after the migration: no Debian page" -- grep -q "$debian_title" <<< "$(body "$mig")"
finish
