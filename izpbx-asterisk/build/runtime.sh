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
# no C/C++ toolchain in the runtime (P0-14): the UCP installer refuses to run
# unless "g++ --version" answers, although its node modules build nothing
install -m 755 "$here/g++-stub" /usr/local/bin/g++
# Debian enables an sshd jail by default: izPBX has no sshd, and without its
# log file fail2ban refuses to start (the izPBX jails are written at start)
rm -f /etc/fail2ban/jail.d/defaults-debian.conf
build_log "runtime ready"
