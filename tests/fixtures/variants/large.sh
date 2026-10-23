# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # sourced by make-fixture.sh: shares its variables
# large (P0-08e): >= 500 extensions, >= 2 million CDR rows, >= 5 GB of recordings.
LARGE_EXTENSIONS=500
LARGE_CDR_ROWS=2000000
LARGE_RECORDINGS=1000          # files of 5 MiB each: 5000 MiB in total
variant_post_populate() {
  log "variant large: $LARGE_EXTENSIONS extensions"
  {
    echo "extension,name,tech,secret,voicemail_enable,voicemail,voicemail_vmpwd,voicemail_email"
    for i in $(seq 1 "$LARGE_EXTENSIONS"); do
      e=$((2000 + i))
      echo "$e,Large $e,pjsip,Fx-large-$e-pw,yes,default,$e,"
    done
  } | docker exec -i "$pbx" sh -c 'cat > /tmp/fixture-large.csv && chown asterisk: /tmp/fixture-large.csv'
  docker exec -u asterisk "$pbx" fwconsole bulkimport --type=extensions /tmp/fixture-large.csv >/dev/null

  log "variant large: $LARGE_CDR_ROWS CDR rows"
  db_sql "$DB_CDR" <<SQL
INSERT INTO cdr (calldate, clid, src, dst, dcontext, channel, dstchannel, lastapp, lastdata,
                 duration, billsec, disposition, amaflags, uniqueid, linkedid, recordingfile, cnum, did)
SELECT FROM_UNIXTIME(1760000000 + seq * 30), CONCAT('"Large" <', 2001 + seq % $LARGE_EXTENSIONS, '>'),
       2001 + seq % $LARGE_EXTENSIONS, CONCAT('06', LPAD(seq % 10000000, 8, '0')), 'from-internal',
       CONCAT('PJSIP/', 2001 + seq % $LARGE_EXTENSIONS, '-', HEX(seq)), CONCAT('PJSIP/prov-pjsip-reg-', HEX(seq)),
       'Dial', 'PJSIP/prov-pjsip-reg', 60, 50, 'ANSWERED', 3, CONCAT('large.', seq), CONCAT('large.', seq),
       '', 2001 + seq % $LARGE_EXTENSIONS, ''
FROM seq_1_to_$LARGE_CDR_ROWS;
SQL

  log "variant large: $LARGE_RECORDINGS recordings of 5 MiB"
  docker exec "$pbx" bash -c '
    set -e
    src=$(mktemp --suffix=.wav)
    sox -n -r 8000 -c 1 -b 16 "$src" synth 1 sine 500
    for i in $(seq 1 '"$LARGE_RECORDINGS"'); do
      d=/var/spool/asterisk/monitor/2026/01/$(printf %02d $(( i % 28 + 1 )))
      mkdir -p "$d"
      f=$(printf "%s/large-%05d.wav" "$d" "$i")
      { cat "$src"; head -c $((5 * 1048576 - $(stat -c %s "$src"))) /dev/zero; } > "$f"
    done
    rm -f "$src"
    chown -R asterisk:asterisk /var/spool/asterisk/monitor'
}
variant_manifest() {
  echo "anomaly=large volume: $LARGE_EXTENSIONS extensions, $LARGE_CDR_ROWS CDR rows, $LARGE_RECORDINGS x 5 MiB recordings"
  echo "large_extensions=$LARGE_EXTENSIONS"
  echo "large_cdr_rows=$LARGE_CDR_ROWS"
  echo "large_recordings_mb=$((LARGE_RECORDINGS * 5))"
}
