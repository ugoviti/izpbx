#!/usr/bin/env bash
# P4-36: the migration of a production PBX (pbx01, 2026-10-27), reproduced on
# the 20.16.22 fixture with what that PBX had:
# - cidlookup removed on the 16 (no row, no table; a removal may also leave
#   some tables): FreePBX 17 installs it by default and its legacy restore,
#   which asks every active module for its data, failed ("no such table:
#   cidlookup"); now the modules the 16 had not enabled and whose tables are
#   not all in its database are left out of the restore (--ignoremodules);
# - setcid enabled on the 16 and not in the image: "fwconsole ma install"
#   exits 0 also when it fails, so it was never downloaded and its data was
#   lost with a warning. Now it is downloaded; when the download fails the
#   migration stops with an error naming it, and the next start (with
#   Internet) resumes and installs it, its data restored;
# - custom dialplan with a predial hook in Macro/MacroExit, SIPAddHeader,
#   MessageSend to sip: and "#include qhd/on-call.conf": converted
#   (izpbx-dialplan-convert, P4-37), the whole qhd/ copied (the restore of
#   FreePBX brings back only the *_custom.conf files);
# - astdb: a PJSIP registrar contact and a default_user out of sync with the
#   database: no difference for the verification M7 (P4-38);
# then: migration completed, healthy, no "izpbx: error" line in the start that
# completes it, restore without errors, the notice of the bind address of the
# fresh install removed, the converted hook and the included context loaded.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-36
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
sqlroot() { docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot -N "$@"; }
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | sqlroot || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" | sqlroot

# --- the FreePBX 16 of pbx01, on the fixture
sqlroot asterisk <<'EOF'
DELETE FROM modules WHERE modulename = 'cidlookup';
DROP TABLE cidlookup;
DROP TABLE cidlookup_incoming;
INSERT INTO modules (modulename, version, enabled) VALUES ('setcid', '16.0.4', 1);
CREATE TABLE setcid (cid_id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, description VARCHAR(50), cid_name VARCHAR(150), cid_num VARCHAR(150), dest VARCHAR(255));
INSERT INTO setcid (description, cid_name, cid_num, dest) VALUES ('fixture setcid', 'Fixture', '0612345', 'app-blackhole,hangup,1');
EOF
v=$(t_volume data)
cat > "$work/prep.sh" <<'EOS'
tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
cat >> /data/etc/asterisk/extensions_custom.conf <<"EOD"
#include qhd/on-call.conf
[messages]
exten => _X.,1,MessageSend(sip:${EXTEN},"${CALLERID(name)}"${MESSAGE(from)})
[macro-masq-overlap-callerid]
exten => s,1,Set(CALLERID(num)=${SITE_ID})
exten => s,n,MacroExit()
[macro-dialout-trunk-predial-hook]
exten => s,1,GotoIf($[${REGEX("^88[2-8][0-9][0-9]$" ${CALLERID(dnid)})} = 1]?dialoutOverlapCallerID,1)
exten => s,n,MacroExit()
exten => dialoutOverlapCallerID,1,Set(ARRAY(SITE_ID,SITE_NAME)=88888,Site / )
exten => dialoutOverlapCallerID,n,Macro(masq-overlap-callerid)
[from-401]
exten => _XXX,1,SIPAddHeader(Alert-Info: citofono)
include => from-internal
EOD
mkdir -p /data/etc/asterisk/qhd
printf '[qhd-test]\nexten => s,1,NoOp(on call)\n same => n,Return()\n' > /data/etc/asterisk/qhd/on-call.conf
printf '; not included\n' > /data/etc/asterisk/qhd/unused.conf
chown -R --reference=/data/etc/asterisk/extensions_custom.conf /data/etc/asterisk/qhd
php /w/astdb.php
EOS
cat > "$work/astdb.php" <<'EOS'
<?php
$d = new PDO("sqlite:/data/var/lib/asterisk/astdb.sqlite3");
$d->prepare("INSERT INTO astdb (key, value) VALUES (?, ?)")->execute(["/registrar/contact/1001;@c0ffee", '{"via_addr":"10.1.0.217"}']);
$d->prepare("DELETE FROM astdb WHERE key = ?")->execute(["/DEVICE/1001/default_user"]);
$d->prepare("INSERT INTO astdb (key, value) VALUES (?, ?)")->execute(["/DEVICE/1001/default_user", "izadmin"]);
EOS
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" -v "$work:/w:ro" "$image" sh -e /w/prep.sh
docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" php -r '$d = new PDO("sqlite:/data/var/lib/asterisk/astdb.sqlite3"); foreach ($d->query("SELECT key, value FROM astdb WHERE key LIKE \"/registrar/%\" OR key = \"/DEVICE/1001/default_user\"") as $r) echo "$r[0]=$r[1]\n";' > "$work/astdb.txt"
assert_eq 2 "$(wc -l < "$work/astdb.txt")" "fixture: registrar contact and default_user izadmin in the astdb of the 16"

