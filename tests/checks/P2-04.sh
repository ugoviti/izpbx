#!/usr/bin/env bash
# P2-04: services enabled and disabled by *_ENABLED (design S3, S12) with the
# 20.16 rules (Postfix replaces msmtp; DHCP/TFTP enable dnsmasq). Matrix T19:
# - every *_ENABLED=false: no service runs;
# - each service enabled alone (a new container = the next restart with the
#   new setting): it runs, the others do not (httpd brings php-fpm, which
#   serves it); fop2 is covered by P2-03 (it needs FOP2 installed);
# - POSTFIX_ENABLED + MSMTP_ENABLED: only Postfix, /usr/sbin/sendmail is
#   Postfix's; MSMTP_ENABLED alone: sendmail is msmtp;
# - DHCP_ENABLED or TFTP_ENABLED alone start dnsmasq;
# - every s6 service is in SERVICE_VARS (service.sh).
# Negative: a service missing from SERVICE_VARS is reported and stays down.
# FreePBX 17 is seen as installed (t_freepbx17 in lib.sh): with
# IZPBX_ENABLED=true and an empty /data izpbx-init would install it (P3-19).
source "$(dirname "$0")/../lib.sh"
t_freepbx17
dir="$REPO_DIR/izpbx-asterisk"
rc_dir="$dir/rootfs/etc/s6-overlay/s6-rc.d"
image=izpbx-asterisk:p2-04
services="asterisk php-fpm httpd cron fail2ban postfix dnsmasq ntp zabbix fop2"
declare -A proc=([asterisk]=asterisk [php-fpm]=php-fpm8.2 [httpd]=apache2 [cron]=cron [fail2ban]=fail2ban-server
  [postfix]=master [dnsmasq]=dnsmasq [ntp]=chronyd [zabbix]=zabbix_agent2 [fop2]=fop2_server)
off=("${T_FREEPBX17[@]}" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=false -e HTTPD_ENABLED=false -e CRON_ENABLED=false -e FAIL2BAN_ENABLED=false
  -e POSTFIX_ENABLED=false -e MSMTP_ENABLED=false -e DNSMASQ_ENABLED=false -e DHCP_ENABLED=false -e TFTP_ENABLED=false
  -e NTP_ENABLED=false -e ZABBIX_ENABLED=false -e FOP2_ENABLED=false)
declare -A var=([asterisk]=IZPBX_ENABLED [httpd]=HTTPD_ENABLED [cron]=CRON_ENABLED [fail2ban]=FAIL2BAN_ENABLED
  [postfix]=POSTFIX_ENABLED [dnsmasq]=DNSMASQ_ENABLED [ntp]=NTP_ENABLED [zabbix]=ZABBIX_ENABLED)

# --- static: every s6 longrun has its variables in SERVICE_VARS
table=$(sed -n '/^declare -A SERVICE_VARS=(/,/^)/p' "$dir/rootfs/usr/local/lib/izpbx/service.sh")
for d in "$rc_dir"/*/; do
  s=$(basename "$d"); [ "$(cat "$d/type" 2>/dev/null)" == longrun ] || continue
  assert_contains "$table" "[$s]=" "service $s is in SERVICE_VARS"
done

assert_cmd "image builds" -- t_build_image "$image"
up() { docker exec "$1" /command/s6-svstat -o up "/run/service/$2" 2>/dev/null; }
running() { docker exec "$1" pgrep -x "$2" >/dev/null; }
settled() { # container: izpbx-init done and every enabled service up
  # grep reads the whole log (no -q): with a long log (zabbix_agent2 logs to
  # the console) an early exit of grep breaks docker logs and the pipeline
  docker logs "$1" 2>&1 | grep 'service izpbx-init successfully started' >/dev/null && sleep 5
}
states() { local s; for s in $services; do printf '%s=%s ' "$s" "$(up "$1" "$s")"; done; }

# --- every service disabled
c=$(t_run alloff "$image" "${off[@]}")
t_wait_for 60 -- settled "$c"
log "all false: $(states "$c")"
for s in $services; do
  assert_eq "false" "$(up "$c" "$s")" "all false: $s is down"
  assert_cmd_fails "all false: no ${proc[$s]}" -- running "$c" "${proc[$s]}"
done

# --- each service alone
for s in asterisk httpd cron fail2ban postfix dnsmasq ntp zabbix; do
  c=$(t_run "only-$s" "$image" "${off[@]}" -e "${var[$s]}=true")
  t_wait_for 60 -- settled "$c"
  expect="$s"; [ "$s" == httpd ] && expect="httpd php-fpm"
  got=$( { for x in $services; do [ "$(up "$c" "$x")" == true ] && echo "$x"; done; true; } | sort | tr '\n' ' ')
  assert_eq "$(tr ' ' '\n' <<< "$expect" | sort | tr '\n' ' ')" "$got" "${var[$s]}=true alone: running services"
  assert_cmd "${var[$s]}=true alone: ${proc[$s]} runs" -- running "$c" "${proc[$s]}"
  docker rm -f "$c" >/dev/null
done

# --- Postfix replaces msmtp
c=$(t_run both "$image" "${off[@]}" -e POSTFIX_ENABLED=true -e MSMTP_ENABLED=true)
t_wait_for 60 -- settled "$c"
assert_eq "true" "$(up "$c" postfix)" "POSTFIX + MSMTP: postfix runs"
assert_eq "/usr/sbin/sendmail.postfix" "$(docker exec "$c" readlink /usr/sbin/sendmail)" "POSTFIX + MSMTP: sendmail is Postfix's, not msmtp"
assert_contains "$(docker logs "$c" 2>&1)" "POSTFIX_ENABLED=true turns msmtp off" "POSTFIX + MSMTP: the rule is logged"
c=$(t_run msmtp "$image" "${off[@]}" -e MSMTP_ENABLED=true)
t_wait_for 60 -- settled "$c"
assert_eq "/usr/bin/msmtp" "$(docker exec "$c" readlink /usr/sbin/sendmail)" "MSMTP alone: sendmail is msmtp"
assert_cmd "msmtp is installed" -- docker exec "$c" msmtp --version

# --- DHCP and TFTP turn dnsmasq on
for v in DHCP_ENABLED TFTP_ENABLED; do
  c=$(t_run "${v%%_*}" "$image" "${off[@]}" -e "$v=true")
  t_wait_for 60 -- settled "$c"
  assert_eq "true" "$(up "$c" dnsmasq)" "$v=true alone starts dnsmasq"
done

# --- negative: a service missing from the table
out=$(docker run --rm --entrypoint "" "$image" bash -c '. /usr/local/lib/izpbx/service.sh; service_is_enabled izpbx-nosuch; echo "rc=$?"' 2>&1)
assert_contains "$out" "service izpbx-nosuch is not in SERVICE_VARS" "control: a service missing from SERVICE_VARS is reported"
assert_contains "$out" "rc=1" "control: and it is not enabled"
docker rmi "$image" >/dev/null 2>&1 || true
finish
