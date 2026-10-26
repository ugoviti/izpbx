#!/bin/bash
# Release the next izPBX patch version (X.Y.Z -> X.Y.Z+1) and update CHANGELOG.md.
#
#   izpbx-asterisk/tools/make-release.sh            dry run: the CHANGELOG entry and the changes, nothing written
#   izpbx-asterisk/tools/make-release.sh --commit   review the entry in $EDITOR, commit "X.Y.Z release", tag X.Y.Z
#   izpbx-asterisk/tools/make-release.sh --push     as --commit, then push the branch and the tag
# other options: --version X.Y.Z, --ai, --yes (no review), --no-fetch (offline)
#
# Version: the series X.Y comes from izpbx-asterisk/versions.env (Asterisk major,
# FreePBX major; on release/20.16, without versions.env, from the last tag);
# the patch is the last tag X.Y.N + 1, or X.Y.0 for a new series.
# Branch: release/X.Y when that branch exists, otherwise main.
#
# CHANGELOG.md (Keep a Changelog): the entries written during development under
# "## [Unreleased]" (or "## [X.Y.Z] - Unreleased") become "## [X.Y.Z] - YYYY-MM-DD"
# and an empty "## [Unreleased]" is left on top. The script adds by itself, under
# "### Changed", one line per component updated since the previous tag
# (versions.env and build/freepbx-modules.txt). When nothing was written by hand:
#   --ai   asks Claude Code (claude -p) for a draft from the commits and the diff;
#   else   the commit subjects are used as a draft.
# The entry is opened in $EDITOR for review (skipped with --yes).
#
# --commit: compose.yml and README.md move from izpbx-asterisk:<previous X.Y.N> to
# the new version, one commit "X.Y.Z release", annotated tag X.Y.Z. --push: the
# branch and the tag go to origin, the tag starts the izpbx-release workflow
# (Gitea registry only; Docker Hub needs izpbx-promote).

set -Eeuo pipefail
die() { echo "release: ERROR: $*" >&2; exit 1; }
log() { echo "release: $*" >&2; }

version='' ai='' yes='' push='' dry=1 fetch=1
while [ $# -gt 0 ]; do
  case "$1" in
    --version) version=${2:?--version X.Y.Z}; shift ;;
    --ai) ai=1 ;;
    --yes|-y) yes=1 ;;
    --commit) dry='' ;;
    --push) dry='' push=1 ;;
    --dry-run|-n) ;;   # the default
    --no-fetch) fetch='' ;;
    -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
  shift
done

root=$(git rev-parse --show-toplevel) || die "not in a git repository"
cd "$root"
venv=izpbx-asterisk/versions.env
mods=izpbx-asterisk/build/freepbx-modules.txt

# --- preconditions
if ! git diff --quiet || ! git diff --cached --quiet; then die "uncommitted changes: commit or stash them first"; fi
[ -n "$fetch" ] && { git fetch -q --tags origin || die "git fetch --tags origin failed (--no-fetch to skip)"; }
branch=$(git rev-parse --abbrev-ref HEAD)

semver='^[0-9]+\.[0-9]+\.[0-9]+$'
prev=$(git tag --merged HEAD | grep -E "$semver" | sort -V | tail -1 || true)
if [ -f "$venv" ]; then
  # shellcheck disable=SC1090
  series=$(set -a; . "./$venv"; echo "${ASTERISK_VER%%.*}.$FREEPBX_VER")
else
  [ -n "$prev" ] || die "no $venv and no previous X.Y.Z tag: use --version"
  series=${prev%.*}
fi
last=$(git tag -l "$series.*" | grep -E "^${series//./\\.}\.[0-9]+$" | sort -V | tail -1 || true)
if [ -z "$version" ]; then
  if [ -n "$last" ]; then version="$series.$(( ${last##*.} + 1 ))"; else version="$series.0"; fi
