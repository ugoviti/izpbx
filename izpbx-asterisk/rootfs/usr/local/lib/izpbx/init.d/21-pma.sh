# shellcheck shell=bash
# izpbx-init step: phpMyAdmin on or off (services/pma.sh), after httpd
# shellcheck source=../services/pma.sh
. /usr/local/lib/izpbx/services/pma.sh
if [ "$PMA_ENABLED" == "true" ] && [ "$HTTPD_ENABLED" == "true" ]; then cfg_pma; else cfg_pma_disable; fi
