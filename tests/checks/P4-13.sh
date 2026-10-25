#!/usr/bin/env bash
# P4-13: crontabs after the migration (M6, C4): the 20.16.22 fixture, with a
# custom line added to its asterisk crontab, migrated in a real start.
# 20.16 kept /var/spool/cron/<user>, Debian reads /var/spool/cron/crontabs.
# - crontabs/asterisk: the FreePBX jobs (written by FreePBX 17) and the
#   custom line; each FreePBX job once (the 20.16 copies are not added);
# - crontabs/root: the custom line of the fixture (FOP2 cleanup);
# - asterisk:crontab 0600; the custom job runs (as asterisk) within 2 minutes;
# - control: the 20.16 crontab directory was moved to the snapshot.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-13
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
  docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot
v=$(t_volume data)
custom='* * * * * id -un > /tmp/izpbx-p4-13-cron'
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" -e CUSTOM="$custom" "$image" \
  sh -c 'tar -C /data -xzf /fx/data.tar.gz 2>/dev/null; printf "%s\n" "$CUSTOM" >> /data/var/spool/cron/asterisk'

c=$(t_run pbx "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 2400
docker logs "$c" 2>&1 | grep 'crontab' | sed 's/^/    | /' >&2
ast=$(docker exec "$c" cat /var/spool/cron/crontabs/asterisk 2>/dev/null)
log "crontabs/asterisk:"; sed 's/^/    | /' <<< "$ast" >&2
assert_cmd "crontabs/asterisk: the custom line of 20.16" -- grep -qxF -- "$custom" <<< "$ast"
assert_cmd "crontabs/asterisk: the FreePBX job runner (fwconsole job --run)" -- grep -q 'fwconsole job --run' <<< "$ast"
assert_eq 1 "$(grep -c 'fwconsole job --run' <<< "$ast")" "each FreePBX job once (the 20.16 copies not added)"
assert_eq 1 "$(grep -c 'fwconsole userman --syncall' <<< "$ast")" "userman sync once"
assert_cmd "crontabs/root: the custom line of the fixture (FOP2 cleanup)" -- \
  docker exec "$c" grep -q 'fop2_cleanup.php' /var/spool/cron/crontabs/root
assert_eq "asterisk crontab 600" "$(docker exec "$c" stat -c '%U %G %a' /var/spool/cron/crontabs/asterisk)" "crontabs/asterisk 0600 asterisk:crontab"
assert_cmd "the custom job runs within 2 minutes" -- t_wait_for 130 -- docker exec "$c" test -s /tmp/izpbx-p4-13-cron
assert_eq asterisk "$(docker exec "$c" cat /tmp/izpbx-p4-13-cron 2>/dev/null)" "the custom job runs as asterisk"
snap=$(docker exec "$c" sh -c 'sed -n "s/^snapshot_dir=//p" /data/.izpbx-migration/state | tail -n 1')
assert_cmd "control: the 20.16 crontabs are in the snapshot" -- docker exec "$c" test -f "$snap/fs/var/spool/cron/asterisk"
finish
