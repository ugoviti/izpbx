# shellcheck shell=bash
# test step of izpbx-init (P2-02): shows the container environment reaches
# the init, takes some time, and fails on request
log_info "probe step: IZPBX_PROBE_VALUE=${IZPBX_PROBE_VALUE:-unset}"
sleep 2
if [ "${IZPBX_PROBE_FAIL:-}" == 1 ]; then
  false
fi
