#!/usr/bin/env bash
# Shared setup for the checks that use the FreePBX 17 prototype (P0-10, P0-11).
# Source it after tests/lib.sh. Provides:
#   proto_up                start the prototype + its DB and install FreePBX 17
#   proto_restore ARCHIVE [fwconsole options]   restore, output in $work/<name>.log
#   proto_sql SQL           query the prototype DB (asterisk schema)
# and the variables proto_image, pbx, db, work.

proto_image=izpbx-proto/fpbx17:17.0.33
: "${work:?set work before sourcing proto.sh}"

proto_up() {
  docker build -q -t "$proto_image" "$TESTS_DIR/proto/fpbx17" >/dev/null || return 1
  local net="$TEST_PROJECT-net"
  docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
  db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=proto-root \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  pbx=$(t_run pbx "$proto_image" --network "$net" --hostname izpbx-proto -e MYSQL_PASSWORD=proto-pw -e MYSQL_ROOT_PASSWORD=proto-root)
  t_wait_healthy "$db" 120 || return 1
  docker exec "$pbx" proto-install.sh
}

proto_restore() { # archive [fwconsole options...]
  local archive=$1 name; shift
  name=$(basename "$archive" .tar.gz)
  docker cp "$archive" "$pbx:/home/asterisk/$name.tar.gz"
  docker exec "$pbx" chown asterisk: "/home/asterisk/$name.tar.gz"
  docker exec "$pbx" sh -c "cd /home/asterisk && fwconsole backup --restore=/home/asterisk/$name.tar.gz -n $*" > "$work/$name.log" 2>&1
}

proto_sql() { docker exec "$db" mariadb -uroot -pproto-root -N -B asterisk -e "$1"; }
