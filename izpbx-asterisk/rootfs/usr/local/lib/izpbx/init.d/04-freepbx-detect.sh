# shellcheck shell=bash
# izpbx-init step: detection M1 of an initialized /data, before the
# persistence step (05) links or seeds anything under APP_DATA: the version
# of the database says normal start (17) or migration (16); other versions
# stop the start with instructions. A new installation (empty /data) and
# the dry-run are left to 18-freepbx.sh.
# In migration mode the read only checks M2 (izpbx-preflight) always run:
# report in the log and in ${APP_DATA}/.izpbx-migration, result ("ok" or
# "blocked") in /run/izpbx/preflight. Without the opt-in
# IZPBX_MIGRATE_FREEPBX=true, or with a blocking check, the container goes in
# maintenance mode (D4, S10): izpbx-init stops after this step, no service
# starts, the healthcheck is unhealthy, /data and the databases stay as
# they are.
# shellcheck source=../services/freepbx.sh
. /usr/local/lib/izpbx/services/freepbx.sh
if [ "$IZPBX_ENABLED" == "true" ] && ! izpbx_dry_run && persistence_initialized; then
  mode=$(freepbx_detect) || die "freepbx: start refused (see above)"
  izpbx_mode_set "$mode"
  [ "$mode" != migration ] || freepbx_migration_preflight
fi
