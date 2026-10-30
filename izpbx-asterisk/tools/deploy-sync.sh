#!/bin/bash
# Refresh the files izpbx-deploy reads in the image (docs/izpbx-deploy.md) that
# come from the git tags, under izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy:
#   history/VERSION.env            default.env and compose.yml of every release X.Y.Z
#   history/VERSION.compose.yml    with IZPBX_VERSION in default.env (22.17.0 and later),
#                                  except the version of the current default.env
#   keys.txt                       every variable default.env ever had (all the tags and the current one)
# compose.yml and default.env live there (the files of a deploy); renames.tsv
# (OLD NEW VERSION) is written by hand.
#
#   izpbx-asterisk/tools/deploy-sync.sh           write the files
#   izpbx-asterisk/tools/deploy-sync.sh --check   exit 1 if a file is out of date (lint); without
#                                                 git tags only keys.txt against default.env
# Run after a change of default.env (tools/make-release.sh runs it).

set -Eeuo pipefail
die() { echo "deploy-sync: ERROR: $*" >&2; exit 2; }

check=''
case "${1:-}" in
  --check) check=1 ;;
  '') ;;
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) die "unknown option: $1" ;;
esac

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
dest=izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy
[ -f "$dest/default.env" ] || die "$dest/default.env not found"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/history"

# the variables of a default.env, active (KEY=) and commented (#KEY=)
keys_of() { awk '{ s = $0; sub(/\r$/, "", s); sub(/^#[ \t]*/, "", s); sub(/^[ \t]+/, "", s); sub(/^export[ \t]+/, "", s)
  if (s ~ /^[A-Za-z_][A-Za-z0-9_]*=/) print substr(s, 1, index(s, "=") - 1) }'; }
current=$(sed -n 's/^IZPBX_VERSION=//p' "$dest/default.env" | tail -1)

keys_of < "$dest/default.env" > "$work/keys"
git_ok=''
if git rev-parse --git-dir >/dev/null 2>&1 && [ -n "$(git tag -l)" ]; then git_ok=1; fi
if [ -n "$git_ok" ]; then
  while read -r t; do
    # default.env and compose.yml were at the root of the repository up to 22.17.0
    if git cat-file -e "$t:$dest/default.env" 2>/dev/null; then p=$dest/; else p=''; fi
    git show "$t:${p}default.env" > "$work/tag.env" 2>/dev/null || continue
    keys_of < "$work/tag.env" >> "$work/keys"
    if [[ "$t" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ "$t" != "$current" ] && grep -q '^IZPBX_VERSION=' "$work/tag.env"; then
      cp "$work/tag.env" "$work/history/$t.env"
      git show "$t:${p}compose.yml" > "$work/history/$t.compose.yml" 2>/dev/null || rm -f "$work/history/$t.compose.yml"
    fi
  done < <(git tag -l)
fi
LC_ALL=C sort -u "$work/keys" > "$work/keys.txt"

if [ -n "$check" ]; then
  rc=0
  if [ -n "$git_ok" ]; then
    cmp -s "$work/keys.txt" "$dest/keys.txt" || { echo "deploy-sync: $dest/keys.txt out of date (run izpbx-asterisk/tools/deploy-sync.sh)" >&2; rc=1; }
    for f in "$work"/history/*; do
      [ -e "$f" ] || continue
      cmp -s "$f" "$dest/history/${f##*/}" || { echo "deploy-sync: $dest/history/${f##*/} out of date (run izpbx-asterisk/tools/deploy-sync.sh)" >&2; rc=1; }
    done
  else
    # without tags: at least every variable of the current default.env
    missing=$(LC_ALL=C comm -23 "$work/keys.txt" <(LC_ALL=C sort -u "$dest/keys.txt" 2>/dev/null))
    [ -z "$missing" ] || { echo "deploy-sync: $dest/keys.txt lacks: $(echo "$missing" | xargs) (run izpbx-asterisk/tools/deploy-sync.sh)" >&2; rc=1; }
  fi
  exit "$rc"
fi

mkdir -p "$dest/history"
if [ -n "$git_ok" ]; then
  cp "$work/keys.txt" "$dest/"
  for f in "$work"/history/*; do [ -e "$f" ] && cp "$f" "$dest/history/"; done
else
  # without tags the current variables are added, nothing is removed
  LC_ALL=C sort -u "$work/keys.txt" "$dest/keys.txt" -o "$dest/keys.txt" 2>/dev/null || cp "$work/keys.txt" "$dest/keys.txt"
  echo "deploy-sync: no git tags: history/ not refreshed" >&2
fi
[ -f "$dest/renames.tsv" ] || printf '# renamed variables of default.env, read by izpbx-deploy: OLD_NAME NEW_NAME VERSION\n' > "$dest/renames.tsv"
echo "deploy-sync: $dest refreshed"
