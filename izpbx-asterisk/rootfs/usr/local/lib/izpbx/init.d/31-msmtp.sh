# shellcheck shell=bash
# izpbx-init step: msmtp configuration (services/msmtp.sh), when msmtp is
# the MTA (MSMTP_ENABLED, turned off by POSTFIX_ENABLED in service.sh)
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/msmtp.sh
. /usr/local/lib/izpbx/services/msmtp.sh
if [ "$MSMTP_ENABLED" == "true" ]; then cfg_msmtp; else log_info "msmtp: disabled, not configured"; fi
