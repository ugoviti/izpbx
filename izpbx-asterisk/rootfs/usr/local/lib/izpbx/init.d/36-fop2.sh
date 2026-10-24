# shellcheck shell=bash
# izpbx-init step: FOP2 install and configuration (services/fop2.sh), when
# fop2 runs; a failed install leaves the service down, not the container
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh
# shellcheck source=../services/fop2.sh
. /usr/local/lib/izpbx/services/fop2.sh
if service_is_enabled fop2; then cfg_fop2; else log_info "fop2: disabled, not configured"; fi
