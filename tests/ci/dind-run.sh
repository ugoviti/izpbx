#!/usr/bin/env bash
# Run checks of tests/run.sh inside a Docker-in-Docker container, for CI
# runners that run the job in a container: the checks bind mount paths of
# the repository and of mktemp, which exist inside the DinD container, not
# on the host of a containerized runner.
#   tests/ci/dind-run.sh IMAGE CHECK...
#   tests/ci/dind-run.sh --lint         tests/lint.sh (its tools bind mount the repository too)
# IMAGE (the izpbx-asterisk image of the run, already in the local docker)
# is loaded in the DinD daemon and given to tests/run.sh as TEST_IMAGE.
# Environment passed through: TEST_REUSE_FIXTURES, P4_08_AFTER_RESTORE_SQL,
# TEST_CHECKS_DIR, MIGRATE_VERSION and MIGRATE_BREAK (tests/ci/checks/MIGRATE.sh);
# TEST_KEEP is passed through too, and also keeps the DinD container (debug:
# docker exec -it <name> docker ps -a).
# Logs copied back to tests/.logs; exit status of tests/run.sh.
set -euo pipefail
image=${1:?usage: $0 IMAGE CHECK... | --lint}; shift
[ $# -gt 0 ] || [ "$image" == --lint ] || { echo "usage: $0 IMAGE CHECK... | --lint" >&2; exit 2; }
repo=$(cd "$(dirname "$0")/../.." && pwd)
# unique: parallel CI jobs share the Docker daemon of the host, and the PID of
# this shell is the same small number in every job container
name="izpbx-ci-dind-${GITHUB_RUN_ID:-local}-$$-$(od -An -N4 -tx4 /dev/urandom | tr -d ' ')"
dind=docker.io/library/docker:27.5.1-dind
cleanup() {
  if [ -n "${TEST_KEEP:-}" ]; then echo "kept: DinD container $name" >&2; return 0; fi
  docker rm -fv "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# the daemon on its unix socket only (no TCP API, docker exec reaches it)
# DinD containers left behind by a job that was killed (out of memory, timeout,
# cancelled: the EXIT trap never ran) keep their whole Docker data on the host
# and fill its disk ("No space left on device" in CI): every start removes the
# ones older than 4 hours (a CI job lasts 90 minutes at most)
now=$(date +%s)
for old in $(docker ps -aq --filter label=izpbx.ci.dind=1); do
  created=$(date -d "$(docker inspect -f '{{.Created}}' "$old" 2>/dev/null)" +%s 2>/dev/null) || continue
  if [ $((now - created)) -gt 14400 ]; then
    echo "dind-run: removing $(docker inspect -f '{{.Name}}' "$old") (left behind, created $(( (now - created) / 3600 )) h ago)" >&2
    docker rm -fv "$old" >/dev/null 2>&1 || true
  fi
done
# "dockerd" given explicitly: with arguments that start with "-" the entrypoint
# of docker:dind adds --host=tcp://0.0.0.0:2375 (no TLS) by itself
docker run -d --privileged --name "$name" --label izpbx.ci.dind=1 -e DOCKER_TLS_CERTDIR= "$dind" dockerd --host=unix:///var/run/docker.sock >/dev/null
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
docker exec -e TEST_IMAGE="$image" -e TEST_REUSE_FIXTURES="${TEST_REUSE_FIXTURES:-}" -e TEST_KEEP="${TEST_KEEP:-}" \
  -e TEST_CHECKS_DIR="${TEST_CHECKS_DIR:-}" -e MIGRATE_VERSION="${MIGRATE_VERSION:-}" -e MIGRATE_BREAK="${MIGRATE_BREAK:-}" \
  -e P4_08_AFTER_RESTORE_SQL="${P4_08_AFTER_RESTORE_SQL:-}" -w /repo "$name" bash tests/run.sh "$@" || rc=$?
mkdir -p "$repo/tests/.logs"
docker exec "$name" tar -C /repo/tests/.logs -cf - . 2>/dev/null | tar -C "$repo/tests/.logs" -xf - || true
exit "$rc"
