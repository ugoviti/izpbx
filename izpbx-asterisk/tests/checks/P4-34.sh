#!/usr/bin/env bash
# P4-34: ENABLE_ARI in the final report (D35). The restore puts ENABLE_ARI
# back to the FreePBX 17 default and the migration does not set it again: the
# report and the log say so when it was enabled in FreePBX 16. Two real
# migrations of the 20.16.22 fixture, side by side:
# - as it is (ENABLE_ARI=1 in its Advanced Settings): ENABLE_ARI not 1 after
#   the migration, the report has the ENABLE_ARI line, the log the warning;
# - control: ENABLE_ARI set to 0 before the migration: no ENABLE_ARI line.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-34
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
migrate() { # name [sql before the migration] -> container id
  local d v
  d=$(t_run "$1-db" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$1-db" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || die "MariaDB did not start"
  for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot || die "cannot load $f"; done
  echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'; ${2:-}" |
    docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot asterisk
  v=$(t_volume "$1")
  docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
  t_run "$1" "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER="$1-db" -e MYSQL_PASSWORD=fixture-pw \
    -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true
}
done_wait() { t_wait_for 2400 -- sh -c "docker logs '$1' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)|MAINTENANCE MODE' >/dev/null"; }
ari_of() { # pbx container, its database alias
  docker exec -e MYSQL_PWD=rootpw "$1" mariadb -h "$2" -uroot -N asterisk -e "SELECT value FROM freepbx_settings WHERE keyword = 'ENABLE_ARI'" 2>/dev/null || true
}

assert_eq 1 "$(gzip -dc "$fx/asterisk.sql.gz" | grep -oE "\('ENABLE_ARI','[01]'" | grep -oE "[01]'$" | tr -d "'")" "the fixture has ENABLE_ARI=1"
on=$(migrate on)
off=$(migrate off "UPDATE freepbx_settings SET value = '0' WHERE keyword = 'ENABLE_ARI';")
done_wait "$on"; done_wait "$off"

# --- ENABLE_ARI on in FreePBX 16
assert_cmd "migrated (ENABLE_ARI on)" -- docker exec "$on" grep -qx 'verify=done' /data/.izpbx-migration/state
after=$(ari_of "$on" on-db)
log "ENABLE_ARI after the migration: '$after'"
assert_ne 1 "$after" "the restore put ENABLE_ARI back to the default (D35: not set again)"
report=$(docker exec "$on" cat /data/.izpbx-migration/report.txt)
assert_contains "$report" "ENABLE_ARI (D35): enabled in FreePBX 16" "the report has the ENABLE_ARI line"
assert_contains "$report" "fwconsole setting ENABLE_ARI 1" "with the instruction to enable it again"
assert_cmd "the log has the warning" -- sh -c "docker logs '$on' 2>&1 | grep 'migration: ENABLE_ARI was enabled in FreePBX 16' >/dev/null"

# --- control: ENABLE_ARI off in FreePBX 16
assert_cmd "migrated (ENABLE_ARI off)" -- docker exec "$off" grep -qx 'verify=done' /data/.izpbx-migration/state
assert_cmd_fails "control: no ENABLE_ARI line when it was off" -- docker exec "$off" grep -q 'ENABLE_ARI' /data/.izpbx-migration/report.txt
finish
