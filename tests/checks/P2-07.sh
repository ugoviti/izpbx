#!/usr/bin/env bash
# P2-07 (T18): orderly stop within the docker stop timeout.
# - docker stop (with asterisk, httpd, php-fpm, cron, fail2ban, postfix,
#   dnsmasq, ntp, zabbix running) ends within 30 s with exit 0; the logs show
#   Asterisk stopping cleanly and every service stopped, no "unable to stop";
# - no orphan processes: after "s6-rc -da change" (the service stop of
#   docker stop) only the s6 tree is left running.
# Negative: a process left behind on purpose is reported as an orphan.
# FreePBX (fwconsole stop, pm2/UCP) is not in the image yet: checked by the
# FreePBX items (variant "direct" of P0-15: Asterisk stops on SIGTERM).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p2-07
on=(-e POSTFIX_ENABLED=true -e DNSMASQ_ENABLED=true -e NTP_ENABLED=true -e ZABBIX_ENABLED=true)
services="asterisk php-fpm httpd cron fail2ban postfix dnsmasq ntp zabbix"
assert_cmd "image builds" -- docker build -q -t "$image" "$REPO_DIR/izpbx-asterisk"

ready() { # every listed service up and Asterisk fully booted
  local s
  for s in $services; do
    [ "$(docker exec "$1" /command/s6-svstat -o up "/run/service/$s" 2>/dev/null)" == true ] || return 1
  done
  docker exec "$1" asterisk -rx 'core waitfullybooted' >/dev/null 2>&1
}
# processes outside the s6 tree (s6-svscan, s6-supervise, s6 tools) and the
# probe itself: anything else left after the services stopped is an orphan
orphans() {
  docker exec "$1" sh -c 'ps -eo pid=,comm=,args=' | awk '
    $2 ~ /^(s6-|s6rc-)/ || $3 ~ /^\/package\/admin\/s6/ || $3 ~ /^\/command\// { next }
    $2 == "ps" || $2 == "sh" || $2 == "awk" { next }
    { print $2 }' | sort -u | tr '\n' ' '
}

# --- docker stop
c=$(t_run stop "$image" "${on[@]}")
t_wait_for 120 -- ready "$c" || die "services did not start"
t0=$SECONDS; docker stop -t 30 "$c" >/dev/null; dt=$((SECONDS - t0))
assert_cmd "docker stop ends within 30 s ($dt s)" -- test "$dt" -le 30
assert_eq 0 "$(docker inspect -f '{{.State.ExitCode}}' "$c")" "docker stop: exit 0"
logs=$(docker logs "$c" 2>&1)
assert_contains "$logs" "Asterisk cleanly ending (0)" "the logs show Asterisk stopping cleanly"
for s in $services; do
  assert_contains "$logs" "service $s successfully stopped" "the logs show $s stopped"
done
assert_eq 0 "$(grep -c 'unable to stop' <<< "$logs" || true)" "no service failed to stop"

# --- no orphans after the services stop
o=$(t_run orphans "$image" "${on[@]}")
t_wait_for 120 -- ready "$o" || die "services did not start"
assert_cmd "every service stops (s6-rc -da change)" -- docker exec "$o" /command/s6-rc -da change
left=$(orphans "$o")
log "left after the stop: [${left}]"
assert_eq "" "$left" "no process left outside the s6 tree"
docker exec -d "$o" sh -c 'sleep 1000 & exit 0'
t_wait_for 10 -- sh -c "docker exec $o pgrep -x sleep >/dev/null"
assert_contains "$(orphans "$o")" "sleep" "control: a process left behind is reported"
docker rmi "$image" >/dev/null 2>&1 || true
finish
