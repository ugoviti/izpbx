#!/usr/bin/env bash
# P3-05: Apache configured by izpbx-init (services/httpd.sh). Golden test of
# the httpd cases (izpbx-asterisk/tests/golden/cases: default, https, letsencrypt): the
# 22.17 dry-run output, through the path mapping of izpbx-asterisk/tests/golden/map/httpd.sh,
# equals the 20.16.22 files; "apache2ctl -t" accepts every case. The
# Let's Encrypt certificates are written by FreePBX: the test puts dummy ones
# in place before "apache2ctl -t". Self-signed certificate: generated when
# missing, CN = APP_FQDN. Negative check: a case with a different
# HTTPD_ALLOW_FROM gives a different view.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-05
golden="$TESTS_DIR/golden"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

FILES="/etc/apache2/sites-available/izpbx.conf /etc/apache2/conf-available/izpbx.conf /etc/apache2/ports.conf /etc/apache2/envvars"
SCRIPT='izpbx-init --dry-run >/tmp/init.log 2>&1 || { cat /tmp/init.log; exit 1; }
k=/etc/asterisk/keys/integration
if grep -q "$k/webserver.crt" /etc/apache2/sites-available/izpbx.conf; then
  mkdir -p $k && openssl req -subj /CN=le -new -newkey rsa:2048 -nodes -x509 -days 1 -keyout $k/webserver.key -out $k/webserver.crt 2>/dev/null && cp $k/webserver.crt $k/certificate.pem
fi
. /etc/apache2/envvars && mkdir -p "$APACHE_RUN_DIR" "$APACHE_LOG_DIR"
apache2ctl -t >/tmp/t.log 2>&1 && echo "syntax ok" >&2 || { echo "syntax error:" >&2; cat /tmp/t.log >&2; }
c=/etc/asterisk/keys/default.crt
[ -e $c ] && echo "selfsigned $(openssl x509 -noout -subject -in $c | sed "s/.*CN = //")" >&2
tar -chf - '"$FILES"' 2>/dev/null'

run_case() { # case outdir [extra docker args]
  local name=$1 out=$2; shift 2
  mkdir -p "$out"
  docker run --rm --entrypoint "" --hostname izpbx-golden --env-file "$golden/cases/$name.env" "$@" \
    "$image" bash -c "$SCRIPT" 2>"$out.err" | tar -C "$out" -xf -
}

for name in default https letsencrypt; do
  run_case "$name" "$work/$name"
  assert_contains "$(cat "$work/$name.err")" "syntax ok" "$name: apache2ctl -t"
  "$golden/map/httpd.sh" old "$golden/20.16.22/$name/files" > "$work/$name.old"
  "$golden/map/httpd.sh" new "$work/$name" > "$work/$name.new" 2>&1 || true
  if diff -u "$work/$name.old" "$work/$name.new" > "$work/$name.diff"; then
    pass "$name: same as 20.16.22 apart from the path mapping"
  else
    fail "$name: differs from 20.16.22"; head -40 "$work/$name.diff" >&2
  fi
done
assert_contains "$(cat "$work/https.err")" "selfsigned pbx.example.com" "https: self-signed certificate with CN = APP_FQDN"

# negative check: another access list must show in the comparison
run_case https "$work/neg" -e HTTPD_ALLOW_FROM=172.16.0.0/12
"$golden/map/httpd.sh" new "$work/neg" > "$work/neg.new" 2>&1 || true
assert_cmd_fails "control: a different HTTPD_ALLOW_FROM is caught" -- diff -q "$work/https.old" "$work/neg.new"
finish
