#!/bin/bash
# Stage "builder": Asterisk addons installed into /staging next to Asterisk:
# bcg729 (G.729 library), asterisk-g72x (codec_g729), chan-dongle, sngrep.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
load_versions "$here/../versions.env"

: "${STAGING:=/staging}"
src=/usr/src/build
cache=/usr/src/download-cache
mkdir -p "$src" "$cache"
export CC="ccache gcc" CXX="ccache g++" CCACHE_DIR=${CCACHE_DIR:-/root/.ccache}
jobs=$(nproc)
arch=$(build_arch)

unpack() { # name url sha256 -> extracted into $src/name, cwd there
  fetch_verified "$2" "$3" "$cache/$1.tar.gz"
  rm -rf "${src:?}/$1" && mkdir -p "$src/$1"
  tar -xzf "$cache/$1.tar.gz" -C "$src/$1" --strip-components=1
  cd "$src/$1"
}

## bcg729: installed in the builder (asterisk-g72x links to it) and in /staging
unpack bcg729 "https://github.com/BelledonneCommunications/bcg729/archive/$BCG729_VER.tar.gz" "$BCG729_SHA256"
cmake . -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_PREFIX_PATH=/usr \
  -DBUILD_SHARED_LIBS=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON >/dev/null
make -j"$jobs" >/dev/null
make install >/dev/null
make install DESTDIR="$STAGING" >/dev/null
ldconfig

## asterisk-g72x: codec_g729 on top of bcg729
unpack asterisk-g72x "https://github.com/arkadijs/asterisk-g72x/archive/$ASTERISK_G72X_VER.tar.gz" "$ASTERISK_G72X_SHA256"
./autogen.sh >/dev/null 2>&1
g72x_opts=(--prefix=/usr --libdir=/usr/lib64 --with-bcg729)
[ "$arch" == "x86_64" ] && g72x_opts+=(--disable-penryn)
./configure "${g72x_opts[@]}" >/dev/null
make -j"$jobs" >/dev/null
make install DESTDIR="$STAGING" >/dev/null

## chan-dongle (GSM USB dongles)
unpack asterisk-chan-dongle "https://github.com/$ASTERISK_CHAN_DONGLE_REPO/archive/$ASTERISK_CHAN_DONGLE_VER.tar.gz" "$ASTERISK_CHAN_DONGLE_SHA256"
./bootstrap >/dev/null 2>&1
# its Makefile hardcodes the module directory found by configure ("DESTDIR"),
# so the module is copied into /staging by hand
./configure --with-astversion="$ASTERISK_VER" DESTDIR=/usr/lib64/asterisk/modules >/dev/null
make -j"$jobs" >/dev/null
install -D -m 644 chan_dongle.so "$STAGING/usr/lib64/asterisk/modules/chan_dongle.so"

## sngrep (SIP capture TUI, D15)
unpack sngrep "https://github.com/irontec/sngrep/releases/download/v$SNGREP_VER/sngrep-$SNGREP_VER.tar.gz" "$SNGREP_SHA256"
./bootstrap.sh >/dev/null 2>&1
./configure --prefix=/usr >/dev/null
make -j"$jobs" >/dev/null
make install DESTDIR="$STAGING" >/dev/null

## Asterisk loads modules from /usr/lib64/asterisk/modules only
moddir="$STAGING/usr/lib64/asterisk/modules"
while IFS= read -r so; do
  [ "$(dirname "$so")" == "$moddir" ] && continue
  build_log "moving $(basename "$so") from ${so#"$STAGING"} to /usr/lib64/asterisk/modules"
  mv -f "$so" "$moddir/"
done < <(find "$STAGING" -path '*/asterisk/modules/*.so' -type f)
for m in codec_g729.so chan_dongle.so; do
  [ -f "$moddir/$m" ] || build_die "$m was not installed"
done
build_log "addons installed: bcg729 $BCG729_VER, codec_g729, chan_dongle, sngrep $SNGREP_VER"
