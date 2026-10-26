#!/usr/bin/env bash
# P1-04: the 22.17 multi-stage Dockerfile. "docker build izpbx-asterisk" with
# no arguments succeeds (T20); the Dockerfile has <= 150 lines, no "&& \"
# chains, the dockerfile:1 syntax line, the base/builder/freepbx/runtime
# stages, every external image pinned by digest (Debian = versions.env), every
# RUN calls a single build script, and hadolint is clean.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
dir="$REPO_DIR/izpbx-asterisk"
df="$dir/Dockerfile"

check_dockerfile() { # Dockerfile versions.env -> prints problems, exit 1 if any
  local f=$1 env=$2 rc=0 n debian
  n=$(wc -l < "$f"); [ "$n" -le 150 ] || { echo "$n lines (max 150)"; rc=1; }
  if grep -nE '&&[[:space:]]*\\$' "$f"; then echo '"&& \" chains'; rc=1; fi
  [ "$(head -1 "$f")" == "# syntax=docker/dockerfile:1" ] || { echo "first line is not '# syntax=docker/dockerfile:1'"; rc=1; }
  for s in base builder freepbx runtime; do
    grep -qiE "^FROM .+ AS $s\$" "$f" || { echo "missing stage $s"; rc=1; }
  done
  # FROM of an external image (not a stage name) must carry a digest
  while read -r img; do
    grep -qiE "^FROM .+ AS $img\$" "$f" && continue
    [[ "$img" == *@sha256:* ]] || { echo "FROM $img is not pinned by digest"; rc=1; }
  done < <(awk 'toupper($1)=="FROM"{print $2}' "$f")
  debian=$(sed -n 's/^DEBIAN_IMAGE=//p' "$env")
  grep -qE "^FROM $debian AS base\$" "$f" || { echo "base image differs from DEBIAN_IMAGE of versions.env ($debian)"; rc=1; }
  # every RUN (continuation lines joined) runs one script or ldconfig
  while read -r cmd; do
    [[ "$cmd" =~ ^(/usr/src/izpbx/build/[a-z0-9_-]+\.sh( [^\;\&\|]*)?|ldconfig)$ ]] || { echo "RUN is not a single build script: $cmd"; rc=1; }
  done < <(awk '/^RUN /{r=$0; while (r ~ /\\$/) {sub(/\\$/, "", r); getline l; r = r l} print r}' "$f" \
           | sed -E 's/^RUN +//; s/--mount=[^ ]+ +//g; s/^ +//; s/ +$//')
  return $rc
}

out=$(check_dockerfile "$df" "$dir/versions.env") && rc=0 || rc=$?
[ -z "$out" ] || log "$out"
assert_eq 0 "$rc" "Dockerfile structure and pinning"
mkdir -p "$work/lint"; cp "$df" "$work/lint/Dockerfile"
assert_cmd "hadolint is clean" -- "$TESTS_DIR/lint.sh" "$work/lint"
assert_cmd "docker build izpbx-asterisk (no build arguments) succeeds" -- docker build -q -t izpbx-asterisk:p1-04 "$dir"
assert_eq "Asterisk 22.11.0" "$(docker run --rm --entrypoint "" izpbx-asterisk:p1-04 asterisk -V)" "the built image runs Asterisk 22.11.0"

# negatives on copies
{ cat "$df"; printf 'RUN apt-get update && \\\n    true\n'; } > "$work/chain"
sed -E 's|^FROM docker.io/library/debian:bookworm-slim@sha256:[0-9a-f]+ AS base|FROM debian:bookworm-slim AS base|' "$df" > "$work/tag"
sed -E 's/ AS freepbx$/ AS fpbx/' "$df" > "$work/stage"
sed -E 's|^    /usr/src/izpbx/build/extras.sh$|    /usr/src/izpbx/build/extras.sh; rm -rf /tmp/x|' "$df" > "$work/multi"
for c in chain tag stage multi; do
  assert_cmd_fails "a Dockerfile with a $c defect is rejected" -- check_dockerfile "$work/$c" "$dir/versions.env"
done

finish
