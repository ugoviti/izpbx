# shellcheck shell=bash
# izpbx-init step: time zone of the system and of PHP from TZ (services/php.sh)
# shellcheck source=../services/php.sh
. /usr/local/lib/izpbx/services/php.sh
cfg_timezone
