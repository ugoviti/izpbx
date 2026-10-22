#!/usr/bin/env bash
# P0-02: the test harness works (assertions, timeouts, cleanup after errors).
source "$(dirname "$0")/../lib.sh"

assert_cmd "harness selftest passes" -- "$TESTS_DIR/run.sh" selftest
assert_cmd "support services compose file is valid" -- \
  docker compose -f "$COMPOSE_FILE" --profile mail --profile sip config -q
for f in run.sh lib.sh selftest.sh; do
  assert_cmd "$f is valid bash" -- bash -n "$TESTS_DIR/$f"
done

finish
