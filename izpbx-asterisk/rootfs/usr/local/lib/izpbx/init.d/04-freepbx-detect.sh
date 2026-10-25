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
# they are. Otherwise the migration starts here, before the persistence step:
# inventory M3, snapshot M4 (the FreePBX 16 directories moved away) and
# archive M5.1; the restore, M6 and the verification M7 follow in
# 18-freepbx.sh. A migration in progress (state in
# ${APP_DATA}/.izpbx-migration) is resumed whatever the database holds; after a
# completed one, every start reports the snapshot still there and its size.
# shellcheck source=../services/migration.sh
. /usr/local/lib/izpbx/services/migration.sh
if [ "$IZPBX_ENABLED" == "true" ] && ! izpbx_dry_run && persistence_initialized; then
  if migration_in_progress; then
    izpbx_mode_set migration
    log_info "freepbx: migration to FreePBX 17 in progress ($(migration_state snapshot_dir)): resuming"
  else
    mode=$(freepbx_detect) || die "freepbx: start refused (see above)"
    izpbx_mode_set "$mode"
    [ "$mode" != normal ] || migration_snapshot_notice
    if [ "$mode" == migration ]; then freepbx_migration_preflight || true; fi
  fi
  if [ "$(izpbx_mode)" == migration ] && [ ! -e "$IZPBX_MAINTENANCE_FLAG" ]; then
    migration_inventory_before || die "freepbx: migration inventory failed (see above): restart the container to resume"
    migration_snapshot || die "freepbx: migration snapshot failed (see above): restart the container to resume"
    migration_archive || die "freepbx: migration archive failed (see above): restart the container to resume"
  fi
fi