env=(-e APP_DATA=/data -e MYSQL_SERVER=db -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true)
ended() { docker logs "$1" 2>&1 | grep -E 'migration: (FreePBX 16 -> .* completed|VERIFICATION FAILED)|MAINTENANCE MODE|rc.init: fatal' >/dev/null; }

# --- first start: the module list of FreePBX 17 readable (a local copy: the
# checks pass) but no download (HTTP and HTTPS rejected): setcid cannot be
# installed. (Without the list the checks block before anything is changed.)
mkdir -p "$work/hooks/pre-init"
printf 'iptables -A OUTPUT -p tcp -m multiport --dports 80,443 -j REJECT\n' > "$work/hooks/pre-init/00-offline.custom-inc"
printf '<xml><module><rawname>setcid</rawname></module></xml>\n' > "$work/all-17.0.xml"
c1=$(t_run offline "$image" --network "$net" --cap-add NET_ADMIN -v "$v:/data" -v "$work:/w:ro" -e APP_CUSTOM_SCRIPTS=/w/hooks \
  -e IZPBX_FREEPBX_MIRROR_LIST=file:///w/all-17.0.xml "${env[@]}")
t_wait_for 2400 -- ended "$c1"
docker logs "$c1" 2>&1 | grep -E 'izpbx: (error|warning)|migration: (installing|module)' | sed 's/^/    | /' | tail -n 12 >&2
assert_contains "$(docker logs "$c1" 2>&1)" "migration: modules of FreePBX 16 not installed: setcid" "offline: the migration stops naming setcid"
assert_cmd_fails "offline: no restore without setcid" -- sh -c "docker logs '$c1' 2>&1 | grep -q 'migration: restoring'"
docker rm -f "$c1" >/dev/null

# --- second start, with Internet: resumes and completes
c=$(t_run pbx "$image" --network "$net" -v "$v:/data" "${env[@]}")
t_wait_for 2400 -- ended "$c"
log=$(docker logs "$c" 2>&1)
grep -E 'migration:|izpbx: (error|warning)' <<< "$log" | sed 's/^/    | /' | tail -n 40 >&2
assert_contains "$log" "migration to FreePBX 17 in progress" "online: the migration resumes"
assert_contains "$log" "module setcid is not in the image, downloading it" "online: setcid downloaded"
assert_contains "$log" "modules not enabled in FreePBX 16 and without their tables in its database, nothing to restore: cidlookup" "cidlookup left out of the restore"
assert_contains "$log" "qhd/ (2 file(s)), included by the custom dialplan of 20.16, copied" "qhd/ copied"
assert_contains "$log" "custom dialplan converted for Asterisk 22: 6 change(s)" "custom dialplan converted"
assert_contains "$log" "migration: verification passed" "verification M7 passed"
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 600
assert_eq "" "$(grep 'izpbx: error' <<< "$log" || true)" "no error in the start that completes the migration"
state=$(docker exec "$c" cat /data/.izpbx-migration/state)
snap=$(sed -n 's/^snapshot_dir=//p' <<< "$state" | tail -n 1)
assert_cmd_fails "restore without errors" -- docker exec "$c" grep -q 'There were errors' "$snap/restore.log"
assert_eq "fixture setcid" "$(sqlroot asterisk -e 'SELECT description FROM setcid')" "setcid data restored"
assert_cmd_fails "no notice of the bind address of the fresh install" -- sh -c "docker exec '$c' fwconsole notifications --list 2>/dev/null | grep -q core_bindaddress_changed"
hook=$(docker exec "$c" asterisk -rx 'dialplan show macro-dialout-trunk-predial-hook')
assert_contains "$hook" "Gosub(macro-masq-overlap-callerid,s,1())" "hook loaded with Gosub"
assert_contains "$hook" "3. Return()" "hook: Return() added at the end of dialoutOverlapCallerID"
assert_contains "$(docker exec "$c" asterisk -rx 'dialplan show from-401')" "Set(__ALERT_INFO=citofono)" "SIPAddHeader converted"
assert_contains "$(docker exec "$c" asterisk -rx 'dialplan show qhd-test')" "NoOp(on call)" "included qhd/on-call.conf loaded"
assert_cmd "qhd/unused.conf copied too" -- docker exec "$c" test -f /etc/asterisk/qhd/unused.conf
assert_contains "$(docker exec "$c" cat /data/.izpbx-migration/report.txt)" "custom dialplan converted for Asterisk 22" "the report names the conversion"
finish
