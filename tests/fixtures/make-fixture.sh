#!/usr/bin/env bash
# Build a migration fixture: install izPBX <version> from scratch, populate it
# with the T5 content (see populate.sh), then export a DB dump and a tar of /data.
#
#   tests/fixtures/make-fixture.sh [-v VERSION] [-o OUTDIR] [--variant NAME] [--reuse]
#                                  [--stop-after install|populate]
#
# Output: OUTDIR/NAME/{asterisk.sql.gz,asteriskcdrdb.sql.gz,data.tar.gz,manifest.txt}
# with NAME = VERSION or VERSION-VARIANT. Default OUTDIR: tests/fixtures/out
# (not versioned). TEST_KEEP=1 leaves the containers running.
#
# The two dumps keep their role names whatever the database names are:
# asterisk.sql.gz is the config DB, asteriskcdrdb.sql.gz the CDR DB. The real
# names, the port and other variant facts are in manifest.txt.
#
# Variants are tests/fixtures/variants/NAME.sh. They may set, before the run:
#   CHAIN=(VERSION...)        images to install first, on the same volumes
#   CHAIN_ENV=(-e K=V ...)    extra env for the chain images
#   PBX_ENV=(-e K=V ...)      extra env for the izPBX container
#   DB_ARGS=(...)             extra mariadbd arguments
#   DB_PORT DB_NAME DB_CDR    port and database names (default 3306 asterisk asteriskcdrdb)
#   NO_ROOT=1                 izPBX gets no MYSQL_ROOT_PASSWORD
#   SKIP_POPULATE=1           export right after the install step
# and define the functions variant_pre_pbx, variant_install,
# variant_post_populate, variant_manifest (all optional).
# File-only variants are made by derive-variant.sh.
#
# --reuse skips the build when OUTDIR/NAME exists and was made from the same
# inputs (scripts, version, variant): see "inputs=" in manifest.txt.

TEST_ID=fixture
VERSION=20.16.22
OUTDIR=
STOP_AFTER=
VARIANT=
REUSE=
while [ $# -gt 0 ]; do
  case "$1" in
    -v) VERSION=$2; shift 2 ;;
    -o) OUTDIR=$2; shift 2 ;;
    --stop-after) STOP_AFTER=$2; shift 2 ;;
    --variant) VARIANT=$2; shift 2 ;;
    --reuse) REUSE=1; shift ;;
    *) echo "usage: $0 [-v VERSION] [-o OUTDIR] [--variant NAME] [--reuse] [--stop-after install|populate]" >&2; exit 2 ;;
  esac
done
TEST_PROJECT="izpbxfx-${VERSION//./-}${VARIANT:+-$VARIANT}-$$"
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

FIXTURES_DIR="$TESTS_DIR/fixtures"
OUTDIR=${OUTDIR:-$FIXTURES_DIR/out}
NAME=$VERSION${VARIANT:+-$VARIANT}
dest="$OUTDIR/$NAME"
# checks running in parallel (tests/run.sh -j) may ask for the same fixture:
# one builds it, the others wait here and then reuse it
mkdir -p "$OUTDIR"
exec 9>"$OUTDIR/.$NAME.lock"
flock 9
variant_file=
if [ -n "$VARIANT" ]; then
  variant_file="$FIXTURES_DIR/variants/$VARIANT.sh"
  [ -f "$variant_file" ] || die "unknown variant '$VARIANT' (no $variant_file)"
fi

# hash of everything that shapes the fixture
inputs=$( { echo "$VERSION $VARIANT"; cat "$FIXTURES_DIR"/{make-fixture.sh,populate.sh,populate.php,extensions.csv,fixture.env} ${variant_file:+"$variant_file"}; } | sha256sum | cut -c1-16)
if [ -n "$REUSE" ] && grep -qx "inputs=$inputs" "$dest/manifest.txt" 2>/dev/null; then
  log "reusing $dest (inputs $inputs unchanged)"
  exit 0
fi
IMAGE="docker.io/izdock/izpbx-asterisk:$VERSION"
DB_IMAGE="docker.io/mariadb:10.11.19"
DB_ROOT_PW="fixture-root-pw"
DB_PW="fixture-pw"
: "${FIXTURE_INSTALL_TIMEOUT:=2400}"

# variant defaults and hooks
CHAIN=() CHAIN_ENV=() PBX_ENV=() DB_ARGS=()
DB_PORT=3306 DB_NAME=asterisk DB_CDR=asteriskcdrdb NO_ROOT='' SKIP_POPULATE=''
variant_pre_pbx() { :; }
variant_post_populate() { :; }
variant_manifest() { :; }
variant_install() { wait_installed "$pbx"; }
# shellcheck source=/dev/null
[ -n "$variant_file" ] && source "$variant_file"

db_sql() { docker exec -i "$db" mariadb -uroot -p"$DB_ROOT_PW" -P "$DB_PORT" "$@"; }

# done when supervisord took over from the entrypoint and Asterisk answers
# (18.15.x writes an empty .initialized, 20.16.x a timestamp)
installed() {
  docker logs "$1" 2>&1 | grep -q 'supervisord started' &&
    docker exec "$1" sh -c 'test -e /data/.initialized && asterisk -rx "core show version" | grep -q Asterisk'
}
wait_installed() { # container
  local start=$SECONDS
  until installed "$1"; do
    [ "$(docker inspect -f '{{.State.Running}}' "$1")" == "true" ] || { docker logs --tail 80 "$1" >&2; die "izPBX exited during install"; }
    [ $((SECONDS - start)) -lt "$FIXTURE_INSTALL_TIMEOUT" ] || { docker logs --tail 80 "$1" >&2; die "install timeout"; }
    sleep 10
  done
  log "$1 ready in $((SECONDS - start))s"
}

