#!/usr/bin/env bash
# P4-07: the FreePBX "legacy" backup archive built from the raw data (M5.1,
# izpbx-migrate archive after the snapshot), from the 20.16.22 fixture:
# - <snapshot>/backup/izpbx-migration.tar.gz with manifest, astdb,
#   mysql-2.sql and etc/asterisk/*_custom.conf, its sha256 recorded, state
#   archive=done;
# - validated by the Backup module of a FreePBX 17 installed by the image
#   (tests/fixtures/validate-legacy-archive.php: type detection, extraction,
#   manifest and astdb, the dump loaded into SQLite and mapped to the
#   modules, nothing restored): type legacy, FreePBX 16 version, every
#   table of the dump loaded, the row counts of the main tables equal to the
#   fixture database, as many astdb families as astdb.sqlite3;
# - negative check: the same archive with a corrupted manifest is rejected.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-07
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
mariadb_up() { # name -> a MariaDB on the network (alias = name)
  local d
  d=$(t_run "$1" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$1" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || die "MariaDB did not start"
  printf '%s\n' "$d"
}
sqlroot() { docker exec -i -e MYSQL_PWD=rootpw "$1" mariadb -uroot -N "${@:2}"; }
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

# --- FreePBX 17 installed by the image (empty /data), started first: it takes minutes
mariadb_up db17 >/dev/null
pbx=$(t_run pbx "$image" --network "$net" -v "$(t_volume data17):/data" -e APP_DATA=/data \
  -e MYSQL_SERVER=db17 -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw)

# --- the archive from the fixture
db16=$(mariadb_up db16)
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | sqlroot "$db16" || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" | sqlroot "$db16"
v=$(t_volume data16)
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
out=$(docker run --rm --entrypoint "" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db16 \
  -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw "$image" \
  sh -c 'izpbx-migrate snapshot && izpbx-migrate archive' 2>&1) && rc=0 || rc=$?
log "$(grep 'migration: archive' <<< "$out")"
assert_eq 0 "$rc" "izpbx-migrate snapshot + archive succeed"
in16() { docker run --rm --entrypoint "" -v "$v:/data" "$image" sh -c "$1"; }
arc=$(in16 'sed -n "s/^archive_file=//p" /data/.izpbx-migration/state | tail -n 1')
assert_contains "$arc" "/backup/izpbx-migration.tar.gz" "archive recorded in the state ($arc)"
assert_eq "done" "$(in16 'sed -n "s/^archive=//p" /data/.izpbx-migration/state | tail -n 1')" "state: archive=done"
assert_cmd "archive matches its sha256" -- in16 "cd '$(dirname "$arc")' && sha256sum -c izpbx-migration.tar.gz.sha256"
docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" cat "$arc" > "$work/arc.tar.gz"
listing=$(tar -tzf "$work/arc.tar.gz")
for f in ./manifest ./astdb ./mysql-2.sql ./etc/asterisk/extensions_custom.conf; do
  assert_contains "$listing" "$f" "archive holds $f"
done
create_tables=$(tar -xzOf "$work/arc.tar.gz" ./mysql-2.sql | grep -c '^CREATE TABLE')
assert_cmd_fails "archive has no CREATE DATABASE" -- sh -c "tar -xzOf '$work/arc.tar.gz' ./mysql-2.sql | grep -q '^CREATE DATABASE'"

# --- validated by the FreePBX 17 Backup module
assert_cmd "FreePBX 17 installed: healthy" -- t_wait_healthy "$pbx" 1500
docker cp "$TESTS_DIR/fixtures/validate-legacy-archive.php" "$pbx:/tmp/validate.php" >/dev/null
validate() { # archive on the host -> JSON on stdout, exit code of the validator
  docker cp "$1" "$pbx:/tmp/arc.tar.gz" >/dev/null
  docker exec "$pbx" sh -c 'chown asterisk:asterisk /tmp/arc.tar.gz /tmp/validate.php; rm -f /tmp/validate.json'
  docker exec -u asterisk "$pbx" php /tmp/validate.php /tmp/arc.tar.gz /tmp/validate.json "${tables[@]}" >/dev/null 2>&1 || return $?
  docker exec "$pbx" cat /tmp/validate.json
}
tables=(devices users sip trunks incoming outbound_routes ivr_details queues_config ringgroups timeconditions recordings fax_users userman_users)
json=$(validate "$work/arc.tar.gz") && rc=0 || rc=$?
assert_eq 0 "$rc" "the FreePBX 17 Backup module reads the archive"
log "validation: $(jq -c '{type, manifest, astdb_families, tables, unknown: (.unknown | length), rows}' <<< "$json" 2>/dev/null)"
assert_eq legacy "$(jq -r .type <<< "$json")" "detected as a legacy backup"
assert_eq "$(echo "SELECT value FROM asterisk.admin WHERE variable='version'" | sqlroot "$db16")" \
  "$(jq -r .manifest.pbx_version <<< "$json")" "manifest: the FreePBX 16 version of the fixture"
assert_eq asteriskcdrdb "$(jq -r .manifest.fpbx_cdrdb <<< "$json")" "manifest: the CDR database name"
assert_eq "$create_tables" "$(jq -r .tables <<< "$json")" "every table of the dump loaded by the module ($create_tables)"
assert_ne "0" "$(jq -r '.modules | length' <<< "$json")" "tables mapped to FreePBX 17 modules ($(jq -r '.modules | keys | join(" ")' <<< "$json"))"
for t in "${tables[@]}"; do
  assert_eq "$(echo "SELECT COUNT(*) FROM asterisk.\`$t\`" | sqlroot "$db16")" "$(jq -r ".rows.$t" <<< "$json")" "rows of $t as in the fixture"
done
families=$(docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" php -r '
  $f = []; foreach ((new PDO("sqlite:" . $argv[1]))->query("SELECT key FROM astdb") as $r) {
    $p = explode("/", trim($r[0], "/"), 2); if (count($p) == 2) $f[$p[0]] = 1; } echo count($f);' -- \
  "$(dirname "$(dirname "$arc")")/fs/var/lib/asterisk/astdb.sqlite3")
assert_eq "$families" "$(jq -r .astdb_families <<< "$json")" "astdb: as many families as astdb.sqlite3 ($families)"

# --- negative check: corrupted manifest
mkdir "$work/bad" && tar -C "$work/bad" -xzf "$work/arc.tar.gz"
echo "not a manifest" > "$work/bad/manifest"
tar -C "$work/bad" -czf "$work/bad.tar.gz" .
validate "$work/bad.tar.gz" >/dev/null && rc=0 || rc=$?
assert_ne 0 "$rc" "control: an archive with a corrupted manifest is rejected"
finish
