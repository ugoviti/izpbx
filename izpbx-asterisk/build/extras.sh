#!/bin/bash
# Stage "runtime": ionCube, izsynth, zabbix-templates.
# Filled in by checklist item P1-09.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
build_log "extras: none yet (P1-09)"
