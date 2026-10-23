#!/bin/bash
# Compare izpbx-asterisk/versions.env with upstream and propose updates.
#
#   build/check-updates.sh [--versions FILE]
#
# Prints one line per component of versions.env: current, latest, status
# (ok | UPDATE | manual), and for every UPDATE the new KEY=value lines with
# the sha256 of the new files. Exit code: 0 all current, 10 updates
# available, 1 error. GITHUB_TOKEN (optional) raises the GitHub API rate limit.

set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
versions="$here/../versions.env"
[ "${1:-}" == "--versions" ] && versions=${2:?--versions FILE}
# shellcheck source=lib.sh
. "$here/lib.sh"
load_versions "$versions"

updates=0
proposals=()

row() { printf '%-22s %-44s %-44s %s\n' "$1" "$2" "$3" "$4"; }
report() { # component current latest [note]
  local name=$1 cur=$2 new=$3 note=${4:-}
  if [ -z "$new" ]; then row "$name" "$cur" "?" "manual${note:+ ($note)}"
  elif [ "$cur" == "$new" ]; then row "$name" "$cur" "$new" "ok"
  else row "$name" "$cur" "$new" "UPDATE${note:+ ($note)}"; updates=$((updates + 1)); return 1
  fi
}
propose() { proposals+=("$@"); }
sha_of() { curl -fsSL --proto '=https' --connect-timeout 30 "$1" | sha256sum | cut -d' ' -f1; }

gh_api() { # path
  curl -fsSL --connect-timeout 30 ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    -H 'Accept: application/vnd.github+json' "https://api.github.com/$1"
}
# responses are read whole before filtering ("curl | grep -m1" ends in SIGPIPE)
gh_latest_release() { local j; j=$(gh_api "repos/$1/releases/latest") || return 1; grep -m1 -oE '"tag_name": *"[^"]+"' <<< "$j" | cut -d'"' -f4; }
gh_latest_tag() { local j; j=$(gh_api "repos/$1/tags?per_page=100") || return 1; grep -oE '"name": *"[^"]+"' <<< "$j" | cut -d'"' -f4 | grep -E '^v?[0-9]+(\.[0-9]+)*$' | sort -V | tail -1; }
gh_head() { local j; j=$(gh_api "repos/$1/commits/$2") || return 1; grep -m1 -oE '"sha": *"[0-9a-f]{40}"' <<< "$j" | cut -d'"' -f4; }

row COMPONENT CURRENT LATEST STATUS

# --- base image
new=$(docker buildx imagetools inspect docker.io/library/debian:bookworm-slim 2>/dev/null | awk '/^Digest:/{print $2; exit}' || true)
report DEBIAN_IMAGE "${DEBIAN_IMAGE##*@}" "$new" || propose "DEBIAN_IMAGE=docker.io/library/debian:bookworm-slim@$new"

# --- s6-overlay
new=$(gh_latest_release just-containers/s6-overlay | sed 's/^v//' || true)
if ! report S6_OVERLAY_VER "$S6_OVERLAY_VER" "$new"; then
  propose "S6_OVERLAY_VER=$new"
  for a in noarch x86_64 aarch64; do
    propose "S6_OVERLAY_SHA256_${a^^}=$(curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v$new/s6-overlay-$a.tar.xz.sha256" | cut -d' ' -f1)"
  done
fi

