#!/bin/bash
# Stage "runtime": last step after the build results are copied in.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

ldconfig
# Asterisk runs as asterisk (1000:1000): the files copied from /staging are root's
for d in /etc/asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk /run/asterisk; do
  mkdir -p "$d"
  chown -R asterisk:asterisk "$d"
done
build_log "runtime ready"
