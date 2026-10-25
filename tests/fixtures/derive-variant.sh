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
#   module17  a FreePBX 16 module with no FreePBX 17 release, simulated: irc
#             16.0.1 enabled in the "modules" table and its directory in
#             admin/modules with a minimal module.xml (installing the real
#             module needs services a clean 20.16 does not have)
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
cp "$base/asteriskcdrdb.sql.gz" "$dest.tmp/"
[ "$variant" == module17 ] || cp "$base/asterisk.sql.gz" "$dest.tmp/"
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
    chmod -R u+w "$work" && rm -rf "$work"   # the unpacked tree holds read-only dirs
    ;;
  diskfull)
    cp "$base/data.tar.gz" "$dest.tmp/"
    # space on a 4 KB block filesystem: every file and directory rounded up to a block
    bytes=$(tar -tvzf "$base/data.tar.gz" | awk '{s += int(($3 + 4095) / 4096) * 4096 + ($1 ~ /^d/ ? 4096 : 0)} END {print s}')
    # room for the data plus 5% and 16 MB of slack: far less than a second copy
    extra+=("volume_size_mb=$(( bytes * 105 / 100 / 1048576 + 16 ))" "data_size_mb=$(( bytes / 1048576 ))")
    ;;
  module17)
    module=irc version=16.0.1
    # the dump ends with the tables already created: one more row in "modules"
    { gzip -dc "$base/asterisk.sql.gz"
      echo "INSERT INTO \`modules\` (\`modulename\`, \`version\`, \`enabled\`, \`signature\`) VALUES ('$module','$version',1,NULL);"
    } | gzip -n > "$dest.tmp/asterisk.sql.gz"
    work="$dest.tmp/module"
    dir="./var/www/html/admin/modules/$module"
    mkdir -p "$work/$dir"
    cat > "$work/$dir/module.xml" <<XML
<module>
	<rawname>$module</rawname>
	<repo>unsupported</repo>
	<name>IRC</name>
	<version>$version</version>
	<publisher>Sangoma Technologies Corporation</publisher>
	<license>GPLv3+</license>
	<category>Support</category>
	<description>fixture: FreePBX 16 module with no FreePBX 17 release</description>
	<supported>
		<version>16.0</version>
	</supported>
</module>
XML
    gzip -dc "$base/data.tar.gz" > "$dest.tmp/data.tar"
    tar --numeric-owner --owner=1000 --group=1000 -C "$work" -rf "$dest.tmp/data.tar" "$dir"
    gzip -n "$dest.tmp/data.tar"
    rm -rf "${work:?}"
    extra+=("anomaly=module $module $version has no FreePBX 17 release")
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
