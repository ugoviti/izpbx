#!/usr/bin/env bash
# P4-31: data of the FreePBX phonebook module (D28). The phonebook fixture
# variant (20.16.22 with 3 phonebook entries in the astdb cidname family and
# the system speed dial 11 -> 1003 in sysspeeddials) migrated in a real start.
# FreePBX 17 has no phonebook module; its equivalent is Contact Manager:
# - the 3 entries are in the Contact Manager group "Phonebook (izPBX 20.16)",
#   the speed dial keeps its code (11 -> 1003);
# - the CSV export in the snapshot has as many entries as the fixture;
# - the final report names them; fwconsole reload has no error about the
#   missing module; the migration completes (verify=done);
# - the speed dial works in a sipp call: 1002 dials *1011 (the Contact
#   Manager speed dial code *10 + 11) and the call goes on to 1003.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-31
sipp_image=izpbx-test-sipp:p4-31
base="$TESTS_DIR/fixtures/out/20.16.22"
fx="$TESTS_DIR/fixtures/out/20.16.22-phonebook"
sc="$TESTS_DIR/sipp/scenarios"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
t_on_cleanup "docker image rm $sipp_image >/dev/null 2>&1"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "sipp image builds" -- docker build -q -t "$sipp_image" "$TESTS_DIR/sipp"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
assert_cmd "phonebook variant derives" -- "$TESTS_DIR/fixtures/derive-variant.sh" "$base" phonebook
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
want=$(sed -n 's/^phonebook_entries=//p' "$fx/manifest.txt")
c=$(t_run pbx "$image" --network "$net" --network-alias pbx -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)
t_wait_for 2400 -- sh -c "docker logs '$c' 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED|phonebook to Contact Manager failed)|izpbx-init: maintenance' >/dev/null"
logs=$(docker logs "$c" 2>&1)
grep -E -e 'phonebook|VERIFICATION' -e "$T_LOG_DETAIL_RE" <<< "$logs" | sed 's/^/    | /' >&2
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 300
state=$(docker exec "$c" cat /data/.izpbx-migration/state 2>/dev/null)
assert_cmd "verification M7 passed (verify=done)" -- grep -qx 'verify=done' <<< "$state"
snap=$(sed -n 's/^snapshot_dir=//p' <<< "$state" | tail -n 1)

# --- Contact Manager
gid=$(sql "SELECT id FROM contactmanager_groups WHERE name = 'Phonebook (izPBX 20.16)' AND type = 'external'")
assert_ne "" "$gid" "Contact Manager group 'Phonebook (izPBX 20.16)'"
entries=$(sql "SELECT e.displayname, n.number FROM contactmanager_group_entries e JOIN contactmanager_entry_numbers n ON n.entryid = e.id WHERE e.groupid = '$gid' ORDER BY n.number")
log "entries: $(tr '\t\n' '= ' <<< "$entries")"
assert_eq "$want" "$(grep -c . <<< "$entries")" "Contact Manager: $want entries, as in the fixture"
assert_cmd "Contact Manager: Rossi Mario 0612340001" -- grep -qP '^Rossi Mario\t0612340001$' <<< "$entries"
assert_eq "1003" "$(sql "SELECT n.number FROM contactmanager_entry_speeddials s JOIN contactmanager_entry_numbers n ON n.id = s.numberid WHERE s.id = 11")" \
  "speed dial 11 kept: 1003"

# --- CSV, report, reload
csv=$(docker exec "$c" cat "$snap/phonebook.csv" 2>/dev/null)
assert_eq "$want" "$(tail -n +2 <<< "$csv" | grep -c .)" "CSV export: $want entries"
assert_contains "$(docker exec "$c" cat /data/.izpbx-migration/report.txt 2>/dev/null)" "phonebook (D28): $want entries in the Contact Manager group" \
  "the final report names the phonebook entries"
assert_eq "" "$(docker exec "$c" sh -c "grep -iE 'error|exception|fatal' '$snap/phonebook-reload.log' | grep -i phonebook" || true)" \
  "fwconsole reload: no error about the phonebook module"

# --- the speed dial in a call: 1002 dials *1011
code=$(sql "SELECT IF(customcode <> '', customcode, defaultcode) FROM featurecodes WHERE modulename = 'contactmanager' AND featurename = 'app-contactmanager-sd'")
assert_eq '*10' "$code" "Contact Manager speed dial feature code *10"
printf 'SEQUENTIAL\n1002\n' > "$work/call.csv"
docker run --rm --network "$net" -v "$sc:/sc:ro" -v "$work:/w" -w /w "$sipp_image" pbx:5060 -sf /sc/call.xml -inf /w/call.csv \
  -au 1002 -ap Fx-pjsip-1002-pw -s '*1011' -m 1 -p 5090 -mp 7000 -timeout 40 -trace_msg >/dev/null 2>&1 || true
log "codes to the caller: $(grep -hE '^SIP/2.0 [0-9]+' "$work"/call_*_messages.log 2>/dev/null | awk '{print $2}' | tr '\n' ' ')"
# grep >/dev/null, not -q: the full log is long (SIGPIPE)
assert_cmd "the speed dial *1011 goes on to 1003" -- sh -c "docker exec '$c' grep -E 'Executing \\[\\*1011@from-internal:[0-9]+\\] GotoIf\\(\"PJSIP/1002-[^\"]*\", \"1\\?from-internal,1003,1\"\\)' /var/log/asterisk/full >/dev/null"
finish
