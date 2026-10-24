#!/usr/bin/env bash
# Dead code check of a tree (P3-22): prints each finding, exit 1 if any.
# - names of what 22.17 dropped: alpine, rhel, microdnf, chan_local and the
#   FreePBX 15/16 workarounds FREEPBX-21703 / FREEPBX-22983;
# - blocks of more than 3 consecutive commented-out code lines ("#echo",
#   "# sed ...", "#[ $? = 0 ] ..."); prose comments ("# text") do not count.
#   tests/dead-code.sh DIR
set -uo pipefail
dir=${1:?usage: $0 DIR}
rc=0
if grep -rniE 'alpine|rhel|microdnf|chan_local|FREEPBX-2(1703|2983)' "$dir"; then rc=1; fi
blocks=$(grep -rIlZ . "$dir" | xargs -0 -r awk '
  function iscode(l) {
    if (l ~ /^[ \t]*#!/ || l ~ /^[ \t]*# shellcheck/) return 0
    if (l ~ /^[ \t]*#[^ \t#]/) return 1
    if (l ~ /^[ \t]*#[ \t]*(echo|sed|if|fi|then|else|for|while|done|do|set|local|export|fwconsole|cat|grep|awk|mysql|cd|rm|cp|mv|ln|chown|chmod|\[|\]|\}|\{|[a-zA-Z_]+=|[a-zA-Z_]+\(\))([ \t;]|$)/) return 1
    return 0
  }
  FNR == 1 { n = 0 }
  { if (iscode($0)) { n++; if (n == 4) print FILENAME ":" FNR - 3 ": more than 3 commented-out code lines" } else n = 0 }')
[ -z "$blocks" ] || { printf '%s\n' "$blocks"; rc=1; }
exit $rc
