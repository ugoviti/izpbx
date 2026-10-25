# shellcheck shell=bash
# izpbx-init step: what FreePBX this start finds (M1) and the FreePBX 17
# first install (services/freepbx.sh):
# - IZPBX_ENABLED=false: FreePBX not used;
# - neither /etc/freepbx.conf nor ${APP_DATA}/.initialized (an empty /data):
#   new installation;
# - otherwise the version in the database: 17 normal start, 16 migration
#   (no write to its data here), other versions: error with instructions.
# The mode is written for the next steps (izpbx_mode).
# In migration mode the read only checks M2 (izpbx-preflight) always run:
# report in the log and in ${APP_DATA}/.izpbx-migration, result ("ok" or
# "blocked") in /run/izpbx/preflight.
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
  mode=$(freepbx_detect) || die "freepbx: start refused (see above)"
  izpbx_mode_set "$mode"
  if [ "$mode" == normal ]; then
    freepbx_conf_update
    freepbx_links
    freepbx_fix_paths
    freepbx_backup_dir
    log_info "freepbx: installed ($IZPBX_FREEPBX_CONF)"
  elif [ "$mode" == migration ]; then
    report=$(izpbx-preflight) && result=ok || result=blocked
    while IFS= read -r line; do log_info "preflight: $line"; done <<< "$report"
    echo "$result" > /run/izpbx/preflight
  fi
fi
