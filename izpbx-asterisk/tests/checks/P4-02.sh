#!/usr/bin/env bash
# P4-02: detection M1 (design §7): with an initialized /data the FreePBX
# version in the database (admin.version) chooses the start.
# - the 20.16.22 fixture (FreePBX 16): migration mode (/run/izpbx/mode), no
#   new installation, the database unchanged (checksum of every table);
# - a FreePBX 17 volume: normal start;
# - FreePBX 15 simulated (admin.version 15.0.37 in the fixture): the start is
#   refused with instructions (upgrade with izPBX 20.16.x first), the
#   container stops, the database unchanged;
# - control: an empty /data is a new installation (mode install).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-02
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
t_freepbx17

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
fixture_db() { # name alias [admin version] -> a MariaDB with the fixture dumps
  local d
  d=$(t_run "$1" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$2" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || die "MariaDB did not start"
  for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i "$d" mariadb -uroot -prootpw || die "cannot load $f"; done
  docker exec "$d" mariadb -uroot -prootpw -e "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'"
  [ -z "${3:-}" ] || docker exec "$d" mariadb -uroot -prootpw asterisk -e "UPDATE admin SET value='$3' WHERE variable='version'"
  printf '%s\n' "$d"
}
fixture_data() { # name -> a volume with the fixture /data
  local v; v=$(t_volume "$1")
  docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
  printf '%s\n' "$v"
}
dbsum() { docker exec "$1" sh -c 'mariadb -uroot -prootpw -N -e "SELECT GROUP_CONCAT(table_name ORDER BY table_name) FROM information_schema.tables WHERE table_schema=\"asterisk\"" |
  tr , "\n" | while read -r t; do mariadb -uroot -prootpw -N asterisk -e "CHECKSUM TABLE \`$t\`"; done | md5sum'; }
mode() { docker exec "$1" cat /run/izpbx/mode 2>/dev/null; }
pbx() { # name volume db-alias [args]
  local n=$1 v=$2 a=$3; shift 3
  t_run "$n" "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER="$a" -e MYSQL_PASSWORD=fixture-pw "$@"
}
# grep >/dev/null, not -q: the logs are long (PHP errors of FreePBX 16 in
# migration mode) and "grep -q" would end the pipe with SIGPIPE
init_done() { docker logs "$1" 2>&1 | grep 'izpbx-init: done' >/dev/null; }

# --- FreePBX 16: migration mode
d16=$(fixture_db db16 db16)
before=$(dbsum "$d16")
c16=$(pbx m16 "$(fixture_data data16)" db16)
assert_cmd "FreePBX 16: the init completes" -- t_wait_for 180 -- init_done "$c16"
assert_eq migration "$(mode "$c16")" "FreePBX 16: migration mode"
assert_contains "$(docker logs "$c16" 2>&1)" "FreePBX 16.0.50 found (izPBX 20.16): migration to FreePBX 17 (M1)" "FreePBX 16: reported in the log"
assert_cmd_fails "FreePBX 16: no new installation" -- sh -c "docker logs '$c16' 2>&1 | grep 'NEW INSTALLATION' >/dev/null"
assert_eq "$before" "$(dbsum "$d16")" "FreePBX 16: the database is unchanged"

# --- FreePBX 17: normal start
v17=$(t_volume data17)
# a FreePBX 17 /data: .initialized and freepbx.conf in the volume (with
# APP_DATA it is persisted there); the network and database of t_freepbx17
docker run --rm --entrypoint "" -v "$v17:/data" -v "$TESTS_DIR/fixtures/freepbx-installed:/fx:ro" "$image" \
  sh -c 'echo 17.0.33 > /data/.initialized && mkdir -p /data/etc && cp /fx/freepbx.conf /data/etc/freepbx.conf'
c17=$(t_run m17 "$image" "${T_FREEPBX17[@]:0:6}" -v "$v17:/data" -e APP_DATA=/data)
assert_cmd "FreePBX 17: the init completes" -- t_wait_for 180 -- init_done "$c17"
assert_eq normal "$(mode "$c17")" "FreePBX 17: normal start"
assert_contains "$(docker logs "$c17" 2>&1)" "FreePBX 17.0.33 found: normal start" "FreePBX 17: reported in the log"

# --- FreePBX 15: refused
d15=$(fixture_db db15 db15 15.0.37)
before15=$(dbsum "$d15")
c15=$(pbx m15 "$(fixture_data data15)" db15)
assert_cmd "FreePBX 15: the container stops" -- t_wait_for 180 -- sh -c "[ \"\$(docker inspect -f '{{.State.Running}}' $c15)\" != true ]"
log15=$(docker logs "$c15" 2>&1)
assert_contains "$log15" "unsupported FreePBX version '15.0.37'" "FreePBX 15: the version is refused"
assert_contains "$log15" "upgrade first with izPBX 20.16.x" "FreePBX 15: instructions in the log"
assert_eq "$before15" "$(dbsum "$d15")" "FreePBX 15: the database is unchanged"

# --- control: empty /data
ce=$(t_run empty "$image" -v "$(t_volume dataempty):/data" -e APP_DATA=/data -e IZPBX_DRY_RUN=true -e MYSQL_PASSWORD=x)
assert_cmd "control: empty /data, the init completes" -- t_wait_for 120 -- init_done "$ce"
assert_eq install "$(mode "$ce")" "control: empty /data is a new installation"
finish
