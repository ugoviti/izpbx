#!/usr/bin/env bash
# Lint shell scripts (shellcheck) and Dockerfiles (hadolint).
#
#   tests/lint.sh [ROOT]   lint the files under ROOT (default: the repository)
#
# Both tools run as containers pinned by digest, so the host and CI use the
# same versions. Exit code: 0 clean, 1 findings, 2 usage or setup error.

set -Eeuo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=$(cd "${1:-$REPO_DIR}" && pwd)

SHELLCHECK_IMAGE="docker.io/koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d"
HADOLINT_IMAGE="docker.io/hadolint/hadolint:v2.14.0@sha256:27086352fd5e1907ea2b934eb1023f217c5ae087992eb59fde121dce9c9ff21e"

command -v docker >/dev/null || { echo "lint: docker is required" >&2; exit 2; }

cd "$ROOT"

# find(1) limited to the directories that exist under ROOT.
find_in() { # dirs... -- find args...
  local dirs=()
  while [ "$1" != "--" ]; do [ -d "$1" ] && dirs+=("$1"); shift; done
  shift
  [ ${#dirs[@]} -eq 0 ] || find "${dirs[@]}" "$@"
}

# Shell files, relative to ROOT. The globs follow the checklist (P0-03).
shell_files() {
  {
    find_in izpbx-asterisk/build -- -name '*.sh'
    find_in izpbx-asterisk/rootfs/usr/local/lib/izpbx -- -type f
    find_in izpbx-asterisk/rootfs/usr/local/sbin izpbx-asterisk/rootfs/usr/local/bin -- -maxdepth 1 -type f -name 'izpbx*'
    # s6 service scripts (execline "up" files are not shell)
    find_in izpbx-asterisk/rootfs/etc/s6-overlay/s6-rc.d tests/s6probe -- -type f \( -name run -o -name finish \)
    find_in izpbx-asterisk/rootfs/usr/sbin -- -type f -name safe_asterisk
    find_in tests -- -name '*.sh' -not -path '*/fixtures/data/*'
    find_in .githooks -- -type f
    find_in izpbx-asterisk/tools -- -type f -name '*.sh'
  } | sort -u
}

docker_files() {
  find . -path ./data -prune -o -path ./.git -prune -o -type f \( -name Dockerfile -o -name '*.Dockerfile' \) -print \
    | sed 's|^\./||' | sort
}

mapfile -t sh_list < <(shell_files)
mapfile -t df_list < <(docker_files)

rc=0
if [ ${#sh_list[@]} -gt 0 ]; then
  echo "shellcheck: ${#sh_list[@]} file(s)"
  docker run --rm -v "$ROOT:/mnt:ro" -w /mnt "$SHELLCHECK_IMAGE" \
    --severity=warning --external-sources --source-path=SCRIPTDIR --format=gcc "${sh_list[@]}" || rc=1
fi

if [ ${#df_list[@]} -gt 0 ]; then
  echo "hadolint: ${#df_list[@]} file(s)"
  docker run --rm -v "$ROOT:/mnt:ro" -v "$REPO_DIR/.hadolint.yaml:/etc/hadolint.yaml:ro" -w /mnt \
    "$HADOLINT_IMAGE" hadolint --no-color --config /etc/hadolint.yaml "${df_list[@]}" || rc=1
fi

[ "$rc" -eq 0 ] && echo "lint: clean" || echo "lint: findings above" >&2
exit "$rc"
