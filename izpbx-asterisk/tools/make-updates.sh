#!/bin/bash
# Compare izpbx-asterisk/versions.env with upstream and propose updates.
#
#   izpbx-asterisk/tools/make-updates.sh [--apply] [--versions FILE] [--no-modules]
#
# Prints one line per component of versions.env: current, latest, status
# (OK | UPDATE | manual | unavailable), and for every UPDATE the new KEY=value
# lines with the sha256 of the new files. "manual" = no automatic source,
# "unavailable" = the upstream lookup failed (e.g. GitHub API rate limit).
# When Asterisk has an update, pjproject, jansson and libjwt follow the versions
# of its release (third-party/versions.mak of the tag on GitHub, a raw file: no
# API request, no tarball download). With the default versions.env the FreePBX
# modules pinned in izpbx-asterisk/build/freepbx-modules.txt are checked too (--no-modules
# skips them: the FreePBX mirror can be slow).
#
# --apply writes the proposed lines into versions.env (only KEY=value lines
# already present; every value checked, nothing written if one is missing or
# invalid), the FROM line of the Dockerfile when DEBIAN_IMAGE changes (with the
# repository versions.env) and refreshes build/freepbx-modules.txt. Then: rebuild the image
# and run the tests (izpbx-asterisk/tests/run.sh all-done) before committing.
#
# New major releases of Asterisk (LTS only) and FreePBX (a new izPBX series, never
# proposed nor applied) are listed apart, one "MAJOR <component> <version>"
# line each, and do not change the exit code.
#
# Exit code: 0 all current (or, with --apply, updates applied), 10 updates
# available, 2 incomplete (lookups unavailable), 1 error. GITHUB_TOKEN
# (optional; else the token of "gh auth login", when gh is installed) raises the
# GitHub API rate limit (60 requests/hour without it, 5000 with it): once it is
# reached the remaining GitHub lookups are skipped, with one message.
# On a terminal the report is colored (NO_COLOR=1 disables it); long hashes are
# shortened to 12 characters in the table, never in the proposed lines.

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

# colors only on a terminal: CI and the tests read plain text
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then B=$'\e[1m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' C=$'\e[36m' M=$'\e[35m' N=$'\e[0m'
else B='' G='' Y='' R='' C='' M='' N=''; fi
short() { # sha256 digests and commit hashes: 12 hex characters
  case "$1" in
    sha256:*) printf '%s' "${1:0:19}" ;;
    *) if [[ "$1" =~ ^[0-9a-f]{40}$ ]]; then printf '%s' "${1:0:12}"; else printf '%s' "$1"; fi ;;
  esac
}
row() { # component current latest status
  local l='' s=''
  case "$4" in OK) s=$C ;; UPDATE*) l=$G s=$B$G ;; manual*) s=$Y ;; unavailable*|ERROR*) s=$R ;; esac
  printf '%-24s  %-19s  %s%-19s%s  %s%s%s\n' "$1" "$(short "$2")" "$l" "$(short "$3")" "${l:+$N}" "$s" "$4" "${s:+$N}"
}
title() { printf '%s%s%s\n' "$B" "$*" "$N"; }
report() { # component current latest [note]   (empty latest = manual check)
  local name=$1 cur=$2 new=$3 note=${4:-}
  if [ -z "$new" ]; then row "$name" "$cur" "?" "manual${note:+ ($note)}"
  elif [ "$cur" == "$new" ]; then row "$name" "$cur" "$new" "OK"
  else row "$name" "$cur" "$new" "UPDATE${note:+ ($note)}"; updates=$((updates + 1)); return 1
  fi
}
propose() { proposals+=("$@"); }
majors=()
major() { majors+=("MAJOR $*"); }
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
curl_opts=(--connect-timeout 30 --speed-limit 1024 --speed-time 60 --retry 3 --retry-delay 2 --retry-connrefused)
fetch() {
  local err rc=0
  err=$(mktemp)
  curl -fsSL "${curl_opts[@]}" "$@" 2>"$err" || rc=$?
  [ "$rc" -eq 0 ] || tail -n 1 "$err" >&2
  rm -f "$err"
  return "$rc"
}
# sha256 of a download; empty when the download fails (never the sha256 of an empty file)
sha_of() { local t; t=$(mktemp); if fetch --proto '=https' -o "$t" "$1"; then sha256sum "$t" | cut -d' ' -f1; fi; rm -f "$t"; }

