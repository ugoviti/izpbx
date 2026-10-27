#!/usr/bin/env bash
# P4-12: voicemail and recordings after the migration (M6): the 20.16.22
# fixture migrated in a real start. The mailboxes come back with
# voicemail.conf in the legacy archive (restored by the voicemail module),
# the messages and recordings stay in var/spool/asterisk.
# - messages per mailbox and folder (izpbx-inventory voicemail_messages), the
#   mailboxes (voicemail_boxes) and the number of recordings as before;
# - the spool files belong to asterisk:asterisk;
# - a message plays from UCP: a UCP user with mailbox 1001 lists the INBOX
#   (ajax voicemail grid) and downloads the first message: HTTP 200, the
#   size of the file;
# - control: a mailbox not assigned to the UCP user is forbidden (403).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-12
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
recs_before=$(docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" sh -c 'find /data/var/spool/asterisk/monitor -type f | wc -l')
vm() { jq -S '{voicemail_messages: .categories.voicemail_messages, voicemail_boxes: .categories.voicemail_boxes}' "$1"; }
log "before: $(vm "$work/before.json" | jq -c .), $recs_before recording(s)"

c=$(t_run pbx "$image" --network "$net" -v "$v:/data" "${env[@]}" -e IZPBX_MIGRATE_FREEPBX=true)
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 2400
log "$(docker logs "$c" 2>&1 | grep 'migration: spool in place')"
docker exec "$c" izpbx-inventory --live > "$work/after.json"
assert_eq "$(vm "$work/before.json")" "$(vm "$work/after.json")" "voicemail messages per mailbox and folder, and the mailboxes, as before"
assert_eq "$recs_before" "$(docker exec "$c" sh -c 'find /var/spool/asterisk/monitor -type f | wc -l')" "recordings: same count ($recs_before)"
assert_eq "" "$(docker exec "$c" find /var/spool/asterisk/voicemail /var/spool/asterisk/monitor \( ! -user asterisk -o ! -group asterisk \) -print)" \
  "spool files owned by asterisk:asterisk"

# --- a message from UCP
docker exec -u asterisk "$c" php -r '
  include "/etc/freepbx.conf";
  $u = FreePBX::Userman();
  $r = $u->addUser("vmuser", "VmPass1x", "1001", "P4-12");
  $u->setModuleSettingByID($r["id"], "ucp|Global", "allowLogin", true);
  $u->setModuleSettingByID($r["id"], "ucp|Voicemail", "enable", true);
  $u->setModuleSettingByID($r["id"], "ucp|Voicemail", "assigned", ["1001"]);
' >/dev/null 2>&1
pbxsh() { docker exec "$c" sh -c "$1"; }
login=$(pbxsh 'tok=$(curl -s -c /tmp/uj -b /tmp/uj http://localhost/ucp/ | grep -oE "name=\"token\" value=\"[^\"]*\"" | sed "s/.*value=\"//; s/\"$//")
  curl -s -c /tmp/uj -b /tmp/uj -d "username=vmuser&password=VmPass1x&token=$tok&module=User&command=login" \
    -H "X-Requested-With: XMLHttpRequest" -H "Referer: http://localhost/ucp/" "http://localhost/ucp/ajax.php?module=User&command=login"')
assert_eq "true" "$(jq -r .status <<< "$login" 2>/dev/null)" "UCP login of a user with mailbox 1001"
grid=$(pbxsh 'curl -s -b /tmp/uj -H "X-Requested-With: XMLHttpRequest" -H "Referer: http://localhost/ucp/" \
  "http://localhost/ucp/ajax.php?module=voicemail&command=grid&folder=INBOX&ext=1001&limit=10&offset=0&order=desc"')
msgid=$(jq -r '.rows[0].msg_id // empty' <<< "$grid" 2>/dev/null)
log "UCP INBOX of 1001: $(jq -c '{total, ids: [.rows[].msg_id]}' <<< "$grid" 2>/dev/null || head -c 300 <<< "$grid")"
assert_ne "" "$msgid" "UCP lists the INBOX messages of 1001"
out=$(pbxsh "curl -s -b /tmp/uj -o /tmp/msg.wav -w '%{http_code} %{size_download}' 'http://localhost/ucp/index.php?quietmode=1&module=voicemail&command=download&msgid=$msgid&ext=1001'")
log "download: $out"
assert_eq 200 "${out% *}" "UCP plays the message: HTTP 200 on the audio file"
assert_ne 0 "${out#* }" "the audio file is not empty"
out=$(pbxsh "curl -s -b /tmp/uj -o /dev/null -w '%{http_code}' 'http://localhost/ucp/index.php?quietmode=1&module=voicemail&command=download&msgid=$msgid&ext=1002'")
assert_eq 403 "$out" "control: a mailbox not assigned to the user is forbidden"
finish
