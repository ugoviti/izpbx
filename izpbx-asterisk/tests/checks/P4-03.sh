#!/usr/bin/env bash
# P4-03: read only checks M2 before the migration (izpbx-preflight), report on
# stdout and in ${APP_DATA}/.izpbx-migration/preflight-<ts>.txt.
# - base 20.16.22 fixture: nothing blocks, phonebook (no FreePBX 17 release,
#   D28) listed as removed by the migration; /data (outside
#   .izpbx-migration) and the database unchanged after the checks;
# - each negative fixture trips exactly its own check: diskfull -> space,
#   macro -> dialplan with file and line, module17 -> modules (irc);
#   a user without DROP/CREATE and no root -> database; an old framework ->
#   framework;
# - controls: IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN=true and
#   IZPBX_MIGRATE_IGNORE_MODULES=irc unblock their fixture;
# - a FreePBX 16 start (migration mode) runs the checks in izpbx-init:
#   report in the log, result in /run/izpbx/preflight.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-03
fx="$TESTS_DIR/fixtures/out"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -o "$fx" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
for v in macro diskfull module17; do
  assert_cmd "$v variant derives" -- "$TESTS_DIR/fixtures/derive-variant.sh" "$fx/20.16.22" "$v"
done

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
fixture_db() { # name fixture -> a MariaDB on the network (alias = name) with the fixture dumps
  local d
  d=$(t_run "$1" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$1" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || die "MariaDB did not start"
  for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$2/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot || die "cannot load $f"; done
  echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%';
        CREATE USER lim@'%' IDENTIFIED BY 'lim-pw'; GRANT SELECT, INSERT, UPDATE, DELETE ON asterisk.* TO lim@'%'; GRANT SELECT ON asteriskcdrdb.* TO lim@'%'" |
    docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot
  printf '%s\n' "$d"
}
fixture_data() { # volume fixture
  docker run --rm --entrypoint "" -v "$1:/data" -v "$fx/$2:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
}
datasum() { # volume -> checksum of /data outside .izpbx-migration: every entry
  # (type, mode, owner, symlink target) and the content of the regular files
  docker run --rm --entrypoint "" -v "$1:/data:ro" "$image" sh -c 'cd /data && {
    find . -path ./.izpbx-migration -prune -o -printf "%y %m %U:%G %p %l\n" | LC_ALL=C sort
    find . -path ./.izpbx-migration -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum; } | sha256sum'
}
dbsum() { docker exec -e MYSQL_PWD=rootpw "$1" sh -c 'for s in asterisk asteriskcdrdb; do
  mariadb -uroot -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema=\"$s\" ORDER BY 1" |
  while read -r t; do mariadb -uroot -N "$s" -e "CHECKSUM TABLE \`$t\`"; done; done | md5sum'; }
preflight() { # volume db [env...] -> the report on stdout, exit code of izpbx-preflight
  local v=$1 db=$2; shift 2
  docker run --rm --entrypoint "" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER="$db" \
    -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw "$@" "$image" izpbx-preflight 2>&1
}
blocks() { { grep -oE '^BLOCK [a-z_]+' <<< "$1" || true; } | tr '\n' ' ' | sed 's/ $//'; }

db=$(fixture_db db 20.16.22)
fixture_db dbm 20.16.22-module17 >/dev/null

# --- base fixture: nothing blocks, phonebook removed, nothing changed
vb=$(t_volume base); fixture_data "$vb" 20.16.22
data_before=$(dbsum "$db") files_before=$(datasum "$vb")
out=$(preflight "$vb" db) && rc=0 || rc=$?
log "base report:"; sed 's/^/    | /' <<< "$out" >&2
assert_eq 0 "$rc" "base 20.16.22: nothing blocks (exit 0)"
assert_eq "" "$(blocks "$out")" "base 20.16.22: no BLOCK line"
assert_contains "$out" "REMOVED modules: phonebook has no FreePBX 17 release" "base 20.16.22: phonebook listed as removed"
assert_contains "$out" "INFO chan_sip:" "base 20.16.22: chan_sip conversion reported"
assert_contains "$out" "RESULT: nothing blocks the migration" "base 20.16.22: result line"
report=$(docker run --rm --entrypoint "" -v "$vb:/data:ro" "$image" sh -c 'cat /data/.izpbx-migration/preflight-*.txt')
assert_contains "$report" "REMOVED modules: phonebook" "base 20.16.22: report saved in .izpbx-migration/preflight-<ts>.txt"
assert_eq "$data_before" "$(dbsum "$db")" "base 20.16.22: databases unchanged"
assert_eq "$files_before" "$(datasum "$vb")" "base 20.16.22: /data unchanged outside .izpbx-migration"

# --- negative fixtures: exactly their own check
vm=$(t_volume macro); fixture_data "$vm" 20.16.22-macro
anomaly=$(sed -n 's/^anomaly=//p' "$fx/20.16.22-macro/manifest.txt")
out=$(preflight "$vm" db) && rc=0 || rc=$?
# Macro() is converted by the migration (P4-37): reported, not blocking
assert_eq 0 "$rc" "macro: Macro() is converted by the migration, nothing blocks"
assert_contains "$(grep '^INFO dialplan' <<< "$out")" "converted for Asterisk 22 by the migration" "macro: reported as converted"
assert_contains "$(grep '^INFO dialplan' <<< "$out")" "${anomaly%%:*}" "macro: the report names ${anomaly%%:*}"
# what cannot be converted blocks: Monitor(), also in an included file
docker run --rm --entrypoint "" -v "$vm:/data" "$image" sh -c '
  mkdir -p /data/etc/asterisk/sub
  printf "[fixture-monitor]\nexten => s,1,Monitor(wav,foo)\n" > /data/etc/asterisk/sub/legacy.conf
  echo "#include sub/legacy.conf" >> /data/etc/asterisk/extensions_custom.conf'
out=$(preflight "$vm" db) && rc=0 || rc=$?
assert_ne 0 "$rc" "monitor: blocked (exit != 0)"
assert_eq "BLOCK dialplan" "$(blocks "$out")" "monitor: only the dialplan check blocks"
assert_contains "$(grep '^BLOCK dialplan' <<< "$out")" "etc/asterisk/sub/legacy.conf:2" "monitor: the report names the included file and line"
out=$(preflight "$vm" db -e IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN=true) && rc=0 || rc=$?
assert_eq 0 "$rc" "control: monitor with IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN=true is not blocked"

v17=$(t_volume module17); fixture_data "$v17" 20.16.22-module17
out=$(preflight "$v17" dbm) && rc=0 || rc=$?
assert_ne 0 "$rc" "module17: blocked (exit != 0)"
assert_eq "BLOCK modules" "$(blocks "$out")" "module17: only the modules check blocks"
assert_contains "$(grep '^BLOCK modules' <<< "$out")" "irc" "module17: the report names irc"
out=$(preflight "$v17" dbm -e IZPBX_MIGRATE_IGNORE_MODULES=irc) && rc=0 || rc=$?
assert_eq 0 "$rc" "control: module17 with IZPBX_MIGRATE_IGNORE_MODULES=irc is not blocked"

size=$(sed -n 's/^volume_size_mb=//p' "$fx/20.16.22-diskfull/manifest.txt")
vd="$TEST_PROJECT-diskfull"
docker volume create --label "izpbx.test=$TEST_PROJECT" --driver local \
  --opt type=tmpfs --opt device=tmpfs --opt "o=size=${size}m" "$vd" >/dev/null
# a tmpfs volume is empty again in every container: unpack and check in the same one
out=$(docker run --rm --entrypoint "" --network "$net" -v "$vd:/data" -v "$fx/20.16.22-diskfull:/fx:ro" \
  -e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw "$image" \
  sh -c 'tar -C /data -xzf /fx/data.tar.gz 2>/dev/null; izpbx-preflight' 2>&1) && rc=0 || rc=$?
log "diskfull: $(grep 'space:' <<< "$out")"
assert_ne 0 "$rc" "diskfull: blocked (exit != 0)"
assert_eq "BLOCK space" "$(blocks "$out")" "diskfull: only the space check blocks"

out=$(preflight "$vb" db -e MYSQL_USER=lim -e MYSQL_PASSWORD=lim-pw -e MYSQL_ROOT_PASSWORD=) && rc=0 || rc=$?
assert_ne 0 "$rc" "user without DROP/CREATE and no root: blocked"
assert_eq "BLOCK database" "$(blocks "$out")" "user without DROP/CREATE: only the database check blocks"
out=$(preflight "$vb" db -e MYSQL_ROOT_PASSWORD=) && rc=0 || rc=$?
assert_eq 0 "$rc" "control: a user with ALL on the database and no root is not blocked"

# --- a FreePBX 16 start runs the checks in izpbx-init
c=$(t_run pbx "$image" --network "$net" -v "$vb:/data" -e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw)
assert_cmd "migration start: the init completes" -- \
  t_wait_for 180 -- sh -c "docker logs $c 2>&1 | grep 'izpbx-init: done' >/dev/null"
assert_cmd "migration start: report in the log" -- \
  sh -c "docker logs $c 2>&1 | grep 'preflight: RESULT: nothing blocks the migration' >/dev/null"
assert_eq ok "$(docker exec "$c" cat /run/izpbx/preflight 2>/dev/null)" "migration start: result in /run/izpbx/preflight"
docker rm -f "$c" >/dev/null

# --- old framework (last: it changes the base database)
echo "UPDATE modules SET version = '16.0.10' WHERE modulename = 'framework'" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot asterisk
out=$(preflight "$vb" db) && rc=0 || rc=$?
assert_ne 0 "$rc" "framework 16.0.10: blocked"
assert_eq "BLOCK framework" "$(blocks "$out")" "framework 16.0.10: only the framework check blocks"
finish
