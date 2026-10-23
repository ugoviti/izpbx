#!/bin/bash
# Stage "builder": Asterisk addons (bcg729, asterisk-g72x, chan-dongle, sngrep).
# Filled in by checklist item P1-07.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
build_log "addons: none yet (P1-07)"
