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

  mkdir -p "$(dirname "$dest")"
  for attempt in $(seq 1 "$FETCH_RETRIES"); do
    rm -f "$dest.part"
    if curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 \
         --connect-timeout "$FETCH_CONNECT_TIMEOUT" -o "$dest.part" "$url"; then
      break
    fi
    build_log "download failed ($attempt/$FETCH_RETRIES): $url"
    [ "$attempt" -lt "$FETCH_RETRIES" ] && sleep "$FETCH_RETRY_DELAY"
  done
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
