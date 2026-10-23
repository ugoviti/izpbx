#!/bin/bash
# Populate an izPBX 20.16.x install with the T5 fixture content.
# Runs inside the izPBX container as root, from the directory holding
# populate.php and extensions.csv (copied there by make-fixture.sh).
# DB access uses the container's MYSQL_USER/MYSQL_PASSWORD (works without root).
set -Eeuo pipefail
trap 'echo "populate.sh: error at line $LINENO: $BASH_COMMAND" >&2' ERR

here=$(cd "$(dirname "$0")" && pwd)
: "${RINGGROUPS_TAG:=16.0.11}"
: "${MYSQL_SERVER:=db}"
: "${MYSQL_USER:=asterisk}"
: "${MYSQL_PASSWORD:?}"
: "${MYSQL_DATABASE_CDR:=asteriskcdrdb}"
: "${APP_PORT_MYSQL:=3306}"

step() { echo "populate.sh: $*" >&2; }
as_ast() { su - asterisk -s /bin/bash -c "$*"; }
sql_cdr() { MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_SERVER" -P "$APP_PORT_MYSQL" -u "$MYSQL_USER" "$MYSQL_DATABASE_CDR" -e "$1"; }

step "ring groups module ($RINGGROUPS_TAG, not in the image local repo)"
as_ast "fwconsole ma downloadinstall ringgroups --tag=$RINGGROUPS_TAG" >/dev/null

step "enable chan_sip next to chan_pjsip"
as_ast "fwconsole setting ASTSIPDRIVER both" >/dev/null

step "extensions (1001 chan_sip, 1002/1003 pjsip) with voicemail"
cp "$here/extensions.csv" /tmp/fixture-extensions.csv
chown asterisk: /tmp/fixture-extensions.csv
as_ast "fwconsole bulkimport --type=extensions /tmp/fixture-extensions.csv" >/dev/null

step "database objects (populate.php)"
as_ast "php $here/populate.php"

step "reload"
as_ast "fwconsole reload" >/dev/null
asterisk -rx "module load chan_sip.so" >/dev/null

# --- audio files: 8 kHz mono WAV made with sox
tone() { # file seconds freq
  mkdir -p "$(dirname "$1")"
  sox -n -r 8000 -c 1 -b 16 "$1" synth "$2" sine "$3"
}

step "custom prompt and music on hold"
tone /var/lib/asterisk/sounds/custom/fixture-welcome.wav 2 440
tone /var/lib/asterisk/moh/fixture-moh/fixture-moh-1.wav 5 330
tone /var/lib/asterisk/moh/fixture-moh/fixture-moh-2.wav 5 550

step "voicemail messages"
vm_msg() { # mailbox folder n caller epoch
  local dir=/var/spool/asterisk/voicemail/default/$1/$2 f
  f=$(printf '%s/msg%04d' "$dir" "$3")
  tone "$f.wav" 3 600
  cat > "$f.txt" <<EOF
;
; Message Information file
;
[message]
origmailbox=$1
context=macro-vm
macrocontext=ext-local
exten=s
rdnis=unknown
priority=2
callerchan=PJSIP/$4-00000001
callerid="Fixture caller" <$4>
origdate=$(LC_ALL=C date -d "@$5" +'%a %b %d %r %Z %Y')
origtime=$5
category=
msg_id=$5-0000000$3
flag=
duration=3
EOF
}
vm_msg 1001 INBOX 0 1002 1792652400
vm_msg 1001 INBOX 1 1003 1792656000
vm_msg 1002 Old   0 1001 1792659600

step "call recordings with their CDR rows"
for i in 1 2 3; do
  ts=$((1792652400 + i * 600))
  day=$(date -d "@$ts" +%Y/%m/%d)
  uid="$ts.$i"
  name="out-0612345678-1001-$(date -d "@$ts" +%Y%m%d-%H%M%S)-$uid.wav"
  tone "/var/spool/asterisk/monitor/$day/$name" 4 700
  sql_cdr "INSERT INTO cdr (calldate, clid, src, dst, dcontext, channel, dstchannel, lastapp, lastdata, duration, billsec, disposition, amaflags, uniqueid, linkedid, recordingfile, cnum, did)
           VALUES (FROM_UNIXTIME($ts), '\"Fixture SIP One\" <1001>', '1001', '0612345678', 'from-internal', 'SIP/1001-0000000$i', 'PJSIP/prov-pjsip-reg-0000000$i', 'Dial', 'PJSIP/0612345678@prov-pjsip-reg', 10, 8, 'ANSWERED', 3, '$uid', '$uid', '$name', '1001', '')"
done

step "call forward and do-not-disturb in astdb"
asterisk -rx "database put CF 1001 3331234567" >/dev/null
asterisk -rx "database put CFB 1003 1002" >/dev/null
asterisk -rx "database put CFU 1003 1002" >/dev/null
asterisk -rx "database put DND 1002 YES" >/dev/null

step "chan_dongle configuration"
cat > /etc/asterisk/dongle.conf <<'EOF'
; chan_dongle configuration (fixture)
[general]
interval=15

[defaults]
context=from-trunk
group=0
rxgain=0
txgain=0
autodeletesms=yes
resetdongle=yes
u2diag=-1
usecallingpres=yes
callingpres=allowed_passed_screen
disablesms=no
language=it
smsaspdu=yes
mindtmfgap=45
mindtmfduration=80
mindtmfinterval=200
callwaiting=auto
disable=no
initstate=start
exten=+390612345680
dtmf=relax

[dongle0]
imei=356789012345678
audio=/dev/ttyUSB1
data=/dev/ttyUSB2
EOF

step "ownership"
chown -R asterisk:asterisk /var/lib/asterisk/sounds/custom /var/lib/asterisk/moh/fixture-moh \
  /var/spool/asterisk/voicemail /var/spool/asterisk/monitor /etc/asterisk/dongle.conf

step "done"
