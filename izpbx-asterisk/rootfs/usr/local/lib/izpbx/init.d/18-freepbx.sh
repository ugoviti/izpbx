# shellcheck shell=bash
# izpbx-init step: what FreePBX this start finds (M1) and the FreePBX 17
# first install (services/freepbx.sh):
# - IZPBX_ENABLED=false: FreePBX not used;
# - neither /etc/freepbx.conf nor ${APP_DATA}/.initialized (an empty /data):
#   new installation;
# - otherwise the mode found by 04-freepbx-detect.sh (an initialized /data),
#   or the version in the database: 17 normal start, other versions: error
#   with instructions;
# - migration mode (04 made the snapshot and the archive): database
#   recreated, FreePBX 17 installed, archive restored (migration_restore),
#   then the normal start; a failure stops the container, a restart resumes.
# The mode is written for the next steps (izpbx_mode).
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/migration.sh
. /usr/local/lib/izpbx/services/migration.sh
if [ "$IZPBX_ENABLED" != "true" ]; then
  izpbx_mode_set none
  log_info "freepbx: IZPBX_ENABLED=false, FreePBX not used"
elif ! freepbx_installed && ! persistence_initialized; then
  izpbx_mode_set install
  freepbx_install
elif izpbx_dry_run; then
  izpbx_mode_set normal
  izpbx_record "freepbx: detection of the FreePBX version (M1)"
else
  mode=$(izpbx_mode)
  if [ "$mode" != normal ] && [ "$mode" != migration ]; then
    mode=$(freepbx_detect) || die "freepbx: start refused (see above)"
    izpbx_mode_set "$mode"
    # FreePBX 16 without an initialized /data: no persistent volume to migrate
    if [ "$mode" == migration ]; then
      freepbx_migration_preflight || return 0
      die "freepbx: the migration needs the FreePBX 16 data in APP_DATA (the /data volume of izPBX 20.16)"
    fi
  fi
  if [ "$mode" == migration ]; then
    migration_restore || die "freepbx: migration failed (see above): restart the container to resume"
    migration_sip_transport || die "freepbx: migration failed (see above): restart the container to resume"
    migration_audio || die "freepbx: migration failed (see above): restart the container to resume"
    migration_astdb || die "freepbx: migration failed (see above): restart the container to resume"
    migration_spool || die "freepbx: migration failed (see above): restart the container to resume"
    izpbx_mode_set normal
    mode=normal
  fi
  if [ "$mode" == normal ]; then
    freepbx_conf_update
    freepbx_links
    freepbx_fix_paths
    freepbx_backup_dir
    log_info "freepbx: installed ($IZPBX_FREEPBX_CONF)"
  fi
fi
