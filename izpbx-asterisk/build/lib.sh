#!/bin/bash
# Shared helpers for the izPBX build scripts (build/*.sh). Source it:
#   . /usr/src/izpbx/build/lib.sh
#
# fetch_verified URL SHA256 DEST   download over HTTPS only, check the sha256
# build_arch                       x86_64 | aarch64 (TARGETARCH or uname -m)
# arch_var NAME                    value of NAME_X86_64 / NAME_AARCH64 for this arch
# load_versions [FILE]             export the KEY=value lines of versions.env

set -Eeuo pipefail

: "${FETCH_RETRIES:=5}"          # attempts for each download
: "${FETCH_RETRY_DELAY:=5}"      # seconds between attempts
: "${FETCH_CONNECT_TIMEOUT:=30}"
# every attempt but the last one is aborted when slower than FETCH_SLOW_SPEED
# bytes/s for FETCH_SLOW_TIME seconds: a new connection to a slow mirror is
# often fast (the 22.17.0-rc4 release spent 23 minutes on two downloads at a
# few tens of KB/s). The next attempt resumes the partial file.
: "${FETCH_SLOW_TIME:=30}"
: "${FETCH_SLOW_SPEED:=102400}"
# the last attempt accepts a slow server and is aborted only when stalled
# (under FETCH_STALL_SPEED bytes/s for FETCH_STALL_TIME seconds), which would
# otherwise hang the build forever
: "${FETCH_STALL_TIME:=60}"
: "${FETCH_STALL_SPEED:=1024}"
# present in a download cache filled by build/downloads.sh: a download made by
# another script is then reported, it is missing from build/downloads.sh
: "${FETCH_PREFETCH_MARK:=/usr/src/download-cache/.prefetched}"

build_log() { printf 'build: %s\n' "$*" >&2; }
build_die() { printf 'build: ERROR: %s\n' "$*" >&2; exit 1; }

# fetch_verified URL SHA256 DEST
# - only https:// URLs, also after redirects
# - the file is written to DEST.part and moved to DEST only when its sha256
#   matches: a wrong checksum leaves no file behind
# - an existing DEST with the right sha256 is kept (no download)
fetch_verified() {
  local url=${1:?url} sha=${2:?sha256} dest=${3:?destination} got attempt
  case "$url" in
    https://*) ;;
    *) build_log "refusing non-HTTPS URL: $url"; return 2 ;;
  esac
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { build_log "invalid sha256 '$sha' for $url"; return 2; }

  if [ -f "$dest" ] && [ "$(sha256sum "$dest" | cut -d' ' -f1)" == "$sha" ]; then
    build_log "cached: $dest"
    return 0
  fi

  [ -e "$FETCH_PREFETCH_MARK" ] && build_log "WARNING: $url is not in build/downloads.sh, downloading it now"

  mkdir -p "$(dirname "$dest")"
  rm -f "$dest.part"
  local speed time rc
  for attempt in $(seq 1 "$FETCH_RETRIES"); do
    if [ "$attempt" -lt "$FETCH_RETRIES" ]; then
      speed=$FETCH_SLOW_SPEED time=$FETCH_SLOW_TIME
    else
      speed=$FETCH_STALL_SPEED time=$FETCH_STALL_TIME
    fi
    rc=0
    curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
      --connect-timeout "$FETCH_CONNECT_TIMEOUT" --speed-limit "$speed" --speed-time "$time" \
      -C - -o "$dest.part" "$url" || rc=$?
    [ "$rc" -eq 0 ] && break
    # 33: the server does not resume, 36: bad resume offset -> start again
    case "$rc" in 33|36) rm -f "$dest.part" ;; esac
    build_log "download failed ($attempt/$FETCH_RETRIES, curl exit $rc, $(stat -c %s "$dest.part" 2>/dev/null || echo 0) bytes so far): $url"
    [ "$attempt" -lt "$FETCH_RETRIES" ] && sleep "$FETCH_RETRY_DELAY"
  done
  [ "$rc" -eq 0 ] || { rm -f "$dest.part"; build_log "giving up on $url"; return 1; }
  [ -s "$dest.part" ] || { rm -f "$dest.part"; build_log "giving up on $url"; return 1; }

  got=$(sha256sum "$dest.part" | cut -d' ' -f1)
  if [ "$got" != "$sha" ]; then
    rm -f "$dest.part"
    build_log "sha256 mismatch for $url: expected $sha, got $got"
    return 1
  fi
  mv -f "$dest.part" "$dest"
  build_log "verified: $dest ($sha)"
}

# x86_64 | aarch64, from the BuildKit TARGETARCH when set
build_arch() {
  local a=${TARGETARCH:-$(uname -m)}
  case "$a" in
    amd64|x86_64) echo x86_64 ;;
    arm64|aarch64) echo aarch64 ;;
    *) build_log "unsupported architecture: $a"; return 1 ;;
  esac
}

# arch_var NAME -> value of NAME_X86_64 or NAME_AARCH64
arch_var() {
  local name arch
  arch=$(build_arch | tr '[:lower:]' '[:upper:]')
  name="${1:?variable}_${arch}"
  [ -n "${!name:-}" ] || { build_log "$name is not defined"; return 1; }
  printf '%s\n' "${!name}"
}

# load_versions [FILE]: export every KEY=value of versions.env (no shell code runs)
load_versions() {
  local file=${1:-$(dirname "${BASH_SOURCE[0]}")/../versions.env} line
  [ -r "$file" ] || build_die "cannot read $file"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=([^[:space:]]+)$ ]] || build_die "bad line in $file: $line"
    export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
  done < "$file"
}

# pkg_list FILE -> package names, comments and blank lines removed
pkg_list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' "${1:?package list}" | grep -v '^$'; }

# apt_install FILE: install a package list without recommends (apt cache may be a BuildKit mount)
apt_install() {
  local pkgs
  mapfile -t pkgs < <(pkg_list "$1")
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
}
