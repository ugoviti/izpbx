# shellcheck shell=bash
# izpbx-init step: what FreePBX this start finds (M1) and the FreePBX 17
# first install (services/freepbx.sh):
# - IZPBX_ENABLED=false: FreePBX not used;
# - neither /etc/freepbx.conf nor ${APP_DATA}/.initialized (an empty /data):
#   new installation;
# - otherwise the mode found by 04-freepbx-detect.sh (an initialized /data),
#   or the version in the database: 17 normal start, other versions: error
#   with instructions; FreePBX 16 (migration mode): checks M2 and, without
#   the opt-in or with a blocking check, maintenance mode (as in 04).
# The mode is written for the next steps (izpbx_mode).
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/freepbx.sh
. /usr/local/lib/izpbx/services/freepbx.sh
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
    [ "$mode" != migration ] || freepbx_migration_preflight
  fi
  if [ "$mode" == normal ]; then
    freepbx_conf_update
    freepbx_links
    freepbx_fix_paths
    freepbx_backup_dir
    log_info "freepbx: installed ($IZPBX_FREEPBX_CONF)"
  fi
fi
