# shellcheck shell=bash
# izpbx-init step: chronyd configuration (services/ntp.sh), when ntp runs
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/ntp.sh
. /usr/local/lib/izpbx/services/ntp.sh
if service_is_enabled ntp; then cfg_ntp; else log_info "ntp: disabled, not configured"; fi
