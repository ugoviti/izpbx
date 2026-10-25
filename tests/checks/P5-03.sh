#!/usr/bin/env bash
# P5-03: fax with spandsp (res_fax_spandsp), SendFax -> ReceiveFax between two
# channels of one Asterisk (tests/fixtures/fax), with a 2-page TIFF
# (tests/fixtures/fax/test-2pages.tif: 1728 px, 204x196 dpi, Group 4):
# - G.711: two Local channels (audio fax);
# - T.38: Asterisk calls itself over PJSIP with UDPTL (endpoint loop);
# - each side: FAXSTATUS=SUCCESS and 2 pages; the received TIFF has 2 pages
#   (tiffinfo); spandsp counts the session as G.711 or T.38 ("fax show stats");
# - tiff2pdf turns the received fax into a PDF (FreePBX fax to email; the
#   libtiff-tools of 20.16, missing before this item);
# - negative check: SendFax of a missing file -> FAILED on both sides.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p5-03
fx="$TESTS_DIR/fixtures/fax"
assert_cmd "image builds" -- t_build_image "$image"
c=$(t_run ast "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true -e HTTPD_ENABLED=false -e FAIL2BAN_ENABLED=false \
  -e CRON_ENABLED=false -v "$fx/extensions.conf:/etc/asterisk/extensions.conf:ro" \
  -v "$fx/pjsip.conf:/etc/asterisk/pjsip.conf:ro" -v "$fx:/fax:ro")
assert_cmd "Asterisk starts" -- t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted'
ast() { docker exec "$c" asterisk -rx "$1"; }
result() { ast "database get faxtest $1" | sed -n 's/^Value: //p'; }
pages() { docker exec "$c" sh -c "tiffinfo $1 2>/dev/null | grep -c '^TIFF Directory'" || true; }
stat() { ast 'fax show stats' | awk -v sec="$1" -v key="$2" '$0 ~ "^Spandsp " sec {s = 1} s && index($0, key) == 1 {print $NF; exit}'; }
fax() { # mode originate-args
  ast "channel originate $2" >/dev/null
  t_wait_for 120 -- sh -c "[ -n \"\$(docker exec $c asterisk -rx 'database get faxtest rx-$1' | sed -n 's/^Value: //p')\" ] &&
                           [ -n \"\$(docker exec $c asterisk -rx 'database get faxtest tx-$1' | sed -n 's/^Value: //p')\" ]" ||
    log "$1: no result after 120 s"
}

assert_eq 2 "$(pages /fax/test-2pages.tif)" "the test TIFF has 2 pages"
fax g711 "Local/s@fax-rx-g711 extension s@fax-tx-g711"
assert_eq "SUCCESS:2" "$(result tx-g711)" "G.711: SendFax SUCCESS, 2 pages"
assert_eq "SUCCESS:2" "$(result rx-g711)" "G.711: ReceiveFax SUCCESS, 2 pages"
assert_eq 2 "$(pages /tmp/rx-g711.tif)" "G.711: the received TIFF has 2 pages"
assert_eq 2 "$(stat G.711 Success)" "G.711: spandsp counts 2 audio sessions"

fax t38 "PJSIP/rx@loop extension s@fax-tx-t38"
assert_eq "SUCCESS:2" "$(result tx-t38)" "T.38: SendFax SUCCESS, 2 pages"
assert_eq "SUCCESS:2" "$(result rx-t38)" "T.38: ReceiveFax SUCCESS, 2 pages"
assert_eq 2 "$(pages /tmp/rx-t38.tif)" "T.38: the received TIFF has 2 pages"
assert_eq 2 "$(stat T.38 Success)" "T.38: spandsp counts 2 T.38 sessions"

assert_cmd "tiff2pdf turns the received fax into a PDF" -- \
  sh -c "docker exec $c sh -c 'tiff2pdf -o /tmp/rx.pdf /tmp/rx-t38.tif && head -c 5 /tmp/rx.pdf' | grep -q '%PDF-'"

fax bad "Local/s@fax-rx-bad extension s@fax-tx-bad"
assert_contains "$(result tx-bad)" "FAILED" "control: a missing file cannot be sent"
assert_cmd_fails "control: and nothing is received" -- sh -c "[ \"\$(docker exec $c asterisk -rx 'database get faxtest rx-bad' | sed -n 's/^Value: //p')\" = SUCCESS:2 ]"
finish
