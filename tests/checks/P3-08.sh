#!/usr/bin/env bash
# P3-08: msmtp configured by izpbx-init (services/msmtp.sh) as sendmail.
# - golden: /etc/msmtprc of the default and msmtp cases equals 20.16.22
#   apart from the CA bundle path (Rocky ca-bundle.crt -> Debian
#   ca-certificates.crt, design C6);
# - /etc/msmtprc is 640 root:asterisk, /usr/sbin/sendmail is msmtp;
# - sendmail run as asterisk delivers to mailpit (no TLS, so no auth: msmtp
#   refuses to send a password in clear, as with the 20.16 file; the auth
#   lines are covered by the golden msmtp case);
# - negative checks: a different relay changes the file; the user nobody
#   cannot read /etc/msmtprc (the password stays private).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-08
mailpit_image=docker.io/axllent/mailpit:v1.20.0
golden="$TESTS_DIR/golden"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- docker build -q -t "$image" "$REPO_DIR/izpbx-asterisk"

CA_MAP='s|/etc/pki/tls/certs/ca-bundle.crt|/etc/ssl/certs/ca-certificates.crt|'
gen() { # case [docker args] -> msmtprc on stdout, stat on stderr
  local name=$1; shift
  docker run --rm --entrypoint "" --hostname izpbx-golden --env-file "$golden/cases/$name.env" "$@" "$image" \
    bash -c 'izpbx-init --dry-run >/dev/null 2>&1; stat -c "%a %U:%G" /etc/msmtprc >&2; readlink -f /usr/sbin/sendmail >&2; cat /etc/msmtprc'
}
for name in default msmtp; do
  gen "$name" > "$work/$name.new" 2> "$work/$name.err"
  sed "$CA_MAP" "$golden/20.16.22/$name/files/etc/msmtprc" > "$work/$name.old"
  if diff -u "$work/$name.old" "$work/$name.new" > "$work/$name.diff"; then
    pass "$name: msmtprc same as 20.16.22 (apart from the CA path)"
  else
    fail "$name: msmtprc differs"; cat "$work/$name.diff" >&2
  fi
  assert_contains "$(cat "$work/$name.err")" "640 root:asterisk" "$name: /etc/msmtprc 640 root:asterisk"
  assert_contains "$(cat "$work/$name.err")" "/usr/bin/msmtp" "$name: sendmail is msmtp"
done
assert_contains "$(cat "$work/default.new")" "tls_trust_file /etc/ssl/certs/ca-certificates.crt" "default: Debian CA bundle"
gen msmtp -e SMTP_RELAYHOST=other.example.com > "$work/neg.new" 2>/dev/null
assert_cmd_fails "control: a different relay is caught" -- diff -q "$work/msmtp.old" "$work/neg.new"

# --- delivery through mailpit, sendmail as asterisk
net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
t_run mailpit "$mailpit_image" --network "$net" --network-alias mailpit -- \
  --smtp-auth-accept-any --smtp-auth-allow-insecure >/dev/null
c=$(t_run deliver "$image" --network "$net" -e SMTP_RELAYHOST=mailpit -e SMTP_RELAYHOST_PORT=1025 \
  -e SMTP_STARTTLS=false -e SMTP_MAIL_FROM=pbx@example.com \
  -e HTTPD_ENABLED=false -e ASTERISK_ENABLED=false -e IZPBX_ENABLED=false -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false)
t_wait_for 60 -- sh -c "docker logs $c 2>&1 | grep -q 'izpbx-init: done'" || log "init not done"
docker exec -i -u asterisk "$c" sendmail -t <<MAIL || log "sendmail exit $?"
To: user@example.net
Subject: izpbx-msmtp-delivered

test body
MAIL
assert_cmd "sendmail as asterisk delivers to mailpit" -- t_wait_for 30 -- sh -c "docker exec $c curl -fsS http://mailpit:8025/api/v1/messages | grep -q izpbx-msmtp-delivered"
assert_cmd_fails "control: nobody cannot read /etc/msmtprc" -- docker exec -u nobody "$c" cat /etc/msmtprc
finish
