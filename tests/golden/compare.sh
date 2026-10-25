#!/usr/bin/env bash
# Golden comparison of the whole .env matrix (P3-25, T16):
#   tests/golden/compare.sh IMAGE OUTDIR CASE...    (no CASE: every case)
# For each case: a 22.17 container runs izpbx-init --dry-run with
# tests/golden/cases/<case>.env (hostname izpbx-golden, as the 20.16.22
# capture), then every file of the case's "# expect:" list is compared through
# map/files.sh. OUTDIR/<case>.diff holds the differences. Exit 1 if any case
# differs or has a file without a rule.
set -Eeuo pipefail
image=$1 out=$2; shift 2
# TEST_GOLDEN_DIR: another tree with the same layout (the negative checks)
golden=${TEST_GOLDEN_DIR:-$(cd "$(dirname "$0")" && pwd)}
if [ $# -eq 0 ]; then
  for f in "$golden"/cases/*.env; do f=${f##*/}; set -- "$@" "${f%.env}"; done
fi
mkdir -p "$out"
rc=0
for case in "$@"; do
  files=$(sed -n 's/^# expect: //p' "$golden/cases/$case.env")
  read -r -a list <<< "$files"
  docker run --rm --entrypoint "" --hostname izpbx-golden --env-file "$golden/cases/$case.env" \
    -v "$golden:/golden:ro" "$image" bash -c '
      izpbx-init --dry-run >/tmp/init.log 2>&1 || { echo "izpbx-init failed:"; tail -20 /tmp/init.log; exit 1; }
      case=$1; shift; rc=0
      for f in "$@"; do
        o=$(/golden/map/files.sh old "/golden/20.16.22/$case/files" "$f" 2>&1) || { echo "== $f: $o"; rc=1; continue; }
        [ -n "$o" ] || { echo "== $f: empty 20.16.22 view"; rc=1; continue; }
        n=$(/golden/map/files.sh new "" "$f" 2>&1) || true
        d=$(diff -u --label "20.16.22$f" --label "22.17$f" <(printf "%s\n" "$o") <(printf "%s\n" "$n")) || { echo "$d"; rc=1; }
      done
      exit $rc' _ "$case" "${list[@]}" > "$out/$case.diff" 2>&1 && r=0 || r=$?
  if [ "$r" -eq 0 ]; then
    printf '%-14s same     (%d files)\n' "$case" "${#list[@]}"
  else
    printf '%-14s DIFFERS  (%s)\n' "$case" "$out/$case.diff"; rc=1
  fi
done
exit $rc
