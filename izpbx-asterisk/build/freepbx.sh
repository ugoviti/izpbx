#!/bin/bash
# Stage "freepbx": the FreePBX 17 install tree in /usr/src/freepbx.
# Default modules and signatures: checklist item P1-08.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
load_versions "$here/../versions.env"

cache=/usr/src/download-cache
fetch_verified "https://mirror.freepbx.org/modules/packages/freepbx/freepbx-$FREEPBX_VER.0-latest.tgz" "$FREEPBX_SHA256" "$cache/freepbx-$FREEPBX_VER.tgz"
rm -rf /usr/src/freepbx
tar -xzf "$cache/freepbx-$FREEPBX_VER.tgz" -C /usr/src
got=$(grep -m1 -oE '<version>[^<]+' /usr/src/freepbx/module.xml | cut -d'>' -f2)
[ "$got" == "$FREEPBX_FRAMEWORK_VER" ] || build_die "FreePBX framework $got, expected $FREEPBX_FRAMEWORK_VER"
build_log "FreePBX framework $got in /usr/src/freepbx"
