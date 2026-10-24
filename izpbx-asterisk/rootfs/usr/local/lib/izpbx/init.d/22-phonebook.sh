# shellcheck shell=bash
# izpbx-init step: remote XML phonebook /pb on or off (services/phonebook.sh)
# shellcheck source=../services/phonebook.sh
. /usr/local/lib/izpbx/services/phonebook.sh
if [ "$PHONEBOOK_ENABLED" == "true" ] && [ "$HTTPD_ENABLED" == "true" ]; then cfg_phonebook; else cfg_phonebook_disable; fi
