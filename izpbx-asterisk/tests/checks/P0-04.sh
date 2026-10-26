#!/usr/bin/env bash
# P0-04: the 20.16.22 fixture regenerates from scratch and holds every T5
# element; a tampered copy is rejected.
source "$(dirname "$0")/../lib.sh"

out="$TESTS_DIR/fixtures/out"
fx="$out/20.16.22"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

# TEST_REUSE_FIXTURES=1 (run.sh all-done) reuses a fixture built from unchanged inputs
[ -n "${TEST_REUSE_FIXTURES:-}" ] || rm -rf "$fx"
assert_cmd "fixture regenerates from scratch" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 -o "$out" ${TEST_REUSE_FIXTURES:+--reuse}
"$TESTS_DIR/fixtures/verify-fixture.sh" "$fx" >"$work/verify.log" 2>&1 && rc=0 || rc=$?
cat "$work/verify.log" | grep -v ' PASS: ' >&2
assert_eq 0 "$rc" "every T5 category has at least one element"

# negative: no IVR in the dump, no voicemail messages in /data
bad="$work/bad"
mkdir -p "$bad/data"
cp "$fx/asteriskcdrdb.sql.gz" "$fx/manifest.txt" "$bad/"
# drop the whole INSERT statement (mariadb-dump splits it over several lines)
gzip -dc "$fx/asterisk.sql.gz" | awk '/^INSERT INTO `ivr_details`/{skip=1} !skip{print} skip&&/;$/{skip=0}' | gzip -n > "$bad/asterisk.sql.gz"
tar -C "$bad/data" -xzf "$fx/data.tar.gz" 2>/dev/null
find "$bad/data/var/spool/asterisk/voicemail" -name 'msg*' -delete
tar -C "$bad/data" -czf "$bad/data.tar.gz" . && t_rmtree "$bad/data"
"$TESTS_DIR/fixtures/verify-fixture.sh" "$bad" >"$work/bad.log" 2>&1 && rc=0 || rc=$?
assert_ne 0 "$rc" "a tampered fixture is rejected"
assert_contains "$(cat "$work/bad.log")" "FAIL: ivr is empty" "missing IVR is reported"
assert_contains "$(cat "$work/bad.log")" "FAIL: voicemail messages is empty" "missing voicemail messages are reported"

finish
