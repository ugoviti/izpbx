#!/usr/bin/env bash
# Golden harness (R3): run an izPBX image with each .env case of the matrix and
# save the configuration files its entrypoint generates.
#
#   izpbx-asterisk/tests/golden/run-golden.sh [-v VERSION] [-o OUTDIR] [CASE...]
#
# Default VERSION 20.16.22, OUTDIR izpbx-asterisk/tests/golden/<VERSION>, CASE all of
# izpbx-asterisk/tests/golden/cases/*.env. Each case runs with IZPBX_ENABLED=false (the
# services are configured, FreePBX is not installed) and CMD_OVERRIDE so the
# container idles after the hooks. Output per case:
#   OUTDIR/<case>/files/<path>   generated files
#   OUTDIR/<case>/perms.txt      mode, owner and path of each file
#   OUTDIR/<case>/services.txt   supervisord autostart per service

TEST_ID=golden
VERSION=20.16.22
OUTDIR=
while [ $# -gt 0 ]; do
  case "$1" in
    -v) VERSION=$2; shift 2 ;;
    -o) OUTDIR=$2; shift 2 ;;
    -*) echo "usage: $0 [-v VERSION] [-o OUTDIR] [CASE...]" >&2; exit 2 ;;
    *) break ;;
  esac
done
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

GOLDEN_DIR="$TESTS_DIR/golden"
OUTDIR=${OUTDIR:-$GOLDEN_DIR/$VERSION}
IMAGE="docker.io/izdock/izpbx-asterisk:$VERSION"
cases=("$@")
[ ${#cases[@]} -gt 0 ] || mapfile -t cases < <(find "$GOLDEN_DIR/cases" -name '*.env' -printf '%f\n' | sed 's/\.env$//' | sort)

# every file the 20.16.x hooks may write; missing ones are skipped
CANDIDATES=(
  /etc/httpd/conf/httpd.conf
  /etc/httpd/conf.modules.d/00-mpm.conf
  /etc/httpd/conf.d/virtual.conf
  /etc/httpd/conf.d/phonebook.conf
  /etc/httpd/conf.d/phpMyAdmin.conf
  /etc/httpd/conf.d/phpMyAdmin_izpbx.conf
  /etc/phpMyAdmin/config.inc.php
  /etc/postfix/main.cf
  /etc/postfix/master.cf
  /etc/postfix/sasl_passwd
  /etc/postfix/allowed_senders
  /etc/postfix/sender_canonical_maps
  /etc/postfix/header_checks
  /etc/aliases
  /etc/msmtprc
  /etc/fail2ban/fail2ban.conf
  /etc/fail2ban/jail.d/99-local.conf
  /etc/dnsmasq.d/local.conf
  /etc/chrony.conf
  /etc/zabbix/zabbix_agent2.conf
  /etc/zabbix/zabbix_agent2.d/local.conf
  /etc/izpbx/cron.env
  /etc/php.d/99-timezone.ini
  /etc/timezone
  /etc/sysconfig/fop2
)

# drop values that change on every run (none known yet: keep the hook here)
normalize() { :; }

run_case() { # case
  local name=$1 env="$GOLDEN_DIR/cases/$1.env" dest="$OUTDIR/$1" c start=$SECONDS
  [ -f "$env" ] || die "unknown case '$name'"
  c=$(t_run "$name" "$IMAGE" --hostname izpbx-golden --env-file "$env" \
    -e IZPBX_ENABLED=false -e CMD_OVERRIDE="sleep infinity")
  until docker logs "$c" 2>&1 | grep -q 'entrypoint command:'; do
    [ "$(docker inspect -f '{{.State.Running}}' "$c")" == "true" ] || { docker logs --tail 40 "$c" >&2; die "case $name: container exited"; }
    [ $((SECONDS - start)) -lt 180 ] || die "case $name: hooks did not finish in 180s"
    sleep 1
  done
  rm -rf "$dest" && mkdir -p "$dest/files"
  docker exec "$c" sh -c 'for f in "$@"; do if [ -e "$f" ]; then echo "$f"; fi; done' sh "${CANDIDATES[@]}" > "$dest/list"
  docker exec -i "$c" tar -chf - -T - < "$dest/list" 2>/dev/null | tar -C "$dest/files" -xf -
  docker exec -i "$c" sh -c 'while read -r f; do stat -L -c "%a %U:%G %n" "$f"; done' < "$dest/list" > "$dest/perms.txt"
  docker exec "$c" sh -c 'for f in /etc/supervisord.d/*.ini; do printf "%s %s\n" "$(basename "$f" .ini)" "$(sed -n "s/^autostart=//p" "$f")"; done' > "$dest/services.txt"
  rm -f "$dest/list"
  normalize "$dest"
  docker rm -f "$c" >/dev/null
  log "case $name: $(find "$dest/files" -type f | wc -l) files ($((SECONDS - start))s)"
}

for name in "${cases[@]}"; do run_case "$name"; done
echo "$VERSION" > "$OUTDIR/VERSION"
docker image inspect -f '{{index .RepoDigests 0}}' "$IMAGE" > "$OUTDIR/IMAGE"
log "golden files in $OUTDIR"
