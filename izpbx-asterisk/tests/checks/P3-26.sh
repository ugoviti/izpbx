#!/usr/bin/env bash
# P3-26 (T14): idempotent restarts.
# - FreePBX installed on a /data volume, then two "docker restart": the state
#   of izpbx-asterisk/tests/fixtures/snapshot.sh (checksum, mode and owner of every file of
#   /data and of the generated configuration) is the same after the install
#   and after each restart, apart from what changes by design while running
#   (EXCLUDE below);
# - no duplicated entry: crontab of asterisk, [MySQL] of odbcinst.ini, the
#   sections of jail.d/99-local.conf, the AMPDB lines of freepbx.conf;
# - negative check: an init step that appends a line at every start (mounted
#   in a second container on the same data) changes the state and duplicates
#   the line, and both are caught.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-26
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"
# changes by design while running: logs, the pm2 runtime (pids, dump, logs),
# the ban database of fail2ban, the doctrine cache of the FreePBX dashboard,
# the random seed of gpg (rewritten whenever FreePBX checks a signature)
EXCLUDE='^/data/var/log/|^/data/home/asterisk/\.pm2/|^/data/var/lib/fail2ban/fail2ban\.sqlite3$|^/data/var/spool/asterisk/cache/|^/data/home/asterisk/\.gnupg/random_seed$'

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
vol=$(t_volume data)
common=(--network "$net" -v "$vol:/data" -v "$TESTS_DIR/fixtures/snapshot.sh:/snapshot.sh:ro" -e APP_DATA=/data
        -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw -e "SNAPSHOT_EXCLUDE=$EXCLUDE"
        --health-cmd izpbx-healthcheck --health-interval 5s --health-retries 2 --health-start-period 30m)
c=$(t_run pbx "$image" "${common[@]}")
snap() { docker exec "$1" /snapshot.sh > "$2"; }
# freepbx-start (s6 oneshot) ends after healthy: on a new installation its
# fwconsole reload applies the settings of izpbx-init (P3-37); the state is
# taken once the N-th start of the container has finished it
started() { # container N
  t_wait_for 300 -- sh -c "[ \$(docker logs '$1' 2>&1 | grep -c 'service freepbx-start successfully started') -ge $2 ]"
}
dups() { # container: duplicated entries, one per line
  docker exec "$1" sh -c '
    grep -v "^#" /var/spool/cron/crontabs/asterisk | sort | uniq -d
    [ "$(grep -c "^\[MySQL\]" /etc/odbcinst.ini)" -le 1 ] || echo "odbcinst.ini: [MySQL] twice"
    grep "^\[" /etc/fail2ban/jail.d/99-local.conf | sort | uniq -d
    grep "^\$amp_conf\[.AMPDB" /etc/freepbx.conf | cut -d= -f1 | sort | uniq -d
    grep -h "^izpbx-test-append" /data/etc/asterisk/extensions_custom.conf 2>/dev/null | sort | uniq -d'
}

assert_cmd "FreePBX installed: healthy" -- t_wait_healthy "$c" 1500
assert_cmd "FreePBX post-start done" -- started "$c" 1
snap "$c" "$work/0"
for i in 1 2; do
  docker restart "$c" >/dev/null
  assert_cmd "restart $i: healthy" -- t_wait_healthy "$c" 300
  assert_cmd "restart $i: FreePBX post-start done" -- started "$c" $((i + 1))
  snap "$c" "$work/$i"
  if diff -u "$work/0" "$work/$i" > "$work/diff$i"; then
    pass "restart $i: /data and generated configuration unchanged ($(wc -l < "$work/$i") files)"
  else
    fail "restart $i: state changed"; head -40 "$work/diff$i" >&2
  fi
done
assert_eq "" "$(dups "$c")" "no duplicated entry after two restarts"

# --- negative check: a step that is not idempotent
cat > "$work/98-test-append.sh" <<'EOS'
echo "izpbx-test-append" >> /data/etc/asterisk/extensions_custom.conf
EOS
chmod 644 "$work/98-test-append.sh"
docker rm -f "$c" >/dev/null
n=$(t_run append "$image" "${common[@]}" -v "$work/98-test-append.sh:/usr/local/lib/izpbx/init.d/98-test-append.sh:ro")
t_wait_healthy "$n" 300 || log "control container not healthy"
snap "$n" "$work/n1"
docker restart "$n" >/dev/null; t_wait_healthy "$n" 300 || log "control container not healthy after restart"
snap "$n" "$work/n2"
assert_cmd_fails "control: a step appending at every start changes the state" -- diff -q "$work/n1" "$work/n2"
assert_contains "$(dups "$n")" "izpbx-test-append" "control: the duplicated line is found"
finish
