#!/usr/bin/env bash
# Derive a negative fixture variant from an existing fixture, without a
# FreePBX run.
#
#   tests/fixtures/derive-variant.sh BASE_DIR VARIANT [OUTDIR]
#
# Variants:
#   macro     Macro( in extensions_custom.conf (T9); the manifest records file:line
#   diskfull  same content, plus volume_size_mb: a /data volume of that size is
#             almost full and cannot hold a second copy of the data (T8)
#
# Output: OUTDIR/<base name>-VARIANT (default OUTDIR: the parent of BASE_DIR).

set -Eeuo pipefail
base=$(cd "${1:?usage: $0 BASE_DIR VARIANT [OUTDIR]}" && pwd)
variant=${2:?usage: $0 BASE_DIR VARIANT [OUTDIR]}
outdir=$(cd "${3:-$base/..}" && pwd)
dest="$outdir/$(basename "$base")-$variant"
here=$(cd "$(dirname "$0")" && pwd)

[ -s "$base/manifest.txt" ] || { echo "derive-variant: $base is not a fixture" >&2; exit 2; }
inputs=$( { grep '^inputs=' "$base/manifest.txt"; echo "$variant"; cat "$here/derive-variant.sh"; } | sha256sum | cut -c1-16)

rm -rf "$dest.tmp" && mkdir -p "$dest.tmp"
cp "$base/asterisk.sql.gz" "$base/asteriskcdrdb.sql.gz" "$dest.tmp/"
extra=()

case "$variant" in
  macro)
    work="$dest.tmp/data"
    mkdir -p "$work"
    tar -C "$work" -xzf "$base/data.tar.gz" 2>/dev/null
    conf=etc/asterisk/extensions_custom.conf
    {
      echo
      echo "; fixture: legacy dialplan using Macro(), removed in Asterisk 21+"
      echo "[fixture-legacy-macro]"
      echo "exten => s,1,Macro(user-callerid,)"
    } >> "$work/$conf"
    line=$(grep -n 'Macro(' "$work/$conf" | tail -1 | cut -d: -f1)
    extra+=("anomaly=$conf:$line")
    tar --numeric-owner -C "$work" -czf "$dest.tmp/data.tar.gz" .
    rm -rf "$work"
    ;;
  diskfull)
    cp "$base/data.tar.gz" "$dest.tmp/"
    # space on a 4 KB block filesystem: every file and directory rounded up to a block
    bytes=$(tar -tvzf "$base/data.tar.gz" | awk '{s += int(($3 + 4095) / 4096) * 4096 + ($1 ~ /^d/ ? 4096 : 0)} END {print s}')
    # room for the data plus 5% and 16 MB of slack: far less than a second copy
    extra+=("volume_size_mb=$(( bytes * 105 / 100 / 1048576 + 16 ))" "data_size_mb=$(( bytes / 1048576 ))")
    ;;
  *) echo "derive-variant: unknown variant '$variant'" >&2; exit 2 ;;
esac

{
  grep -E '^(version|image)=' "$base/manifest.txt"
  echo "variant=$variant"
  echo "inputs=$inputs"
  echo "base=$(basename "$base")"
  echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "generator=tests/fixtures/derive-variant.sh"
  printf '%s\n' "${extra[@]}"
  (cd "$dest.tmp" && sha256sum asterisk.sql.gz asteriskcdrdb.sql.gz data.tar.gz)
} > "$dest.tmp/manifest.txt"
rm -rf "$dest" && mv "$dest.tmp" "$dest"
echo "derive-variant: $dest"