# a 403/429 of the GitHub API is the rate limit: one message, then no more
# GitHub requests (a marker file, since the lookups run in subshells)
gh_limited=$(mktemp); trap 'rm -f "$gh_limited"' EXIT
[ -n "${GITHUB_TOKEN:-}" ] || GITHUB_TOKEN=$(gh auth token 2>/dev/null || true)
gh_api() { # path
  [ -s "$gh_limited" ] && return 1
  local j code
  j=$(curl -sSL "${curl_opts[@]}" -w '\n%{http_code}' ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    -H 'Accept: application/vnd.github+json' "https://api.github.com/$1") || return 1
  code=${j##*$'\n'}; j=${j%$'\n'*}
  case "$code" in
    2??) printf '%s\n' "$j" ;;
    403|429) echo 1 > "$gh_limited"
      # reset time from /rate_limit (a request that does not count)
      local reset hint=", set GITHUB_TOKEN or run gh auth login to raise the limit"
      [ -z "${GITHUB_TOKEN:-}" ] || hint=" (with a token)"
      reset=$(curl -sS --max-time 10 ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} https://api.github.com/rate_limit 2>/dev/null |
              grep -m1 -oE '"reset": *[0-9]+' | grep -oE '[0-9]+$' || true)
      [ -z "$reset" ] || hint=" until $(date -d "@$reset" +%H:%M)$hint"
      echo "GitHub API rate limit reached: GitHub lookups skipped$hint" >&2; return 1 ;;
    *) echo "GitHub API: HTTP $code for $1" >&2; return 1 ;;
  esac
}
# responses are read whole before filtering ("curl | grep -m1" ends in SIGPIPE)
gh_latest_release() { local j; j=$(gh_api "repos/$1/releases/latest") || return 1; grep -m1 -oE '"tag_name": *"[^"]+"' <<< "$j" | cut -d'"' -f4; }
gh_latest_tag() { local j; j=$(gh_api "repos/$1/tags?per_page=100") || return 1; grep -oE '"name": *"[^"]+"' <<< "$j" | cut -d'"' -f4 | grep -E '^v?[0-9]+(\.[0-9]+)*$' | sort -V | tail -1; }
gh_head() { local j; j=$(gh_api "repos/$1/commits/$2") || return 1; grep -m1 -oE '"sha": *"[0-9a-f]{40}"' <<< "$j" | cut -d'"' -f4; }

