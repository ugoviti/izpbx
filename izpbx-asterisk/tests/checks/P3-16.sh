#!/usr/bin/env bash
# P3-16: Let's Encrypt and cron.env (services/letsencrypt.sh,
# /etc/cron.daily/freepbx-le-renew).
# - golden: /etc/izpbx/cron.env of the default, https and letsencrypt cases
#   equals 20.16.22, mode 600 root:root;
# - renewal job (cron.daily, run by run-parts): with a fake certificate and a
#   simulated fwconsole (izpbx-asterisk/tests/fixtures/le-renew), httpd and FreePBX are
#   restarted only when the certificate fingerprint changes;
# - certificate request: without FreePBX it is skipped with a warning; with a
#   simulated fwconsole in dry-run the update/generate calls are recorded.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-16
golden="$TESTS_DIR/golden"
fx="$TESTS_DIR/fixtures/le-renew"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

for name in default https letsencrypt; do
  docker run --rm --entrypoint "" --hostname izpbx-golden --env-file "$golden/cases/$name.env" "$image" bash -c \
    'izpbx-init --dry-run >/tmp/init.log 2>&1; stat -c "%a %U:%G" /etc/izpbx/cron.env >&2; cat /etc/izpbx/cron.env' > "$work/$name.env" 2> "$work/$name.err"
  if diff -u "$golden/20.16.22/$name/files/etc/izpbx/cron.env" "$work/$name.env" > "$work/$name.diff"; then
    pass "$name: cron.env same as 20.16.22"
  else
    fail "$name: cron.env differs"; cat "$work/$name.diff" >&2
  fi
  assert_contains "$(cat "$work/$name.err")" "600 root:root" "$name: cron.env 600 root:root"
done

# --- daily renewal job with a simulated fwconsole
out=$(docker run --rm --entrypoint "" -v "$fx:/opt/le:ro" -e HTTPD_HTTPS_ENABLED=true -e LETSENCRYPT_ENABLED=true \
  -e APP_FQDN=pbx.example.com "$image" bash -c '
  izpbx-init --dry-run >/dev/null 2>&1
  run-parts --test /etc/cron.daily | grep -q freepbx-le-renew && echo "job listed by run-parts"
  mkdir -p /etc/asterisk/keys
  openssl req -subj /CN=pbx.example.com -new -newkey rsa:2048 -nodes -x509 -days 90 \
    -keyout /etc/asterisk/keys/pbx.example.com.key -out /etc/asterisk/keys/pbx.example.com.crt 2>/dev/null
  export PATH=/opt/le:$PATH
  env -i PATH="$PATH" /etc/cron.daily/freepbx-le-renew; echo "--- same"; cat /tmp/le-calls.log; : > /tmp/le-calls.log
  touch /tmp/le-renew
  env -i PATH="$PATH" /etc/cron.daily/freepbx-le-renew; echo "--- renewed"; cat /tmp/le-calls.log' 2>&1)
assert_contains "$out" "job listed by run-parts" "cron.daily job runs with run-parts"
same=$(sed -n '/^--- same/,/^--- renewed/p' <<<"$out")
renewed=$(sed -n '/^--- renewed/,$p' <<<"$out")
assert_contains "$same" "fwconsole certificates --updateall -q" "same certificate: renewal attempted (env from cron.env)"
assert_cmd_fails "same certificate: httpd not restarted" -- grep -q 'izpbx-service restart httpd' <<<"$same"
assert_contains "$renewed" "izpbx-service restart httpd" "new certificate: httpd restarted"
assert_contains "$renewed" "fwconsole restart" "new certificate: FreePBX restarted"

# --- certificate request
le=(-e HTTPD_HTTPS_ENABLED=true -e LETSENCRYPT_ENABLED=true -e APP_FQDN=pbx.example.com
    -e LETSENCRYPT_COUNTRY_CODE=IT -e LETSENCRYPT_COUNTRY_STATE=Toscana -e LETSENCRYPT_EMAIL=admin@example.com)
out=$(docker run --rm --entrypoint "" "${le[@]}" "$image" izpbx-init --dry-run 2>&1)
assert_contains "$out" "FreePBX (fwconsole) not installed yet" "without FreePBX: request skipped with a warning"
out=$(docker run --rm --entrypoint "" -v "$fx:/opt/le:ro" "${le[@]}" "$image" bash -c \
  'PATH=/opt/le:$PATH izpbx-init --dry-run >/dev/null 2>&1; cat /run/izpbx/dry-run.log' 2>&1)
assert_contains "$out" "fwconsole certificates -n --generate --type=le --hostname=pbx.example.com --country-code=IT --state=Toscana --email=admin@example.com" "dry-run: generate request recorded"
assert_contains "$out" "fwconsole certificates --default=pbx.example.com" "dry-run: default certificate recorded"
out=$(docker run --rm --entrypoint "" "${le[@]}" -e LETSENCRYPT_COUNTRY_CODE= "$image" izpbx-init --dry-run 2>&1)
assert_contains "$out" "LETSENCRYPT_COUNTRY_CODE is not defined" "control: a missing country code skips the request"
finish
