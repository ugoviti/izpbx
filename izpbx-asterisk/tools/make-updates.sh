#!/bin/bash
# Compare izpbx-asterisk/versions.env with upstream and propose updates.
#
#   izpbx-asterisk/tools/make-updates.sh [--apply] [--versions FILE] [--no-modules]
#
# Prints one line per component of versions.env: current, latest, status
# (ok | UPDATE | manual | unavailable), and for every UPDATE the new KEY=value
# lines with the sha256 of the new files. "manual" = no automatic source,
# "unavailable" = the upstream lookup failed (e.g. GitHub API rate limit).
# When Asterisk has an update, pjproject and jansson follow the versions of its
# tarball (third-party/versions.mak). With the default versions.env the FreePBX
# modules pinned in izpbx-asterisk/build/freepbx-modules.txt are checked too (--no-modules
# skips them: the FreePBX mirror can be slow).
#
# --apply writes the proposed lines into versions.env (only KEY=value lines
# already present; every value checked, nothing written if one is missing or
# invalid) and refreshes build/freepbx-modules.txt. Then: rebuild the image
# and run the tests (izpbx-asterisk/tests/run.sh all-done) before committing.
#
# Exit code: 0 all current (or, with --apply, updates applied), 10 updates
# available, 2 incomplete (lookups unavailable), 1 error. GITHUB_TOKEN
# (optional) raises the GitHub API rate limit (60 requests/hour without it).

set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
img="$here/.."
versions="$img/versions.env"
apply='' modules=1
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --versions) versions=${2:?--versions FILE}; shift ;;
    --no-modules) modules= ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done
# the FreePBX module list belongs to the repository versions.env only
[ "$(realpath "$versions")" == "$(realpath "$img/versions.env")" ] || modules=
# shellcheck source=../build/lib.sh
. "$img/build/lib.sh"
load_versions "$versions"

updates=0
unavailable=0
proposals=()
propose_modules=()

row() { printf '%-22s %-44s %-44s %s\n' "$1" "$2" "$3" "$4"; }
report() { # component current latest [note]   (empty latest = manual check)
  local name=$1 cur=$2 new=$3 note=${4:-}
  if [ -z "$new" ]; then row "$name" "$cur" "?" "manual${note:+ ($note)}"
  elif [ "$cur" == "$new" ]; then row "$name" "$cur" "$new" "ok"
  else row "$name" "$cur" "$new" "UPDATE${note:+ ($note)}"; updates=$((updates + 1)); return 1
  fi
}
propose() { proposals+=("$@"); }
# lookup: like report, but an empty "latest" means the upstream lookup failed
lookup() { # component current latest source
  if [ -z "$3" ]; then row "$1" "$2" "?" "unavailable ($4)"; unavailable=$((unavailable + 1)); return 0; fi
  report "$1" "$2" "$3"
}
# every upstream request retries transient failures (timeouts, 5xx, 429,
# refused connections), not permanent ones such as a 403 rate limit
# curl messages are shown only when the request fails for good, not for the
# attempts that a retry recovers; a transfer stalled below 1 KB/s for 60 s is
# abandoned (a slow mirror that still moves is waited for)
fetch() {
  local err rc=0
  err=$(mktemp)
  curl -fsSL --connect-timeout 30 --speed-limit 1024 --speed-time 60 --retry 3 --retry-delay 2 --retry-connrefused "$@" 2>"$err" || rc=$?
  [ "$rc" -eq 0 ] || tail -n 1 "$err" >&2
  rm -f "$err"
  return "$rc"
}
# sha256 of a download; empty when the download fails (never the sha256 of an empty file)
sha_of() { local t; t=$(mktemp); if fetch --proto '=https' -o "$t" "$1"; then sha256sum "$t" | cut -d' ' -f1; fi; rm -f "$t"; }

