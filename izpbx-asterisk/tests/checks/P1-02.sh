#!/usr/bin/env bash
# P1-02: build/lib.sh fetch_verified downloads over HTTPS only and keeps a
# file only when its sha256 matches (wrong sha -> exit != 0, no file left;
# http:// -> refused), with retries; arch_var and load_versions behave.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
blib="$REPO_DIR/izpbx-asterisk/build/lib.sh"
venv="$REPO_DIR/izpbx-asterisk/versions.env"

# run a snippet with build/lib.sh loaded, in a clean bash
in_lib() { FETCH_RETRY_DELAY=0 bash -c ". '$blib'; $1" >"$work/out" 2>&1; }

url=$(printf 'https://raw.githubusercontent.com/asterisk/third-party/master/jansson/%s/jansson-%s.tar.bz2' \
  "$(sed -n 's/^JANSSON_VER=//p' "$venv")" "$(sed -n 's/^JANSSON_VER=//p' "$venv")")
sha=$(sed -n 's/^JANSSON_SHA256=//p' "$venv")
bad=0000000000000000000000000000000000000000000000000000000000000000

assert_cmd "correct sha256: download kept" -- in_lib "fetch_verified '$url' $sha '$work/ok/jansson.tar.bz2'"
assert_eq "$sha" "$(sha256sum "$work/ok/jansson.tar.bz2" 2>/dev/null | cut -d' ' -f1)" "kept file has the expected sha256"
assert_cmd "second call uses the verified file" -- in_lib "fetch_verified '$url' $sha '$work/ok/jansson.tar.bz2'"
assert_contains "$(cat "$work/out")" "cached" "no second download"

assert_cmd_fails "wrong sha256: fails" -- in_lib "fetch_verified '$url' $bad '$work/bad/jansson.tar.bz2'"
assert_contains "$(cat "$work/out")" "sha256 mismatch" "mismatch is reported"
assert_eq "0" "$(find "$work/bad" -type f 2>/dev/null | wc -l)" "wrong sha256 leaves no file (nor .part)"

assert_cmd_fails "http:// URL: refused" -- in_lib "fetch_verified '${url/https:/http:}' $sha '$work/http/x'"
assert_contains "$(cat "$work/out")" "refusing non-HTTPS" "refusal is reported"
assert_cmd_fails "http:// URL: nothing written" -- test -e "$work/http/x"
assert_cmd_fails "invalid sha256 format: refused" -- in_lib "fetch_verified '$url' abc '$work/fmt/x'"

assert_cmd_fails "unreachable host: fails" -- in_lib "FETCH_RETRIES=3 FETCH_CONNECT_TIMEOUT=2; fetch_verified https://127.0.0.1:9/none $sha '$work/down/x'"
assert_eq "3" "$(grep -c 'download failed' "$work/out")" "three attempts before giving up"

x86=$(sed -n 's/^IONCUBE_SHA256_X86_64=//p' "$venv"); arm=$(sed -n 's/^IONCUBE_SHA256_AARCH64=//p' "$venv")
assert_eq "$x86" "$(bash -c ". '$blib'; load_versions '$venv'; TARGETARCH=amd64 arch_var IONCUBE_SHA256")" "arch_var picks the x86_64 value for amd64"
assert_eq "$arm" "$(bash -c ". '$blib'; load_versions '$venv'; TARGETARCH=arm64 arch_var IONCUBE_SHA256")" "arch_var picks the aarch64 value for arm64"
assert_cmd_fails "arch_var: unknown architecture fails" -- in_lib "load_versions '$venv'; TARGETARCH=s390x arch_var IONCUBE_SHA256"

assert_eq "22.11.0" "$(bash -c ". '$blib'; load_versions '$venv'; echo \$ASTERISK_VER")" "load_versions exports the versions"
printf 'X=$(touch %s/pwned)\n' "$work" > "$work/evil.env"
assert_cmd_fails "load_versions rejects shell code" -- in_lib "load_versions '$work/evil.env'"
assert_cmd_fails "shell code in versions.env is not executed" -- test -e "$work/pwned"

finish
