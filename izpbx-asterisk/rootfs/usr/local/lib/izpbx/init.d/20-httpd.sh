# shellcheck shell=bash
# izpbx-init step: Apache configuration (services/httpd.sh), when httpd runs
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/httpd.sh
. /usr/local/lib/izpbx/services/httpd.sh
if service_is_enabled httpd; then cfg_httpd; else log_info "httpd: disabled, not configured"; fi
