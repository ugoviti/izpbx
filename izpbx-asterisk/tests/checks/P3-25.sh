#!/usr/bin/env bash
# P3-25 (T16): golden test of the whole .env matrix.
# - "izpbx-asterisk/tests/run.sh golden all": every case of izpbx-asterisk/tests/golden/cases is "same"
#   (each file of its "# expect:" list equal to 20.16.22 through the rules of
#   izpbx-asterisk/tests/golden/map/files.sh), exit 0;
# - controls, on a copy of the golden tree (TEST_GOLDEN_DIR): an altered
#   20.16.22 file, a file without a mapping rule and a different value in a
#   case .env are each reported.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-25
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

out=$("$TESTS_DIR/run.sh" golden all 2>&1) && rc=0 || rc=$?
printf '%s\n' "$out" | sed 's/^/    /' >&2
assert_eq 0 "$rc" "izpbx-asterisk/tests/run.sh golden all: exit 0"
ncases=$(find "$TESTS_DIR/golden/cases" -name '*.env' | wc -l)
assert_eq "$ncases" "$(grep -c ' same ' <<< "$out")" "every case ($ncases) same as 20.16.22"

cp -a "$TESTS_DIR/golden" "$work/g"
echo "dhcp-range=10.0.0.1,10.0.0.9,1h" >> "$work/g/20.16.22/dnsmasq/files/etc/dnsmasq.d/local.conf"
sed -i 's|^# expect: \(.*\)|# expect: \1 /etc/no-rule.conf|' "$work/g/cases/msmtp.env"
sed -i 's|^NTP_SERVERS=.*|NTP_SERVERS=other.pool.example|' "$work/g/cases/ntp.env"
grep -q '^NTP_SERVERS=other' "$work/g/cases/ntp.env" || echo "NTP_SERVERS=other.pool.example" >> "$work/g/cases/ntp.env"
neg=$(TEST_GOLDEN_DIR="$work/g" "$TESTS_DIR/golden/compare.sh" "$image" "$work/out" dnsmasq msmtp ntp 2>&1) && rc=0 || rc=$?
printf '%s\n' "$neg" | sed 's/^/    /' >&2
assert_eq 1 "$rc" "control: the altered tree fails"
assert_contains "$neg" "dnsmasq        DIFFERS" "control: an altered 20.16.22 file is reported"
assert_contains "$(cat "$work/out/msmtp.diff")" "no rule for /etc/no-rule.conf" "control: a file without a rule is reported"
assert_contains "$neg" "ntp            DIFFERS" "control: a different value in a case .env is reported"
finish
