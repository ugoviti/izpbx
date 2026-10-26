#!/usr/bin/env bash
# P3-30: the install of FreePBX 17 from scratch (the red of P6-03 in CI).
# The file cache of FreePBX in ASTSPOOLDIR/cache stays in place in a
# migration: the module list cached by FreePBX 16, still valid a few minutes
# after the last write, has certman and fax enabled whatever the new database
# holds, and the installer stopped with "Undefined property: FreePBX::$Certman";
# a failed attempt also left the tables and freepbx.conf of a half
# installation, so every next attempt failed. Now the cache is removed before
# every attempt, and the tables of a failed attempt when the database was
# empty before.
# - migration of the 20.16.22 fixture with its module list cache valid (the
#   lifetime of the cache file moved to 2100, as right after 20.16 stopped):
#   the cache removed, completed (verify=done), the CDR database unchanged;
# with IZPBX_TEST_INSTALL_FAIL_ATTEMPTS=1 (the first attempt fails after the
# installer ran):
# - new installation: the tables of the attempt removed, the second attempt
#   installs, healthy, fwconsole reload exit 0; every attempt has its logs
#   in /tmp/freepbx-install/<n>/;
# - control: a database that already had a table is never emptied.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-30
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

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
sqlr() { docker exec -i -e MYSQL_PWD=rootpw "$1" mariadb -uroot -N; }
fail1=(-e IZPBX_TEST_INSTALL_FAIL_ATTEMPTS=1)

# --- migration (the longest, started first)
mdb=$(db mdb)
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | sqlr "$mdb" || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" | sqlr "$mdb"
cdrsum() {
  echo "SELECT table_name FROM information_schema.tables WHERE table_schema='asteriskcdrdb' ORDER BY 1" | sqlr "$mdb" |
    while read -r t; do echo "CHECKSUM TABLE asteriskcdrdb.\`$t\`" | sqlr "$mdb"; done
}
cdr_before=$(cdrsum)
mv=$(t_volume mig)
docker run --rm --entrypoint "" -v "$mv:/data" -v "$fx:/fx:ro" "$image" sh -c 'tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
  sed -i "s/s:8:\"lifetime\";i:[0-9]*;/s:8:\"lifetime\";i:4102444800;/" /data/var/spool/asterisk/cache/*/*.doctrinecache.php'
assert_cmd "the fixture has the module list cache of FreePBX 16 (now valid)" -- docker run --rm --entrypoint "" -v "$mv:/data" "$image" \
  sh -c 'grep -l "i:4102444800" /data/var/spool/asterisk/cache/*/5b6d6f64756c656c6973745f6d6f64756c65735d5b315d.doctrinecache.php'
mig=$(t_run mig "$image" --network "$net" -v "$mv:/data" -e APP_DATA=/data -e MYSQL_SERVER=mdb -e MYSQL_PASSWORD=fixture-pw \
  -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)

# --- new installation
db ndb >/dev/null
new=$(t_run new "$image" --network "$net" -v "$(t_volume new):/data" -e APP_DATA=/data -e MYSQL_SERVER=ndb \
  -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw "${fail1[@]}")

# --- control: a database with a table already there
kdb=$(db kdb)
echo "CREATE DATABASE asterisk; CREATE TABLE asterisk.keepme (id INT); INSERT INTO asterisk.keepme VALUES (1)" | sqlr "$kdb"
keep=$(t_run keep "$image" --network "$net" -v "$(t_volume keep):/data" -e APP_DATA=/data -e MYSQL_SERVER=kdb \
  -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_FREEPBX_INSTALL_TRIES=2 "${fail1[@]}")

assert_cmd "new installation: healthy" -- t_wait_healthy "$new" 2400
nlog=$(docker logs "$new" 2>&1)
grep -E 'install attempt|failed on purpose|failed attempt|FreePBX 17.* installed' <<< "$nlog" | sed 's/^/    | /' >&2
assert_contains "$nlog" "attempt 1 failed on purpose" "new installation: attempt 1 failed"
assert_contains "$nlog" "the tables of the failed attempt and freepbx.conf removed" "new installation: its tables removed"
assert_contains "$nlog" "install attempt 2/5" "new installation: a second attempt"
assert_cmd "new installation: fwconsole reload exit 0" -- docker exec -u asterisk "$new" fwconsole reload
assert_cmd "logs of both attempts kept" -- docker exec "$new" test -s /tmp/freepbx-install/1/install.log -a -s /tmp/freepbx-install/2/install.log

assert_cmd "control: the database with a table is not emptied" -- \
  t_wait_for 900 -- sh -c "docker logs '$keep' 2>&1 | grep -E 'install attempt 2/2' >/dev/null"
assert_eq 1 "$(echo 'SELECT id FROM asterisk.keepme' | sqlr "$kdb" 2>/dev/null)" "control: its table keepme is still there"
assert_cmd_fails "control: no reset logged" -- sh -c "docker logs '$keep' 2>&1 | grep 'tables of the failed attempt' >/dev/null"

assert_cmd "migration: healthy" -- t_wait_healthy "$mig" 2400
mlog=$(docker logs "$mig" 2>&1)
grep -E 'install attempt|cache|Undefined|installer failed' <<< "$mlog" | sed 's/^/    | /' >&2
assert_cmd "migration: the cache of FreePBX 16 removed" -- grep -qE 'freepbx: FreePBX file cache (/data)?/var/spool/asterisk/cache removed before the install' <<< "$mlog"
assert_cmd_fails "migration: no installer failure" -- grep -q 'installer failed' <<< "$mlog"
assert_cmd "migration completed (verify=done)" -- docker exec "$mig" grep -qx 'verify=done' /data/.izpbx-migration/state
assert_eq "$cdr_before" "$(cdrsum)" "migration: the CDR database unchanged"
finish
