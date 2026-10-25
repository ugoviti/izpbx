#!/usr/bin/env bash
# Run checks of tests/run.sh inside a Docker-in-Docker container, for CI
# runners that run the job in a container: the checks bind mount paths of
# the repository and of mktemp, which exist inside the DinD container, not
# on the host of a containerized runner.
#   tests/ci/dind-run.sh IMAGE CHECK...
#   tests/ci/dind-run.sh --lint         tests/lint.sh (its tools bind mount the repository too)
# IMAGE (the izpbx-asterisk image of the run, already in the local docker)
# is loaded in the DinD daemon and given to tests/run.sh as TEST_IMAGE.
# Environment passed through: TEST_REUSE_FIXTURES, P4_08_AFTER_RESTORE_SQL.
# Logs copied back to tests/.logs; exit status of tests/run.sh.
set -euo pipefail
image=${1:?usage: $0 IMAGE CHECK... | --lint}; shift
[ $# -gt 0 ] || [ "$image" == --lint ] || { echo "usage: $0 IMAGE CHECK... | --lint" >&2; exit 2; }
repo=$(cd "$(dirname "$0")/../.." && pwd)
name="izpbx-ci-dind-$$"
dind=docker.io/library/docker:27.5.1-dind
cleanup() { docker rm -fv "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# the daemon on its unix socket only (no TCP API, docker exec reaches it)
docker run -d --privileged --name "$name" -e DOCKER_TLS_CERTDIR= "$dind" --host=unix:///var/run/docker.sock >/dev/null
for _ in $(seq 1 60); do docker exec "$name" docker info >/dev/null 2>&1 && break; sleep 2; done
docker exec "$name" docker info >/dev/null
docker exec "$name" apk add --no-cache -q bash coreutils findutils grep sed gawk tar gzip jq curl python3 git util-linux >/dev/null
[ "$image" == --lint ] || docker save "$image" | docker exec -i "$name" docker load -q
docker exec "$name" mkdir -p /repo
# the files git tracks (as a CI checkout; not the local data of a deploy)
(cd "$repo" && git ls-files -z | tar --null -T - -cf -) | docker exec -i "$name" tar -C /repo -xf -
rc=0
if [ "$image" == --lint ]; then
  docker exec -w /repo "$name" bash tests/lint.sh || rc=$?
  exit "$rc"
fi
docker exec -e TEST_IMAGE="$image" -e TEST_REUSE_FIXTURES="${TEST_REUSE_FIXTURES:-}" \
  -e P4_08_AFTER_RESTORE_SQL="${P4_08_AFTER_RESTORE_SQL:-}" -w /repo "$name" bash tests/run.sh "$@" || rc=$?
mkdir -p "$repo/tests/.logs"
docker exec "$name" tar -C /repo/tests/.logs -cf - . 2>/dev/null | tar -C "$repo/tests/.logs" -xf - || true
exit "$rc"
