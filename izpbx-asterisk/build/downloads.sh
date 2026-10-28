#!/bin/bash
# Stage "downloads": every file pinned in versions.env and freepbx-modules.txt,
# downloaded once into /downloads. The stages that use them mount /downloads
# as /usr/src/download-cache, where fetch_verified finds them ("cached").
#
# The stage depends only on versions.env, freepbx-modules.txt, lib.sh and this
# script, so the registry build cache keeps it when a build script changes:
# a release no longer downloads everything again from slow mirrors (the
# BuildKit cache mounts are empty in CI, every job creates a new builder).
#
# A new download in a build script belongs here too, with the same URL and
# destination: otherwise the build reports it (WARNING ... not in
# build/downloads.sh) and downloads it at every build.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
load_versions "$here/../versions.env"

# downloaded into the cache mount (kept across local builds), copied to $out
cache=/usr/src/download-cache
out=${DOWNLOADS_DIR:-/downloads}
arch=$(build_arch)
files=()
fetch() { fetch_verified "$1" "$2" "$3"; files+=("${3#"$cache"/}"); }

## asterisk.sh
fetch "https://sources.buildroot.net/spandsp/spandsp-$SPANDSP_VER.tar.gz" "$SPANDSP_SHA256" "$cache/spandsp-$SPANDSP_VER.tar.gz"
fetch "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-$ASTERISK_VER.tar.gz" "$ASTERISK_SHA256" "$cache/asterisk-$ASTERISK_VER.tar.gz"
fetch "https://raw.githubusercontent.com/asterisk/third-party/master/pjproject/$PJPROJECT_VER/pjproject-$PJPROJECT_VER.tar.bz2" "$PJPROJECT_SHA256" "$cache/pjproject-$PJPROJECT_VER.tar.bz2"
fetch "https://raw.githubusercontent.com/asterisk/third-party/master/jansson/$JANSSON_VER/jansson-$JANSSON_VER.tar.bz2" "$JANSSON_SHA256" "$cache/jansson-$JANSSON_VER.tar.bz2"
fetch "https://raw.githubusercontent.com/asterisk/third-party/master/libjwt/$LIBJWT_VER/libjwt-$LIBJWT_VER.tar.gz" "$LIBJWT_SHA256" "$cache/libjwt-$LIBJWT_VER.tar.gz"

## addons.sh
fetch "https://github.com/BelledonneCommunications/bcg729/archive/$BCG729_VER.tar.gz" "$BCG729_SHA256" "$cache/bcg729.tar.gz"
fetch "https://github.com/arkadijs/asterisk-g72x/archive/$ASTERISK_G72X_VER.tar.gz" "$ASTERISK_G72X_SHA256" "$cache/asterisk-g72x.tar.gz"
fetch "https://github.com/$ASTERISK_CHAN_DONGLE_REPO/archive/$ASTERISK_CHAN_DONGLE_VER.tar.gz" "$ASTERISK_CHAN_DONGLE_SHA256" "$cache/asterisk-chan-dongle.tar.gz"
fetch "https://github.com/irontec/sngrep/releases/download/v$SNGREP_VER/sngrep-$SNGREP_VER.tar.gz" "$SNGREP_SHA256" "$cache/sngrep.tar.gz"

## freepbx.sh
fetch "https://mirror.freepbx.org/modules/packages/freepbx/freepbx-$FREEPBX_VER.0-latest.tgz" "$FREEPBX_SHA256" "$cache/freepbx-$FREEPBX_VER.tgz"
while read -r name ver sha; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  [ -n "$sha" ] || build_die "$name: no version/sha256 in freepbx-modules.txt (run izpbx-asterisk/tools/make-updates.sh --apply)"
  pkg="$name-$ver.tgz.gpg"
  fetch "https://mirror.freepbx.org/modules/packages/$name/$pkg" "$sha" "$cache/freepbx-modules/$pkg"
done < "$here/freepbx-modules.txt"

## extras.sh
fetch "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_${arch//_/-}_$IONCUBE_VER.tar.gz" \
  "$(arch_var IONCUBE_SHA256)" "$cache/ioncube-$arch-$IONCUBE_VER.tar.gz"
fetch "https://registry.npmjs.org/npm/-/npm-$NPM_VER.tgz" "$NPM_SHA256" "$cache/npm-$NPM_VER.tgz"
fetch "https://github.com/ugoviti/izsynth/archive/$IZSYNTH_VER.tar.gz" "$IZSYNTH_SHA256" "$cache/izsynth-$IZSYNTH_VER.tar.gz"
fetch "https://github.com/ugoviti/zabbix-templates/archive/$ZABBIX_TEMPLATE_VER.tar.gz" "$ZABBIX_TEMPLATE_SHA256" \
  "$cache/zabbix-templates-$ZABBIX_TEMPLATE_VER.tar.gz"

## s6.sh
s6="https://github.com/just-containers/s6-overlay/releases/download/v$S6_OVERLAY_VER"
fetch "$s6/s6-overlay-noarch.tar.xz" "$S6_OVERLAY_SHA256_NOARCH" "$cache/s6-overlay-noarch-$S6_OVERLAY_VER.tar.xz"
fetch "$s6/s6-overlay-$arch.tar.xz" "$(arch_var S6_OVERLAY_SHA256)" "$cache/s6-overlay-$arch-$S6_OVERLAY_VER.tar.xz"

# only the files fetched above (the cache mount may hold older versions)
rm -rf "$out"
for f in "${files[@]}"; do
  mkdir -p "$(dirname "$out/$f")"
  cp -a "$cache/$f" "$out/$f"
done
touch "$out/.prefetched"
build_log "downloads: ${#files[@]} files in $out ($(du -sh "$out" | cut -f1))"