# --- Asterisk 22.x (stable releases only)
new=$(curl -fsSL https://downloads.asterisk.org/pub/telephony/asterisk/releases/ | grep -oE "asterisk-${ASTERISK_VER%%.*}\.[0-9]+\.[0-9]+\.tar\.gz\"" | tr -d '"' | sed 's/^asterisk-//; s/\.tar\.gz$//' | sort -V | tail -1 || true)
if ! report ASTERISK_VER "$ASTERISK_VER" "$new" "then refresh PJPROJECT/JANSSON from third-party/versions.mak"; then
  propose "ASTERISK_VER=$new" "ASTERISK_SHA256=$(curl -fsSL "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-$new.sha256" | cut -d' ' -f1)"
fi
report PJPROJECT_VER "$PJPROJECT_VER" "" "follows ASTERISK_VER" || true
report JANSSON_VER "$JANSSON_VER" "" "follows ASTERISK_VER" || true
report ASTERISK_MP3_SVN_REV "$ASTERISK_MP3_SVN_REV" "" "svn info https://svn.digium.com/svn/thirdparty/mp3/trunk" || true

# --- addons
report SPANDSP_VER "$SPANDSP_VER" "" "git snapshot on sources.buildroot.net" || true
new=$(gh_latest_tag BelledonneCommunications/bcg729 || true)
report BCG729_VER "$BCG729_VER" "$new" || propose "BCG729_VER=$new" "BCG729_SHA256=$(sha_of "https://github.com/BelledonneCommunications/bcg729/archive/$new.tar.gz")"
new=$(gh_head arkadijs/asterisk-g72x master || true)
report ASTERISK_G72X_VER "$ASTERISK_G72X_VER" "$new" || propose "ASTERISK_G72X_VER=$new" "ASTERISK_G72X_SHA256=$(sha_of "https://github.com/arkadijs/asterisk-g72x/archive/$new.tar.gz")"
new=$(gh_head "$ASTERISK_CHAN_DONGLE_REPO" master || true)
report ASTERISK_CHAN_DONGLE_VER "$ASTERISK_CHAN_DONGLE_VER" "$new" || propose "ASTERISK_CHAN_DONGLE_VER=$new" "ASTERISK_CHAN_DONGLE_SHA256=$(sha_of "https://github.com/$ASTERISK_CHAN_DONGLE_REPO/archive/$new.tar.gz")"
new=$(gh_latest_release irontec/sngrep | sed 's/^v//' || true)
report SNGREP_VER "$SNGREP_VER" "$new" || propose "SNGREP_VER=$new" "SNGREP_SHA256=$(sha_of "https://github.com/irontec/sngrep/releases/download/v$new/sngrep-$new.tar.gz")"

# --- FreePBX: the mirror only has "17.0-latest", so compare the content
fpbx=https://mirror.freepbx.org/modules/packages/freepbx/freepbx-${FREEPBX_VER}.0-latest.tgz
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
if curl -fsSL --connect-timeout 30 -o "$tmp" "$fpbx"; then
  new=$(tar -xzOf "$tmp" freepbx/module.xml 2>/dev/null | grep -m1 -oE '<version>[^<]+' | cut -d'>' -f2 || true)
  row FREEPBX_VER "$FREEPBX_VER" "$FREEPBX_VER" "ok"
  report FREEPBX_FRAMEWORK_VER "$FREEPBX_FRAMEWORK_VER" "$new" || propose "FREEPBX_FRAMEWORK_VER=$new" "FREEPBX_SHA256=$(sha256sum "$tmp" | cut -d' ' -f1)"
else
  report FREEPBX_FRAMEWORK_VER "$FREEPBX_FRAMEWORK_VER" "" "mirror unreachable" || true
fi

# --- ionCube: the unversioned tarball holds the latest loaders; same sha256
# as the pinned versioned tarball means no update, otherwise read the version
# string ("version: X.Y.Z") from the PHP 8.2 loader
ic=$(mktemp)
if curl -fsSL --connect-timeout 30 -o "$ic" https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz; then
  if [ "$(sha256sum "$ic" | cut -d' ' -f1)" == "$IONCUBE_SHA256_X86_64" ]; then new=$IONCUBE_VER
  else new=$(tar -xzOf "$ic" ioncube/ioncube_loader_lin_8.2.so | grep -aoE 'version: [0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d' ' -f2 || true); fi
else
  new=
fi
rm -f "$ic"
if ! report IONCUBE_VER "$IONCUBE_VER" "$new"; then
  propose "IONCUBE_VER=$new" \
    "IONCUBE_SHA256_X86_64=$(sha_of "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64_$new.tar.gz")" \
    "IONCUBE_SHA256_AARCH64=$(sha_of "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_aarch64_$new.tar.gz")"
fi

# --- FOP2: the download links redirect to the current files
fop2_file() { curl -fsSI -L "https://www.fop2.com/$1" | grep -i '^location:.*download2' | tail -1 | grep -oE 'fop2-[0-9.]+-debian-[a-z0-9_]+\.tgz' || true; }
f=$(fop2_file download/debian64); new=$(sed -E 's/^fop2-([0-9.]+)-.*/\1/' <<< "$f")
report FOP2_VER "$FOP2_VER" "$new" || propose "FOP2_VER=$new" "FOP2_SHA256_X86_64=$(sha_of "https://download2.fop2.com/$f")"
f=$(fop2_file 'file.php?file=24'); new=$(sed -E 's/^fop2-([0-9.]+)-.*/\1/' <<< "$f")
report FOP2_VER_AARCH64 "$FOP2_VER_AARCH64" "$new" "file $f" || propose "FOP2_VER_AARCH64=$new" "FOP2_SHA256_AARCH64=$(sha_of "https://download2.fop2.com/$f")"

# --- Zabbix: LTS major chosen by hand
report ZABBIX_VER "$ZABBIX_VER" "" "LTS branch, key $ZABBIX_GPG_FPR" || true

# --- izPBX tools
new=$(gh_latest_tag ugoviti/izsynth || true)
report IZSYNTH_VER "$IZSYNTH_VER" "$new" || propose "IZSYNTH_VER=$new" "IZSYNTH_SHA256=$(sha_of "https://github.com/ugoviti/izsynth/archive/$new.tar.gz")"
new=$(gh_head ugoviti/zabbix-templates main || true)
report ZABBIX_TEMPLATE_VER "$ZABBIX_TEMPLATE_VER" "$new" || propose "ZABBIX_TEMPLATE_VER=$new" "ZABBIX_TEMPLATE_SHA256=$(sha_of "https://github.com/ugoviti/zabbix-templates/archive/$new.tar.gz")"

echo
if [ "$updates" -eq 0 ]; then
  echo "all components are current"
  exit 0
fi
echo "$updates update(s) available, proposed versions.env lines:"
printf '  %s\n' "${proposals[@]}"
exit 10
