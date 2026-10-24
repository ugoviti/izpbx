#!/usr/bin/env bash
# P3-17: cron with the Debian spool (services/cron.sh).
# - "crontab -" as asterisk writes /var/spool/cron/crontabs/asterisk,
#   0600 asterisk:crontab, the spool root:crontab 1730;
# - a job of asterisk runs within 2 minutes (as asterisk);
# - spool and crontab with wrong owner/mode (as 20.16 left them, or an old
#   volume) are fixed at the next start and the job runs again;
# - negative check: a crontab with the wrong owner is not run by cron.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-17
assert_cmd "image builds" -- docker build -q -t "$image" "$REPO_DIR/izpbx-asterisk"

c=$(t_run run "$image" -e CRON_ENABLED=true -e HTTPD_ENABLED=false -e ASTERISK_ENABLED=false \
  -e IZPBX_ENABLED=false -e FAIL2BAN_ENABLED=false -e POSTFIX_ENABLED=false)
assert_cmd "cron runs" -- t_wait_for 60 -- docker exec "$c" pgrep -x cron
docker exec -u asterisk "$c" bash -c 'echo "* * * * * id -un >> /tmp/cron-ok" | crontab -'
assert_eq "$(docker exec "$c" stat -c '%U %G %a' /var/spool/cron/crontabs/asterisk)" "asterisk crontab 600" \
  "crontab of asterisk 600 asterisk:crontab"
assert_eq "$(docker exec "$c" stat -L -c '%U %G %a' /var/spool/cron/crontabs)" "root crontab 1730" \
  "spool root:crontab 1730"
assert_cmd "the job of asterisk runs within 2 minutes" -- t_wait_for 130 -- docker exec "$c" test -s /tmp/cron-ok
assert_eq "$(docker exec "$c" head -1 /tmp/cron-ok)" "asterisk" "the job runs as asterisk"

# wrong owner and modes: cron ignores the crontab (negative check)
docker exec "$c" bash -c 'chown root:root /var/spool/cron/crontabs /var/spool/cron/crontabs/asterisk
  chmod 0700 /var/spool/cron/crontabs; chmod 0644 /var/spool/cron/crontabs/asterisk
  touch /var/spool/cron/crontabs; rm -f /tmp/cron-ok; echo "* * * * * id -un >> /tmp/cron-ok" > /tmp/ct
  cat /tmp/ct > /var/spool/cron/crontabs/asterisk'
sleep 125
assert_cmd_fails "control: a crontab with the wrong owner is not run" -- docker exec "$c" test -s /tmp/cron-ok

# the next start fixes them
docker restart "$c" >/dev/null
assert_cmd "cron runs after the restart" -- t_wait_for 60 -- docker exec "$c" pgrep -x cron
assert_eq "$(docker exec "$c" stat -c '%U %G %a' /var/spool/cron/crontabs/asterisk)" "asterisk crontab 600" \
  "after a restart: crontab fixed to 600 asterisk:crontab"
assert_eq "$(docker exec "$c" stat -L -c '%U %G %a' /var/spool/cron/crontabs)" "root crontab 1730" \
  "after a restart: spool fixed to root:crontab 1730"
assert_cmd "after a restart: the job runs within 2 minutes" -- t_wait_for 130 -- docker exec "$c" test -s /tmp/cron-ok
finish
