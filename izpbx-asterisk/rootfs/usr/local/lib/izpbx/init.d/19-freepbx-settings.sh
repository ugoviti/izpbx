# shellcheck shell=bash
# izpbx-init step: FreePBX Advanced Settings (FREEPBX_*) and SIP Settings from
# the environment (services/freepbx.sh), at every start with FreePBX (in
# dry-run they are recorded even before the install)
# shellcheck source=../services/freepbx.sh
. /usr/local/lib/izpbx/services/freepbx.sh
if [ "$IZPBX_ENABLED" == "true" ] && { freepbx_installed || izpbx_dry_run; }; then
  cfg_freepbx_settings
fi
