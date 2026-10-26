#!/usr/bin/env bash
# P4-14: FOP2 after the migration (M6, migration_fop2): the 20.16.22 fixture
# (fop2.cfg, FOP2 enabled), with a marker line added to its fop2.cfg,
# migrated in a real start with FOP2_ENABLED=true.
# - fop2_server -v reports FOP2_VER of versions.env (the Debian package);
# - fop2.cfg of the fixture kept, but the keys the fop2 step sets at every
#   start (manager_* from the FreePBX AMI settings, ssl_certificate_*);
# - fop2settings.db of the fixture kept (tables setup and chatlog), so
#   fop2_server logs no "no such table" error;
# - the fop2 service is up and answers on port 4445;
# - control: the marker line proves the file is the one of 20.16, not the
#   default of the package.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-14
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
ver=$(sed -n 's/^FOP2_VER=//p' "$REPO_DIR/izpbx-asterisk/versions.env")

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
marker='; izpbx test P4-14: fop2.cfg of 20.16'
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" -e MARKER="$marker" "$image" \
  sh -c 'tar -C /data -xzf /fx/data.tar.gz 2>/dev/null; printf "%s\n" "$MARKER" >> /data/usr/local/fop2/fop2.cfg'
docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" cat /data/usr/local/fop2/fop2.cfg > "$work/before.cfg"
dbsum_before=$(docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" sha256sum /data/usr/local/fop2/fop2settings.db | cut -d' ' -f1)

c=$(t_run pbx "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true -e FOP2_ENABLED=true)
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 2400
docker logs "$c" 2>&1 | grep -E 'migration: .*FOP2|fop2:' | sed 's/^/    | /' >&2
assert_contains "$(docker exec "$c" /usr/local/fop2/fop2_server -v 2>&1)" "$ver" "fop2_server -v reports FOP2_VER ($ver)"
docker exec "$c" cat /usr/local/fop2/fop2.cfg > "$work/after.cfg"
keys='^(manager_(host|port|user|secret)|ssl_certificate(_key)?_file)[[:space:]]*='
assert_eq "" "$(diff <(grep -vE "$keys" "$work/before.cfg") <(grep -vE "$keys" "$work/after.cfg"))" \
  "fop2.cfg of 20.16 kept (but the keys set at every start)"
assert_cmd "control: the marker line of the fixture fop2.cfg is there" -- grep -qxF -- "$marker" "$work/after.cfg"
assert_eq "$dbsum_before" "$(docker exec "$c" sha256sum /usr/local/fop2/fop2settings.db | cut -d' ' -f1)" \
  "fop2settings.db of 20.16 kept"
assert_cmd "the fop2 service is up" -- t_wait_for 60 -- sh -c "docker exec '$c' /command/s6-svstat /run/service/fop2 | grep -q '^up'"
assert_cmd "FOP2 answers on port 4445" -- t_wait_for 60 -- docker exec "$c" bash -c 'exec 3<>/dev/tcp/127.0.0.1/4445'
assert_cmd_fails "fop2_server logs no missing table" -- sh -c "docker logs '$c' 2>&1 | grep 'no such table' >/dev/null"
finish
