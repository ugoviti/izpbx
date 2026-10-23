# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # sourced by make-fixture.sh: shares its variables
# module17: a module with no FreePBX 17 release installed.
# irc is GPL and installs without extra services (xmpp needs MongoDB,
# cloudmigration and vega are commercial).
variant_post_populate() {
  log "variant module17: installing irc 16.0.1 (no FreePBX 17 release)"
  docker exec -u asterisk "$pbx" fwconsole ma downloadinstall irc --tag=16.0.1
  docker exec "$pbx" fwconsole ma list | grep -qE '^\| irc +\| 16\.0\.1 +\| Enabled' || die "irc 16.0.1 is not enabled"
}
variant_manifest() { echo "anomaly=module irc 16.0.1 has no FreePBX 17 release"; }
