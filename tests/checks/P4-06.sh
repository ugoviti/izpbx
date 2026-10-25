#!/usr/bin/env bash
# P4-06 (T7): the migration state machine resumes after a crash. For each
# phase M4-M6 the 20.16.22 fixture is migrated with IZPBX_TEST_KILL_AT=<point>:
# izpbx-init is killed (kill -9) once at that point, the container stops; it
# is started again and must complete the migration:
#   snapshot (M4, after the first directory moved), archive (M5.1, before the
#   tar), dbreset (M5.2, after the DROP of the config database), install
#   (M5.3, after FreePBX 17 is installed), restore (M5.4, after the restore),
#   audio (M6, after the copy of the audio files).
# For each point:
# - the first start stops at the point (the kill is logged, the container
#   exits);
# - after "docker start" the container becomes healthy, the state has
#   restore=done and the resume is logged;
# - izpbx-inventory --diff of the fixture before and of the PBX after is
#   empty with the mapping of P4-08.
# Three scenarios run at a time (each one a database and a volume).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-06
fx="$TESTS_DIR/fixtures/out/20.16.22"
points="snapshot archive dbreset install restore audio"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
fixture_db() { # name -> a MariaDB on the network (alias = name) with the fixture
  local d
  d=$(t_run "$1" docker.io/mariadb:10.11.19 --network "$net" --network-alias "$1" -e MARIADB_ROOT_PASSWORD=rootpw \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$d" 120 || return 1
  for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot || return 1; done
  echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
    docker exec -i -e MYSQL_PWD=rootpw "$d" mariadb -uroot
}
fixture_data() { # volume
  docker run --rm --entrypoint "" -v "$1:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
}
env_of() { echo "-e APP_DATA=/data -e MYSQL_SERVER=$1 -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw"; }

# inventory before, once (every scenario starts from the same fixture)
fixture_db dbref || die "MariaDB did not start"
vref=$(t_volume ref); fixture_data "$vref"
# shellcheck disable=SC2046
docker run --rm --entrypoint "" --network "$net" -v "$vref:/data:ro" $(env_of dbref) "$image" izpbx-inventory > "$work/before.json"
printf '%s\n' \
  "extensions	tech=sip	tech=pjsip" \
  "trunks	tech=sip	tech=pjsip" \
  "modules	^module=phonebook enabled=1$	module=framework enabled=1" \
  "astdb	ignore" "files	ignore" "advanced_settings	ignore" "pjsip_endpoints	ignore" > "$work/map"

scenario() { # point -> $work/<point>.result: killed healthy restored diff-rc
  local p=$1 db="db-$1" v c killed=0 healthy=0 restored=0 rc=9
  fixture_db "$db" || { echo "nodb" > "$work/$p.result"; return; }
  v=$(t_volume "data-$p"); fixture_data "$v"
  # shellcheck disable=SC2046
  c=$(t_run "pbx-$p" "$image" --network "$net" -v "$v:/data" $(env_of "$db") \
    -e IZPBX_MIGRATE_FREEPBX=true -e IZPBX_TEST_KILL_AT="$p")
  if t_wait_for 1500 -- sh -c "[ \"\$(docker inspect -f '{{.State.Running}}' $c)\" != true ]" &&
     docker logs "$c" 2>&1 | grep "migration: test kill at '$p'" >/dev/null; then
    killed=1
  fi
  docker logs "$c" > "$work/$p.log1" 2>&1
  docker start "$c" >/dev/null
  t_wait_healthy "$c" 2400 && healthy=1
  docker logs "$c" > "$work/$p.log2" 2>&1
  docker exec "$c" grep -qx 'restore=done' /data/.izpbx-migration/state && restored=1
  if [ "$healthy" == 1 ]; then
    docker exec "$c" izpbx-inventory --live > "$work/$p.after.json"
    docker cp "$work/before.json" "$c:/tmp/before.json" >/dev/null
    docker cp "$work/$p.after.json" "$c:/tmp/after.json" >/dev/null
    docker cp "$work/map" "$c:/tmp/map" >/dev/null
    docker exec "$c" izpbx-inventory --diff /tmp/before.json /tmp/after.json --mapping /tmp/map > "$work/$p.diff" 2>&1 && rc=0 || rc=$?
  fi
  echo "$killed $healthy $restored $rc" > "$work/$p.result"
  docker rm -f "$c" "$TEST_PROJECT-$db" >/dev/null 2>&1
}

set -- $points
while [ $# -gt 0 ]; do
  for p in "$1" "${2:-}" "${3:-}"; do [ -n "$p" ] && scenario "$p" & done
  wait
  shift $(( $# < 3 ? $# : 3 ))
done

for p in $points; do
  read -r killed healthy restored rc < "$work/$p.result" || true
  log "$p: killed=$killed healthy=$healthy restore=$restored diff-rc=$rc; resume: $(grep -c 'in progress.*resuming' "$work/$p.log2" 2>/dev/null) line(s)"
  [ "${rc:-9}" == 0 ] || sed 's/^/    | /' "$work/$p.diff" 2>/dev/null | head -n 20 >&2
  [ "${healthy:-0}" == 1 ] || grep -E 'error|die|failed' "$work/$p.log2" 2>/dev/null | tail -n 10 | sed 's/^/    | /' >&2
  assert_eq 1 "${killed:-0}" "$p: the first start is killed at the point and stops"
  assert_eq 1 "${healthy:-0}" "$p: after the restart the container becomes healthy"
  assert_eq 1 "${restored:-0}" "$p: the state has restore=done"
  assert_cmd "$p: the restart resumes the migration" -- grep -q 'migration to FreePBX 17 in progress.*resuming' "$work/$p.log2"
  assert_eq 0 "${rc:-9}" "$p: inventory diff empty with the mapping"
done
finish
