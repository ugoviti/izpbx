#!/usr/bin/env bash
# P4-32: data of the FreePBX speeddial module (D30), installed on the
# installs born on FreePBX 15 (fixture P0-08b): the speeddial variant of
# 20.16.22-fp15 (system speed dial 12 -> 1002 in sysspeeddials, personal one
# of 1001, 5 -> 0612349999 in AMPUSER/1001/speeddials) migrated in a real
# start, without IZPBX_MIGRATE_IGNORE_MODULES.
# speeddial is a known exception (no FreePBX 17 release, like phonebook):
# - the checks M2 list it as removed, nothing blocks; the migration completes
#   (verify=done, no Broken module);
# - the system speed dial is a Contact Manager speed dial (12 -> 1002) and
#   works in a sipp call: 1003 dials *1012 and the call goes on to 1002;
# - the personal speed dial (no FreePBX 17 equivalent) is in
#   speeddials-users.csv of the snapshot; the log and the final report name
#   both; fwconsole reload has no error about the missing module.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-32
sipp_image=izpbx-test-sipp:p4-32
base="$TESTS_DIR/fixtures/out/20.16.22-fp15"
fx="$TESTS_DIR/fixtures/out/20.16.22-fp15-speeddial"
sc="$TESTS_DIR/sipp/scenarios"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
t_on_cleanup "docker image rm $sipp_image >/dev/null 2>&1"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "sipp image builds" -- docker build -q -t "$sipp_image" "$TESTS_DIR/sipp"
assert_cmd "fp15 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 --variant fp15 ${TEST_REUSE_FIXTURES:+--reuse}
assert_cmd "speeddial variant derives" -- "$TESTS_DIR/fixtures/derive-variant.sh" "$base" speeddial
chmod 777 "$work"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
sql() { echo "$1" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot -N asterisk; }
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
  docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot
v=$(t_volume data)
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
c=$(t_run pbx "$image" --network "$net" --network-alias pbx -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)
t_wait_for 2400 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED|phonebook to Contact Manager failed)|izpbx-init: maintenance' >/dev/null"
logs=$(docker logs "$c" 2>&1)
grep -E 'preflight: (BLOCK|REMOVED|RESULT)|phonebook|speed dial|VERIFICATION|error:   ' <<< "$logs" | sed 's/^/    | /' >&2
assert_cmd "M2: speeddial removed on purpose" -- grep -q 'preflight: REMOVED modules: speeddial has no FreePBX 17 release' <<< "$logs"
assert_cmd "M2: nothing blocks" -- grep -q 'preflight: RESULT: nothing blocks the migration' <<< "$logs"
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 300
state=$(docker exec "$c" cat /data/.izpbx-migration/state 2>/dev/null)
assert_cmd "verification M7 passed (verify=done)" -- grep -qx 'verify=done' <<< "$state"
snap=$(sed -n 's/^snapshot_dir=//p' <<< "$state" | tail -n 1)
assert_eq "" "$(docker exec -u asterisk "$c" fwconsole ma list 2>/dev/null | grep -iE '^\| [^|]+\| [^|]+\| Broken' || true)" "no module Broken"

# --- system speed dial: Contact Manager
assert_eq "1002" "$(sql "SELECT n.number FROM contactmanager_entry_speeddials s JOIN contactmanager_entry_numbers n ON n.id = s.numberid WHERE s.id = 12")" \
  "system speed dial 12 -> 1002 in Contact Manager"

# --- personal speed dial: CSV, log, report
ucsv=$(docker exec "$c" cat "$snap/speeddials-users.csv" 2>/dev/null)
log "speeddials-users.csv: $(tr '\n' ' ' <<< "$ucsv")"
assert_cmd "personal speed dial in speeddials-users.csv" -- grep -qx '1001,5,0612349999' <<< "$ucsv"
assert_cmd "the log names the personal speed dial" -- grep -q '1 personal speed dial(s) of FreePBX 16 (speeddial module) have no FreePBX 17 equivalent' <<< "$logs"
report=$(docker exec "$c" cat /data/.izpbx-migration/report.txt 2>/dev/null)
assert_contains "$report" "personal speed dials (D30, speeddial module, no FreePBX 17 equivalent): 1 in" "the final report names the personal speed dial"
assert_contains "$report" "modules left out (no FreePBX 17 release): phonebook speeddial" "the final report names speeddial left out"
assert_eq "" "$(docker exec "$c" sh -c "grep -iE 'error|exception|fatal' '$snap/phonebook-reload.log' | grep -i speeddial" || true)" \
  "fwconsole reload: no error about the speeddial module"

# --- the speed dial in a call: 1003 dials *1012
printf 'SEQUENTIAL\n1003\n' > "$work/call.csv"
docker run --rm --network "$net" -v "$sc:/sc:ro" -v "$work:/w" -w /w "$sipp_image" pbx:5060 -sf /sc/call.xml -inf /w/call.csv \
  -au 1003 -ap Fx-pjsip-1003-pw -s '*1012' -m 1 -p 5090 -mp 7000 -timeout 40 -trace_msg >/dev/null 2>&1 || true
log "codes to the caller: $(grep -hE '^SIP/2.0 [0-9]+' "$work"/call_*_messages.log 2>/dev/null | awk '{print $2}' | tr '\n' ' ')"
# grep >/dev/null, not -q: the full log is long (SIGPIPE)
assert_cmd "the speed dial *1012 goes on to 1002" -- sh -c "docker exec '$c' grep -E 'Executing \\[\\*1012@from-internal:[0-9]+\\] GotoIf\\(\"PJSIP/1003-[^\"]*\", \"1\\?from-internal,1002,1\"\\)' /var/log/asterisk/full >/dev/null"
finish
