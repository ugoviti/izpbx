#!/usr/bin/env bash
# P3-32: the izpbx-* tools of 20.16 back in the image, checked and fixed
# (regression: the 22.17 Dockerfile copied only izpbx-healthcheck). Removed:
# izpbx-check-oooh323 (no chan_ooh323 in Asterisk 22), izpbx-system-mkswap (a
# swap file is the job of the host). Made generic and renamed: izpbx-rtrt-*
# -> izpbx-enumrewrite, izpbx-freepbx2ldap; izpbx-reboot-{portech,gxw4024,
# kirkettone} -> izpbx-reboot-device TYPE HOST.
# - every tool in the image, executable; -h prints the usage (exit 2); the
#   removed and renamed ones are gone;
# - on an Asterisk running in the image, with a call (a Local channel in
#   Wait): izpbx-callstats lists it; izpbx-hangup-stucked-calls -n lists it
#   and hangs nothing up, without -n hangs it up; izpbx-check-iax2 reports 0
#   peers; izpbx-blfmonitor -1 sets Custom:linea1..N NOT_INUSE;
# - izpbx-trunkrotate on a MariaDB with a route of 3 trunks: -n prints the
#   rotation, a run rotates (first trunk last) and reloads FreePBX (a
#   fwconsole stub); unknown route: exit 1;
# - izpbx-freepbx2ldap: -t prints the LDIF of the users; a run imports them
#   into an OpenLDAP container (password through a file, never on the command
#   line), a second run sees no change; no configuration: exit 2;
# - izpbx-enumrewrite on a copy of enumlookup.agi: the domain first, a second
#   run changes nothing;
# - izpbx-reboot-device against a fake web device: portech (POST with basic
#   auth), grandstream-gxw (login, cookie, /cgi-bin/rs), kirk (any auth);
#   unknown type: exit 2; no password without a terminal: exit 2.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-32
assert_cmd "image builds" -- t_build_image "$image"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
chmod 755 "$work"
tools="izpbx-blfmonitor izpbx-callstats izpbx-check-iax2 izpbx-enumrewrite izpbx-freepbx2ldap izpbx-hangup-stucked-calls izpbx-healthcheck izpbx-mtrstats izpbx-reboot-device izpbx-trunkrotate"
assert_eq "$(tr ' ' '\n' <<< "$tools" | sort | tr '\n' ' ')" \
  "$(docker run --rm --entrypoint "" "$image" sh -c 'cd /usr/local/bin && for f in izpbx-*; do [ -x "$f" ] && echo "$f"; done' | sort | tr '\n' ' ')" \
  "the izpbx-* tools in the image, executable"
for t in $tools; do
  [ "$t" == izpbx-healthcheck ] && continue
  rc=0; docker run --rm --entrypoint "" "$image" "$t" -h >/dev/null 2>&1 || rc=$?
  assert_eq 2 "$rc" "$t -h: usage, exit 2"
done

# --- Asterisk running in the image, with a call
net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
cat > "$work/fwconsole" <<'EOF'
#!/bin/sh
echo "fwconsole $*" >> /tmp/fwconsole.log
EOF
chmod 755 "$work/fwconsole"
c=$(t_run ast "$image" --network "$net" -v "$work/fwconsole:/usr/local/sbin/fwconsole:ro" \
  -e MYSQL_SERVER=db -e MYSQL_USER=asterisk -e MYSQL_PASSWORD=astpw -e MYSQL_DATABASE=asterisk \
  --entrypoint "" -- asterisk -f -U asterisk -G asterisk)
assert_cmd "Asterisk boots" -- t_wait_for 120 -- docker exec "$c" asterisk -rx 'core waitfullybooted'
docker exec "$c" asterisk -rx 'dialplan add extension s,1,Wait(600) into izpbxtest' >/dev/null
docker exec "$c" asterisk -rx 'channel originate Local/s@izpbxtest application Wait 600' >/dev/null
assert_cmd "a call up" -- t_wait_for 20 -- sh -c "docker exec '$c' asterisk -rx 'core show channels concise' | grep -q '^Local/s@izpbxtest'"
sleep 2
out=$(docker exec "$c" izpbx-callstats)
log "callstats: $(tr '\n' '|' <<< "$out")"
assert_cmd "izpbx-callstats: header and the call" -- sh -c "head -n 1 <<'X' | grep -q '^N\\. *ORIG *FROM *TO *STATE *DURATION'
$out
X
grep -q ' 00:00:0[0-9]' <<'X'
$out
X"
assert_cmd "izpbx-callstats -b: one line per call" -- sh -c "docker exec '$c' izpbx-callstats -b | grep -q '^1) orig:\\['"
assert_cmd "izpbx-hangup-stucked-calls -n 1: lists, hangs nothing up" -- sh -c "docker exec '$c' izpbx-hangup-stucked-calls -n 1 | grep -q 'would hang up Local/s@izpbxtest'"
assert_cmd "  the call still up" -- sh -c "docker exec '$c' asterisk -rx 'core show channels concise' | grep -q '^Local/s@izpbxtest'"
assert_cmd "izpbx-hangup-stucked-calls 1: hangs it up" -- sh -c "docker exec '$c' izpbx-hangup-stucked-calls 1 | grep -q 'hanging up Local/s@izpbxtest'"
assert_cmd "  no call left" -- t_wait_for 10 -- sh -c "! docker exec '$c' asterisk -rx 'core show channels concise' | grep -q izpbxtest"
assert_contains "$(docker exec "$c" izpbx-check-iax2)" "0 IAX2 peer(s) unreachable" "izpbx-check-iax2: 0 unreachable peers"
docker exec "$c" izpbx-blfmonitor -1 -t test -l 2 >/dev/null
assert_eq "2" "$(docker exec "$c" asterisk -rx 'devstate list' | grep -cE "Custom:linea[12]'.*NOT_INUSE" || true)" "izpbx-blfmonitor -1: Custom:linea1/2 NOT_INUSE"

