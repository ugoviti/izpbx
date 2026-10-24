#!/usr/bin/env bash
# P2-06 (design S6): izpbx-service restart|start|stop|status NAME, used by
# cron.daily/freepbx-le-renew and by logrotate, so scripts do not depend on s6.
# - grep -r supervisorctl izpbx-asterisk/rootfs = 0 (control: the same files
#   before P2-06 have it); both scripts call izpbx-service;
# - izpbx-service restart httpd changes the pid of httpd, which is up again;
#   restart asterisk brings a new Asterisk and is not counted as a failure;
#   stop/status/start; an unknown service is refused;
# - logrotate -f /etc/logrotate.d/httpd rotates /var/log/apache2 and restarts
#   httpd through izpbx-service (Debian's logrotate.d/apache2 removed).
source "$(dirname "$0")/../lib.sh"
dir="$REPO_DIR/izpbx-asterisk"
image=izpbx-asterisk:p2-06
before=8fa6d3b

assert_eq 0 "$( { grep -r supervisorctl "$dir/rootfs" || true; } | wc -l)" "no supervisorctl in izpbx-asterisk/rootfs"
old=$(git -C "$REPO_DIR" show "$before:izpbx-asterisk/rootfs/etc/cron.daily/freepbx-le-renew" "$before:izpbx-asterisk/rootfs/etc/logrotate.d/httpd")
assert_ne 0 "$(grep -c supervisorctl <<< "$old" || true)" "control: the files before P2-06 call supervisorctl"
assert_cmd "cron.daily/freepbx-le-renew restarts httpd through izpbx-service" -- grep -q 'izpbx-service restart httpd' "$dir/rootfs/etc/cron.daily/freepbx-le-renew"
assert_cmd "logrotate.d/httpd restarts httpd through izpbx-service" -- grep -q 'izpbx-service restart httpd' "$dir/rootfs/etc/logrotate.d/httpd"

assert_cmd "image builds" -- t_build_image "$image"
c=$(t_run svc "$image")
t_wait_for 90 -- docker exec "$c" asterisk -rx 'core waitfullybooted' || die "Asterisk did not start"
pid() { docker exec "$c" /command/s6-svstat -o pid "/run/service/$1"; }
up() { docker exec "$c" /command/s6-svstat -o up "/run/service/$1"; }

p=$(pid httpd)
assert_cmd "izpbx-service restart httpd" -- docker exec "$c" izpbx-service restart httpd
assert_ne "$p" "$(pid httpd)" "restart httpd changes its pid"
assert_eq "true" "$(up httpd)" "httpd is up after the restart"

a=$(docker exec "$c" pgrep -xo asterisk)
assert_cmd "izpbx-service restart asterisk" -- docker exec "$c" izpbx-service restart asterisk
assert_ne "$a" "$(docker exec "$c" pgrep -xo asterisk)" "restart asterisk: a new Asterisk process"
assert_eq "true" "$(up asterisk)" "asterisk is up after the restart (not left down)"
assert_eq 0 "$(docker logs "$c" 2>&1 | grep -c 'asterisk failed' || true)" "a restart is not counted as an Asterisk failure"

assert_cmd "izpbx-service stop cron" -- docker exec "$c" izpbx-service stop cron
assert_cmd_fails "izpbx-service status cron: down after stop" -- docker exec "$c" izpbx-service status cron
assert_cmd "izpbx-service start cron" -- docker exec "$c" izpbx-service start cron
assert_cmd "izpbx-service status cron: up after start" -- docker exec "$c" izpbx-service status cron
assert_cmd_fails "control: an unknown service is refused" -- docker exec "$c" izpbx-service restart izpbx-nosuch
assert_cmd_fails "control: a name with a path is refused" -- docker exec "$c" izpbx-service restart ../service/httpd

assert_cmd_fails "Debian's logrotate.d/apache2 is removed" -- docker exec "$c" test -e /etc/logrotate.d/apache2
docker exec "$c" sh -c 'echo p2-06 >> /var/log/apache2/access.log'
p=$(pid httpd)
assert_cmd "logrotate -f /etc/logrotate.d/httpd" -- docker exec "$c" logrotate -f /etc/logrotate.d/httpd
assert_cmd "the Apache logs are rotated" -- docker exec "$c" sh -c 'ls /var/log/apache2/access.log-*.gz'
assert_ne "$p" "$(pid httpd)" "logrotate restarts httpd (new pid)"
assert_eq "true" "$(up httpd)" "httpd is up after logrotate"
docker rmi "$image" >/dev/null 2>&1 || true
finish
