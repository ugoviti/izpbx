#!/usr/bin/env bash
# P0-07: the golden harness runs 20.16.22 on every .env case, each case yields
# its expected non-empty files, two runs are byte-identical and match the
# golden files committed in tests/golden/20.16.22.
source "$(dirname "$0")/../lib.sh"

golden="$TESTS_DIR/golden"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

# expected files of a case: the "# expect:" header of its .env
expected_ok() { # run_dir -> 0 if every case has all its expected files, non-empty
  local env name f rc=0
  for env in "$golden"/cases/*.env; do
    name=$(basename "$env" .env)
    for f in $(sed -n 's/^# expect: //p' "$env"); do
      [ -s "$1/$name/files$f" ] || { echo "case $name: missing or empty $f"; rc=1; }
    done
  done
  return $rc
}

assert_cmd "first golden run" -- "$golden/run-golden.sh" -o "$work/a"
assert_cmd "second golden run" -- "$golden/run-golden.sh" -o "$work/b"
ncases=$(find "$golden/cases" -name '*.env' | wc -l)
assert_eq "$ncases" "$(find "$work/a" -mindepth 1 -maxdepth 1 -type d | wc -l)" "one output directory per case ($ncases)"
out=$(expected_ok "$work/a") && rc=0 || rc=$?
[ -z "$out" ] || log "$out"
assert_eq 0 "$rc" "every case produced its expected non-empty files"
assert_cmd "two consecutive runs are byte-identical" -- diff -r "$work/a" "$work/b"
assert_cmd "the run matches the committed golden files" -- diff -r "$work/a" "$golden/20.16.22"

# negative: a changed byte and a missing expected file are both caught
cp -a "$work/a" "$work/c"
sed -i 's/Listen 80/Listen 81/' "$work/c/default/files/etc/httpd/conf/httpd.conf"
assert_cmd_fails "a changed file is detected" -- diff -r "$work/a" "$work/c"
rm "$work/c/postfix/files/etc/postfix/sasl_passwd"
assert_cmd_fails "a missing expected file is detected" -- expected_ok "$work/c"

finish
