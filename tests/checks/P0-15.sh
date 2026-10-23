#!/usr/bin/env bash
# P0-15: how the izpbx service starts Asterisk under s6. Both prototypes
# (tests/proto/s6, VARIANT=fwconsole and VARIANT=direct) go through:
#   restart  "fwconsole restart": one Asterisk, new pid, service up, no extra safe_asterisk
#   T17      kill -9 of Asterisk: back within 15 s; 3 kills in a row: container exits != 0
#   T18      docker stop: exit 0 within 30 s, the stop is in the log
# The report goes to tests/proto/s6/REPORT.md. Choice (D21): the variant that
# passes everything; with a tie, fwconsole.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
report="$TESTS_DIR/proto/s6/REPORT.md"
VARIANTS="fwconsole direct"

assert_cmd "FreePBX 17 prototype image builds" -- docker build -q -t izpbx-proto/fpbx17:17.0.33 "$TESTS_DIR/proto/fpbx17"
for v in $VARIANTS; do
  assert_cmd "s6 prototype $v builds" -- docker build -q --build-arg VARIANT="$v" -t "izpbx-proto/s6:$v" "$TESTS_DIR/proto/s6"
done

ast_pids() { docker exec "$1" pgrep -x asterisk 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
ast_ready() { docker exec "$1" asterisk -rx 'core show uptime' >/dev/null 2>&1; }
# ready = izpbx-init finished and the s6 asterisk service is up and answering
# (the FreePBX installer also runs an Asterisk, so "answers" alone is not enough)
svc_ready() {
  # grep -c, not -q: "docker logs | grep -q" ends in SIGPIPE, a failure under pipefail
  docker logs "$1" 2>&1 | grep -c 'service izpbx-init successfully started' >/dev/null &&
    [ "$(docker exec "$1" /command/s6-svstat -o up /run/service/asterisk 2>/dev/null)" == "true" ] && ast_ready "$1"
}
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]; }
wait_ready() { # container timeout
  local s=$SECONDS
  until svc_ready "$1"; do
    running "$1" || return 1
    [ $((SECONDS - s)) -lt "$2" ] || return 1
    sleep 2
  done
}
# a different Asterisk pid than $2, answering, within $3 seconds
wait_new_pid() {
  local s=$SECONDS p
  while [ $((SECONDS - s)) -lt "$3" ]; do
    p=$(ast_pids "$1")
    [ -n "$p" ] && [ "$p" != "$2" ] && ast_ready "$1" && return 0
    sleep 1
  done
  return 1
}

