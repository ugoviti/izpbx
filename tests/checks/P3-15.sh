#!/usr/bin/env bash
# P3-15: remote XML phonebook /pb with the security fixes of 20.16.22.
# FreePBX is not in the image yet: tests/fixtures/phonebook/freepbx.conf
# stands in for its bootstrap (PDO on SQLite with the same tables, SQL errors
# as exceptions).
# - golden: conf-available/phonebook.conf equals the 20.16.22
#   conf.d/phonebook.conf of the default and https cases;
# - every vendor (fanvil, gigaset, yealink) answers valid XML for the
#   extensions and the contacts (as in 20.16 /pb/<vendor>/contacts reads the
#   contact manager group named "contacts": its contact is there);
# - ph=../x -> 400; ph=<script> -> 400 and not echoed back;
# - cgroup=' UNION ... -> valid XML, empty phonebook, no SQL error (the
#   injection reaches the parameterized query: the group "contacts" exists);
# - negative check: PHONEBOOK_ENABLED=false -> /pb is 404.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-15
golden="$TESTS_DIR/golden"
fx="$TESTS_DIR/fixtures/phonebook/freepbx.conf"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

for name in default https; do
  docker run --rm --entrypoint "" --hostname izpbx-golden --env-file "$golden/cases/$name.env" "$image" bash -c \
    'izpbx-init --dry-run >/dev/null 2>&1; cat /etc/apache2/conf-available/phonebook.conf' > "$work/$name.conf" 2>&1
  if diff -u "$golden/20.16.22/$name/files/etc/httpd/conf.d/phonebook.conf" "$work/$name.conf" > "$work/$name.diff"; then
    pass "$name: phonebook.conf same as 20.16.22"
  else
    fail "$name: phonebook.conf differs"; cat "$work/$name.diff" >&2
  fi
done

common=(-v "$fx:/etc/freepbx.conf:ro" -e ASTERISK_ENABLED=false -e IZPBX_ENABLED=false -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false)
c=$(t_run pb "$image" "${common[@]}")
t_wait_for 90 -- docker exec "$c" curl -fsS -o /dev/null http://127.0.0.1/pb/ || log "phonebook not answering"
get() { docker exec "$c" curl -s -w '\n%{http_code}' "http://127.0.0.1$1"; }
body() { sed '$d' <<<"$1"; }
status() { tail -n1 <<<"$1"; }
xml_ok() { docker exec -i "$c" php -r 'libxml_use_internal_errors(true); exit(simplexml_load_string(stream_get_contents(STDIN)) === false ? 1 : 0);'; }

for v in fanvil gigaset yealink; do
  r=$(get "/pb/$v/ext")
  assert_eq 200 "$(status "$r")" "$v ext: HTTP 200"
  assert_cmd "$v ext: valid XML" -- xml_ok <<<"$(body "$r")"
  assert_contains "$(body "$r")" "Alice" "$v ext: extension listed"
  r=$(get "/pb/$v/contacts")
  assert_cmd "$v contacts: valid XML" -- xml_ok <<<"$(body "$r")"
  assert_contains "$(body "$r")" "Carol Contact" "$v contacts: contact of the group listed"
done

r=$(get "/pb/index.php?ph=../x&pb=y")
assert_eq 400 "$(status "$r")" "ph=../x: HTTP 400"
r=$(get "/pb/index.php?ph=%3Cscript%3Ealert(1)%3C/script%3E")
assert_eq 400 "$(status "$r")" "ph=<script>: HTTP 400"
assert_cmd_fails "ph=<script>: not echoed back" -- grep -qi '<script>' <<<"$(body "$r")"

for v in fanvil gigaset yealink; do
  r=$(get "/pb/$v/contacts?cgroup=%27%20UNION%20SELECT%20id,description,tech,id,0%20FROM%20devices--%20")
  assert_eq 200 "$(status "$r")" "$v cgroup=' UNION: HTTP 200"
  assert_cmd "$v cgroup=' UNION: valid XML" -- xml_ok <<<"$(body "$r")"
  assert_cmd_fails "$v cgroup=' UNION: no injected rows" -- grep -qE 'Alice|Bob' <<<"$(body "$r")"
  assert_cmd_fails "$v cgroup=' UNION: no SQL error" -- grep -qiE 'SQLSTATE|syntax error|Fatal' <<<"$(body "$r")"
done

# negative check: phonebook off
c2=$(t_run off "$image" "${common[@]}" -e PHONEBOOK_ENABLED=false)
t_wait_for 90 -- docker exec "$c2" curl -fsS -o /dev/null http://127.0.0.1/ || log "httpd not answering"
assert_eq 404 "$(docker exec "$c2" curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/pb/)" "control: PHONEBOOK_ENABLED=false -> /pb 404"
finish
