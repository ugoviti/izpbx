#!/command/with-contenv bash
# shellcheck shell=bash
# izpbx-init oneshot of the P0-15 prototype: install FreePBX 17 on the first
# start, then leave Asterisk stopped (the asterisk service starts it).
set -Eeuo pipefail
if [ ! -s /etc/freepbx.conf ]; then
  /usr/local/bin/proto-install.sh
fi
asterisk -rx "core stop now" >/dev/null 2>&1 || true
for _ in $(seq 1 30); do pgrep -x asterisk >/dev/null || break; sleep 1; done
pkill -x safe_asterisk 2>/dev/null || true
apachectl start >/dev/null 2>&1 || true
echo "izpbx-init: done"