fi
[[ "$version" =~ $semver ]] || die "invalid version '$version' (X.Y.Z)"
git rev-parse -q --verify "refs/tags/$version" >/dev/null && die "tag $version already exists"
[ -z "$last" ] || [ "$(printf '%s\n%s\n' "$last" "$version" | sort -V | tail -1)" == "$version" ] ||
  die "$version is older than the last release $last"

series=${version%.*}
want=main
git show-ref -q --verify "refs/heads/release/$series" && want="release/$series"
git show-ref -q --verify "refs/remotes/origin/release/$series" && want="release/$series"
[ "$branch" == "$want" ] || die "$version is released from '$want', current branch is '$branch'"
if [ -n "$push" ] && git show-ref -q --verify "refs/remotes/origin/$branch"; then
  [ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$branch")" ] ||
    die "$branch differs from origin/$branch: pull or push it first"
fi
log "version $version (previous release ${prev:-none}, last of $series: ${last:-none}), branch $branch"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# --- component lines: what changed in versions.env and freepbx-modules.txt since $prev
label() {
  case "$1" in
    ASTERISK_VER) echo "PBX engine Asterisk" ;;
    FREEPBX_VER) echo "FreePBX major version" ;;
    FREEPBX_FRAMEWORK_VER) echo "FreePBX framework" ;;
    S6_OVERLAY_VER) echo "s6-overlay" ;;
    PJPROJECT_VER) echo "bundled pjproject" ;;
    JANSSON_VER) echo "bundled jansson" ;;
    ASTERISK_MP3_SVN_REV) echo "format_mp3 sources (svn revision)" ;;
    SPANDSP_VER) echo "spandsp" ;;
    BCG729_VER) echo "bcg729" ;;
    ASTERISK_G72X_VER) echo "asterisk-g72x (G.729 codec)" ;;
    ASTERISK_CHAN_DONGLE_VER) echo "chan_dongle" ;;
    SNGREP_VER) echo "sngrep" ;;
    IONCUBE_VER) echo "ionCube loader" ;;
    FOP2_VER) echo "FOP2" ;;
    FOP2_VER_AARCH64) echo "FOP2 (arm64)" ;;
    ZABBIX_VER) echo "Zabbix agent 2" ;;
    NPM_VER) echo "npm" ;;
    IZSYNTH_VER) echo "izsynth" ;;
    ZABBIX_TEMPLATE_VER) echo "Zabbix templates" ;;
    *) echo "$1" ;;
  esac
}
short() { [[ "$1" =~ ^[0-9a-f]{40}$ ]] && echo "${1:0:12}" || echo "$1"; }
kv() { grep -E '^[A-Z0-9_]+=' | grep -vE '_SHA256|_FPR|_REPO=' || true; }
: > "$work/components"
if [ -n "$prev" ] && git cat-file -e "$prev:$venv" 2>/dev/null && [ -f "$venv" ]; then
  git show "$prev:$venv" | kv > "$work/old.env"
  kv < "$venv" > "$work/new.env"
  while IFS='=' read -r k new; do
    old=$(sed -n "s/^$k=//p" "$work/old.env")
    [ "$old" != "$new" ] || continue
    if [ "$k" == "DEBIAN_IMAGE" ]; then
      echo "- Rebuilt on the latest \`debian:bookworm-slim\` base image (Debian security updates)"
    elif [ "$k" == "ASTERISK_VER" ]; then
      echo "- Updated PBX engine to Asterisk \`$new\` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-$new.md)"
    elif [ -z "$old" ]; then
      echo "- Added $(label "$k") \`$(short "$new")\`"
    else
      echo "- Updated $(label "$k") from \`$(short "$old")\` to \`$(short "$new")\`"
    fi
  done < "$work/new.env" >> "$work/components"
