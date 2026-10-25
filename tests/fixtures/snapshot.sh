#!/bin/bash
# P3-26: state of a container that a restart must not change. Prints, sorted:
#   sha256  mode owner:group  path
# for every file of the /data tree and of the configuration izpbx-init
# generates, and "L target path" for symlinks (crontabs: the sorted entries). Excluded: what changes by
# design while running (logs, call spool, Asterisk astdb and the runtime
# caches listed below), passed in SNAPSHOT_EXCLUDE (extended regex on paths).
set -uo pipefail
ex=${SNAPSHOT_EXCLUDE:-^$}
{ {
  find /data /etc/apache2 /etc/php/8.2 /etc/fail2ban /etc/postfix /etc/msmtprc /etc/chrony /etc/izpbx \
       /etc/odbc.ini /etc/odbcinst.ini /etc/dnsmasq.d /etc/zabbix /etc/default/fop2 /etc/timezone /etc/aliases \
       /etc/phpmyadmin /var/spool/cron/crontabs /usr/sbin/fwconsole /usr/sbin/amportal \( -type f -o -type l \) 2>/dev/null || true; } |
    grep -Ev "$ex" | while read -r f; do
      if [ -L "$f" ]; then printf 'L %s %s\n' "$(readlink "$f")" "$f"
      # a crontab: FreePBX reinstalls it every minute while running, "crontab"
      # writes the time in the comment header and the order of the lines
      # changes: only the set of entries counts
      elif [[ "$f" == */crontabs/* ]]; then printf '%s %s %s\n' "$(grep -v '^#' "$f" | LC_ALL=C sort | sha256sum | cut -c1-16)" "$(stat -c '%a %U:%G' "$f")" "$f"
      else printf '%s %s %s\n' "$(sha256sum < "$f" | cut -c1-16)" "$(stat -c '%a %U:%G' "$f")" "$f"; fi
    done
} | LC_ALL=C sort -k3
# paths missing in this configuration (zabbix, fop2 off...) are not an error
exit 0
