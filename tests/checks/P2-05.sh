#!/usr/bin/env bash
# P2-05 (T17, design S5): s6 restarts a failed service; Asterisk failing N=3
# times in a row stops the container (as the 20.16 watchdog).
# - kill -9 of the httpd and php-fpm processes supervised by s6: the service
#   is up again with a new pid within 10 s and answers (HTTP / fpm socket);
# - kill -9 of asterisk 3 times in a row: the container exits with code != 0
#   and logs why;
# - a failure after Asterisk has been up for 60 s or more starts the count
#   again: 2 kills, 65 s up, 1 kill -> still running; 2 more kills -> exit.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p2-05
assert_cmd "image builds" -- docker build -q -t "$image" "$REPO_DIR/izpbx-asterisk"

svc_pid() { docker exec "$1" /command/s6-svstat -o up,pid "/run/service/$2" 2>/dev/null | awk '$1=="true"{print $2}'; }
ast_pid() { docker exec "$1" pgrep -xo asterisk 2>/dev/null; }
ast_ready() { docker exec "$1" asterisk -rx 'core waitfullybooted' >/dev/null 2>&1; }
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == true ]; }
new_pid() { # container service old-pid
  local p; p=$(svc_pid "$1" "$2"); [ -n "$p" ] && [ "$p" != "$3" ]
}
kill_asterisk() { # container: kill -9 Asterisk, wait for a new one (unless the container stops)
  local p; p=$(ast_pid "$1")
  docker exec "$1" kill -9 "$p"
  t_wait_for 60 -- sh -c "[ \"\$(docker inspect -f '{{.State.Running}}' $1)\" != true ] || { q=\$(docker exec $1 pgrep -xo asterisk); [ -n \"\$q\" ] && [ \"\$q\" != $p ] && docker exec $1 asterisk -rx 'core waitfullybooted' >/dev/null 2>&1; }"
}

# --- httpd and php-fpm restart
c=$(t_run svc "$image")
t_wait_for 90 -- sh -c "docker exec $c curl -fsS -o /dev/null http://localhost/" || log "httpd not answering"
for s in httpd php-fpm; do
  p=$(svc_pid "$c" "$s")
  assert_ne "" "$p" "$s is up before the kill"
  t0=$SECONDS; docker exec "$c" kill -9 "$p"
  t_wait_for 10 -- new_pid "$c" "$s" "$p" && rc=0 || rc=$?
  assert_eq 0 "$rc" "kill -9 $s: up again with a new pid within 10 s ($((SECONDS - t0)) s)"
done
assert_cmd "httpd answers after the restarts" -- t_wait_for 15 -- docker exec "$c" curl -fsS -o /dev/null http://localhost/
assert_cmd "php-fpm socket is back" -- t_wait_for 15 -- docker exec "$c" test -S /run/php/php8.2-fpm.sock

# --- Asterisk: 3 failures in a row stop the container
a=$(t_run halt "$image")
t_wait_for 90 -- ast_ready "$a" || die "Asterisk did not start"
for _ in 1 2 3; do kill_asterisk "$a"; done
t_wait_for 30 -- sh -c "! docker inspect -f '{{.State.Running}}' $a | grep -q true" || true
assert_cmd_fails "3 Asterisk failures in a row: the container stopped" -- running "$a"
assert_ne "0" "$(docker inspect -f '{{.State.ExitCode}}' "$a")" "3 Asterisk failures in a row: exit code != 0"
assert_contains "$(docker logs "$a" 2>&1)" "asterisk failed 3 times in a row, stopping the container" "the reason is logged"

# --- a failure after a long run starts the count again
w=$(t_run window "$image")
t_wait_for 90 -- ast_ready "$w" || die "Asterisk did not start"
kill_asterisk "$w"; kill_asterisk "$w"
sleep 65
kill_asterisk "$w"
assert_cmd "2 kills, 65 s up, 1 kill: still running (count restarted)" -- running "$w"
assert_eq 2 "$(docker logs "$w" 2>&1 | grep -c 'asterisk failed (1/3' || true)" "the late failure counts as the first again (two '1/3' in the log)"
kill_asterisk "$w"; kill_asterisk "$w"
t_wait_for 30 -- sh -c "! docker inspect -f '{{.State.Running}}' $w | grep -q true" || true
assert_cmd_fails "then 2 more quick kills: the container stopped" -- running "$w"
docker rmi "$image" >/dev/null 2>&1 || true
finish
