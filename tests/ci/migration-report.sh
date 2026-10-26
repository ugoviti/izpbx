#!/usr/bin/env bash
# Table of the weekly migration job (P6-08): the result lines of
# tests/ci/checks/MIGRATE.sh ("VERSION<TAB>RESULT<TAB>DETAIL", one file per
# version) as "VERSION RESULT DETAIL", in version order.
#   tests/ci/migration-report.sh DIR [EXPECTED_VERSIONS...]
# Exit 1 when a version failed, or when an expected version has no result
# (its job did not run to the end): listed as "missing".
set -euo pipefail
dir=${1:?usage: $0 DIR [EXPECTED_VERSIONS...]}; shift
rc=0
lines=$(find "$dir" -type f -name 'migrate-*.txt' -exec cat {} + 2>/dev/null | grep -P '^[^\t]+\t[a-z]+\t' || true)
for v in "$@"; do
  grep -qP "^\Q$v\E\t" <<< "$lines" || lines+=$'\n'"$v"$'\tmissing\tno result: its job did not run to the end'
done
table=$(grep . <<< "$lines" | sort -t$'\t' -k1,1V | awk -F'\t' '{printf "%-9s %-8s %s\n", $1, $2, $3}')
printf '%s\n' "$table"
n_ok=$(grep -cE '^\S+ +ok ' <<< "$table" || true); n_bl=$(grep -cE '^\S+ +blocked ' <<< "$table" || true)
n_bad=$(grep -cE '^\S+ +(failed|missing) ' <<< "$table" || true)
echo "summary: $(grep -c . <<< "$table") version(s): $n_ok ok, $n_bl blocked with instructions, $n_bad failed or missing"
[ "$n_bad" -eq 0 ] || rc=1
exit "$rc"