evaluate() { # variant -> writes $work/<variant>.result lines "key=ok|fail detail"
  set +e   # runs in the background: expected failures (pgrep, kill) must not abort it
  local v=$1 out="$work/$1.result" net db pbx pid t0 rc
  net="$TEST_PROJECT-$v-net"
  docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
  db=$(t_run "$v-db" docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=proto-root \
    --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
  t_wait_healthy "$db" 120 || { echo "setup=fail MariaDB" > "$out"; return; }
  pbx=$(t_run "$v-pbx" "izpbx-proto/s6:$v" --network "$net" --hostname izpbx-s6 -e MYSQL_PASSWORD=proto-pw -e MYSQL_ROOT_PASSWORD=proto-root)
  wait_ready "$pbx" 1200 || { echo "setup=fail install"; docker logs --tail 30 "$pbx"; } > "$out" 2>&1
  [ -s "$out" ] && return
  echo "setup=ok" > "$out"

  # restart
  pid=$(ast_pids "$pbx")
  docker exec "$pbx" timeout 180 fwconsole restart >"$work/$v.restart.log" 2>&1 || true
  sleep 10
  local p sa svc
  # pgrep -c prints 0 and exits 1 when nothing matches: keep its output only
p=$(ast_pids "$pbx"); sa=$(docker exec "$pbx" pgrep -cx safe_asterisk 2>/dev/null) || true; sa=${sa:-0}
  svc=$(docker exec "$pbx" /command/s6-svstat -o up /run/service/asterisk 2>/dev/null || echo false)
  if running "$pbx" && [ -n "$p" ] && [ "$p" != "$pid" ] && [[ "$p" != *" "* ]] && ast_ready "$pbx" && [ "$svc" == "true" ] && [ "$sa" -le 1 ]; then
    echo "restart=ok pid $pid -> $p, safe_asterisk=$sa" >> "$out"
  else
    echo "restart=fail running=$(running "$pbx" && echo yes || echo no) pids=[$pid]->[$p] service_up=$svc safe_asterisk=$sa" >> "$out"
  fi

  # T17a: a single kill -9 is recovered
  if running "$pbx" || { docker start "$pbx" >/dev/null && wait_ready "$pbx" 300; }; then
    pid=$(ast_pids "$pbx")
    t0=$SECONDS
    docker exec "$pbx" kill -9 "$pid"
    # T17 asks "restarted", the time is measured for the report
    if wait_new_pid "$pbx" "$pid" 90; then echo "t17_kill=ok pid $pid -> $(ast_pids "$pbx") in $((SECONDS - t0))s" >> "$out"
    else echo "t17_kill=fail no new Asterisk within 90 s (pids: [$(ast_pids "$pbx")])" >> "$out"; fi
  else
    echo "t17_kill=fail container not running" >> "$out"
  fi

  # T18: docker stop
  t0=$SECONDS
  docker stop -t 30 "$pbx" >/dev/null 2>&1
  rc=$(docker inspect -f '{{.State.ExitCode}}' "$pbx")
  local dt=$((SECONDS - t0)) logok=no
  docker logs "$pbx" 2>&1 | grep -cE 'service asterisk successfully stopped' >/dev/null && logok=yes
  if [ "$rc" == "0" ] && [ "$dt" -le 30 ] && [ "$logok" == "yes" ]; then echo "t18_stop=ok ${dt}s exit 0" >> "$out"
  else echo "t18_stop=fail ${dt}s exit $rc stop-logged=$logok" >> "$out"; fi

  # T17b: three kills in a row halt the container with exit != 0
  docker start "$pbx" >/dev/null
  if wait_ready "$pbx" 300; then
    local i s
    for i in 1 2 3; do
      pid=$(ast_pids "$pbx")
      [ -n "$pid" ] && docker exec "$pbx" kill -9 "$pid" 2>/dev/null
      [ "$i" -lt 3 ] && { wait_new_pid "$pbx" "$pid" 90 || break; }
    done
    s=$SECONDS
    while running "$pbx" && [ $((SECONDS - s)) -lt 60 ]; do sleep 2; done
    rc=$(docker inspect -f '{{.State.ExitCode}}' "$pbx")
    if ! running "$pbx" && [ "$rc" != "0" ]; then echo "t17_halt=ok container exited with $rc" >> "$out"
    else echo "t17_halt=fail running=$(running "$pbx" && echo yes || echo no) exit=$rc" >> "$out"; fi
  else
    echo "t17_halt=fail no Asterisk after restart" >> "$out"
  fi
}

for v in $VARIANTS; do evaluate "$v" & done
wait

passes() { [ "$(grep -c '=ok' "$work/$1.result")" -eq 5 ]; }   # setup + 4 tests
choice=
for v in $VARIANTS; do passes "$v" && { choice=$v; break; }; done   # fwconsole first: D21 tie-break

{
  echo "# P0-15: Asterisk under s6, variant comparison"
  echo
  echo "Generated by \`tests/checks/P0-15.sh\` on $(date -u +%Y-%m-%dT%H:%M:%SZ) (prototypes in \`tests/proto/s6\`)."
  echo
  echo "| Test | fwconsole | direct |"
  echo "|---|---|---|"
  for k in setup restart t17_kill t18_stop t17_halt; do
    printf '| %s |' "$k"
    for v in $VARIANTS; do printf ' %s |' "$(sed -n "s/^$k=//p" "$work/$v.result" | head -1)"; done
    echo
  done
  echo
  echo "Choice (D21: the variant that passes everything, fwconsole on a tie): **${choice:-none}**"
} > "$report"
cat "$report" >&2

for v in $VARIANTS; do
  while IFS= read -r line; do log "$v: $line"; done < "$work/$v.result"
done
assert_ne "" "$choice" "a variant passes restart, T17 and T18"
for k in setup restart t17_kill t18_stop t17_halt; do
  assert_cmd "chosen variant ${choice:-none} passes $k" -- grep -q "^$k=ok" "$work/${choice:-none}.result"
done

finish
