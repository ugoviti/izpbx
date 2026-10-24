# shellcheck shell=bash
# izpbx-init step: fail2ban configuration (services/fail2ban.sh), when it runs
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/fail2ban.sh
. /usr/local/lib/izpbx/services/fail2ban.sh
if service_is_enabled fail2ban; then cfg_fail2ban; else log_info "fail2ban: disabled, not configured"; fi
