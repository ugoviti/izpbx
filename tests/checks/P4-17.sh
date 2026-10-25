#!/usr/bin/env bash
# P4-17: documentation, rest-api and static-http of Asterisk equal to the
# image at every start (persistence_sync_dist, M6; 20.16 synced the
# documentation only). A migrated volume gets var/lib/asterisk from the image
# anyway (the 16 one goes to the snapshot); an existing volume after an image
# update is the case checked here, with Asterisk alone (IZPBX_ENABLED=false).
# - after the first start the three directories in /data equal
#   /var/lib/asterisk.dist (diff -rq: content, missing and extra files; rsync
#   is not in the image);
# - the volume damaged while the container is stopped (the XML documentation
#   of codec_opus removed, a stale file in rest-api, a static-http page
#   changed): a one-off container sees the differences (control), the next
#   start makes them equal again and logs it;
# - codec_opus is Running after the restart, without documentation errors
#   in the Asterisk log.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-17
assert_cmd "image builds" -- t_build_image "$image"
v=$(t_volume data)
run() { t_run "$1" "$image" -v "$v:/data" -e APP_DATA=/data -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true; }
dirs="documentation rest-api static-http"
same() { # container -> "" when the three directories equal the image
  local d
  for d in $dirs; do
    docker exec "$1" diff -rq --no-dereference "/var/lib/asterisk.dist/$d" "/data/var/lib/asterisk/$d" 2>&1 || true
  done
}
up() { t_wait_for 120 -- sh -c "docker exec $1 asterisk -rx 'core waitfullybooted' >/dev/null 2>&1"; }

c=$(run first)
assert_cmd "first start: Asterisk up" -- up "$c"
assert_eq "" "$(same "$c")" "first start: documentation, rest-api, static-http equal to the image"
docker rm -f "$c" >/dev/null

# damage the volume as an old image would leave it
docker run --rm --entrypoint "" -v "$v:/data" "$image" sh -c '
  rm -f /data/var/lib/asterisk/documentation/thirdparty/codec_opus_config-en_US.xml
  echo stale > /data/var/lib/asterisk/rest-api/stale-from-old-image.json
  echo changed >> /data/var/lib/asterisk/static-http/astman.css'
damage=$(docker run --rm --entrypoint "" -v "$v:/data" "$image" sh -c '
  for d in documentation rest-api static-http; do
    diff -rq --no-dereference /var/lib/asterisk/$d /data/var/lib/asterisk/$d 2>&1; done' || true)
log "damaged volume:"; sed 's/^/    | /' <<< "$damage" >&2
assert_eq 3 "$(grep -c . <<< "$damage")" "control: the damaged volume differs from the image (3 differences)"

c=$(run second)
assert_cmd "restart: Asterisk up" -- up "$c"
assert_eq "" "$(same "$c")" "restart: the three directories equal to the image again"
assert_cmd "restart: the update is logged" -- \
  sh -c "docker logs '$c' 2>&1 | grep 'persistence: /data/var/lib/asterisk/documentation updated from the image' >/dev/null"
assert_cmd "codec_opus is Running" -- sh -c "docker exec '$c' asterisk -rx 'module show like codec_opus' | grep -E 'codec_opus\.so .*Running'"
assert_eq "" "$(docker exec "$c" sh -c "grep -rhiE 'codec_opus.*(documentation|xml)|(documentation|xml).*codec_opus' /var/log/asterisk 2>/dev/null | grep -iE 'error|warning|unable|fail'" || true)" \
  "no documentation error about codec_opus in the Asterisk log"
finish