# --- izpbx-trunkrotate and izpbx-freepbx2ldap on a MariaDB
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  -e MARIADB_DATABASE=asterisk -e MARIADB_USER=asterisk -e MARIADB_PASSWORD=astpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot asterisk <<'EOF'
CREATE TABLE outbound_routes (route_id INT PRIMARY KEY, name VARCHAR(40));
CREATE TABLE trunks (trunkid INT PRIMARY KEY, name VARCHAR(40));
CREATE TABLE outbound_route_trunks (route_id INT, trunk_id INT, seq INT);
CREATE TABLE users (extension VARCHAR(20), name VARCHAR(50), sipname VARCHAR(50));
INSERT INTO outbound_routes VALUES (1, 'gsm');
INSERT INTO trunks VALUES (10, 'sim1'), (11, 'sim2'), (12, 'sim3');
INSERT INTO outbound_route_trunks VALUES (1, 10, 0), (1, 11, 1), (1, 12, 2);
INSERT INTO users VALUES ('1001', 'Mario Rossi', ''), ('1002', 'Anna', '0551234567');
EOF
order() { docker exec -e MYSQL_PWD=rootpw "$db" mariadb -uroot -N asterisk -e "SELECT trunk_id FROM outbound_route_trunks ORDER BY seq" | tr '\n' ' ' | sed 's/ $//'; }
out=$(docker exec "$c" izpbx-trunkrotate -n gsm sim1 sim2 sim3)
assert_contains "$out" "sim1: position 0 -> 2" "izpbx-trunkrotate -n: sim1 goes last"
assert_eq "10 11 12" "$(order)" "  -n changes nothing"
assert_cmd "izpbx-trunkrotate: rotates and reloads" -- docker exec "$c" izpbx-trunkrotate gsm sim1 sim2 sim3
assert_eq "11 12 10" "$(order)" "  new order sim2 sim3 sim1"
assert_cmd "  fwconsole reload run" -- docker exec "$c" grep -qx 'fwconsole reload' /tmp/fwconsole.log
rc=0; docker exec "$c" izpbx-trunkrotate nosuchroute sim1 sim2 >/dev/null 2>&1 || rc=$?
assert_eq 1 "$rc" "izpbx-trunkrotate: unknown route, exit 1"

ldap=$(t_run ldap docker.io/osixia/openldap:1.5.0 --network "$net" --network-alias ldap \
  -e LDAP_ORGANISATION=Test -e LDAP_DOMAIN=example.org -e LDAP_ADMIN_PASSWORD=ldappw)
t_wait_for 90 -- docker exec "$ldap" ldapsearch -x -H ldap://localhost -b dc=example,dc=org -D cn=admin,dc=example,dc=org -w ldappw -LLL dn >/dev/null 2>&1
printf 'dn: o=Phones,dc=example,dc=org\nobjectClass: organization\no: Phones\n' |
  docker exec -i "$ldap" ldapadd -x -H ldap://localhost -D cn=admin,dc=example,dc=org -w ldappw >/dev/null
docker exec "$c" sh -c 'mkdir -p /etc/izpbx && printf "%s\n" LDAP_URI=ldap://ldap LDAP_BIND_DN=cn=admin,dc=example,dc=org \
  LDAP_PASSWORD_FILE=/etc/izpbx/ldap.pw LDAP_BASE_DN=dc=example,dc=org LDAP_OU=Phones > /etc/izpbx/freepbx2ldap.conf
  printf ldappw > /etc/izpbx/ldap.pw; chmod 600 /etc/izpbx/ldap.pw'
