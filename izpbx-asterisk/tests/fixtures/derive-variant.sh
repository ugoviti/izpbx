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
#   commercial  a commercial module installed (queuestats 16.0.3, no license),
#             simulated as module17: its row in "modules" and its module.xml
#             (license Commercial, repo commercial) in admin/modules
#   phonebook three entries of the FreePBX 16 phonebook module (astdb cidname)
#             and a system speed dial (astdb sysspeeddials 11 -> 1003)
#   speeddial speed dials of the speeddial module (meant for the fp15 fixture,
#             where it is installed): system 12 -> 1002 (sysspeeddials) and a
#             personal one of 1001, 5 -> 0612349999 (AMPUSER/1001/speeddials)
#   module17  a FreePBX 16 module with no FreePBX 17 release, simulated: irc
#             16.0.1 enabled in the "modules" table and its directory in
#             admin/modules with a minimal module.xml (installing the real
#             module needs services a clean 20.16 does not have)
#
# Output: OUTDIR/<base name>-VARIANT (default OUTDIR: the parent of BASE_DIR).
# A variant already derived from the same inputs (this script, the variant,
# the base fixture and its files) is reused; checks running in parallel may
# derive the same variant: each one works in its own temporary directory.

set -Eeuo pipefail
base=$(cd "${1:?usage: $0 BASE_DIR VARIANT [OUTDIR]}" && pwd)
variant=${2:?usage: $0 BASE_DIR VARIANT [OUTDIR]}
outdir=$(cd "${3:-$base/..}" && pwd)
dest="$outdir/$(basename "$base")-$variant"
here=$(cd "$(dirname "$0")" && pwd)

[ -s "$base/manifest.txt" ] || { echo "derive-variant: $base is not a fixture" >&2; exit 2; }
inputs=$( { grep -E '^inputs=|^[0-9a-f]{64}  ' "$base/manifest.txt"; echo "$variant"; cat "$here/derive-variant.sh"; } | sha256sum | cut -c1-16)
same_inputs() { [ -s "$dest/manifest.txt" ] && grep -qx "inputs=$inputs" "$dest/manifest.txt"; }
if same_inputs; then echo "derive-variant: $dest (reused)"; exit 0; fi

tmp=$(mktemp -d "$dest.tmp.XXXXXX")
trap '[ ! -d "${tmp:?}" ] || { chmod -R u+w "$tmp"; rm -rf "$tmp"; }' EXIT
cp "$base/asteriskcdrdb.sql.gz" "$tmp/"
case "$variant" in module17|commercial) ;; *) cp "$base/asterisk.sql.gz" "$tmp/" ;; esac
extra=()

case "$variant" in
  macro)
    work="$tmp/data"
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
    tar --numeric-owner -C "$work" -czf "$tmp/data.tar.gz" .
    chmod -R u+w "$work" && rm -rf "$work"   # the unpacked tree holds read-only dirs
    ;;
  diskfull)
    cp "$base/data.tar.gz" "$tmp/"
    # space on a 4 KB block filesystem: every file and directory rounded up to a block
    bytes=$(tar -tvzf "$base/data.tar.gz" | awk '{s += int(($3 + 4095) / 4096) * 4096 + ($1 ~ /^d/ ? 4096 : 0)} END {print s}')
    # room for the data plus 5% and 16 MB of slack: far less than a second copy
    extra+=("volume_size_mb=$(( bytes * 105 / 100 / 1048576 + 16 ))" "data_size_mb=$(( bytes / 1048576 ))")
    ;;
  module17|commercial)
    if [ "$variant" == commercial ]; then
      module=queuestats version=16.0.3 repo=commercial license=Commercial name="Queue Stats"
    else
      module=irc version=16.0.1 repo=unsupported license=GPLv3+ name=IRC
    fi
    # the dump ends with the tables already created: one more row in "modules"
    { gzip -dc "$base/asterisk.sql.gz"
      echo "INSERT INTO \`modules\` (\`modulename\`, \`version\`, \`enabled\`, \`signature\`) VALUES ('$module','$version',1,NULL);"
    } | gzip -n > "$tmp/asterisk.sql.gz"
    work="$tmp/module"
    dir="./var/www/html/admin/modules/$module"
    mkdir -p "$work/$dir"
    cat > "$work/$dir/module.xml" <<XML
