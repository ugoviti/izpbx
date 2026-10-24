#!/usr/bin/env bash
# P3-07: Postfix configured by izpbx-init (services/postfix.sh).
# - golden: the postfix and hostile cases (tests/golden/cases) give, through
#   tests/golden/map/postfix.sh, the same view as 20.16.22; postfix check OK;
#   sasl_passwd and sasl_passwd.db 600 root:root;
# - delivery: with mailpit as relay (SMTP auth accepted) a mail sent with
#   sendmail is delivered (relay credentials set, no SASL error), with From
#   rewritten to SMTP_MAIL_FROM;
# - negative checks: a relay port where nothing listens delivers nothing; a
#   different SMTP_MYNETWORKS changes the view.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-07
mailpit_image=docker.io/axllent/mailpit:v1.20.0
golden="$TESTS_DIR/golden"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

# view of one side, with the postconf of the image (old: the golden files mounted)
view() { # dir
  docker run --rm --entrypoint "" -v "$1:/v:ro" -v "$golden/map/postfix.sh:/map.sh:ro" "$image" \
    bash /map.sh "postconf -c /v/etc/postfix -h" /v
}
SCRIPT='izpbx-init --dry-run >/tmp/init.log 2>&1 || { cat /tmp/init.log >&2; exit 1; }
postfix check >&2 && echo "postfix check ok" >&2
stat -c "%a %U:%G %n" /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db >&2 2>/dev/null || true
tar -chf - /etc/postfix /etc/aliases 2>/dev/null'
run_case() { # case outdir [docker args]
  local name=$1 out=$2; shift 2
  mkdir -p "$out"
  docker run --rm --entrypoint "" --hostname izpbx-golden --env-file "$golden/cases/$name.env" "$@" \
    "$image" bash -c "$SCRIPT" 2>"$out.err" | tar -C "$out" -xf -
}

for name in postfix hostile; do
  run_case "$name" "$work/$name"
  err=$(cat "$work/$name.err")
  assert_contains "$err" "postfix check ok" "$name: postfix check"
  assert_contains "$err" "600 root:root /etc/postfix/sasl_passwd" "$name: sasl_passwd 600 root"
  assert_contains "$err" "600 root:root /etc/postfix/sasl_passwd.db" "$name: sasl_passwd.db 600 root"
  view "$golden/20.16.22/$name/files" > "$work/$name.old"
  view "$work/$name" > "$work/$name.new"
  if diff -u "$work/$name.old" "$work/$name.new" > "$work/$name.diff"; then
    pass "$name: same as 20.16.22 (golden view)"
  else
    fail "$name: differs from 20.16.22"; head -40 "$work/$name.diff" >&2
  fi
done
run_case postfix "$work/neg" -e SMTP_MYNETWORKS=10.0.0.0/8
view "$work/neg" > "$work/neg.new"
assert_cmd_fails "control: a different SMTP_MYNETWORKS is caught" -- diff -q "$work/postfix.old" "$work/neg.new"

# --- delivery through mailpit
net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
t_run mailpit "$mailpit_image" --network "$net" --network-alias mailpit -- \
  --smtp-auth-accept-any --smtp-auth-allow-insecure >/dev/null
common=(--network "$net" -e POSTFIX_ENABLED=true -e SMTP_RELAYHOST=mailpit -e SMTP_STARTTLS=false
        -e SMTP_MAIL_FROM=pbx@example.com -e HTTPD_ENABLED=false -e ASTERISK_ENABLED=false -e IZPBX_ENABLED=false
        -e FAIL2BAN_ENABLED=false -e CRON_ENABLED=false)
msgs() { docker exec "$1" curl -fsS http://mailpit:8025/api/v1/messages 2>/dev/null || echo '{}'; }
send() { # container subject
  docker exec -i "$1" sendmail -t <<MAIL
To: user@example.net
From: someone@other.example
Subject: $2

test body
MAIL
}

c=$(t_run deliver "$image" "${common[@]}" -e SMTP_RELAYHOST_PORT=1025 -e SMTP_RELAYHOST_USERNAME=u -e SMTP_RELAYHOST_PASSWORD=p)
t_wait_for 60 -- docker exec "$c" test -S /var/spool/postfix/public/pickup
send "$c" izpbx-delivered
assert_cmd "mail delivered to mailpit" -- t_wait_for 60 -- sh -c "docker exec $c curl -fsS http://mailpit:8025/api/v1/messages | grep -q izpbx-delivered"
assert_contains "$(msgs "$c")" '"Address":"pbx@example.com"' "From rewritten to SMTP_MAIL_FROM"
assert_cmd_fails "no SASL error in the log" -- sh -c "docker logs $c 2>&1 | grep -Eiq 'SASL authentication failed|no mechanism available'"

# negative check: nothing listens on the relay port
c2=$(t_run noport "$image" "${common[@]}" -e SMTP_RELAYHOST_PORT=2999)
t_wait_for 60 -- docker exec "$c2" test -S /var/spool/postfix/public/pickup
send "$c2" izpbx-not-delivered
sleep 15
assert_cmd_fails "control: wrong relay port, nothing delivered" -- sh -c "docker exec $c curl -fsS http://mailpit:8025/api/v1/messages | grep -q izpbx-not-delivered"
finish