printf '%s%-24s  %-19s  %-19s  %s%s\n' "$B" COMPONENT CURRENT LATEST STATUS "$N"

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
ast_releases=$(fetch https://downloads.asterisk.org/pub/telephony/asterisk/releases/ | grep -oE 'asterisk-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz"' | tr -d '"' | sed 's/^asterisk-//; s/\.tar\.gz$//' | sort -uV || true)
new=$(grep -E "^${ASTERISK_VER%%.*}\." <<< "$ast_releases" | tail -1 || true)
# newer LTS majors (even numbers; izPBX follows the LTS lines only): the latest release of each
for m in $(cut -d. -f1 <<< "$ast_releases" | sort -un); do
  [ "$m" -gt "${ASTERISK_VER%%.*}" ] && [ $((m % 2)) -eq 0 ] || continue
  major ASTERISK "$(grep -E "^$m\." <<< "$ast_releases" | tail -1)" LTS
done
if [ -z "$new" ]; then
  lookup ASTERISK_VER "$ASTERISK_VER" "" downloads.asterisk.org
  report PJPROJECT_VER "$PJPROJECT_VER" "" "follows ASTERISK_VER" || true
  report JANSSON_VER "$JANSSON_VER" "" "follows ASTERISK_VER" || true
  report LIBJWT_VER "$LIBJWT_VER" "" "follows ASTERISK_VER" || true
elif report ASTERISK_VER "$ASTERISK_VER" "$new"; then
  report PJPROJECT_VER "$PJPROJECT_VER" "$PJPROJECT_VER" || true
  report JANSSON_VER "$JANSSON_VER" "$JANSSON_VER" || true
  report LIBJWT_VER "$LIBJWT_VER" "$LIBJWT_VER" || true
else
  propose "ASTERISK_VER=$new" "ASTERISK_SHA256=$(fetch "https://downloads.asterisk.org/pub/telephony/asterisk/releases/asterisk-$new.sha256" | cut -d' ' -f1)"
  # the bundled libraries follow the release: third-party/versions.mak of its tag
  vmak=$(fetch --proto '=https' "https://raw.githubusercontent.com/asterisk/asterisk/$new/third-party/versions.mak" 2>/dev/null || true)
  for lib in PJPROJECT JANSSON LIBJWT; do
    cur_var="${lib}_VER"; lname=${lib,,}
    # tarball type of asterisk/third-party: libjwt is a .tar.gz, the others .tar.bz2
    ext=tar.bz2; [ "$lib" == "LIBJWT" ] && ext=tar.gz
    libnew=$(sed -n "s/^${lib}_VERSION=//p" <<< "$vmak" | tr -d '[:space:]')
    lookup "$cur_var" "${!cur_var}" "$libnew" "versions.mak of asterisk-$new" ||
      propose "${lib}_VER=$libnew" "${lib}_SHA256=$(sha_of "https://raw.githubusercontent.com/asterisk/third-party/master/$lname/$libnew/$lname-$libnew.$ext")"
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
tmp=$(mktemp); trap 'rm -f "$tmp" "$gh_limited"' EXIT
if fetch -o "$tmp" "$fpbx"; then
  new=$(tar -xzOf "$tmp" freepbx/module.xml 2>/dev/null | grep -m1 -oE '<version>[^<]+' | cut -d'>' -f2 || true)
  row FREEPBX_VER "$FREEPBX_VER" "$FREEPBX_VER" "OK"
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
      row FREEPBX_MODULES "$nmod modules" "$nmod modules" "OK"
    else
      row FREEPBX_MODULES "$nmod modules" "${#mod_new[@]} newer" "UPDATE (izpbx-asterisk/build/freepbx-modules.txt)"
      updates=$((updates + 1))
    fi
  else
    row FREEPBX_MODULES "$nmod modules" "?" "unavailable (mirror.freepbx.org)"; unavailable=$((unavailable + 1))
  fi
  rm -f "$mxml"
fi

# --- ionCube: the unversioned tarball holds the latest loaders. Same ETag as
# the pinned versioned tarball (the same file on the server) means no update,
# without downloading 30 MB; otherwise same sha256 as the pin means no update,
# else read the version string ("version: X.Y.Z") from the PHP 8.2 loader
icurl=https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64
etag() { fetch -I "$1" 2>/dev/null | tr -d '\r' | grep -i '^etag:' | tail -1 | cut -d' ' -f2- || true; }
ic=$(mktemp)
e=$(etag "$icurl.tar.gz")
if [ -n "$e" ] && [ "$e" == "$(etag "${icurl}_$IONCUBE_VER.tar.gz")" ]; then
  new=$IONCUBE_VER
elif fetch -o "$ic" "$icurl.tar.gz"; then
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
# (one FOP2_VER for amd64 and arm64: the arm64 file is fop2-<ver>-debian12-aarch64.tgz)
fop2_file() { fetch -I "https://www.fop2.com/$1" | grep -i '^location:.*download2' | tail -1 | grep -oE 'fop2-[0-9.]+-debian[0-9]*-[a-z0-9_]+\.tgz' || true; }
f=$(fop2_file download/debian64); new=$(sed -E 's/^fop2-([0-9.]+)-.*/\1/' <<< "$f")
lookup FOP2_VER "$FOP2_VER" "$new" "fop2.com" || propose "FOP2_VER=$new" \
  "FOP2_SHA256_X86_64=$(sha_of "https://download2.fop2.com/$f")" \
  "FOP2_SHA256_AARCH64=$(sha_of "https://download2.fop2.com/fop2-$new-debian12-aarch64.tgz")"

# --- Zabbix: LTS major chosen by hand
report ZABBIX_VER "$ZABBIX_VER" "" "LTS branch, key $ZABBIX_GPG_FPR" || true

# --- npm: newest release of the major in versions.env (npm 11+ needs Node 20)
tags=$(fetch https://registry.npmjs.org/-/package/npm/dist-tags || true)
new=$(grep -oE "\"next-${NPM_VER%%.*}\": *\"[^\"]+\"" <<< "$tags" | cut -d'"' -f4 || true)
lookup NPM_VER "$NPM_VER" "$new" "registry.npmjs.org" || propose "NPM_VER=$new" "NPM_SHA256=$(sha_of "https://registry.npmjs.org/npm/-/npm-$new.tgz")"

# a newer FreePBX major on the mirror (freepbx-<N>.0-latest.tgz)
fpbx_next=$((FREEPBX_VER + 1))
if fetch -I -o /dev/null "https://mirror.freepbx.org/modules/packages/freepbx/freepbx-${fpbx_next}.0-latest.tgz" 2>/dev/null; then
  major FREEPBX "$fpbx_next" "mirror.freepbx.org"
fi

# --- izPBX tools
new=$(gh_latest_tag ugoviti/izsynth || true)
lookup IZSYNTH_VER "$IZSYNTH_VER" "$new" "GitHub API" || propose "IZSYNTH_VER=$new" "IZSYNTH_SHA256=$(sha_of "https://github.com/ugoviti/izsynth/archive/$new.tar.gz")"
new=$(gh_head ugoviti/zabbix-templates main || true)
lookup ZABBIX_TEMPLATE_VER "$ZABBIX_TEMPLATE_VER" "$new" "GitHub API" || propose "ZABBIX_TEMPLATE_VER=$new" "ZABBIX_TEMPLATE_SHA256=$(sha_of "https://github.com/ugoviti/zabbix-templates/archive/$new.tar.gz")"

echo
if [ ${#majors[@]} -gt 0 ]; then
  title "new major releases (a new izPBX series: not proposed, not applied):"
  for m in "${majors[@]}"; do printf '%s%s%s\n' "$B$M" "$m" "$N"; done
  echo
fi
[ "$unavailable" -eq 0 ] || echo "$unavailable lookup(s) unavailable: the report is incomplete" >&2
if [ "$updates" -eq 0 ]; then
  [ "$unavailable" -eq 0 ] || exit 2
  printf '%s%s%s\n' "$G" "all components are current" "$N"
  exit 0
fi
if [ ${#proposals[@]} -gt 0 ]; then
  title "$updates update(s) available, proposed versions.env lines:"
  for p in "${proposals[@]}"; do printf '  %s%s%s=%s\n' "$G" "${p%%=*}" "$N" "${p#*=}"; done
fi
if [ ${#propose_modules[@]} -gt 0 ]; then
  title "FreePBX modules (izpbx-asterisk/build/freepbx-modules.txt):"
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
  # the base image is pinned in the FROM line too (P1-04: equal to DEBIAN_IMAGE)
  dimg=$(printf '%s\n' "${proposals[@]}" | sed -n 's/^DEBIAN_IMAGE=//p')
  if [ -n "$dimg" ] && [ "$(realpath "$versions")" == "$(realpath "$img/versions.env")" ]; then
    df="$img/Dockerfile"
    grep -qE '^FROM [^ ]+ AS base$' "$df" || { echo "apply: no 'FROM ... AS base' line in $df" >&2; exit 1; }
    sed -i -E "s#^FROM [^ ]+ AS base\$#FROM $dimg AS base#" "$df"
    echo "applied DEBIAN_IMAGE to the FROM line of $df"
  fi
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