<module>
	<rawname>$module</rawname>
	<repo>$repo</repo>
	<name>$name</name>
	<version>$version</version>
	<publisher>Sangoma Technologies Corporation</publisher>
	<license>$license</license>
	<category>Support</category>
	<description>fixture variant $variant</description>
	<supported>
		<version>16.0</version>
	</supported>
</module>
XML
    gzip -dc "$base/data.tar.gz" > "$tmp/data.tar"
    tar --numeric-owner --owner=1000 --group=1000 -C "$work" -rf "$tmp/data.tar" "$dir"
    gzip -n "$tmp/data.tar"
    rm -rf "${work:?}"
    if [ "$variant" == commercial ]; then extra+=("anomaly=commercial module $module $version, no license")
    else extra+=("anomaly=module $module $version has no FreePBX 17 release"); fi
    ;;
  phonebook|speeddial)
    work="$tmp/pb" db=./var/lib/asterisk/astdb.sqlite3
    mkdir -p "$work"
    gzip -dc "$base/data.tar.gz" > "$tmp/data.tar"
    tar -C "$work" -xf "$tmp/data.tar" "$db"
    python3 -I - "$work/$db" "$variant" <<'PY'
import sqlite3, sys
keys = {'phonebook': [('/cidname/0612340001', 'Rossi Mario'), ('/cidname/0612340002', 'Bianchi Anna'),
                      ('/cidname/1003', 'Fixture Three (phonebook)'), ('/sysspeeddials/11', '1003')],
        'speeddial': [('/sysspeeddials/12', '1002'), ('/AMPUSER/1001/speeddials/5', '0612349999')]}
db = sqlite3.connect(sys.argv[1])
for key, value in keys[sys.argv[2]]:
    db.execute('INSERT OR REPLACE INTO astdb (key, value) VALUES (?, ?)', (key, value))
db.commit()
PY
    tar --delete -f "$tmp/data.tar" "$db"
    tar --numeric-owner --owner=1000 --group=1000 -C "$work" -rf "$tmp/data.tar" "$db"
    gzip -n "$tmp/data.tar"
    chmod -R u+w "$work" && rm -rf "${work:?}"
    if [ "$variant" == phonebook ]; then
      extra+=("anomaly=phonebook: 3 entries (cidname), speed dial 11 -> 1003 (sysspeeddials)" "phonebook_entries=3")
    else
      extra+=("anomaly=speeddial: system 12 -> 1002, personal 1001/5 -> 0612349999" "speeddials_system=1" "speeddials_personal=1")
    fi
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
  (cd "$tmp" && sha256sum asterisk.sql.gz asteriskcdrdb.sql.gz data.tar.gz)
} > "$tmp/manifest.txt"
# another run may have derived the same variant meanwhile: keep that one
if same_inputs; then rm -rf "${tmp:?}"; echo "derive-variant: $dest (reused)"; exit 0; fi
# replace by renames: the old variant set aside, then the new one moved in;
# if another run moved its own in first, keep that one
old=$(mktemp -u "$dest.old.XXXXXX")
[ ! -e "$dest" ] || mv -T "$dest" "$old" 2>/dev/null || true
if ! mv -T "$tmp" "$dest" 2>/dev/null; then
  same_inputs || { echo "derive-variant: cannot replace $dest" >&2; exit 1; }
  echo "derive-variant: $dest (reused)"; exit 0
fi
[ ! -d "$old" ] || { chmod -R u+w "$old"; rm -rf "${old:?}"; }
echo "derive-variant: $dest"
