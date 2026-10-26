#!/usr/bin/env bash
# P1-01: izpbx-asterisk/versions.env holds every component version and
# checksum: plain KEY=value lines, every *_SHA256* is 64 hex chars, every
# *_VER / *_SHA256* used by build/*.sh is defined, and the 22.17 Dockerfile
# (once it exists, P1-04) declares no "ARG <NAME>_VER=" default.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
dir="$REPO_DIR/izpbx-asterisk"

check_versions() { # versions.env build_dir dockerfile -> prints problems, exit 1 if any
  local env=$1 build=$2 df=$3 rc=0 line v
  [ -s "$env" ] || { echo "missing $env"; return 1; }
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*=[^[:space:]\"\'\`\$\;\&\|]+$ ]] || { echo "not a plain KEY=value line: $line"; rc=1; }
  done < "$env"
  while IFS='=' read -r k v; do
    [[ "$v" =~ ^[0-9a-f]{64}$ ]] || { echo "$k is not a sha256: '$v'"; rc=1; }
  done < <(grep -E '^[A-Z0-9_]*SHA256[A-Z0-9_]*=' "$env")
  while IFS='=' read -r k v; do
    [[ "$v" =~ ^[0-9A-F]{40}$ ]] || { echo "$k is not a 40 hex GPG fingerprint: '$v'"; rc=1; }
  done < <(grep -E '^[A-Z0-9_]*_FPR=' "$env")
  for v in $(grep -rhoE '\$\{?[A-Z][A-Z0-9_]*(_VER|SHA256[A-Z0-9_]*)\b' "$build" 2>/dev/null | tr -d '${' | sort -u); do
    grep -q "^$v=" "$env" || { echo "$v is used in $build but not defined in versions.env"; rc=1; }
  done
  if [ -f "$df" ] && grep -nE '^ARG [A-Z0-9_]+_VER=' "$df"; then echo "versions declared in $df"; rc=1; fi
  return $rc
}

out=$(check_versions "$dir/versions.env" "$dir/build" "$dir/Dockerfile") && rc=0 || rc=$?
[ -z "$out" ] || log "$out"
assert_eq 0 "$rc" "versions.env is complete and well formed"
assert_cmd "versions.env can be sourced" -- bash -c "set -eu; set -a; . '$dir/versions.env'; [ -n \"\$ASTERISK_VER\" ]"
assert_eq "22.11.0" "$(sed -n 's/^ASTERISK_VER=//p' "$dir/versions.env")" "Asterisk version is 22.11.0 (D5)"
assert_eq "17" "$(sed -n 's/^FREEPBX_VER=//p' "$dir/versions.env")" "FreePBX major version is 17"

# negatives on copies
mkdir -p "$work/build"
cp "$dir/versions.env" "$work/ok.env"
sed 's/^ASTERISK_SHA256=.*/ASTERISK_SHA256=abc/' "$dir/versions.env" > "$work/badsha.env"
printf '#!/bin/sh\nfetch "$UNKNOWN_COMPONENT_VER" "${UNKNOWN_COMPONENT_SHA256}"\n' > "$work/build/x.sh"
printf 'FROM scratch\nARG FOO_VER=1.0\n' > "$work/Dockerfile"
printf 'BAD_VER=1.0 && echo pwned\n' >> "$work/cmd.env"; cat "$dir/versions.env" >> "$work/cmd.env"
assert_cmd_fails "a short sha256 is rejected" -- check_versions "$work/badsha.env" "$dir/build" /nonexistent
assert_cmd_fails "a version used by a build script but undefined is rejected" -- check_versions "$work/ok.env" "$work/build" /nonexistent
assert_cmd_fails "an ARG version default in the Dockerfile is rejected" -- check_versions "$work/ok.env" "$dir/build" "$work/Dockerfile"
assert_cmd_fails "a line that is not KEY=value is rejected" -- check_versions "$work/cmd.env" "$dir/build" /nonexistent

finish
