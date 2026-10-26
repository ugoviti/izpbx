#!/usr/bin/env bash
# P3-35: mailq when msmtp is the MTA (the default). The FreePBX dashboard
# runs mailq and shows "Unknown output from mailq: [["mailq: no recipients
# found"],64]" as a critical error: msmtp called as mailq does not know the
# command. msmtp has no queue (it delivers or refuses while sendmail runs), so
# /usr/bin/mailq answers as Postfix with an empty queue, which the dashboard
# reads as "No outbound mail in queue".
# - default (msmtp): mailq exits 0 with "Mail queue is empty";
# - POSTFIX_ENABLED=true: mailq is Postfix's again, and answers the same with
#   its empty queue;
# - negative: msmtp itself called as mailq gives the error the dashboard showed.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-34
assert_cmd "image builds" -- t_build_image "$image"

start() { # name [docker run args...] -> container with izpbx-init done
  local c
  c=$(t_run "$1" "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=false "${@:2}")
  t_wait_for 120 -- sh -c "docker logs '$c' 2>&1 | grep -q 'izpbx-init: done'" || die "izpbx-init did not finish in $1"
  printf '%s\n' "$c"
}

c=$(start msmtp)
out=$(docker exec "$c" mailq 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "msmtp: mailq exits 0"
assert_eq "Mail queue is empty" "$out" "msmtp: mailq says the queue is empty (the answer the dashboard reads as ok)"
assert_eq /usr/bin/msmtp "$(docker exec "$c" readlink -f /usr/sbin/sendmail)" "msmtp: sendmail is still msmtp"
neg=$(docker exec "$c" sh -c 'cd /tmp && ln -sf /usr/bin/msmtp mailq && ./mailq; echo "rc=$?"' 2>&1)
assert_contains "$neg" "no recipients found" "negative: msmtp called as mailq does not know the command"
assert_contains "$neg" "rc=64" "negative: and exits 64 (the error of the dashboard)"

p=$(start postfix -e POSTFIX_ENABLED=true)
assert_eq /usr/sbin/sendmail.postfix "$(docker exec "$p" readlink -f /usr/sbin/sendmail)" "postfix: sendmail is Postfix's"
t_wait_for 60 -- docker exec "$p" sh -c 'mailq 2>&1 | grep -q "Mail queue is empty"' \
  && pass "postfix: mailq is Postfix's, queue empty" || fail "postfix: mailq is not Postfix's: $(docker exec "$p" mailq 2>&1 | head -3)"
finish
