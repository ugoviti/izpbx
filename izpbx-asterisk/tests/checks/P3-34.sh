#!/usr/bin/env bash
# P3-34: log rotation in the image (regression: in 22.17 only logrotate.d/httpd
# was copied, while 20.16 copied the whole rootfs). /etc/logrotate.d/asterisk,
# fail2ban, fop2 and httpd are in the image, logrotate parses the whole
# configuration without errors, and a forced rotation rotates the Asterisk
# full log, the fail2ban log and the FOP2 debug log. The daily cron job of
# Debian runs logrotate (no systemd in the container). Control: without
# logrotate.d/asterisk the full log is not rotated.
source "$(dirname "$0")/../lib.sh"

image=izpbx-asterisk:p3-34
t_build_image "$image"
c=$(t_run lr "$image" --entrypoint /bin/sleep -- infinity)
x() { docker exec "$c" bash -c "$1"; }

for f in asterisk fail2ban fop2 httpd; do
  assert_cmd "/etc/logrotate.d/$f in the image" -- x "test -s /etc/logrotate.d/$f"
done
assert_cmd "logrotate parses the configuration without errors" -- x "! logrotate -d /etc/logrotate.conf 2>&1 | grep -q ^error"
assert_cmd "cron.daily runs logrotate (no systemd)" -- x "test -x /etc/cron.daily/logrotate && test ! -d /run/systemd/system && run-parts --test /etc/cron.daily | grep -qx /etc/cron.daily/logrotate"

d=$(date +%Y%m%d)
x "mkdir -p /var/log/asterisk /var/log/fail2ban /var/log/fop && chown asterisk:asterisk /var/log/asterisk &&
   echo full > /var/log/asterisk/full && chown asterisk:asterisk /var/log/asterisk/full &&
   echo f2b > /var/log/fail2ban/fail2ban.log && echo fop > /var/log/fop/fop2_debug.log"
x "logrotate -f /etc/logrotate.conf" >/dev/null 2>&1 || true
assert_cmd "Asterisk full log rotated" -- x "ls /var/log/asterisk/full-$d* >/dev/null 2>&1"
assert_cmd "fail2ban log rotated" -- x "ls /var/log/fail2ban/fail2ban.log-$d* >/dev/null 2>&1"
assert_cmd "FOP2 debug log rotated" -- x "ls /var/log/fop/fop2_debug.log-$d* >/dev/null 2>&1"

# control: no logrotate.d/asterisk, no rotation of the full log
o=$(t_run lr2 "$image" --entrypoint /bin/sleep -- infinity)
docker exec "$o" bash -c "rm /etc/logrotate.d/asterisk && mkdir -p /var/log/asterisk && echo full > /var/log/asterisk/full && logrotate -f /etc/logrotate.conf" >/dev/null 2>&1 || true
assert_cmd_fails "control: without logrotate.d/asterisk the full log is not rotated" -- docker exec "$o" bash -c "ls /var/log/asterisk/full-$d*"

finish