# izPBX container on the fixture volumes: name image [extra docker run args]
start_pbx() {
  local name=$1 image=$2; shift 2
  local root_env=(-e MYSQL_ROOT_PASSWORD="$DB_ROOT_PW")
  [ -n "$NO_ROOT" ] && root_env=()
  t_run "$name" "$image" --network "$net" --hostname izpbx-fixture \
    -v "$data_vol:/data" \
    --env-file "$FIXTURES_DIR/fixture.env" \
    -e MYSQL_DATABASE="$DB_NAME" -e MYSQL_DATABASE_CDR="$DB_CDR" -e APP_PORT_MYSQL="$DB_PORT" \
    "${root_env[@]}" -e MYSQL_PASSWORD="$DB_PW" "$@"
}

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
db_vol=$(t_volume db)
data_vol=$(t_volume data)

log "starting MariaDB (port $DB_PORT)"
db=$(t_run db "$DB_IMAGE" --network "$net" --network-alias db \
  -v "$db_vol:/var/lib/mysql" \
  -e MARIADB_ROOT_PASSWORD="$DB_ROOT_PW" \
  --health-cmd "healthcheck.sh --connect --innodb_initialized" --health-interval 3s --health-retries 60 \
  -- --sql-mode=ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION --port="$DB_PORT" "${DB_ARGS[@]}")
t_wait_healthy "$db" 180 || die "MariaDB did not start"

variant_pre_pbx

for v in "${CHAIN[@]}"; do
  log "chain: installing izPBX $v first"
  c=$(start_pbx "chain-${v//./-}" "docker.io/izdock/izpbx-asterisk:$v" "${CHAIN_ENV[@]}")
  wait_installed "$c"
  docker stop -t 120 "$c" >/dev/null
  docker rm "$c" >/dev/null
done

log "starting izPBX $VERSION (timeout ${FIXTURE_INSTALL_TIMEOUT}s)"
pbx=$(start_pbx pbx "$IMAGE" "${PBX_ENV[@]}")
variant_install
log "installed: $(docker exec "$pbx" cat /data/.initialized 2>/dev/null || echo '?')"
[ "$STOP_AFTER" == "install" ] && { log "stopping after install (containers: $db $pbx)"; exit 0; }

if [ -z "$SKIP_POPULATE" ]; then
  log "populating"
  docker exec "$pbx" mkdir -p /tmp/fixture
  docker cp "$FIXTURES_DIR/populate.sh" "$pbx:/tmp/fixture/"
  docker cp "$FIXTURES_DIR/populate.php" "$pbx:/tmp/fixture/"
  docker cp "$FIXTURES_DIR/extensions.csv" "$pbx:/tmp/fixture/"
  docker exec "$pbx" chmod -R a+rX /tmp/fixture
  docker exec "$pbx" bash /tmp/fixture/populate.sh
  variant_post_populate
fi
[ "$STOP_AFTER" == "populate" ] && { log "stopping after populate (containers: $db $pbx)"; exit 0; }

log "stopping izPBX"
docker stop -t 120 "$pbx" >/dev/null || true

rm -rf "$dest.tmp" && mkdir -p "$dest.tmp"
log "dumping databases ($DB_NAME, $DB_CDR)"
docker exec "$db" mariadb-dump -uroot -p"$DB_ROOT_PW" -P "$DB_PORT" --single-transaction --routines --triggers --skip-dump-date \
  --databases "$DB_NAME" | gzip -n > "$dest.tmp/asterisk.sql.gz"
docker exec "$db" mariadb-dump -uroot -p"$DB_ROOT_PW" -P "$DB_PORT" --single-transaction --routines --triggers --skip-dump-date \
  --databases "$DB_CDR" | gzip -n > "$dest.tmp/asteriskcdrdb.sql.gz"
grants=$(db_sql -N -B -e "SHOW GRANTS FOR 'asterisk'@'%'" 2>/dev/null | tr '\n' ';' || true)
log "archiving /data"
docker run --rm -v "$data_vol:/data:ro" -v "$dest.tmp:/out" --entrypoint tar "$DB_IMAGE" \
  --numeric-owner -C /data -czf /out/data.tar.gz .
docker run --rm -v "$dest.tmp:/out" --entrypoint chown "$DB_IMAGE" -R "$(id -u):$(id -g)" /out

{
  echo "version=$VERSION"
  echo "variant=${VARIANT:-none}"
  echo "inputs=$inputs"
  echo "image=$(docker image inspect -f '{{index .RepoDigests 0}}' "$IMAGE")"
  [ ${#CHAIN[@]} -gt 0 ] && echo "chain=${CHAIN[*]} $VERSION"
  echo "db_config=$DB_NAME"
  echo "db_cdr=$DB_CDR"
  echo "db_port=$DB_PORT"
  echo "db_user=asterisk"
  echo "db_root=$([ -n "$NO_ROOT" ] && echo none || echo given)"
  echo "db_grants=$grants"
  variant_manifest
  echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "generator=tests/fixtures/make-fixture.sh"
  (cd "$dest.tmp" && sha256sum asterisk.sql.gz asteriskcdrdb.sql.gz data.tar.gz)
} > "$dest.tmp/manifest.txt"
rm -rf "$dest" && mv "$dest.tmp" "$dest"
log "fixture ready in $dest"
