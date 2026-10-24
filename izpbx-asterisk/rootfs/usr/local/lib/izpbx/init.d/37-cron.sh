# shellcheck shell=bash
# izpbx-init step: cron spool permissions (services/cron.sh), when cron runs
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/cron.sh
. /usr/local/lib/izpbx/services/cron.sh
if service_is_enabled cron; then cfg_cron; else log_info "cron: disabled, not configured"; fi
