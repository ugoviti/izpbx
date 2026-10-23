#!/usr/bin/env bash
# P2-03: one s6 service each for asterisk (IZPBX_ENABLED or ASTERISK_ENABLED,
# variant "direct" of P0-15), php-fpm, httpd, cron, fail2ban, postfix,
# dnsmasq, ntp (chronyd), zabbix, fop2.
# - static: longrun, dependencies.d/izpbx-init, in the user bundle;
#   httpd after php-fpm, fop2 after asterisk (design S4);
# - with every *_ENABLED=true (FOP2 installed as P3-13 will, tests/s6services)
#   s6-svstat is up for each, stays up with the same pid, and the expected
#   process runs;
# - with the defaults of the contract only asterisk, php-fpm, httpd, cron and
#   fail2ban are up; the others are down, not restarting, no process.
# Negative: FOP2_ENABLED=true without FOP2 installed leaves fop2 down with an
# error; IZPBX_ENABLED=false and ASTERISK_ENABLED=false leave asterisk down,
# ASTERISK_ENABLED=true alone brings it up.
# Also: docker stop with every service is clean (< 40 s, exit 0, no Asterisk
# failure counted) and a one-off command does not hang on the services.
source "$(dirname "$0")/../lib.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
dir="$REPO_DIR/izpbx-asterisk"
rc_dir="$dir/rootfs/etc/s6-overlay/s6-rc.d"
bundle="$dir/rootfs/etc/s6-overlay/user-bundles.d/user/contents.d"
image=izpbx-asterisk:p2-03
test_image=izpbx-s6services:p2-03
declare -A proc=([asterisk]=asterisk [php-fpm]=php-fpm8.2 [httpd]=apache2 [cron]=cron [fail2ban]=fail2ban-server
  [postfix]=master [dnsmasq]=dnsmasq [ntp]=chronyd [zabbix]=zabbix_agent2 [fop2]=fop2_server)
services="asterisk php-fpm httpd cron fail2ban postfix dnsmasq ntp zabbix fop2"
all_enabled=(-e IZPBX_ENABLED=true -e HTTPD_ENABLED=true -e CRON_ENABLED=true -e FAIL2BAN_ENABLED=true -e POSTFIX_ENABLED=true
  -e DNSMASQ_ENABLED=true -e NTP_ENABLED=true -e ZABBIX_ENABLED=true -e FOP2_ENABLED=true)

# --- static
for s in $services; do
  assert_eq "longrun" "$(cat "$rc_dir/$s/type" 2>/dev/null)" "$s is a longrun"
  assert_cmd "$s depends on izpbx-init and is in the user bundle" -- test -e "$rc_dir/$s/dependencies.d/izpbx-init" -a -e "$bundle/$s"
  assert_cmd "$s/run is executable" -- test -x "$rc_dir/$s/run"
done
assert_cmd "httpd starts after php-fpm" -- test -e "$rc_dir/httpd/dependencies.d/php-fpm"
assert_cmd "fop2 starts after asterisk" -- test -e "$rc_dir/fop2/dependencies.d/asterisk"

# --- images (FOP2 fetched on the host: the build needs no network)
assert_cmd "image builds" -- docker build -q -t "$image" "$dir"
fop2_ver=$(sed -n 's/^FOP2_VER=//p' "$dir/versions.env"); fop2_sha=$(sed -n 's/^FOP2_SHA256_X86_64=//p' "$dir/versions.env")
cp "$TESTS_DIR/s6services/Dockerfile" "$work/"
assert_cmd "FOP2 $fop2_ver downloaded (sha256 of versions.env)" -- sh -c "curl -fsSL --proto '=https' -o '$work/fop2.tgz' 'https://download2.fop2.com/fop2-$fop2_ver-debian-x86_64.tgz' && echo '$fop2_sha  $work/fop2.tgz' | sha256sum -c -"
assert_cmd "test image with FOP2 builds" -- docker build -q -t "$test_image" --build-arg BASE="$image" --build-arg FOP2_SHA256="$fop2_sha" "$work"

