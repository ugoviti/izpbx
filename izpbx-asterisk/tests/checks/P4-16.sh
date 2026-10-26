#!/usr/bin/env bash
# P4-16: Node, pm2 and UCP after the migration (M6): the 20.16.22 fixture
# (its /data holds the node tree of 20.16 in home/asterisk/.node) migrated in
# a real start. home/asterisk and var/www go to the snapshot, FreePBX 17
# installs ucp and pm2 from its own tree, "fwconsole start --post" starts
# them (freepbx-start).
# - "fwconsole pm2 --list": ucp online, same PID after 20 s (no restart loop);
# - the UCP node server answers on NODEJSBINDPORT (socket.io handshake);
# - no process uses a file of the old installation (open files and mapped
#   files under the snapshot or home/asterisk/.node, from /proc: lsof is not
#   in the image);
# - control: the snapshot does hold the node tree of 20.16.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-16
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
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 2400

fc() { docker exec -u asterisk "$c" fwconsole "$@"; }
ucp_state() { fc pm2 --list 2>/dev/null | awk -F'|' '$2 ~ /^ *ucp *$/ {gsub(/ /,""); print $4, $3, $5}'; }
stable_online() { # ucp online, then same PID and restarts after 20 s
  local a b
  t_wait_for 120 -- sh -c "docker exec -u asterisk $c fwconsole pm2 --list | grep -E '^\| ucp +\| [0-9]+ +\| online'" || return 1
  a=$(ucp_state); sleep 20; b=$(ucp_state)
  log "ucp: $a -> $b"
  [ "${a%% *}" == online ] && [ "$a" == "$b" ]
}
assert_cmd "pm2: ucp online and stable" -- stable_online
port=$(fc setting NODEJSBINDPORT 2>/dev/null | awk -F'[][{}]' '{print $2}')
port=${port:-8001}
hs=$(docker exec "$c" curl -s --max-time 10 "http://127.0.0.1:$port/socket.io/?EIO=4&transport=polling" || true)
[[ "$hs" == *'"sid"'* ]] || hs=$(docker exec "$c" curl -s --max-time 10 "http://127.0.0.1:$port/socket.io/?EIO=3&transport=polling" || true)
log "UCP node server on $port: ${hs:0:120}"
assert_contains "$hs" '"sid"' "UCP node server answers the websocket handshake on port $port"

snap=$(docker exec "$c" sh -c 'sed -n "s/^snapshot_dir=//p" /data/.izpbx-migration/state | tail -n 1')
old=$(docker exec "$c" sh -c "for p in /proc/[0-9]*; do
    ls -l \$p/fd 2>/dev/null | sed -n 's/.* -> //p'; awk '{print \$6}' \$p/maps 2>/dev/null; readlink \$p/cwd \$p/exe 2>/dev/null
  done | grep -E '^($snap|/data/home/asterisk/\.node|/home/asterisk/\.node)' | sort -u")
assert_eq "" "$old" "no process uses a file of the old installation (snapshot, home/asterisk/.node)"
assert_ne 0 "$(docker exec "$c" sh -c "find '$snap/fs/home/asterisk/.node' -type f 2>/dev/null | wc -l")" \
  "control: the snapshot holds the node tree of 20.16"
finish
