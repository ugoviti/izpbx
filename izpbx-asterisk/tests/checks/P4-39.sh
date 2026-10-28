#!/usr/bin/env bash
# P4-39: values of FreePBX 16 damaged by the legacy restore of FreePBX 17
# (pbx01, 2026-10-28: "error 500" opening a calendar). The restore loads the
# dump of the 16 into SQLite without undoing its escapes: CR, quotes,
# apostrophes and backslashes come back as "\r", \", \', \\.
# izpbx-migrate repair-escapes (migration_repair_escapes, also run by the
# migration after the restore) on a database damaged as on pbx01:
# - --check: lists the columns to repair, writes nothing;
# - --apply: the calendar event (CR at the end of the lines, \"MO,TU\"), the
#   outbound route email (\r), the voicemail email body (\\n), the paging
#   header (\\;) and a description with an apostrophe get back the value of
#   FreePBX 16; the tables are saved first in the snapshot;
# - left alone: a backslash FreePBX 16 already had, a value changed after the
#   migration (with escapes undone it is no value of FreePBX 16), a table
#   only FreePBX 17 has; the dump goes to its own database, which is dropped
#   (the config database gets none of its rows); a second run changes nothing.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-39
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
sql() { docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot -N --raw "$@"; }

# FreePBX 16: the original values (PHP writes them, so CR and quotes are real)
schema="CREATE TABLE kvstore_FreePBX_modules_Calendar (\`key\` char(255), val longblob, type char(16), id char(255));
CREATE TABLE outbound_route_email (route_id int, emailfrom varchar(255), emailbody text);
CREATE TABLE kvstore_FreePBX_modules_Voicemail (\`key\` char(255), val varchar(4096), type char(16), id char(255));
CREATE TABLE paging_autoanswer (useragent varchar(255), var varchar(20), setting varchar(255));
CREATE TABLE users (extension varchar(20), name varchar(50));"
printf '%s\n' "CREATE DATABASE asterisk16; USE asterisk16; $schema CREATE TABLE only16 (v varchar(10)); INSERT INTO only16 VALUES ('x');" \
  "CREATE DATABASE asterisk; USE asterisk; $schema CREATE TABLE only17 (v varchar(50)); INSERT INTO only17 VALUES ('a\\\\rb');" | sql
cat > "$work/values.php" <<'EOF'
<?php
// [table, column, FreePBX 16, FreePBX 17 after the restore]
$ical = "BEGIN:VEVENT\r\nDTSTART;TZID=Europe/Rome:20230801T083000\r\nRRULE:FREQ=WEEKLY;BYDAY=\"MO,TU\"\r\nEND:VEVENT";
return [
  ['kvstore_FreePBX_modules_Calendar', 'val', $ical, str_replace(["\r", '"'], ['\r', '\"'], $ical)],
  ['outbound_route_email', 'emailbody', "Call Details:\r\nCaller: {{CALLERALL}}", 'Call Details:\r' . "\n" . 'Caller: {{CALLERALL}}'],
  ['kvstore_FreePBX_modules_Voicemail', 'val', '${VM_NAME},\n\nThere is a new voicemail', '${VM_NAME},\\\\n\\\\nThere is a new voicemail'],
  ['paging_autoanswer', 'setting', '<uri>\;answer-after=0', '<uri>\\\\;answer-after=0'],
  ['users', 'name', "Sant'Anna", "Sant\\'Anna"],
  // a backslash FreePBX 16 already had: the same in both
  ['paging_autoanswer', 'setting', '<sip:x>\;info=alert', '<sip:x>\;info=alert'],
  // changed after the migration: no value of FreePBX 16 with escapes undone
  ['users', 'name', 'Old name', 'New \"name\"'],
];
EOF
docker run --rm --network "$net" --entrypoint "" -v "$work:/w:ro" "$image" php -r '
  $db = new PDO("mysql:host=db", "root", "rootpw", [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
  foreach (require "/w/values.php" as [$t, $c, $v16, $v17]) {
    $db->prepare("INSERT INTO asterisk16.$t ($c) VALUES (?)")->execute([$v16]);
    $db->prepare("INSERT INTO asterisk.$t ($c) VALUES (?)")->execute([$v17]);
  }' || die "cannot write the values"
# the snapshot of the migration (M4): dump with CREATE DATABASE / USE of the database dumped
docker exec -e MYSQL_PWD=rootpw "$db" mariadb-dump -uroot --databases asterisk16 | sed 's/`asterisk16`/`asterisk`/g' | gzip > "$work/asterisk.sql.gz"
assert_cmd "the dump of the 16 has CREATE DATABASE and USE of the config database" -- sh -c "gzip -dc '$work/asterisk.sql.gz' | grep -q '^USE \`asterisk\`'"
sql -e "DROP DATABASE asterisk16"
v=$(t_volume data)
docker run --rm --entrypoint "" -v "$v:/data" -v "$work:/w:ro" "$image" sh -c '
  mkdir -p /data/.izpbx-migration/20261027T182551Z/db && cp /w/asterisk.sql.gz /data/.izpbx-migration/20261027T182551Z/db/
  printf "snapshot_dir=/data/.izpbx-migration/20261027T182551Z\nmigration=done\n" > /data/.izpbx-migration/state'

state() { # table column -> the values, hex, sorted
  sql -e "SELECT HEX($2) FROM asterisk.$1 ORDER BY 1"
}
before=$(for t in "kvstore_FreePBX_modules_Calendar val" "outbound_route_email emailbody" "kvstore_FreePBX_modules_Voicemail val" "paging_autoanswer setting" "users name" "only17 v"; do state $t; done)
mig() { docker run --rm --network "$net" --entrypoint "" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_ROOT_PASSWORD=rootpw -e MYSQL_PASSWORD=x -e IZPBX_LOG_COLOR=false "$image" izpbx-migrate repair-escapes "$@" 2>&1; }

out=$(mig --check); log "$out"
assert_contains "$out" "FIX kvstore_FreePBX_modules_Calendar.val: 1 row(s)" "check: the calendar event listed"
assert_contains "$out" "FIX users.name: 1 row(s)" "check: the apostrophe listed"
after=$(for t in "kvstore_FreePBX_modules_Calendar val" "outbound_route_email emailbody" "kvstore_FreePBX_modules_Voicemail val" "paging_autoanswer setting" "users name" "only17 v"; do state $t; done)
assert_eq "$before" "$after" "check: nothing written"

out=$(mig --apply); log "$out"
assert_contains "$out" "put back" "apply: the repair is logged"
docker run --rm --network "$net" --entrypoint "" -v "$work:/w:ro" "$image" php -r '
  $db = new PDO("mysql:host=db", "root", "rootpw", [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
  foreach (require "/w/values.php" as $i => [$t, $c, $v16, $v17]) {
    $n = $db->prepare("SELECT COUNT(*) FROM asterisk.$t WHERE $c = BINARY ?");
    $n->execute([$i == 6 ? $v17 : $v16]);
    printf("%d %s.%s %s\n", $n->fetchColumn(), $t, $c, $i == 6 ? "changed after the migration, kept" : "as in FreePBX 16");
  }' > "$work/check.txt"
while read -r n what; do assert_eq 1 "$n" "apply: $what"; done < "$work/check.txt"
assert_eq "1" "$(sql -e "SELECT COUNT(*) FROM asterisk.only17 WHERE v = 'a\\\\rb'")" "a table only FreePBX 17 has: untouched"
assert_eq "" "$(sql -e "SHOW TABLES FROM asterisk LIKE 'only16'")" "the config database got nothing of the dump"
assert_eq "" "$(sql -e "SHOW DATABASES LIKE 'izpbx_fpbx16_repair'")" "the repair database is dropped"
assert_cmd "the tables saved before the repair" -- docker run --rm --entrypoint "" -v "$v:/data" "$image" sh -c \
  'zcat /data/.izpbx-migration/20261027T182551Z/repair-escapes-*.sql.gz | grep -q "INSERT INTO \`users\`"'
out=$(mig --apply); log "$out"
assert_contains "$out" "no value damaged by the restore" "a second run changes nothing"
finish