gh_api() { # path
  fetch ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    -H 'Accept: application/vnd.github+json' "https://api.github.com/$1"
}
# responses are read whole before filtering ("curl | grep -m1" ends in SIGPIPE)
gh_latest_release() { local j; j=$(gh_api "repos/$1/releases/latest") || return 1; grep -m1 -oE '"tag_name": *"[^"]+"' <<< "$j" | cut -d'"' -f4; }
gh_latest_tag() { local j; j=$(gh_api "repos/$1/tags?per_page=100") || return 1; grep -oE '"name": *"[^"]+"' <<< "$j" | cut -d'"' -f4 | grep -E '^v?[0-9]+(\.[0-9]+)*$' | sort -V | tail -1; }
gh_head() { local j; j=$(gh_api "repos/$1/commits/$2") || return 1; grep -m1 -oE '"sha": *"[0-9a-f]{40}"' <<< "$j" | cut -d'"' -f4; }

row COMPONENT CURRENT LATEST STATUS

# --- base image
new=$(docker buildx imagetools inspect docker.io/library/debian:bookworm-slim 2>/dev/null | awk '/^Digest:/{print $2; exit}' || true)
lookup DEBIAN_IMAGE "${DEBIAN_IMAGE##*@}" "$new" "docker hub" || propose "DEBIAN_IMAGE=docker.io/library/debian:bookworm-slim@$new"

# --- s6-overlay
new=$(gh_latest_release just-containers/s6-overlay | sed 's/^v//' || true)
if ! lookup S6_OVERLAY_VER "$S6_OVERLAY_VER" "$new" "GitHub API"; then
  propose "S6_OVERLAY_VER=$new"
  for a in noarch x86_64 aarch64; do
    propose "S6_OVERLAY_SHA256_${a^^}=$(fetch "https://github.com/just-containers/s6-overlay/releases/download/v$new/s6-overlay-$a.tar.xz.sha256" | cut -d' ' -f1)"
  done
fi