ldif=$(docker exec "$c" izpbx-freepbx2ldap -t)
assert_contains "$ldif" "dn: uid=1001,o=Phones,dc=example,dc=org" "izpbx-freepbx2ldap -t: the LDIF of 1001"
assert_contains "$ldif" "telephoneNumber: 0551234567" "  sipname as telephoneNumber"
assert_contains "$(docker exec "$c" izpbx-freepbx2ldap)" "2 extension(s) imported" "izpbx-freepbx2ldap: imported into OpenLDAP"
assert_eq "2" "$(docker exec "$ldap" ldapsearch -x -H ldap://localhost -b o=Phones,dc=example,dc=org -D cn=admin,dc=example,dc=org -w ldappw -LLL '(uid=*)' dn | grep -c '^dn: uid=')" "  2 entries in LDAP"
assert_contains "$(docker exec "$c" izpbx-freepbx2ldap)" "extensions unchanged" "  a second run: no change"
rc=0; docker exec -e IZPBX_FREEPBX2LDAP_CONF=/nonexistent "$c" izpbx-freepbx2ldap >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc" "izpbx-freepbx2ldap: no configuration, exit 2"

# --- izpbx-enumrewrite on a copy of enumlookup.agi
docker exec "$c" sh -c 'cp /usr/src/freepbx/amp_conf/htdocs/admin/modules/core/agi-bin/enumlookup.agi /tmp/enum.agi'
docker exec -e IZPBX_ENUM_FILES=/tmp/enum.agi "$c" izpbx-enumrewrite e164.example.net >/dev/null
assert_cmd "izpbx-enumrewrite: the domain first" -- docker exec "$c" grep -qF "\$enums = Array('e164.example.net','e164.org'" /tmp/enum.agi
docker exec -e IZPBX_ENUM_FILES=/tmp/enum.agi "$c" izpbx-enumrewrite e164.example.net >/dev/null
assert_eq 1 "$(docker exec "$c" grep -o "e164.example.net" /tmp/enum.agi | wc -l)" "  a second run changes nothing"

# --- izpbx-reboot-device against a fake web device
cat > "$work/device.py" <<'EOF'
import base64, http.server, sys
log = open("/tmp/device.log", "a")
class H(http.server.BaseHTTPRequestHandler):
    def reply(self, code, headers=()):
        self.send_response(code)
        for k, v in headers: self.send_header(k, v)
        self.end_headers()
    def auth(self):
        a = self.headers.get("Authorization", "")
        return base64.b64decode(a[6:]).decode() if a.startswith("Basic ") else ""
    def handle_req(self, method):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0) or 0)).decode()
        log.write(f"{method} {self.path} auth={self.auth()} body={body} cookie={self.headers.get('Cookie', '')}\n"); log.flush()
        if self.path.startswith("/firmware.html") and not self.auth():
            return self.reply(401, [("WWW-Authenticate", 'Basic realm="kirk"')])
        if self.path == "/cgi-bin/dologin":
            return self.reply(200, [("Set-Cookie", "session=gxw42; Path=/")])
        self.reply(200)
    def do_GET(self): self.handle_req("GET")
    def do_POST(self): self.handle_req("POST")
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", 8080), H).serve_forever()
EOF
docker cp "$work/device.py" "$c:/tmp/device.py"
docker exec -d "$c" python3 /tmp/device.py
t_wait_for 20 -- docker exec "$c" curl -s -o /dev/null http://127.0.0.1:8080/
reboot() { docker exec -e IZPBX_DEVICE_PASSWORD=devpw "$c" izpbx-reboot-device "$@" 127.0.0.1:8080; }
assert_cmd "reboot portech" -- reboot portech
assert_cmd "  POST /rebootsys.cgi with admin:devpw" -- docker exec "$c" grep -q '^POST /rebootsys.cgi auth=admin:devpw body=submit=Reboot' /tmp/device.log
assert_cmd "reboot grandstream-gxw" -- reboot grandstream-gxw
assert_cmd "  login with P2=devpw" -- docker exec "$c" grep -q '^POST /cgi-bin/dologin auth= body=P2=devpw' /tmp/device.log
assert_cmd "  /cgi-bin/rs with the session cookie" -- docker exec "$c" grep -q '^GET /cgi-bin/rs .*cookie=session=gxw42' /tmp/device.log
assert_cmd "reboot kirk" -- reboot kirk
assert_cmd "  RebootIdle with admin:devpw after the 401" -- docker exec "$c" grep -q '^GET /firmware.html?action=RebootIdle auth=admin:devpw' /tmp/device.log
rc=0; docker exec -e IZPBX_DEVICE_PASSWORD=devpw "$c" izpbx-reboot-device fridge 127.0.0.1:8080 >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc" "izpbx-reboot-device: unknown type, exit 2"
rc=0; docker exec "$c" izpbx-reboot-device portech 127.0.0.1:8080 </dev/null >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc" "izpbx-reboot-device: no password and no terminal, exit 2"
finish
