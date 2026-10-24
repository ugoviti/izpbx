# shellcheck shell=bash
# izpbx-init step: Postfix configuration (services/postfix.sh), when it runs
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/postfix.sh
. /usr/local/lib/izpbx/services/postfix.sh
if service_is_enabled postfix; then cfg_postfix; else log_info "postfix: disabled, not configured"; fi
