# shellcheck shell=bash
# izpbx-init step: variables of the 20.16 entrypoint removed in 22.17 (D22):
# a warning for each one set, the container starts normally; an invalid
# UMASK is reported (env.sh applies only a valid one)
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh
for v in APP_RUNAS MULTISERVICE CMD_OVERRIDE ENTRYPOINT_TINI; do
  [ -n "${!v:-}" ] && log_warn "legacy: $v is not supported since 22.17 and is ignored (s6 runs the services): remove it from the environment"
done
if [ -n "$UMASK" ]; then
  if [[ "$UMASK" =~ ^0?[0-7]{3}$ ]]; then log_info "legacy: umask $UMASK for izpbx-init and the services"
  else log_warn "legacy: UMASK='$UMASK' is not an octal umask (e.g. 0027): ignored"; fi
fi
