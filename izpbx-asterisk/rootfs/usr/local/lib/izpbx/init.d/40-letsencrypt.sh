# shellcheck shell=bash
# izpbx-init step: Let's Encrypt certificate (when HTTPS and Let's Encrypt are
# enabled) and the environment of the cron jobs (services/letsencrypt.sh)
# shellcheck source=../services/letsencrypt.sh
. /usr/local/lib/izpbx/services/letsencrypt.sh
# shellcheck source=../services/freepbx.sh
. /usr/local/lib/izpbx/services/freepbx.sh
# not in migration mode: fwconsole would be the FreePBX 16 one of /data
if [ "$HTTPD_HTTPS_ENABLED" == "true" ] && [ "$LETSENCRYPT_ENABLED" == "true" ]; then
  if [ "$(izpbx_mode)" == migration ]; then log_info "letsencrypt: migration mode, certificate request skipped"; else cfg_letsencrypt; fi
fi
cfg_cronenv
