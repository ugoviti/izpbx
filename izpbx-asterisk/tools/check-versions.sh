#!/bin/bash
# The versions written in the README, in docs/*.md and in the deploy files
# (izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy) are the current ones:
#   izPBX    every reference of the version series of IZPBX_VERSION (default.env):
#            image izpbx-asterisk:X.Y.Z, IZPBX_VERSION=X.Y.Z, ${IZPBX_VERSION:-X.Y.Z},
#            download URL .../ugoviti/izpbx/X.Y.Z/ is IZPBX_VERSION
#            (tools/make-release.sh moves them at every release);
#   MariaDB  every image mariadb:X.Y.Z, MARIADB_VERSION=X.Y.Z, ${MARIADB_VERSION:-X.Y.Z}
#            out of a comment line is MARIADB_VERSION (changed by hand: change them all).
# Versions in prose ("from 22.17.0", "20.16.22"), release candidates (X.Y.Z-rcN),
# series tags (izpbx-asterisk:22.17) and other series (20.16) are not checked.
#
#   izpbx-asterisk/tools/check-versions.sh [ROOT]   exit 1 listing every stale reference
# Run by tests/lint.sh (pre-commit) and by P7-09 after a release.

set -Eeuo pipefail
root=$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/../..}" && pwd)
cd "$root"
deploy="izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy"
env=$deploy/default.env
[ -f "$env" ] || { echo "check-versions: $env not found" >&2; exit 2; }
izpbx=$(sed -n 's/^IZPBX_VERSION=//p' "$env" | tail -1)
mariadb=$(sed -n 's/^MARIADB_VERSION=//p' "$env" | tail -1)
[ -n "$izpbx" ] && [ -n "$mariadb" ] || { echo "check-versions: no IZPBX_VERSION or MARIADB_VERSION in $env" >&2; exit 2; }
series=${izpbx%.*}; sq=${series//./\\.}

files=()
for f in README.md docs/*.md "$deploy/compose.yml" "$env"; do [ -f "$f" ] && files+=("$f"); done

rc=0
# stale FILE:LINE:REFERENCE WANT
report() { echo "check-versions: $1 (want $2)" >&2; rc=1; }
while IFS= read -r hit; do
  v=$(sed -E 's/.*(izpbx-asterisk:|IZPBX_VERSION=|IZPBX_VERSION:-|ugoviti\/izpbx\/)//; s/[^0-9.a-z-].*$//; s/\/$//' <<< "${hit#*:*:}")
  [[ "$v" == *-rc* ]] && continue   # a release candidate: history, as for make-release.sh
  [ "$v" == "$izpbx" ] || report "$hit" "$izpbx"
done < <(grep -noE "(izpbx-asterisk:|IZPBX_VERSION=|IZPBX_VERSION:-|ugoviti/izpbx/)${sq}\.[0-9]+(-rc[0-9]+)?" "${files[@]}" || true)
while IFS= read -r hit; do
  v=$(sed -E 's/.*(mariadb:|MARIADB_VERSION=|MARIADB_VERSION:-)//' <<< "${hit#*:*:}")
  [ "$v" == "$mariadb" ] || report "$hit" "$mariadb"
done < <(grep -nE "(mariadb:|MARIADB_VERSION=|MARIADB_VERSION:-)[0-9]+\.[0-9]+\.[0-9]+" "${files[@]}" |
         grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' |
         sed -E 's/^([^:]+:[0-9]+:).*((mariadb:|MARIADB_VERSION=|MARIADB_VERSION:-)[0-9]+\.[0-9]+\.[0-9]+).*/\1\2/' || true)
[ "$rc" -ne 0 ] || echo "check-versions: izPBX $izpbx, MariaDB $mariadb everywhere"
exit "$rc"
