#!/bin/bash
# The README of the repository as the Docker Hub overview of izdock/izpbx-asterisk.
#
#   izpbx-asterisk/tools/readme-dockerhub.sh REF [README]   rewritten README on stdout
#
# Docker Hub does not resolve relative links: every relative link of README
# (default: README.md of the repository, "-" for stdin) is made absolute on
# GitHub at REF (a tag such as 22.17.0, or a branch): images to
# raw.githubusercontent.com/<repo>/REF/<path>, other links to
# github.com/<repo>/blob/REF/<path>. Absolute links, mailto: and in-page
# anchors (#...) are kept. Docker Hub refuses an overview over 25000 bytes:
# exit 1 when the result is bigger (the text is not printed).
# Used by the izpbx-promote workflow (Docker Hub overview) and by
# izpbx-asterisk/tests/lint.sh (size check). PUBLIC_REPO (default
# ugoviti/izpbx) is the GitHub repository.

set -Eeuo pipefail
die() { echo "readme-dockerhub: ERROR: $*" >&2; exit 1; }

: "${PUBLIC_REPO:=ugoviti/izpbx}"
: "${DOCKERHUB_OVERVIEW_MAX:=25000}"
ref=${1:-}
[ -n "$ref" ] && [[ "$ref" =~ ^[A-Za-z0-9._/-]+$ ]] || { sed -n '2,4p' "$0" | sed 's/^# \{0,1\}/usage: /' >&2; exit 2; }
src=${2:-$(cd "$(dirname "$0")/../.." && pwd)/README.md}
[ "$src" == - ] && src=/dev/stdin

# a relative target: does not start with a scheme (x:), "/" or "#"
rel='[^):/#[:space:]][^):[:space:]]*'
out=$(sed -E \
  -e "s#(!\\[[^]]*\\]\\()($rel)\\)#\\1https://raw.githubusercontent.com/$PUBLIC_REPO/$ref/\\2)#g" \
  -e "s#(\\]\\()($rel)\\)#\\1https://github.com/$PUBLIC_REPO/blob/$ref/\\2)#g" \
  "$src")
size=$(printf '%s\n' "$out" | wc -c)
[ "$size" -le "$DOCKERHUB_OVERVIEW_MAX" ] ||
  die "the Docker Hub overview is $size bytes, over the limit of $DOCKERHUB_OVERVIEW_MAX: move sections of README.md into docs/"
printf '%s\n' "$out"
