# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # sourced by make-fixture.sh: shares its variables
# extdb (P0-08d): external DB on the bridge network with non standard
# database names and port.
#
# The 20.16.x first install cannot use a port other than 3306: the FreePBX
# installer ignores --dbport in its credentials check ("Connection refused").
# So, like a real setup, FreePBX is installed on 3306, then MariaDB moves to
# 3307 and izPBX restarts with APP_PORT_MYSQL=3307 (the entrypoint rewrites
# AMPDBPORT in /etc/freepbx.conf on every start).
DB_NAME=pbxconfig
DB_CDR=pbxcdr
EXTDB_PORT=3307
variant_install() {
  wait_installed "$pbx"
  log "variant extdb: moving MariaDB to port $EXTDB_PORT"
  docker stop -t 120 "$pbx" >/dev/null && docker rm "$pbx" >/dev/null
  docker stop -t 60 "$db" >/dev/null && docker rm "$db" >/dev/null
  DB_PORT=$EXTDB_PORT
  db=$(t_run db "$DB_IMAGE" --network "$net" --network-alias db -v "$db_vol:/var/lib/mysql" \
    --health-cmd "healthcheck.sh --connect --innodb_initialized" --health-interval 3s --health-retries 60 \
    -- --sql-mode=ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION --port="$DB_PORT")
  t_wait_healthy "$db" 180 || die "MariaDB did not restart on port $DB_PORT"
  pbx=$(start_pbx pbx "$IMAGE" "${PBX_ENV[@]}")
  wait_installed "$pbx"
  docker exec "$pbx" grep -q "AMPDBPORT'\] = '$DB_PORT'" /etc/freepbx.conf || die "freepbx.conf does not use port $DB_PORT"
}
variant_manifest() { echo "anomaly=database names $DB_NAME/$DB_CDR on port $DB_PORT (installed on 3306, then moved)"; }