# --- Asterisk 22.x (stable releases only)
new=$(fetch https://downloads.asterisk.org/pub/telephony/asterisk/releases/ | grep -oE "asterisk-${ASTERISK_VER%%.*}\.[0-9]+\.[0-9]+\.tar\.gz\"" | tr -d '"' | sed 's/^asterisk-//; s/\.tar\.gz$//' | sort -V | tail -1 || true)
if [ -z "$new" ]; then
  lookup ASTERISK_VER "$ASTERISK_VER" "" downloads.asterisk.org
  report PJPROJECT_VER "$PJPROJECT_VER" "" "follows ASTERISK_VER" || true
  report JANSSON_VER "$JANSSON_VER" "" "follows ASTERISK_VER" || true
elif report ASTERISK_VER "$ASTERISK_VER" "$new"; then
  report PJPROJECT_VER "$PJPROJECT_VER" "$PJPROJECT_VER" || true
  report JANSSON_VER "$JANSSON_VER" "$JANSSON_VER" || true
else
  propose "ASTERISK_VER=$new" "ASTERISK_SHA256=$(fetch "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-$new.sha256" | cut -d' ' -f1)"
  # the bundled libraries follow the release: third-party/versions.mak of its tarball
  at=$(mktemp)
  vmak=$( { fetch --proto '=https' -o "$at" "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-$new.tar.gz" &&
            tar -xzOf "$at" "asterisk-$new/third-party/versions.mak"; } 2>/dev/null || true)
  rm -f "$at"
  for lib in PJPROJECT JANSSON; do
    cur_var="${lib}_VER"; lname=${lib,,}
    libnew=$(sed -n "s/^${lib}_VERSION=//p" <<< "$vmak" | tr -d '[:space:]')
    lookup "$cur_var" "${!cur_var}" "$libnew" "versions.mak of asterisk-$new" ||
      propose "${lib}_VER=$libnew" "${lib}_SHA256=$(sha_of "https://raw.githubusercontent.com/asterisk/third-party/master/$lname/$libnew/$lname-$libnew.tar.bz2")"
  done
fi
report ASTERISK_MP3_SVN_REV "$ASTERISK_MP3_SVN_REV" "" "svn info https://svn.digium.com/svn/thirdparty/mp3/trunk" || true

# --- addons
report SPANDSP_VER "$SPANDSP_VER" "" "git snapshot on sources.buildroot.net" || true
new=$(gh_latest_tag BelledonneCommunications/bcg729 || true)
lookup BCG729_VER "$BCG729_VER" "$new" "GitHub API" || propose "BCG729_VER=$new" "BCG729_SHA256=$(sha_of "https://github.com/BelledonneCommunications/bcg729/archive/$new.tar.gz")"
new=$(gh_head arkadijs/asterisk-g72x master || true)
lookup ASTERISK_G72X_VER "$ASTERISK_G72X_VER" "$new" "GitHub API" || propose "ASTERISK_G72X_VER=$new" "ASTERISK_G72X_SHA256=$(sha_of "https://github.com/arkadijs/asterisk-g72x/archive/$new.tar.gz")"
new=$(gh_head "$ASTERISK_CHAN_DONGLE_REPO" master || true)
lookup ASTERISK_CHAN_DONGLE_VER "$ASTERISK_CHAN_DONGLE_VER" "$new" "GitHub API" || propose "ASTERISK_CHAN_DONGLE_VER=$new" "ASTERISK_CHAN_DONGLE_SHA256=$(sha_of "https://github.com/$ASTERISK_CHAN_DONGLE_REPO/archive/$new.tar.gz")"
new=$(gh_latest_release irontec/sngrep | sed 's/^v//' || true)
lookup SNGREP_VER "$SNGREP_VER" "$new" "GitHub API" || propose "SNGREP_VER=$new" "SNGREP_SHA256=$(sha_of "https://github.com/irontec/sngrep/releases/download/v$new/sngrep-$new.tar.gz")"

# --- FreePBX: the mirror only has "17.0-latest", so compare the content
fpbx=https://mirror.freepbx.org/modules/packages/freepbx/freepbx-${FREEPBX_VER}.0-latest.tgz
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
if fetch -o "$tmp" "$fpbx"; then
  new=$(tar -xzOf "$tmp" freepbx/module.xml 2>/dev/null | grep -m1 -oE '<version>[^<]+' | cut -d'>' -f2 || true)
  row FREEPBX_VER "$FREEPBX_VER" "$FREEPBX_VER" "ok"
  report FREEPBX_FRAMEWORK_VER "$FREEPBX_FRAMEWORK_VER" "$new" || propose "FREEPBX_FRAMEWORK_VER=$new" "FREEPBX_SHA256=$(sha256sum "$tmp" | cut -d' ' -f1)"
else
  # every component has its row, also when the mirror does not answer
  lookup FREEPBX_VER "$FREEPBX_VER" "" mirror.freepbx.org
  lookup FREEPBX_FRAMEWORK_VER "$FREEPBX_FRAMEWORK_VER" "" mirror.freepbx.org
fi

# --- FreePBX modules pre-downloaded into the image (build/freepbx-modules.txt):
# for every module listed there, the latest FreePBX release on the mirror (queried
# like Module Admin does: POST phpver to all-<ver>.0.xml). A line with the module
# name only (a new module) gets its version and sha256 with --apply.
mlist="$img/build/freepbx-modules.txt"
mod_new=()
if [ -n "$modules" ]; then
  nmod=$(grep -vcE '^(#|$)' "$mlist" || true)
  mxml=$(mktemp)
  if fetch --proto '=https' -X POST -d "phpver=8.2" -o "$mxml" "https://mirror.freepbx.org/all-$FREEPBX_VER.0.xml"; then
    # "rawname version location" of the <module> entries (not edge/previous)
    mapfile -t mlatest < <(python3 -I - "$mxml" <<'PY'
import sys, xml.etree.ElementTree as ET
# FreePBX 16 lists <module> entries; FreePBX 17 wraps one element per module
# (named after it) in a single <module>
for top in ET.parse(sys.argv[1]).getroot().findall('module'):
    for m in ([top] if top.find('rawname') is not None else list(top)):
        if m.findtext('rawname'):
            print(m.findtext('rawname'), m.findtext('version'), m.findtext('location'))
PY
)
    missing=''
    while read -r name cur sha _; do
      [[ -z "$name" || "$name" == \#* ]] && continue
      line=$(printf '%s\n' "${mlatest[@]}" | awk -v n="$name" '$1 == n' | head -1)
      [ -n "$line" ] || { missing+=" $name"; continue; }
      read -r _ ver loc <<< "$line"
      if [ "$ver" != "${cur:-}" ] || [ -z "${sha:-}" ]; then
        mod_new+=("$name $ver $loc"); propose_modules+=("$name: ${cur:-new} -> $ver")
      fi
    done < "$mlist"
    if [ -n "$missing" ]; then
      row FREEPBX_MODULES "$nmod modules" "?" "ERROR: not on the FreePBX $FREEPBX_VER mirror:$missing"
      unavailable=$((unavailable + 1)); mod_new=()
    elif [ ${#mod_new[@]} -eq 0 ]; then
      row FREEPBX_MODULES "$nmod modules" "$nmod modules" "ok"
    else
      row FREEPBX_MODULES "$nmod modules" "${#mod_new[@]} newer" "UPDATE (izpbx-asterisk/build/freepbx-modules.txt)"
      updates=$((updates + 1))
    fi
  else
    row FREEPBX_MODULES "$nmod modules" "?" "unavailable (mirror.freepbx.org)"; unavailable=$((unavailable + 1))
  fi
  rm -f "$mxml"
fi

# --- ionCube: the unversioned tarball holds the latest loaders; same sha256
# as the pinned versioned tarball means no update, otherwise read the version
# string ("version: X.Y.Z") from the PHP 8.2 loader
ic=$(mktemp)
if fetch -o "$ic" https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz; then
  if [ "$(sha256sum "$ic" | cut -d' ' -f1)" == "$IONCUBE_SHA256_X86_64" ]; then new=$IONCUBE_VER
  else new=$(tar -xzOf "$ic" ioncube/ioncube_loader_lin_8.2.so | grep -aoE 'version: [0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d' ' -f2 || true); fi
else
  new=
fi
rm -f "$ic"
if ! lookup IONCUBE_VER "$IONCUBE_VER" "$new" "ioncube.com"; then
  propose "IONCUBE_VER=$new" \
    "IONCUBE_SHA256_X86_64=$(sha_of "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64_$new.tar.gz")" \
    "IONCUBE_SHA256_AARCH64=$(sha_of "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_aarch64_$new.tar.gz")"
fi

# --- FOP2: the download links redirect to the current files
fop2_file() { fetch -I "https://www.fop2.com/$1" | grep -i '^location:.*download2' | tail -1 | grep -oE 'fop2-[0-9.]+-debian-[a-z0-9_]+\.tgz' || true; }
f=$(fop2_file download/debian64); new=$(sed -E 's/^fop2-([0-9.]+)-.*/\1/' <<< "$f")
lookup FOP2_VER "$FOP2_VER" "$new" "fop2.com" || propose "FOP2_VER=$new" "FOP2_SHA256_X86_64=$(sha_of "https://download2.fop2.com/$f")"
f=$(fop2_file 'file.php?file=24'); new=$(sed -E 's/^fop2-([0-9.]+)-.*/\1/' <<< "$f")
lookup FOP2_VER_AARCH64 "$FOP2_VER_AARCH64" "$new" "fop2.com" || propose "FOP2_VER_AARCH64=$new" "FOP2_SHA256_AARCH64=$(sha_of "https://download2.fop2.com/$f")"

# --- Zabbix: LTS major chosen by hand
report ZABBIX_VER "$ZABBIX_VER" "" "LTS branch, key $ZABBIX_GPG_FPR" || true

# --- npm: newest release of the major in versions.env (npm 11+ needs Node 20)
tags=$(fetch https://registry.npmjs.org/-/package/npm/dist-tags || true)
new=$(grep -oE "\"next-${NPM_VER%%.*}\": *\"[^\"]+\"" <<< "$tags" | cut -d'"' -f4 || true)
lookup NPM_VER "$NPM_VER" "$new" "registry.npmjs.org" || propose "NPM_VER=$new" "NPM_SHA256=$(sha_of "https://registry.npmjs.org/npm/-/npm-$new.tgz")"

# --- izPBX tools
new=$(gh_latest_tag ugoviti/izsynth || true)
lookup IZSYNTH_VER "$IZSYNTH_VER" "$new" "GitHub API" || propose "IZSYNTH_VER=$new" "IZSYNTH_SHA256=$(sha_of "https://github.com/ugoviti/izsynth/archive/$new.tar.gz")"
new=$(gh_head ugoviti/zabbix-templates main || true)
lookup ZABBIX_TEMPLATE_VER "$ZABBIX_TEMPLATE_VER" "$new" "GitHub API" || propose "ZABBIX_TEMPLATE_VER=$new" "ZABBIX_TEMPLATE_SHA256=$(sha_of "https://github.com/ugoviti/zabbix-templates/archive/$new.tar.gz")"

echo
[ "$unavailable" -eq 0 ] || echo "$unavailable lookup(s) unavailable: the report is incomplete" >&2
if [ "$updates" -eq 0 ]; then
  [ "$unavailable" -eq 0 ] || exit 2
  echo "all components are current"
  exit 0
fi
if [ ${#proposals[@]} -gt 0 ]; then
  echo "$updates update(s) available, proposed versions.env lines:"
  printf '  %s\n' "${proposals[@]}"
fi
if [ ${#propose_modules[@]} -gt 0 ]; then
  echo "FreePBX modules (izpbx-asterisk/build/freepbx-modules.txt):"
  printf '  %s\n' "${propose_modules[@]}"
fi
[ -n "$apply" ] || exit 10

# --- --apply: replace the KEY=value lines, all or nothing
for line in "${proposals[@]}"; do
  k=${line%%=*} v=${line#*=}
  [[ "$k" =~ ^[A-Z0-9_]+$ ]] || { echo "apply: invalid line '$line'" >&2; exit 1; }
  grep -q "^$k=" "$versions" || { echo "apply: $k is not in $versions" >&2; exit 1; }
  [ -n "$v" ] || { echo "apply: $k has no value (upstream lookup failed): nothing written" >&2; exit 1; }
  case "$k" in *_SHA256*) [[ "$v" =~ ^[0-9a-f]{64}$ ]] || { echo "apply: $k is not a sha256 ('$v'): nothing written" >&2; exit 1; } ;; esac
done
# module lines with the sha256 of the new packages, computed before writing anything
declare -A modline=()
for m in "${mod_new[@]}"; do
  read -r name ver loc <<< "$m"
  sha=$(sha_of "https://mirror.freepbx.org/modules/$loc")
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "apply: module $name $ver: download failed: nothing written" >&2; exit 1; }
  modline[$name]=$(printf '%-18s %-14s %s' "$name" "$ver" "$sha")
done
echo
if [ ${#proposals[@]} -gt 0 ]; then
  out=$(mktemp "$versions.XXXXXX")
  awk 'NR == FNR { i = index($0, "="); val[substr($0, 1, i - 1)] = substr($0, i + 1); next }
       !/^#/ && (i = index($0, "=")) > 1 && ((k = substr($0, 1, i - 1)) in val) { print k "=" val[k]; next }
       { print }' <(printf '%s\n' "${proposals[@]}") "$versions" > "$out"
  chmod --reference="$versions" "$out"
  mv -f "$out" "$versions"
  echo "applied ${#proposals[@]} line(s) to $versions"
fi
if [ ${#modline[@]} -gt 0 ]; then
  out=$(mktemp "$mlist.XXXXXX")
  while IFS= read -r l; do
    n=${l%% *}
    if [[ -n "$l" && "$l" != \#* && -n "${modline[$n]:-}" ]]; then echo "${modline[$n]}"; else echo "$l"; fi
  done < "$mlist" > "$out"
  chmod --reference="$mlist" "$out"
  mv -f "$out" "$mlist"
  echo "applied ${#modline[@]} module(s) to $mlist"
fi
echo "next: rebuild the image and run izpbx-asterisk/tests/run.sh all-done, then commit (git diff to review)"
[ "$unavailable" -eq 0 ] || exit 2
exit 0
