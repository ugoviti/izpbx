#!/usr/bin/env bash
# P4-30: volume whose first 20.16.x install was interrupted (fixture P0-08f,
# 20.16.22-interrupted: killed during the module install, then started once
# more, so .initialized exists while the database lacks most modules).
# - the checks M2 detect the incomplete install and block on it only, with
#   the instructions (complete it on 20.16.x with the exact command, or start
#   from scratch) and the missing modules;
# - a real start, even with IZPBX_MIGRATE_FREEPBX=true: maintenance mode,
#   /data (outside .izpbx-migration) and the databases unchanged;
# - control: on the complete 20.16.22 fixture the install check passes.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-30
fx="$TESTS_DIR/fixtures/out/20.16.22-interrupted"
base="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "interrupted fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 --variant interrupted ${TEST_REUSE_FIXTURES:+--reuse}
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
fixture_db() { # name fixture-dir
  local d
  d=$(t_run "$1" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$1" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || die "MariaDB did not start"
  for f in asterisk asteriskcdrdb; do gzip -dc "$2/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot || die "cannot load $f"; done
  echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
    docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot
  printf '%s\n' "$d"
}
fixture_data() { docker run --rm --entrypoint "" -v "$1:/data" -v "$2:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null; }
dbsum() { docker exec -e MYSQL_PWD=rootpw "$1" sh -c 'for s in asterisk asteriskcdrdb; do
  mariadb -uroot -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema=\"$s\" ORDER BY 1" |
  while read -r t; do mariadb -uroot -N "$s" -e "CHECKSUM TABLE \`$t\`"; done; done | md5sum'; }
datasum() {
  docker run --rm --entrypoint "" -v "$1:/data:ro" "$image" sh -c 'cd /data && {
    find . -path ./.izpbx-migration -prune -o -printf "%y %m %U:%G %p %l\n" | LC_ALL=C sort
    find . -path ./.izpbx-migration -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum; } | sha256sum'
}
env_of() { echo "-e APP_DATA=/data -e MYSQL_SERVER=$1 -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw"; }

db=$(fixture_db db "$fx")
v=$(t_volume data); fixture_data "$v" "$fx"
db_before=$(dbsum "$db") data_before=$(datasum "$v")

# --- the checks M2
# shellcheck disable=SC2046
out=$(docker run --rm --entrypoint "" --network "$net" -v "$v:/data" $(env_of db) "$image" izpbx-preflight 2>&1) && rc=0 || rc=$?
grep -E '^(BLOCK|INFO|RESULT)' <<< "$out" | sed 's/^/    | /' >&2
assert_ne 0 "$rc" "the checks block"
assert_eq "BLOCK install" "$(grep -oE '^BLOCK [a-z_]+' <<< "$out" | tr '\n' ' ' | sed 's/ $//')" "only the install check blocks"
line=$(grep '^BLOCK install' <<< "$out")
assert_contains "$line" "the first installation of FreePBX 16 did not complete" "the report names the incomplete install"
assert_contains "$line" "fwconsole ma downloadinstall" "instructions: complete it on 20.16.x with the exact command"
assert_contains "$line" "start again from an empty /data and empty databases" "instructions: or start from scratch"
assert_contains "$line" "ucp" "the missing modules are listed"

# --- a real start, with the opt-in: maintenance, nothing changed
# shellcheck disable=SC2046
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" $(env_of db) -e IZPBX_MIGRATE_FREEPBX=true)
t_wait_for 300 -- sh -c "docker logs '$c' 2>&1 | grep 'izpbx-init: maintenance mode' >/dev/null"
assert_cmd "real start: maintenance mode" -- docker exec "$c" test -e /run/izpbx/maintenance
docker rm -f "$c" >/dev/null
assert_eq "$db_before" "$(dbsum "$db")" "the databases are unchanged"
assert_eq "$data_before" "$(datasum "$v")" "/data is unchanged outside .izpbx-migration"

# --- control: a complete install passes the check
fixture_db dbbase "$base" >/dev/null
vb=$(t_volume base); fixture_data "$vb" "$base"
# shellcheck disable=SC2046
outb=$(docker run --rm --entrypoint "" --network "$net" -v "$vb:/data" $(env_of dbbase) "$image" izpbx-preflight 2>&1 || true)
assert_cmd "control: complete 20.16.22 install: OK install" -- grep -q '^OK install: the first installation of FreePBX 16 is complete' <<< "$outb"
finish
