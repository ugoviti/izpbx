#!/usr/bin/env bash
# P4-33: migration without Internet access (D36). The 20.16.22 fixture and
# its database on a Docker network created with --internal (no way out),
# migrated in a real start with FOP2 enabled:
# - the checks M2 pass: the modules of the image, framework included, need no
#   mirror;
# - FreePBX 17 installs with pm2 and ucp: their Node packages are in the image
#   (build/node-modules.sh), npm needs no registry; every module Enabled;
# - the system prompts are there (vm-intro of every language of the 16), the
#   ones of the 16 taken from the snapshot by migration_audio (same checksum);
# - FOP2 cannot be downloaded: an error in the log, the migration goes on and
#   completes (verify=done), the container is healthy;
# - negative checks: the network really has no way out (curl to the FreePBX
#   mirror fails from the container), and a module the image does not have
#   (module17 variant) blocks the checks offline with the mirror message.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-33
base="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
assert_cmd "module17 variant derives" -- "$TESTS_DIR/fixtures/derive-variant.sh" "$base" module17

net="$TEST_PROJECT-net"
docker network create --internal --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
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
env_of() { echo "-e APP_DATA=/data -e MYSQL_SERVER=$1 -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw"; }

# --- negative: a module the image does not have blocks offline
fixture_db db17 "$base-module17" >/dev/null
v17=$(t_volume m17); fixture_data "$v17" "$base-module17"
# shellcheck disable=SC2046
out17=$(docker run --rm --entrypoint "" --network "$net" -v "$v17:/data" $(env_of db17) "$image" izpbx-preflight 2>&1 || true)
assert_cmd "negative: irc (not in the image) blocks offline: module list not readable" -- \
  grep -qE '^BLOCK modules: FreePBX 17 module list not readable .*irc' <<< "$out17"

# --- the migration offline
fixture_db db "$base" >/dev/null
v=$(t_volume data); fixture_data "$v" "$base"
# shellcheck disable=SC2046
out=$(docker run --rm --entrypoint "" --network "$net" -v "$v:/data" $(env_of db) "$image" izpbx-preflight 2>&1) && rc=0 || rc=$?
grep -E '^(BLOCK|RESULT)' <<< "$out" | sed 's/^/    | /' >&2
assert_eq 0 "$rc" "checks offline: nothing blocks (framework and the default modules from the image)"
# shellcheck disable=SC2046
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" $(env_of db) -e IZPBX_MIGRATE_FREEPBX=true -e FOP2_ENABLED=true)
assert_cmd_fails "negative: no way out of the network (curl to the FreePBX mirror)" -- \
  docker exec "$c" curl -fsS --max-time 15 -o /dev/null https://mirror.freepbx.org/
t_wait_for 2400 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)|MAINTENANCE MODE|izpbx-init: (failed|maintenance)' >/dev/null"
logs=$(docker logs "$c" 2>&1)
grep -E 'migration: (FreePBX 16 ->|VERIFICATION|FOP2|.*audio)|modules not installed|fop2: download|error:' <<< "$logs" | sed 's/^/    | /' >&2
state=$(docker exec "$c" cat /data/.izpbx-migration/state 2>/dev/null)
assert_cmd "migration completed offline (verify=done)" -- grep -qx 'verify=done' <<< "$state"
assert_cmd "healthy" -- t_wait_healthy "$c" 600
assert_cmd_fails "every module installed (no 'modules not installed')" -- grep -q 'modules not installed' <<< "$logs"
mods=$(docker exec -u asterisk "$c" fwconsole ma list 2>/dev/null)
for m in pm2 ucp soundlang; do
  assert_cmd "$m Enabled" -- grep -qE "^\| $m +\| [^|]+\| Enabled" <<< "$mods"
done
assert_eq "" "$(grep -iE '\| (Broken|Needs upgrade|Disabled; Pending upgrade)' <<< "$mods" || true)" "no module Broken or waiting for an upgrade"

# --- the system prompts, from the snapshot
snap=$(sed -n 's/^snapshot_dir=//p' <<< "$state" | tail -n 1)
langs=$(docker exec "$c" sh -c "cd '$snap/fs/var/lib/asterisk/sounds' && ls -d */ | tr -d / | grep -vxE 'custom|tmp'")
assert_ne "" "$langs" "the 16 had system prompts"
for l in $langs; do
  f=$(docker exec "$c" sh -c "cd '$snap/fs/var/lib/asterisk/sounds/$l' && ls vm-intro.* | head -n 1")
  assert_eq "$(docker exec "$c" sha256sum "$snap/fs/var/lib/asterisk/sounds/$l/$f" | cut -d' ' -f1)" \
    "$(docker exec "$c" sha256sum "/var/lib/asterisk/sounds/$l/$f" 2>/dev/null | cut -d' ' -f1)" "$l: system prompt $f from the snapshot"
done
assert_contains "$logs" "migration: FOP2 install failed: retried at the next start" "FOP2 without Internet: error logged, the migration goes on"
finish