fi
if [ -n "$prev" ] && git cat-file -e "$prev:$mods" 2>/dev/null && [ -f "$mods" ]; then
  changed=$(LC_ALL=C join <(git show "$prev:$mods" | grep -vE '^(#|$)' | awk '{print $1, $2}' | LC_ALL=C sort) \
                 <(grep -vE '^(#|$)' "$mods" | awk '{print $1, $2}' | LC_ALL=C sort) |
            awk '$2 != $3 {printf "%s`%s` %s → %s", sep, $1, $2, $3; sep=", "}')
  [ -z "$changed" ] || echo "- Updated FreePBX modules: $changed" >> "$work/components"
fi

# --- the Unreleased block of CHANGELOG.md
cl=CHANGELOG.md
[ -f "$cl" ] || die "$cl not found"
start=$(grep -nE '^## \[(Unreleased|[0-9][^]]*)\]( - Unreleased)?[[:space:]]*$' "$cl" | grep -E 'Unreleased' | head -1 | cut -d: -f1 || true)
first=$(grep -nE '^## \[' "$cl" | head -1 | cut -d: -f1 || true)
[ -n "$first" ] || die "$cl has no '## [' entry"
if [ -n "$start" ]; then
  heading=$(sed -n "${start}p" "$cl")
  hv=$(sed -nE 's/^## \[([0-9][^]]*)\].*/\1/p' <<< "$heading")
  [ -z "$hv" ] || [ "$hv" == "$version" ] || die "$cl has '$heading' but the next version is $version (use --version $hv?)"
  end=$(awk -v s="$start" 'NR > s && /^## \[/ {print NR - 1; exit}' "$cl")
  [ -n "$end" ] || end=$(wc -l < "$cl")
  sed -n "$((start + 1)),${end}p" "$cl" > "$work/body"
else
  start=$first end=$((first - 1))
  : > "$work/body"
fi
# trim blank lines at both ends of the body
sed -i -e '/./,$!d' "$work/body"
tac "$work/body" | sed -e '/./,$!d' | tac > "$work/body.t" && mv "$work/body.t" "$work/body"

# components not already written by hand
: > "$work/add"
while IFS= read -r line; do
  # shellcheck disable=SC2016  # literal backticks
  key=$(grep -oE '`[^`]+`' <<< "$line" | tail -1)
  [ -n "$key" ] && grep -qF -- "$key" "$work/body" && continue
  echo "$line" >> "$work/add"
done < "$work/components"

draft=''
if ! grep -qE '^- ' "$work/body"; then
  if [ -n "$ai" ]; then
    command -v claude >/dev/null || die "--ai needs Claude Code (claude) in PATH"
    examples=$(awk '/^## \[[0-9]/ && !/Unreleased/ {n++} n >= 1 && n <= 2' "$cl")
    commits=$(git log --no-merges --format='* %s%n%b' "${prev:+$prev..}HEAD" | grep -v '^$' | head -300 || true)
    stat=$(git diff --stat "${prev:-$(git rev-list --max-parents=0 HEAD | tail -1)}" HEAD | tail -60 || true)
    prompt="You write the CHANGELOG.md entry body of the izPBX release $version (Docker image of Asterisk and FreePBX).
Output ONLY the markdown body: one or more sections among '### Security', '### Changed', '### Removed', '### Fixed' (in this order), each with '- ' bullet lines in English, concise, user facing (what changed for whoever runs izPBX, not internal refactors or test-only changes), code names in backticks. No heading '## [...]', no preamble, no closing remarks. Do not repeat these component lines, they are added separately:
$(cat "$work/add")

Style examples (previous entries):
$examples

Commits since ${prev:-the beginning}:
$commits

Files changed:
$stat"
    log "asking Claude Code for a draft of the entry..."
    claude -p "$prompt" > "$work/body" || die "claude -p failed"
    sed -i -e '/./,$!d' "$work/body"
    grep -qE '^### ' "$work/body" || die "the AI draft has no '### ' section: $(head -3 "$work/body")"
    draft=AI
  else
    {
      echo "### Changed"
      git log --no-merges --format='- %s' "${prev:+$prev..}HEAD" | grep -vE '^- [0-9]+\.[0-9]+\.[0-9]+ release' || true
    } > "$work/body"
    draft=commits
  fi
