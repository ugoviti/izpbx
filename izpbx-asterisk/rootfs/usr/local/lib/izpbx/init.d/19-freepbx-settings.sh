# shellcheck shell=bash
# izpbx-init step: FreePBX Advanced Settings (FREEPBX_*) and SIP Settings from
# the environment (services/freepbx.sh), at every start with FreePBX (in
# dry-run they are recorded even before the install), then the fixes of
# 20.16's freepbxSettingsFix (HEP (P3-39)),
# and the FreePBX notices that do not apply to izPBX (P3-37)
# shellcheck source=../services/freepbx.sh
. /usr/local/lib/izpbx/services/freepbx.sh
# in migration mode the FreePBX 16 data is not touched (M2)
if [ "$(izpbx_mode)" != migration ]; then
  cfg_asterisk_hep
  if [ "$IZPBX_ENABLED" == "true" ] && { freepbx_installed || izpbx_dry_run; }; then
    cfg_freepbx_settings
    freepbx_notices_cleanup
  fi
fi
