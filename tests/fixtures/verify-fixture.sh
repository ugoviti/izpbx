#!/usr/bin/env bash
# Check that a fixture made by make-fixture.sh holds every T5 element.
#
#   tests/fixtures/verify-fixture.sh FIXTURE_DIR
#
# Loads the dumps into a throwaway MariaDB, unpacks data.tar.gz, prints one
# count per category and exits 1 if any count is 0.

TEST_ID=verify-fixture
dir=$(cd "${1:?usage: $0 FIXTURE_DIR}" && pwd)
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

for f in asterisk.sql.gz asteriskcdrdb.sql.gz data.tar.gz manifest.txt; do
  [ -s "$dir/$f" ] || die "missing $dir/$f"
done

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
tar -C "$work" -xzf "$dir/data.tar.gz" 2>/dev/null || die "cannot unpack data.tar.gz"
d="$work"

db=$(t_run db docker.io/mariadb:10.11.19 -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
for f in asterisk asteriskcdrdb; do
  gzip -dc "$dir/$f.sql.gz" | docker exec -i "$db" mariadb -uroot || die "cannot load $f dump"
done

q() { # a failed query counts 0 (the check fails) and its error is shown
  local r
  if r=$(docker exec "$db" mariadb -uroot -N -B -e "$1" 2>&1); then printf '%s\n' "$r"
  else log "query failed: $1: $r"; echo 0; fi
}
files() { find "$d/$1" -type f ${2:+-name "$2"} 2>/dev/null | wc -l; }
astdb() { python3 -I -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT count(*) FROM astdb WHERE key LIKE ?", (sys.argv[2],)).fetchone()[0])' \
  "$d/var/lib/asterisk/astdb.sqlite3" "$1" 2>/dev/null || echo 0; }

check() { # category count
  printf '%-34s %s\n' "$1" "$2"
  if [ "${2:-0}" -gt 0 ] 2>/dev/null; then pass "$1"; else fail "$1 is empty"; fi
}

# real database names (the dump files keep their role names)
A=$(sed -n 's/^db_config=//p' "$dir/manifest.txt"); A=${A:-asterisk}
C=$(sed -n 's/^db_cdr=//p' "$dir/manifest.txt"); C=${C:-asteriskcdrdb}
check "extension chan_sip"            "$(q "SELECT count(*) FROM $A.devices WHERE tech='sip'")"
check "extension pjsip"               "$(q "SELECT count(*) FROM $A.devices WHERE tech='pjsip'")"
check "trunk chan_sip ip auth"        "$(q "SELECT count(*) FROM $A.trunks t JOIN $A.sip s ON s.id=CONCAT('tr-peer-',t.trunkid) AND s.keyword='insecure' WHERE t.tech='sip'")"
check "chan_sip on port 5160"         "$(grep -c '^udpbindaddr=.*:5160$' "$d/etc/asterisk/sip_general_additional.conf" 2>/dev/null)"
check "trunk pjsip registration"      "$(q "SELECT count(*) FROM $A.trunks t JOIN $A.pjsip p ON p.id=t.trunkid AND p.keyword='registration' AND p.data='send' WHERE t.tech='pjsip'")"
check "outbound route"                "$(q "SELECT count(*) FROM $A.outbound_route_trunks")"
check "inbound route"                 "$(q "SELECT count(*) FROM $A.incoming")"
check "ivr"                           "$(q "SELECT count(*) FROM $A.ivr_details d JOIN $A.ivr_entries e ON e.ivr_id=d.id")"
check "queue with members"            "$(q "SELECT count(*) FROM $A.queues_details WHERE keyword='member'")"
check "ring group"                    "$(q "SELECT count(*) FROM $A.ringgroups")"
check "time condition"                "$(q "SELECT count(*) FROM $A.timeconditions c JOIN $A.timegroups_details g ON g.timegroupid=c.time")"
check "voicemail box"                 "$(q "SELECT count(*) FROM $A.users WHERE voicemail='default'")"
check "voicemail messages"            "$(files var/spool/asterisk/voicemail/default 'msg*.txt')"
check "call recordings"               "$(files var/spool/asterisk/monitor '*.wav')"
check "call recordings in cdr"        "$(q "SELECT count(*) FROM $C.cdr WHERE recordingfile<>''")"
check "astdb call forward"            "$(astdb '/CF%')"
check "astdb do not disturb"          "$(astdb '/DND/%')"
check "custom prompt"                 "$(q "SELECT count(*) FROM $A.recordings")"
check "custom prompt file"            "$(files var/lib/asterisk/sounds/custom)"
# a row in the music table, or only the directory with older music modules (20.16.0)
check "music on hold category"        "$(( $(q "SELECT count(*) FROM $A.music WHERE category<>'default'") + $(test -d "$d/var/lib/asterisk/moh/fixture-moh" && echo 1 || echo 0) ))"
check "music on hold files"           "$(files var/lib/asterisk/moh/fixture-moh)"
check "fax detection"                 "$(q "SELECT count(*) FROM $A.fax_incoming WHERE detection<>''")"
check "fax users"                     "$(q "SELECT count(*) FROM $A.fax_users WHERE faxenabled='true'")"
check "userman users"                 "$(q "SELECT count(*) FROM $A.userman_users")"
check "dongle.conf"                   "$(grep -c '^\[dongle' "$d/etc/asterisk/dongle.conf" 2>/dev/null)"
check "fop2.cfg"                      "$(grep -c '^manager_host' "$d/usr/local/fop2/fop2.cfg" 2>/dev/null)"

finish