svstat() { docker exec "$1" /command/s6-svstat "/run/service/$2" 2>&1; }
pid_of() { svstat "$1" "$2" | sed -n 's/^up (pid \([0-9]*\).*/\1/p'; }
running() { docker exec "$1" pgrep -x "$2" >/dev/null; }

# --- every service enabled
c=$(t_run all "$test_image" "${all_enabled[@]}")
all_up() { local s; for s in $services; do [[ "$(svstat "$c" "$s")" == up* ]] || return 1; done; }
t_wait_for 120 -- all_up || log "$(for s in $services; do echo "$s: $(svstat "$c" "$s")"; done)"
declare -A first
for s in $services; do first[$s]=$(pid_of "$c" "$s"); done
sleep 10
for s in $services; do
  assert_cmd "$s is up (s6-svstat)" -- test -n "${first[$s]}"
  assert_eq "${first[$s]}" "$(pid_of "$c" "$s")" "$s stays up with the same pid (no restart loop)"
  assert_cmd "$s: process ${proc[$s]} runs" -- running "$c" "${proc[$s]}"
done

# a clean stop: every service goes down in time, a requested stop is not an
# Asterisk failure (fail2ban and Asterisk drop a SIGTERM while starting)
t0=$SECONDS; docker stop -t 60 "$c" >/dev/null 2>&1
assert_cmd "docker stop with every service: within 15 s ($((SECONDS - t0)) s)" -- test $((SECONDS - t0)) -le 15
assert_eq 0 "$(docker inspect -f '{{.State.ExitCode}}' "$c")" "docker stop with every service: exit 0"
assert_eq 0 "$(docker logs "$c" 2>&1 | grep -c 'asterisk failed' || true)" "a requested stop is not counted as an Asterisk failure"
# a one-off command starts and stops the default services: it must not hang
rc=0; t0=$SECONDS; timeout 90 docker run --rm "$image" true >/dev/null 2>&1 || rc=$?
assert_eq 0 "$rc" "one-off 'docker run image true' with the default services ends with 0 ($((SECONDS - t0)) s, limit 90 s)"

# --- defaults of the contract
d=$(t_run defaults "$test_image")
t_wait_for 60 -- sh -c "docker exec $d /command/s6-svstat /run/service/fail2ban | grep -q '^up'"
sleep 5
for s in asterisk php-fpm httpd cron fail2ban; do
  assert_cmd "default: $s up" -- sh -c "docker exec $d /command/s6-svstat /run/service/$s | grep -q '^up'"
done
for s in postfix dnsmasq ntp zabbix fop2; do
  assert_eq "false false" "$(docker exec "$d" /command/s6-svstat -o up,wantedup "/run/service/$s")" "default: $s down and not restarting"
  assert_cmd_fails "default: no ${proc[$s]} process" -- running "$d" "${proc[$s]}"
done

# --- negative: fop2 without FOP2, asterisk switches
n=$(t_run nofop2 "$image" -e FOP2_ENABLED=true)
t_wait_for 60 -- sh -c "docker logs $n 2>&1 | grep -q 'FOP2 is not installed'"
assert_contains "$(docker logs "$n" 2>&1)" "fop2: FOP2_ENABLED=true but FOP2 is not installed" "control: FOP2 enabled but missing is reported"
assert_eq "false false" "$(docker exec "$n" /command/s6-svstat -o up,wantedup /run/service/fop2)" "control: fop2 without FOP2 stays down"
o=$(t_run noast "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=false)
t_wait_for 60 -- sh -c "docker logs $o 2>&1 | grep -q 'asterisk: disabled'"
assert_eq "false" "$(docker exec "$o" /command/s6-svstat -o up /run/service/asterisk)" "control: IZPBX_ENABLED=false ASTERISK_ENABLED=false leaves asterisk down"
assert_cmd_fails "control: no asterisk process" -- running "$o" asterisk
p=$(t_run plain "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true)
t_wait_for 60 -- sh -c "docker exec $p /command/s6-svstat /run/service/asterisk | grep -q '^up'"
assert_cmd "ASTERISK_ENABLED=true alone starts asterisk" -- running "$p" asterisk

docker rmi "$test_image" "$image" >/dev/null 2>&1 || true
finish
