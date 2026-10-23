#!/usr/bin/env bash
# P0-10: variant B prototype. An archive rebuilt from the raw data of the
# 20.16.22 fixture is restored by FreePBX 17 (fwconsole backup --restore) on a
# fresh install: exit 0, and extensions, trunks, IVR, queues, ring groups and
# routes match the fixture. Negative: an archive without the IVR table is
# restored too, and the comparison catches the missing IVR.
source "$(dirname "$0")/../lib.sh"

fx="$TESTS_DIR/fixtures/out/20.16.22"
proto_image=izpbx-proto/fpbx17:17.0.33
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
assert_cmd "FreePBX 17 prototype image builds" -- docker build -q -t "$proto_image" "$TESTS_DIR/proto/fpbx17"

# reference DB with the fixture content
ref=$(t_run ref docker.io/mariadb:10.11.19 -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
# FreePBX 17 prototype + its DB
net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=proto-root \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
pbx=$(t_run pbx "$proto_image" --network "$net" --hostname izpbx-proto -e MYSQL_PASSWORD=proto-pw -e MYSQL_ROOT_PASSWORD=proto-root)
t_wait_healthy "$ref" 120 || die "reference MariaDB did not start"
t_wait_healthy "$db" 120 || die "prototype MariaDB did not start"
gzip -dc "$fx/asterisk.sql.gz" | docker exec -i "$ref" mariadb -uroot

assert_cmd "FreePBX 17 installs on the prototype" -- docker exec "$pbx" proto-install.sh

assert_cmd "legacy archive builds from the fixture" -- "$TESTS_DIR/proto/build-legacy-archive.sh" "$fx" "$work/restore.tar.gz"
assert_cmd "legacy archive without IVR builds" -- "$TESTS_DIR/proto/build-legacy-archive.sh" "$fx" "$work/restore-noivr.tar.gz" --drop-table ivr_details

restore() { # archive -> output in $work/<name>.log, exit code of fwconsole
  local name; name=$(basename "$1" .tar.gz)
  docker cp "$1" "$pbx:/home/asterisk/$name.tar.gz"
  docker exec "$pbx" chown asterisk: "/home/asterisk/$name.tar.gz"
  docker exec "$pbx" sh -c "cd /home/asterisk && fwconsole backup --restore=/home/asterisk/$name.tar.gz --convertchansipexts2pjsip --convertchansiptrunks2pjsip -n" > "$work/$name.log" 2>&1
}

TABLES="devices trunks ivr_details queues_config ringgroups outbound_routes incoming timeconditions userman_users recordings fax_incoming"
counts() { # container password -> "table=count ..."
  local c=$1 pw=$2 t
  for t in $TABLES; do
    printf '%s=%s ' "$t" "$(docker exec "$c" mariadb -uroot ${pw:+-p"$pw"} -N -B -e "SELECT count(*) FROM asterisk.$t" 2>/dev/null || echo missing)"
  done
}
expected=$(counts "$ref" "")
log "fixture:  $expected"

restore "$work/restore.tar.gz" && rc=0 || rc=$?
assert_eq 0 "$rc" "fwconsole backup --restore exits 0"
assert_contains "$(cat "$work/restore.log")" "Restore completed successfully" "restore reports success"
got=$(counts "$db" proto-root)
log "restored: $got"
for t in $TABLES; do
  assert_eq "$(tr ' ' '\n' <<< "$expected" | grep "^$t=")" "$(tr ' ' '\n' <<< "$got" | grep "^$t=")" "restored $t matches the fixture"
done
techs=$(docker exec "$db" mariadb -uroot -pproto-root -N -B -e "SELECT CONCAT((SELECT count(*) FROM asterisk.devices WHERE tech='sip'), '/', (SELECT count(*) FROM asterisk.trunks WHERE tech='sip'))")
assert_eq "0/0" "$techs" "no chan_sip device or trunk left (converted by the restore)"

# negative: the IVR missing from the archive must show up in the comparison
restore "$work/restore-noivr.tar.gz" || true
assert_ne "$(tr ' ' '\n' <<< "$expected" | grep '^ivr_details=')" \
  "$(tr ' ' '\n' <<< "$(counts "$db" proto-root)" | grep '^ivr_details=')" "an archive without the IVR is caught by the comparison"

finish
