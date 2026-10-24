# shellcheck shell=bash
# izpbx-init step: FreePBX 17 first install (services/freepbx.sh) when izPBX
# runs FreePBX (IZPBX_ENABLED) and neither /etc/freepbx.conf nor
# ${APP_DATA}/.initialized exist (an empty /data)
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/freepbx.sh
. /usr/local/lib/izpbx/services/freepbx.sh
if [ "$IZPBX_ENABLED" != "true" ]; then
  log_info "freepbx: IZPBX_ENABLED=false, FreePBX not used"
elif freepbx_installed; then
  freepbx_links
  freepbx_fix_paths
  log_info "freepbx: installed ($FREEPBX_CONF)"
elif persistence_initialized; then
  log_warn "freepbx: ${APP_DATA}/.initialized exists but $FREEPBX_CONF is missing: not installing over existing data"
else
  freepbx_install
fi
