#!/usr/bin/env bash
# P4-35: hints and dial strings of chan_sip in the astdb after the migration
# (found by the weekly job P6-08 on 20.16.15): the ex chan_sip extension 1001
# kept its hint SIP/1001&Custom:DND1001,... (BLF broken: Asterisk 22 has no
# chan_sip) and the verification M7 stopped the migration. migration_astdb
# converts /AMPUSER/<ext>/hint and /DEVICE/<ext>/dial (SIP/ -> PJSIP/, also
# inside hints of several devices) and /DEVICE/<ext>/tech (sip -> pjsip).
# - the 20.16.15 fixture has the hint SIP/1001... (precondition);
# - migrated: verify=done, healthy; in the astdb of Asterisk the hint of 1001
#   is PJSIP/1001&..., its dial PJSIP/1001, no hint or dial on SIP/ left;
#   "core show hint 1001" on PJSIP/1001;
# - the voicemail.conf of 20.16.15 has the comment line ": Storage database:"
#   that the parser of FreePBX 17 refuses (every fwconsole reload failed, so
#   no hint was ever written): made a comment, and the new phase of M7
#   reloads FreePBX 17 (reload.log in the snapshot), which writes the hints of
#   ext-local;
# - control: astdb keys that are not chan_sip ones (call forward) unchanged.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-35
fx="$TESTS_DIR/fixtures/out/20.16.15"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.15 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.15 ${TEST_REUSE_FIXTURES:+--reuse}

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
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
astdb_old() { # key -> its value in the astdb of the fixture
  docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" php -r '$q = (new PDO("sqlite:/data/var/lib/asterisk/astdb.sqlite3"))->prepare("SELECT value FROM astdb WHERE key = ?"); $q->execute([$argv[1]]); echo $q->fetchColumn();' -- "$1"
}
assert_cmd "the fixture has the chan_sip hint SIP/1001 (precondition)" -- grep -q '^SIP/1001&' <<< "$(astdb_old /AMPUSER/1001/hint)"
cf_before=$(astdb_old /CF/1001)

c=$(t_run pbx "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw \
  -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)
t_wait_for 2400 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)|MAINTENANCE MODE|rc.init: fatal' >/dev/null"
docker logs "$c" 2>&1 | grep -E 'migration: (.*astdb|VERIFICATION|FreePBX 16 ->)|error:   ' | sed 's/^/    | /' >&2
assert_cmd "migration completed (verify=done)" -- docker exec "$c" grep -qx 'verify=done' /data/.izpbx-migration/state
assert_cmd "healthy" -- t_wait_healthy "$c" 300
dbget() { docker exec "$c" asterisk -rx "database get $1 $2" 2>/dev/null | sed -n 's/^Value: //p'; }
hint=$(dbget AMPUSER/1001 hint)
log "AMPUSER/1001/hint: $hint"
assert_cmd "hint of 1001 on PJSIP" -- grep -q '^PJSIP/1001&' <<< "$hint"
assert_eq "PJSIP/1001" "$(dbget DEVICE/1001 dial)" "dial of 1001 on PJSIP"
assert_eq "" "$(docker exec "$c" asterisk -rx 'database show' 2>/dev/null | grep -E '/(hint|dial) +: +(.*&)?SIP/' || true)" "no hint or dial on SIP/ left"
assert_cmd "the voicemail.conf of the fixture has the ':' line (precondition)" -- \
  docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" sh -c 'grep -q "^: Storage database:" "$(sed -n "s/^snapshot_dir=//p" /data/.izpbx-migration/state | tail -n 1)/fs/etc/asterisk/voicemail.conf"'
assert_cmd_fails "voicemail.conf: no line starting with ':' left" -- docker exec "$c" grep -qE '^:[[:space:]]' /etc/asterisk/voicemail.conf
assert_cmd "the migration reloaded FreePBX 17" -- sh -c "docker logs '$c' 2>&1 | grep 'migration: FreePBX 17 reloads the migrated configuration' >/dev/null"
assert_cmd "fwconsole reload works" -- docker exec -u asterisk "$c" fwconsole reload
assert_cmd "core show hint 1001: 1001@ext-local on PJSIP/1001" -- \
  sh -c "docker exec '$c' asterisk -rx 'core show hint 1001' | grep -qE '^ *1001@ext-local +: PJSIP/1001'"
assert_eq "$cf_before" "$(dbget CF 1001)" "control: the call forward of 1001 unchanged"
finish
