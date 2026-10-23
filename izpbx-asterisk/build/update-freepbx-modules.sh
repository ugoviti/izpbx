#!/bin/bash
# Refresh build/freepbx-modules.txt: for every module name listed there, the
# latest FreePBX 17 release on the mirror (queried like Module Admin does:
# POST phpver to all-17.0.xml) and the sha256 of its signed package.
#   build/update-freepbx-modules.sh [--check]
# --check: only report the modules whose pinned version differs (exit 10).
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
load_versions "$here/../versions.env"
list="$here/freepbx-modules.txt"
check=; [ "${1:-}" == "--check" ] && check=1

xml=$(mktemp); trap 'rm -f "$xml"' EXIT
curl -fsSL --proto '=https' --connect-timeout 30 -X POST -d "phpver=8.2" \
  "https://mirror.freepbx.org/all-$FREEPBX_VER.0.xml" -o "$xml"

# rawname version location, from the <module> entries (not edge/previous)
mapfile -t latest < <(python3 -I - "$xml" <<'PY'
import sys, xml.etree.ElementTree as ET
# FreePBX 16 lists <module> entries; FreePBX 17 wraps one element per module
# (named after it) in a single <module>
for top in ET.parse(sys.argv[1]).getroot().findall('module'):
    for m in ([top] if top.find('rawname') is not None else list(top)):
        if m.findtext('rawname'):
            print(m.findtext('rawname'), m.findtext('version'), m.findtext('location'))
PY
)

out=$(mktemp); changed=0
{
  sed -n '/^#/p' "$list"
  while read -r name cur _; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    line=$(printf '%s\n' "${latest[@]}" | awk -v n="$name" '$1==n' | head -1)
    [ -n "$line" ] || build_die "module $name is not on the FreePBX $FREEPBX_VER mirror"
    read -r _ ver loc <<< "$line"
    if [ "$ver" != "${cur:-}" ]; then
      changed=$((changed + 1)); build_log "$name: ${cur:-none} -> $ver"
    fi
    if [ -n "$check" ]; then
      printf '%s\n' "$(grep -E "^$name " "$list")"
    else
      sha=$(curl -fsSL --proto '=https' --connect-timeout 30 "https://mirror.freepbx.org/modules/$loc" | sha256sum | cut -d' ' -f1)
      printf '%-18s %-14s %s\n' "$name" "$ver" "$sha"
    fi
  done < <(grep -v '^#' "$list")
} > "$out"
if [ -n "$check" ]; then
  rm -f "$out"; [ "$changed" -eq 0 ] || exit 10; exit 0
fi
mv "$out" "$list"
build_log "$list updated ($changed change(s))"
