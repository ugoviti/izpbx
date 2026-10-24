# shellcheck shell=bash
# izpbx-init step: Let's Encrypt certificate (when HTTPS and Let's Encrypt are
# enabled) and the environment of the cron jobs (services/letsencrypt.sh)
# shellcheck source=../services/letsencrypt.sh
. /usr/local/lib/izpbx/services/letsencrypt.sh
if [ "$HTTPD_HTTPS_ENABLED" == "true" ] && [ "$LETSENCRYPT_ENABLED" == "true" ]; then cfg_letsencrypt; fi
cfg_cronenv
