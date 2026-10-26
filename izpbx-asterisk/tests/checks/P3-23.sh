#!/usr/bin/env bash
# P3-23: variables of the 20.16 entrypoint removed with a warning (D22).
# - APP_RUNAS, MULTISERVICE, CMD_OVERRIDE, ENTRYPOINT_TINI, each set alone:
#   the start log warns about it and the container works (Asterisk boots);
#   none of them is declared in env.sh; all are listed in §13 of the design;
# - UMASK=0027: the log file Asterisk creates is 0640 (0644 without UMASK);
# - controls: without the variables no warning; an invalid UMASK is reported
#   and ignored.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-23
design="$REPO_DIR/.specs/2026-10-23-release-22.17.0-freepbx17.md"
assert_cmd "image builds" -- t_build_image "$image"
base=(-e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true -e HTTPD_ENABLED=false -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false)
booted() { docker exec "$1" asterisk -rx 'core waitfullybooted' >/dev/null 2>&1; }

declare -A val=([APP_RUNAS]=true [MULTISERVICE]=true [CMD_OVERRIDE]="sleep infinity" [ENTRYPOINT_TINI]=true)
declare -A cid
for v in "${!val[@]}"; do cid[$v]=$(t_run "${v,,}" "$image" "${base[@]}" -e "$v=${val[$v]}"); done
u=$(t_run umask "$image" "${base[@]}" -e UMASK=0027)
n=$(t_run plain "$image" "${base[@]}")
b=$(t_run badumask "$image" "${base[@]}" -e UMASK=rwx)

for v in "${!val[@]}"; do
  assert_cmd "$v set: the container works (Asterisk boots)" -- t_wait_for 120 -- booted "${cid[$v]}"
  assert_contains "$(docker logs "${cid[$v]}" 2>&1)" "legacy: $v is not supported since 22.17" "$v set: warning in the start log"
  assert_cmd_fails "$v: not declared in env.sh" -- grep -qE "^: \"\\\$\{$v:=" "$REPO_DIR/izpbx-asterisk/rootfs/usr/local/lib/izpbx/env.sh"
  assert_cmd "$v listed in §13 of the design" -- sh -c "sed -n '/^## 13\\./,/^## 14\\./p' '$design' | grep -q '$v'"
done

mode() { docker exec "$1" stat -c %a /var/log/asterisk/messages.log 2>/dev/null || docker exec "$1" stat -c %a /var/log/asterisk/messages; }
for c in "$u" "$n" "$b"; do t_wait_for 120 -- booted "$c" || log "Asterisk not booted in $c"; done
t_wait_for 30 -- sh -c "docker exec $u sh -c 'ls /var/log/asterisk/messages*' >/dev/null 2>&1" || true
assert_eq 640 "$(mode "$u")" "UMASK=0027: the Asterisk log is 0640"
assert_eq 644 "$(mode "$n")" "control: without UMASK the Asterisk log is 0644"
assert_cmd_fails "control: no warning without the legacy variables" -- sh -c "docker logs '$n' 2>&1 | grep -q 'legacy: .* is not supported'"
assert_contains "$(docker logs "$b" 2>&1)" "UMASK='rwx' is not an octal umask" "control: an invalid UMASK is reported"
assert_eq 644 "$(mode "$b")" "control: an invalid UMASK is ignored"
finish
