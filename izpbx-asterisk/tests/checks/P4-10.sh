#!/usr/bin/env bash
# P4-10: custom prompts, sounds/custom and music on hold after the migration
# (M6, migration_audio): the 20.16.22 fixture migrated in a real start.
# - the categories sounds_custom and moh of izpbx-inventory (path and sha256
#   of every file) after the migration (--live) equal the inventory before;
# - the copied files belong to asterisk;
# - control: one prompt removed after the migration is a difference.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-10
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

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
env=(-e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw)
docker run --rm --entrypoint "" --network "$net" -v "$v:/data:ro" "${env[@]}" "$image" izpbx-inventory > "$work/before.json"
audio() { jq -S '{sounds_custom: .categories.sounds_custom, moh: .categories.moh}' "$1"; }
log "before: $(audio "$work/before.json" | jq -c .)"
assert_ne "null" "$(jq -c '.categories.sounds_custom' "$work/before.json")" "the fixture has custom prompts"
assert_ne "null" "$(jq -c '.categories.moh' "$work/before.json")" "the fixture has music on hold"

c=$(t_run pbx "$image" --network "$net" -v "$v:/data" "${env[@]}" -e IZPBX_MIGRATE_FREEPBX=true)
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 2400
log "$(docker logs "$c" 2>&1 | grep 'migration: .* audio file' | sed 's/^izpbx: info: //')"
docker exec "$c" izpbx-inventory --live > "$work/after.json"
assert_eq "$(audio "$work/before.json")" "$(audio "$work/after.json")" "sounds_custom and moh: same files and checksums as before"
assert_eq "" "$(docker exec "$c" find /var/lib/asterisk/sounds/custom /var/lib/asterisk/moh/fixture-moh ! -user asterisk)" \
  "the copied files belong to asterisk"

# control: a prompt removed after the migration
docker exec "$c" rm -f /var/lib/asterisk/sounds/custom/fixture-welcome.wav
docker exec "$c" izpbx-inventory --live > "$work/after-1.json"
assert_ne "$(audio "$work/before.json")" "$(audio "$work/after-1.json")" "control: a missing prompt is a difference"
finish
