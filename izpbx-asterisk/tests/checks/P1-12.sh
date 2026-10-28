#!/usr/bin/env bash
# P1-12: obsolete workarounds removed. Each pattern has 0 matches under
# izpbx-asterisk/: php74.patch, SECLEVEL=1, gpg --refresh-keys, RHEL_VER,
# microdnf, branches for Asterisk <= 18, chan_local, Encoding.php,
# framework 16.0.41.
# Negative: every pattern matches the same files as they were before P1-12
# (commit f6492c6: legacy-20.16/Dockerfile, rootfs/entrypoint-hooks.sh).
source "$(dirname "$0")/../lib.sh"

before=f6492c6
dir="$REPO_DIR/izpbx-asterisk"
declare -A patterns=(
  [php74.patch]='php74\.patch'
  [SECLEVEL=1]='SECLEVEL=1'
  [gpg --refresh-keys]='refresh-keys'
  [RHEL_VER]='RHEL_VER'
  [microdnf]='microdnf'
  [Asterisk <= 18 branches]='ASTERISK_VER[^ ]* +-(le|lt) +1[0-9]\b'
  [chan_local]='chan_local'
  [Encoding.php]='Encoding\.php'
  [framework 16.0.41]='16\\?\.0\\?\.41'
)
git -C "$REPO_DIR" cat-file -e "$before" 2>/dev/null || die "commit $before not found"
old=$( { git -C "$REPO_DIR" show "$before:izpbx-asterisk/legacy-20.16/Dockerfile"
         git -C "$REPO_DIR" show "$before:izpbx-asterisk/rootfs/entrypoint-hooks.sh"; } )

assert_cmd_fails "izpbx-asterisk/patch/php74.patch removed" -- test -e "$dir/patch/php74.patch"
assert_cmd_fails "izpbx-asterisk/legacy-20.16 removed" -- test -e "$dir/legacy-20.16"
for name in "${!patterns[@]}"; do
  re=${patterns[$name]}
  # the image sources only: tests/ and tools/ of izpbx-asterisk name these patterns on purpose
  found=$(grep -rnE -- "$re" "$dir/Dockerfile" "$dir/versions.env" "$dir/build" "$dir/rootfs" || true)
  [ -z "$found" ] || log "$name:"$'\n'"$found"
  assert_eq 0 "$(grep -c . <<< "$found" || true)" "no $name in izpbx-asterisk/"
  assert_ne 0 "$(grep -cE -- "$re" <<< "$old" || true)" "control: the pattern for $name matches the files before P1-12"
done
finish
