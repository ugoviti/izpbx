#!/bin/bash
# Stage "freepbx": the FreePBX 17 install tree in /usr/src/freepbx, with the
# modules of build/freepbx-modules.txt pre-downloaded for the offline install:
# each signed package is checked by sha256 and by its GPG signature (keys from
# the verified framework tarball, no keyserver), unpacked into
# amp_conf/htdocs/admin/modules/<name>, and kept in modules/_cache.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
load_versions "$here/../versions.env"

: "${FREEPBX_MODULES_LIST:=$here/freepbx-modules.txt}"
cache=/usr/src/download-cache
fpbx=/usr/src/freepbx
fetch_verified "https://mirror.freepbx.org/modules/packages/freepbx/freepbx-$FREEPBX_VER.0-latest.tgz" "$FREEPBX_SHA256" "$cache/freepbx-$FREEPBX_VER.tgz"
rm -rf "$fpbx"
tar -xzf "$cache/freepbx-$FREEPBX_VER.tgz" -C /usr/src
got=$(grep -m1 -oE '<version>[^<]+' "$fpbx/module.xml" | cut -d'>' -f2)
[ "$got" == "$FREEPBX_FRAMEWORK_VER" ] || build_die "FreePBX framework $got, expected $FREEPBX_FRAMEWORK_VER"

# signing keys trusted by the framework itself (GPG.class.php: $freepbxkey,
# $trustkeys, $fskeys); module packages are signed by 456D051E... (fskeys)
trusted="0BDE0BFA09946D732091E26E1588A7366BD35B34 2016349F5BC6F49340FCCAF99F9169F4B33B4659
456D051E9204C27C37D4811BB53D215A755231A3 072410D159E9DA63A459AB203DDB2122FE6D84F7 1013D73FECAC918A0A25823986CE877469D2EAD9"
trusted=${trusted//$'\n'/ }
gnupg=$(mktemp -d)
gpg --homedir "$gnupg" --quiet --import "$fpbx"/amp_conf/htdocs/admin/libraries/BMO/*.key 2>/dev/null

modules="$fpbx/amp_conf/htdocs/admin/modules"
mkdir -p "$modules/_cache"
n=0
while read -r name ver sha; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  [ -n "$sha" ] || build_die "$name: no version/sha256 in $FREEPBX_MODULES_LIST (run izpbx-asterisk/tools/make-updates.sh --apply)"
  pkg="$name-$ver.tgz.gpg"
  fetch_verified "https://mirror.freepbx.org/modules/packages/$name/$pkg" "$sha" "$cache/freepbx-modules/$pkg" \
    || build_die "cannot download module $name $ver"
  status=$(gpg --homedir "$gnupg" --batch --yes --status-fd 1 --output "$cache/$name.tgz" --decrypt "$cache/freepbx-modules/$pkg" 2>/dev/null) \
    || build_die "$name: GPG verification failed"
  signer=$(awk '$2=="VALIDSIG"{print $NF}' <<< "$status")
  [[ " $trusted " == *" $signer "* ]] || build_die "$name: not signed by a trusted FreePBX key (signer: ${signer:-none})"
  rm -rf "${modules:?}/$name" && mkdir -p "$modules/$name"
  tar -xzf "$cache/$name.tgz" -C "$modules/$name" --strip-components=1
  rm -f "$cache/$name.tgz"
  got=$(grep -m1 -oE '<version>[^<]+' "$modules/$name/module.xml" | cut -d'>' -f2)
  [ "$got" == "$ver" ] || build_die "$name: package holds version $got, expected $ver"
  cp -f "$cache/freepbx-modules/$pkg" "$modules/_cache/$pkg"
  n=$((n + 1))
done < "$FREEPBX_MODULES_LIST"
rm -rf "$gnupg"
build_log "FreePBX framework $FREEPBX_FRAMEWORK_VER + $n verified modules in $fpbx"
