#!/bin/bash
# Stage "runtime": s6-overlay (process supervisor, ENTRYPOINT /init). The
# noarch tarball and the one of this architecture, each pinned by sha256.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
load_versions "$here/../versions.env"
cache=/usr/src/download-cache
arch=$(build_arch)
base="https://github.com/just-containers/s6-overlay/releases/download/v$S6_OVERLAY_VER"

fetch_verified "$base/s6-overlay-noarch.tar.xz" "$S6_OVERLAY_SHA256_NOARCH" "$cache/s6-overlay-noarch-$S6_OVERLAY_VER.tar.xz"
fetch_verified "$base/s6-overlay-$arch.tar.xz" "$(arch_var S6_OVERLAY_SHA256)" "$cache/s6-overlay-$arch-$S6_OVERLAY_VER.tar.xz"
tar -C / -Jxpf "$cache/s6-overlay-noarch-$S6_OVERLAY_VER.tar.xz"
tar -C / -Jxpf "$cache/s6-overlay-$arch-$S6_OVERLAY_VER.tar.xz"
[ -x /init ] && [ -x /command/s6-svscan ] || build_die "s6-overlay: /init or s6-svscan missing after install"
build_log "s6-overlay $S6_OVERLAY_VER ($arch)"
