#!/bin/bash
# Stage "builder": spandsp and Asterisk, installed into /staging.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
load_versions "$here/../versions.env"

: "${STAGING:=/staging}"
src=/usr/src/build
cache=/usr/src/download-cache
mkdir -p "$src" "$cache" "$STAGING"
export CC="ccache gcc" CXX="ccache g++" CCACHE_DIR=${CCACHE_DIR:-/root/.ccache}
# the libraries built here go to /usr/lib64, which the linker searches by
# default on x86_64 but not on aarch64 (P1-11): without this, configure
# checks fail there and modules such as res_fax_spandsp are silently skipped
export LIBRARY_PATH=/usr/lib64 PKG_CONFIG_PATH=/usr/lib64/pkgconfig
jobs=$(nproc)

## spandsp (T.38): needed by res_fax_spandsp at build time and at runtime
fetch_verified "https://sources.buildroot.net/spandsp/spandsp-$SPANDSP_VER.tar.gz" "$SPANDSP_SHA256" "$cache/spandsp-$SPANDSP_VER.tar.gz"
rm -rf "$src/spandsp" && mkdir -p "$src/spandsp"
tar -xzf "$cache/spandsp-$SPANDSP_VER.tar.gz" -C "$src/spandsp" --strip-components=1
cd "$src/spandsp"
./configure --prefix=/usr --libdir=/usr/lib64 >/dev/null
make -j"$jobs" >/dev/null
make install >/dev/null
make install DESTDIR="$STAGING" >/dev/null
ldconfig

## Asterisk
fetch_verified "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-$ASTERISK_VER.tar.gz" "$ASTERISK_SHA256" "$cache/asterisk-$ASTERISK_VER.tar.gz"
# bundled third-party sources, prefetched so configure does not download them
fetch_verified "https://raw.githubusercontent.com/asterisk/third-party/master/pjproject/$PJPROJECT_VER/pjproject-$PJPROJECT_VER.tar.bz2" "$PJPROJECT_SHA256" "$cache/pjproject-$PJPROJECT_VER.tar.bz2"
fetch_verified "https://raw.githubusercontent.com/asterisk/third-party/master/jansson/$JANSSON_VER/jansson-$JANSSON_VER.tar.bz2" "$JANSSON_SHA256" "$cache/jansson-$JANSSON_VER.tar.bz2"
rm -rf "$src/asterisk" && mkdir -p "$src/asterisk"
tar -xzf "$cache/asterisk-$ASTERISK_VER.tar.gz" -C "$src/asterisk" --strip-components=1
cd "$src/asterisk"

# format_mp3 sources: svn export at a pinned revision, verified as a tree
svn export -q -r "$ASTERISK_MP3_SVN_REV" https://svn.digium.com/svn/thirdparty/mp3/trunk addons/mp3
got=$(cd addons && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - mp3 | sha256sum | cut -d' ' -f1)
[ "$got" == "$ASTERISK_MP3_TREE_SHA256" ] || build_die "mp3 sources: tree sha256 $got, expected $ASTERISK_MP3_TREE_SHA256"
# same fixup as contrib/scripts/get_mp3_source.sh
grep -q ASTMM_LIBC addons/mp3/interface.c || sed -i -e '/#include "asterisk.h"/i#define ASTMM_LIBC ASTMM_REDIRECT' addons/mp3/interface.c

# AMI DBDel and CLI "database del" (ast_db_del2) log a WARNING when the key
# does not exist; FreePBX deletes queuehint and pausequeuehint of every device
# at each reload (queues module), one WARNING per device. Both callers already
# answer with an error, so the message goes to debug, as in ast_db_del.
sed -i -e 's|ast_log(LOG_WARNING, "AstDB key %s does not exist\\n", fullkey);|ast_debug(1, "AstDB key %s does not exist\\n", fullkey);|' main/db.c
grep -q 'ast_debug(1, "AstDB key %s does not exist' main/db.c || build_die "main/db.c: AstDB key warning not found, update the patch in asterisk.sh"

./configure --prefix=/usr --libdir=/usr/lib64 --with-pjproject-bundled --with-jansson-bundled \
  --with-download-cache="$cache" --with-externals-cache="$cache" >/dev/null
make menuselect.makeopts >/dev/null
while read -r action name; do
  menuselect/menuselect "--$action" "$name" menuselect.makeopts
done < <(sed -e 's/#.*//' "$here/asterisk-menuselect.txt" | grep -E '^(enable|disable)(-category)? ')
menuselect/menuselect --check-deps menuselect.makeopts
make -j"$jobs" >/dev/null
make install DESTDIR="$STAGING" >/dev/null
make samples DESTDIR="$STAGING" >/dev/null
# the sample Lua dialplan, without pbx_lua (asterisk-menuselect.txt)
rm -f "$STAGING/etc/asterisk/extensions.lua"
# headers for the addons built in this stage (addons.sh)
make install-headers >/dev/null
# Debian has /var/run -> /run: a real var/run directory in /staging cannot be
# copied over the symlink by "COPY --from=builder /staging/ /"
if [ -d "$STAGING/var/run" ] && [ ! -L "$STAGING/var/run" ]; then
  mkdir -p "$STAGING/run"
  cp -a "$STAGING/var/run/." "$STAGING/run/"
  rm -rf "$STAGING/var/run"
fi
# modules that depend on libraries found by configure: a failed check would
# drop them without an error
for m in res_fax_spandsp format_mp3 res_xmpp chan_pjsip res_config_odbc; do
  [ -f "$STAGING/usr/lib64/asterisk/modules/$m.so" ] || build_die "$m.so was not built (configure did not find its library?)"
done
build_log "Asterisk $ASTERISK_VER installed into $STAGING"
