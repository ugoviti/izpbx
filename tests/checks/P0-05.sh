#!/usr/bin/env bash
# P0-05: fixtures from 20.16.18 and 20.16.21, plus the negative variants
# (Macro( in the dialplan, a module with no FreePBX 17 release, almost full
# disk). Each one is generated and holds its expected anomaly.
#
# TEST_REUSE_FIXTURES=1 (set by run.sh all-done) reuses fixtures built from
# unchanged inputs instead of regenerating them.
source "$(dirname "$0")/../lib.sh"

out="$TESTS_DIR/fixtures/out"
make() { "$TESTS_DIR/fixtures/make-fixture.sh" -o "$out" ${TEST_REUSE_FIXTURES:+--reuse} "$@" >/dev/null 2>&1; }
derive() { "$TESTS_DIR/fixtures/derive-variant.sh" "$out/20.16.22" "$1" >/dev/null 2>&1; }
mf() { sed -n "s/^$2=//p" "$out/$1/manifest.txt"; }
framework() { gzip -dc "$out/$1/asterisk.sql.gz" | grep -oE "'framework','[0-9.]+'" | head -1 | cut -d"'" -f4; }
verify() { "$TESTS_DIR/fixtures/verify-fixture.sh" "$out/$1" >/dev/null 2>&1; }

# the variants derive from the 20.16.22 fixture (P0-04)
assert_cmd "base 20.16.22 fixture available" -- make -v 20.16.22
fw22=$(framework 20.16.22)

for v in 20.16.18 20.16.21; do
  assert_cmd "fixture $v generates" -- make -v "$v"
  assert_eq "$v" "$(mf "$v" version)" "fixture $v declares its image version"
  assert_cmd "fixture $v holds every T5 element" -- verify "$v"
  fw=$(framework "$v")
  log "framework: $v=$fw, 20.16.22=$fw22"
  assert_ne "" "$fw" "fixture $v records its framework version"
done

# module with no FreePBX 17 release: simulated (irc 16.0.1 in "modules" and
# its admin/modules directory), derived from the 20.16.22 fixture
assert_cmd "module17 variant derives" -- derive module17
m=20.16.22-module17
modsql() { # fixture -> "modulename version enabled" of irc, from the restored dump
  local db
  db=$(t_run "db-${1//./}" docker.io/mariadb:10.11.19 -e MARIADB_ROOT_PASSWORD=rootpw -e MARIADB_DATABASE=asterisk \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$db" 120 || return 1
  gzip -dc "$out/$1/asterisk.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot asterisk || return 1
  echo "SELECT modulename, version, enabled FROM modules WHERE modulename = 'irc'" |
    docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot -N asterisk | tr '\t' ' '
}
assert_eq "irc 16.0.1 1" "$(modsql "$m")" "module17 variant: the dump restores with irc 16.0.1 enabled"
assert_eq "" "$(modsql 20.16.22)" "control: the base 20.16.22 fixture has no irc module"
xml=$(tar -xzOf "$out/$m/data.tar.gz" ./var/www/html/admin/modules/irc/module.xml 2>/dev/null || true)
assert_contains "$xml" "<rawname>irc</rawname>" "module17 variant has admin/modules/irc/module.xml"
assert_contains "$xml" "<version>16.0.1</version>" "module.xml declares version 16.0.1"
assert_eq "module irc 16.0.1 has no FreePBX 17 release" "$(mf "$m" anomaly)" "module17 manifest records the anomaly"
mirror17=$(curl -fsS --max-time 60 -X POST -d phpver=8.2 https://mirror.freepbx.org/all-17.0.xml || true)
assert_contains "$mirror17" "<rawname>core</rawname>" "FreePBX 17 mirror list downloaded"
if [[ "$mirror17" == *"<rawname>irc</rawname>"* ]]; then
  fail "irc now has a FreePBX 17 release: pick another module"
else
  pass "irc has no FreePBX 17 release"
fi

# Macro( in extensions_custom.conf, at the line recorded in the manifest
assert_cmd "macro variant derives" -- derive macro
anomaly=$(mf 20.16.22-macro anomaly)
file=${anomaly%:*}; line=${anomaly##*:}
text=$(tar -xzOf "$out/20.16.22-macro/data.tar.gz" "./$file" | sed -n "${line}p")
assert_contains "$text" "Macro(" "macro variant has Macro( at $anomaly"

# almost full disk: the data fits the recorded volume size, a second copy does not
assert_cmd "diskfull variant derives" -- derive diskfull
size=$(mf 20.16.22-diskfull volume_size_mb)
need=$(mf 20.16.22-diskfull data_size_mb)
free_after_restore() { # volume size in MB -> free MB after unpacking the fixture
  local vol="$TEST_PROJECT-disk$1"
  docker volume create --label "izpbx.test=$TEST_PROJECT" --driver local \
    --opt type=tmpfs --opt device=tmpfs --opt "o=size=${1}m" "$vol" >/dev/null
  docker run --rm --label "izpbx.test=$TEST_PROJECT" -v "$vol:/data" -v "$out/20.16.22-diskfull:/fx:ro" \
    --entrypoint sh docker.io/mariadb:10.11.19 -c 'tar -C /data -xzf /fx/data.tar.gz && df -Pm /data | awk "NR==2{print \$4}"'
}
free=$(free_after_restore "$size")
log "diskfull: volume ${size} MB, data ${need} MB, free after restore ${free} MB"
assert_cmd "diskfull data fits its volume" -- test -n "$free"
assert_cmd "diskfull volume has no room for a second copy" -- test "${free:-0}" -lt "$need"
free_big=$(free_after_restore $((size * 2 + 64)))
assert_cmd "control: a larger volume does have room" -- test "${free_big:-0}" -ge "$need"

finish
