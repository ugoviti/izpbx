#!/usr/bin/env bash
# P4-18: certificates and certman after the migration (M6): the 20.16.22
# fixture (self-signed default certificate of certman in etc/asterisk/keys)
# migrated in a real start with HTTPD_HTTPS_ENABLED=true. The legacy archive
# holds etc/asterisk/keys, restored by certman with its tables.
# - every file of etc/asterisk/keys of the fixture is there with the same
#   content (not the certificates FreePBX 17 generated at the install);
# - the default certificate of certman is the same as before (certman_certs);
# - HTTPS answers with that certificate (fingerprint of default.crt);
# - control: the restore log has the certificate files of the archive
#   (certman did not report them missing).
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-18
fx="$TESTS_DIR/fixtures/out/20.16.22"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
sql() { echo "$1" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot -N asterisk; }
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot || die "cannot load $f"; done
echo "CREATE USER asterisk@'%' IDENTIFIED BY 'fixture-pw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'" |
  docker exec -i -e MYSQL_PWD=rootpw "$db" mariadb -uroot
v=$(t_volume data)
docker run --rm --entrypoint "" -v "$v:/data" -v "$fx:/fx:ro" "$image" tar -C /data -xzf /fx/data.tar.gz 2>/dev/null
keys_before=$(docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" sh -c 'cd /data/etc/asterisk/keys && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum')
fp_before=$(docker run --rm --entrypoint "" -v "$v:/data:ro" "$image" openssl x509 -noout -fingerprint -sha256 -in /data/etc/asterisk/keys/default.crt)
default_before=$(sql "SELECT basename FROM certman_certs WHERE \`default\` = 1")
log "fixture: $(wc -l <<< "$keys_before") key files, default certificate '$default_before', $fp_before"

c=$(t_run pbx "$image" --network "$net" -v "$v:/data" -e APP_DATA=/data -e MYSQL_SERVER=db \
  -e MYSQL_PASSWORD=fixture-pw -e MYSQL_ROOT_PASSWORD=rootpw -e IZPBX_MIGRATE_FREEPBX=true -e HTTPD_HTTPS_ENABLED=true)
assert_cmd "migrated: healthy" -- t_wait_healthy "$c" 2400
missing=$(docker exec -i "$c" sh -c 'cd /etc/asterisk/keys && sha256sum -c --quiet 2>&1' <<< "$keys_before" || true)
assert_eq "" "$missing" "every key file of the fixture is there with the same content"
assert_ne "" "$default_before" "the fixture has a default certificate in certman"
assert_eq "$default_before" "$(sql "SELECT basename FROM certman_certs WHERE \`default\` = 1")" "certman: same default certificate ($default_before)"
fp_https=$(docker exec "$c" sh -c 'echo | openssl s_client -connect 127.0.0.1:443 2>/dev/null | openssl x509 -noout -fingerprint -sha256')
log "HTTPS: $fp_https"
assert_eq "$fp_before" "$fp_https" "HTTPS answers with the default certificate of the fixture"
snap=$(docker exec "$c" sh -c 'sed -n "s/^snapshot_dir=//p" /data/.izpbx-migration/state | tail -n 1')
assert_cmd_fails "control: certman found the certificate files in the archive" -- \
  docker exec "$c" grep -q 'Cerificate files are not found' "$snap/restore.log"
finish
