# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # sourced by make-fixture.sh: shares its variables
# interrupted (P0-08f): first 20.16.x install killed while installing the
# FreePBX modules, then started once more. On that start the 20.16.x
# entrypoint finds /etc/freepbx.conf without /data/.initialized and creates
# .initialized ("LEGACY" workaround), so the volume claims to be installed
# while the DB lacks most modules.
SKIP_POPULATE=1
variant_install() {
  local start=$SECONDS
  log "variant interrupted: waiting for the module install, then killing the container"
  until docker logs "$pbx" 2>&1 | grep -qE '^---> \[1[0-9]/[0-9]+\] installing module'; do
    [ $((SECONDS - start)) -lt "$FIXTURE_INSTALL_TIMEOUT" ] || die "module install never started"
    [ "$(docker inspect -f '{{.State.Running}}' "$pbx")" == "true" ] || die "izPBX exited before the module install"
    sleep 1
  done
  docker kill "$pbx" >/dev/null
  log "variant interrupted: killed at: $(docker logs "$pbx" 2>&1 | grep -E '^---> \[[0-9]+/[0-9]+\] installing module' | tail -1)"
  docker start "$pbx" >/dev/null
  start=$SECONDS
  until docker logs "$pbx" 2>&1 | grep -q 'supervisord started'; do
    [ $((SECONDS - start)) -lt 600 ] || die "second start did not reach supervisord"
    sleep 5
  done
  docker exec "$pbx" test -s /data/.initialized || die "second start did not create /data/.initialized"
}
variant_manifest() { echo "anomaly=first install interrupted during the module install: .initialized present, DB incomplete"; }
