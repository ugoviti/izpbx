#!/usr/bin/env bash
# P4-28: migration with an external database on the bridge network, non
# standard names and port (fixture P0-08d, 20.16.22-extdb: databases
# pbxconfig and pbxcdr on port 3307), in a real start with MYSQL_DATABASE,
# MYSQL_DATABASE_CDR and APP_PORT_MYSQL set as in 20.16:
# - the migration completes: verification M7 passed, inventory diff empty,
#   healthy;
# - the dumps of the snapshot are pbxconfig.sql.gz and pbxcdr.sql.gz;
# - FreePBX 17 after the restore uses the configured names and port
#   (freepbx.conf AMPDBNAME/AMPDBPORT, CDRDBNAME), and so does ODBC
#   (/etc/odbc.ini on port 3307 and pbxcdr, connected in Asterisk);
# - the non standard CDR database has the same checksum of every table.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-28
fx="$TESTS_DIR/fixtures/out/20.16.22-extdb"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "extdb fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 --variant extdb ${TEST_REUSE_FIXTURES:+--reuse}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias extdb -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60 -- --port=3307)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
sqlroot() { docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot -P 3307 -N; }
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | sqlroot || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON pbxconfig.* TO asterisk@'%'; GRANT ALL ON pbxcdr.* TO asterisk@'%'" | sqlroot
cdrsum() {
  echo "SELECT table_name FROM information_schema.tables WHERE table_schema='pbxcdr' ORDER BY 1" | sqlroot |
    while read -r t; do echo "CHECKSUM TABLE pbxcdr.\`$t\`" | sqlroot; done
}
cdr_before=$(cdrsum)
assert_ne "" "$cdr_before" "the fixture has the CDR database pbxcdr"
v=$(t_volume data)
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=extdb -e APP_PORT_MYSQL=3307 \
  -e MYSQL_DATABASE=pbxconfig -e MYSQL_DATABASE_CDR=pbxcdr -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw \
  -e IZPBX_MIGRATE_FREEPBX=true)
t_wait_for 2400 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)|izpbx-init: (maintenance|done)|freepbx: (install failed|migration failed)' >/dev/null"
docker logs "$c" 2>&1 | grep -E 'preflight: (BLOCK|RESULT)|migration: database|VERIFICATION|error|completed' | sed 's/^/    | /' | head -n 30 >&2
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 300
state=$(docker exec "$c" cat /data/.izpbx-migration/state 2>/dev/null)
assert_cmd "verification M7 passed (verify=done)" -- grep -qx 'verify=done' <<< "$state"
snap=$(sed -n 's/^snapshot_dir=//p' <<< "$state" | tail -n 1)
assert_cmd "snapshot dumps named pbxconfig and pbxcdr" -- docker exec "$c" test -s "$snap/db/pbxconfig.sql.gz" -a -s "$snap/db/pbxcdr.sql.gz"
conf=$(docker exec "$c" cat /etc/freepbx.conf 2>/dev/null)
assert_contains "$conf" "\$amp_conf['AMPDBNAME'] = 'pbxconfig';" "freepbx.conf: AMPDBNAME pbxconfig"
assert_contains "$conf" "\$amp_conf['AMPDBPORT'] = '3307';" "freepbx.conf: AMPDBPORT 3307"
assert_contains "$(docker exec -u asterisk "$c" fwconsole setting CDRDBNAME 2>/dev/null)" "[pbxcdr]" "FreePBX setting CDRDBNAME pbxcdr"
odbc=$(docker exec "$c" cat /etc/odbc.ini)
log "odbc.ini: $(tr '\n' ' ' <<< "$odbc")"
assert_cmd "odbc.ini: port 3307" -- grep -qiE '^Port *= *3307' <<< "$odbc"
assert_cmd "odbc.ini: database pbxcdr" -- grep -qiE '^database *= *pbxcdr' <<< "$odbc"
assert_cmd "ODBC connected in Asterisk" -- t_wait_for 60 -- sh -c "docker exec '$c' asterisk -rx 'odbc show' | grep -qi 'Number of active connections: [1-9]'"
diff=$(docker exec "$c" izpbx-inventory --diff /data/.izpbx-migration/inventory-before.json /data/.izpbx-migration/inventory-after.json \
  --mapping /data/.izpbx-migration/mapping.tsv 2>&1) && rc=0 || rc=$?
log "inventory: $(tail -n 1 <<< "$diff")"
assert_eq 0 "$rc" "inventory diff empty"
assert_eq "$cdr_before" "$(cdrsum)" "CDR database pbxcdr unchanged (checksum of every table)"
finish
