#!/usr/bin/env bash
# Build a migration fixture: install izPBX <version> from scratch, populate it
# with the T5 content (see populate.sh), then export a DB dump and a tar of /data.
#
#   tests/fixtures/make-fixture.sh [-v VERSION] [-o OUTDIR] [--stop-after install|populate]
#
# Output: OUTDIR/VERSION/{asterisk.sql.gz,asteriskcdrdb.sql.gz,data.tar.gz,manifest.txt}
# Default OUTDIR: tests/fixtures/out (not versioned). TEST_KEEP=1 leaves the
# containers running (useful with --stop-after).

TEST_ID=fixture
VERSION=20.16.22
OUTDIR=
STOP_AFTER=
while [ $# -gt 0 ]; do
  case "$1" in
    -v) VERSION=$2; shift 2 ;;
    -o) OUTDIR=$2; shift 2 ;;
    --stop-after) STOP_AFTER=$2; shift 2 ;;
    *) echo "usage: $0 [-v VERSION] [-o OUTDIR] [--stop-after install|populate]" >&2; exit 2 ;;
  esac
done
TEST_PROJECT="izpbxfx-${VERSION//./-}-$$"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

FIXTURES_DIR="$TESTS_DIR/fixtures"
OUTDIR=${OUTDIR:-$FIXTURES_DIR/out}
IMAGE="docker.io/izdock/izpbx-asterisk:$VERSION"
DB_IMAGE="docker.io/mariadb:10.11.19"
DB_ROOT_PW="fixture-root-pw"
DB_PW="fixture-pw"
: "${FIXTURE_INSTALL_TIMEOUT:=2400}"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
db_vol=$(t_volume db)
data_vol=$(t_volume data)

log "starting MariaDB"
db=$(t_run db "$DB_IMAGE" --network "$net" --network-alias db \
  -v "$db_vol:/var/lib/mysql" \
  -e MARIADB_ROOT_PASSWORD="$DB_ROOT_PW" \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 3s --health-retries 60 \
  -- --sql-mode=ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION)
t_wait_healthy "$db" 180 || die "MariaDB did not start"

log "starting izPBX $VERSION (first install, timeout ${FIXTURE_INSTALL_TIMEOUT}s)"
pbx=$(t_run pbx "$IMAGE" --network "$net" --hostname izpbx-fixture \
  -v "$data_vol:/data" \
  --env-file "$FIXTURES_DIR/fixture.env" \
  -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PW" -e MYSQL_PASSWORD="$DB_PW")

# done when supervisord took over from the entrypoint and Asterisk answers
installed() {
  docker logs "$pbx" 2>&1 | grep -q 'supervisord started' &&
    docker exec "$pbx" sh -c 'test -s /data/.initialized && asterisk -rx "core show version" | grep -q Asterisk'
}
start=$SECONDS
until installed; do
  [ "$(docker inspect -f '{{.State.Running}}' "$pbx")" == "true" ] || { docker logs --tail 80 "$pbx" >&2; die "izPBX exited during install"; }
  [ $((SECONDS - start)) -lt "$FIXTURE_INSTALL_TIMEOUT" ] || { docker logs --tail 80 "$pbx" >&2; die "install timeout"; }
  sleep 10
done
log "installed in $((SECONDS - start))s: $(docker exec "$pbx" cat /data/.initialized)"
[ "$STOP_AFTER" == "install" ] && { log "stopping after install (containers: $db $pbx)"; exit 0; }

log "populating"
docker exec "$pbx" mkdir -p /tmp/fixture
docker cp "$FIXTURES_DIR/populate.sh" "$pbx:/tmp/fixture/"
docker cp "$FIXTURES_DIR/populate.php" "$pbx:/tmp/fixture/"
docker cp "$FIXTURES_DIR/extensions.csv" "$pbx:/tmp/fixture/"
docker exec "$pbx" chmod -R a+rX /tmp/fixture
docker exec -e MYSQL_ROOT_PASSWORD="$DB_ROOT_PW" "$pbx" bash /tmp/fixture/populate.sh
[ "$STOP_AFTER" == "populate" ] && { log "stopping after populate (containers: $db $pbx)"; exit 0; }

log "stopping izPBX"
docker stop -t 120 "$pbx" >/dev/null

dest="$OUTDIR/$VERSION"
rm -rf "$dest.tmp" && mkdir -p "$dest.tmp"
log "dumping databases"
for d in asterisk asteriskcdrdb; do
  docker exec "$db" mariadb-dump -uroot -p"$DB_ROOT_PW" --single-transaction --routines --triggers --skip-dump-date \
    --databases "$d" | gzip -n > "$dest.tmp/$d.sql.gz"
done
log "archiving /data"
docker run --rm -v "$data_vol:/data:ro" -v "$dest.tmp:/out" --entrypoint tar "$DB_IMAGE" \
  --numeric-owner -C /data -czf /out/data.tar.gz .
docker run --rm -v "$dest.tmp:/out" --entrypoint chown "$DB_IMAGE" -R "$(id -u):$(id -g)" /out

{
  echo "version=$VERSION"
  echo "image=$(docker image inspect -f '{{index .RepoDigests 0}}' "$IMAGE")"
  echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "generator=tests/fixtures/make-fixture.sh"
  (cd "$dest.tmp" && sha256sum asterisk.sql.gz asteriskcdrdb.sql.gz data.tar.gz)
} > "$dest.tmp/manifest.txt"
rm -rf "$dest" && mv "$dest.tmp" "$dest"
log "fixture ready in $dest"