fi

# component lines under "### Changed" (created after "### Security" when missing)
if [ -s "$work/add" ]; then
  if grep -q '^### Changed' "$work/body"; then
    awk -v add="$work/add" '{print} /^### Changed/ && !d {while ((getline l < add) > 0) print l; d = 1}' "$work/body" > "$work/b"
  elif grep -q '^### Security' "$work/body"; then
    awk -v add="$work/add" '
      /^### / && seen && !d {print "### Changed"; while ((getline l < add) > 0) print l; d = 1}
      /^### Security/ {seen = 1} {print}
      END {if (!d) {print "### Changed"; while ((getline l < add) > 0) print l}}' "$work/body" > "$work/b"
  else
    { echo "### Changed"; cat "$work/add"; cat "$work/body"; } > "$work/b"
  fi
  mv "$work/b" "$work/body"
fi
grep -qE '^- ' "$work/body" || die "the entry of $version is empty: write it under '## [Unreleased]' in $cl"

# --- review
{ echo "## [$version] - $(date +%F)"; cat "$work/body"; } > "$work/entry"
if [ -n "$draft" ]; then log "nothing written under Unreleased: $draft draft, review it"; fi
if [ -n "$dry" ]; then
  echo "----- CHANGELOG entry"; cat "$work/entry"; echo "-----"
elif [ -z "$yes" ]; then
  [ -t 0 ] || die "review needed: run in a terminal, or --yes to skip the review"
  "${EDITOR:-vi}" "$work/entry"
  grep -qE "^## \[$version\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" <(head -1 "$work/entry") || die "the first line of the entry must stay '## [$version] - DATE'"
  echo "----- CHANGELOG entry"; cat "$work/entry"; echo "-----"
  read -r -p "release $version from $branch? [y/N] " a
  [[ "$a" =~ ^[yY] ]] || die "aborted"
fi

# --- new CHANGELOG.md: header, empty Unreleased, the entry, the rest
{
  head -n $((first - 1)) "$cl"
  printf '## [Unreleased]\n\n'
  cat "$work/entry"; echo
  tail -n +$((end + 1)) "$cl"
} > "$work/CHANGELOG.md"
# (with an Unreleased block above other entries, head stops before it: start == first)
[ "$start" -eq "$first" ] || [ "$start" -gt "$end" ] || die "the Unreleased block of $cl is not the first entry"

# --- image references of the same series: izpbx-asterisk:<last> -> :<version>
files=()
if [ -n "$last" ]; then
  for f in compose.yml README.md; do
    [ -f "$f" ] && grep -qF "izpbx-asterisk:$last" "$f" && files+=("$f")
  done
fi

if [ -n "$dry" ]; then
  diff -u "$cl" "$work/CHANGELOG.md" | head -40 || true
  for f in "${files[@]}"; do sed "s|izpbx-asterisk:${last//./\\.}\\b|izpbx-asterisk:$version|g" "$f" | diff -u "$f" - || true; done
  log "dry run: nothing written. To release $version from $branch:"
  log "  izpbx-asterisk/tools/make-release.sh --commit   # commit and tag here, push later"
  log "  izpbx-asterisk/tools/make-release.sh --push     # commit, tag and push (starts izpbx-release)"
  exit 0
fi
cp "$work/CHANGELOG.md" "$cl"
for f in "${files[@]}"; do sed -i "s|izpbx-asterisk:${last//./\\.}\\b|izpbx-asterisk:$version|g" "$f"; done
git add "$cl" "${files[@]}"
git commit -q -m "$version release"
git tag -a "$version" -m "izPBX $version"
log "commit $(git rev-parse --short HEAD) and tag $version created"
if [ -n "$push" ]; then
  git push origin "HEAD:refs/heads/$branch"
  git push origin "refs/tags/$version"
  log "pushed $branch and $version: the izpbx-release workflow builds it (Gitea registry)"
else
  log "not pushed: git push origin $branch && git push origin $version"
fi
