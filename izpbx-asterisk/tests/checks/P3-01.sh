#!/usr/bin/env bash
# P3-01: rootfs/usr/local/lib/izpbx/common.sh.
# - sedEscape/phpSquote (izpbx image: sed, php) and sqlEscape/sqlIdent (a
#   MariaDB server) round-trip hostile values: / & ' \ | newline backtick,
#   $(id), %s%n and mixes (izpbx-asterisk/tests/unit/common-escaping.sh); the same values
#   without escaping break the round trip (control);
# - izpbx_strict: an injected error logs "file:line" (also inside a sourced
#   library) and exits != 0; without it the script goes on (control);
# - readfsecret return codes, check_version ordering.
source "$(dirname "$0")/../lib.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
common="$REPO_DIR/izpbx-asterisk/rootfs/usr/local/lib/izpbx/common.sh"
unit="$TESTS_DIR/unit/common-escaping.sh"
image=izpbx-asterisk:p3-01
mounts=(-v "$common:/c/common.sh:ro" -v "$unit:/c/t.sh:ro" -v "$work:/w:ro")

assert_file "$common" "common.sh exists"
assert_cmd "image builds" -- t_build_image "$image"
in_img() { docker run --rm --entrypoint bash "${mounts[@]}" "$image" -c "$1" 2>&1; }

# --- escaping
out=$(in_img '/c/t.sh sed-php') && rc=0 || rc=$?
[ "$rc" -eq 0 ] || log "$out"
assert_eq 0 "$rc" "sedEscape and phpSquote round-trip every hostile value"
assert_ne "broken=0" "$(grep '^broken=' <<< "$out")" "control: unescaped values break sed/php"
db=$(t_run db docker.io/mariadb:10.11.19 -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 "${mounts[@]}" \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
out=$(docker exec "$db" bash /c/t.sh sql 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 0 ] || log "$out"
assert_eq 0 "$rc" "sqlEscape and sqlIdent round-trip every hostile value (MariaDB)"
assert_ne "broken=0" "$(grep '^broken=' <<< "$out")" "control: unescaped values break SQL"

# --- strict mode / error trap
printf 'f_in_lib() {\n  false\n}\n' > "$work/lib.sh"
printf '#!/bin/bash\n. /c/common.sh\nizpbx_strict\n. /w/lib.sh\necho before\nf_in_lib\necho after\n' > "$work/inj.sh"
printf '#!/bin/bash\n. /c/common.sh\nizpbx_strict\nls /izpbx-nonexistent >/dev/null\necho after\n' > "$work/inline.sh"
sed '/^izpbx_strict$/d' "$work/inj.sh" > "$work/loose.sh"
out=$(in_img 'bash /w/inj.sh; echo "rc=$?"')
assert_contains "$out" "/w/lib.sh:2: 'false' exited with status 1" "error inside a library: file:line logged"
assert_contains "$out" "rc=1" "error inside a library: exit != 0"
assert_eq 0 "$(grep -c '^after$' <<< "$out" || true)" "error inside a library: the script stops"
out=$(in_img 'bash /w/inline.sh; echo "rc=$?"')
assert_contains "$out" "/w/inline.sh:4: 'ls /izpbx-nonexistent > /dev/null' exited with status 2" "error in the script: file:line logged"
assert_contains "$out" "rc=2" "error in the script: its exit code"
out=$(in_img 'bash /w/loose.sh; echo "rc=$?"')
assert_contains "$out" $'after\nrc=0' "control: without izpbx_strict the script goes on"

# --- readfsecret, check_version
out=$(in_img '. /c/common.sh; printf "s3 cr3t\n" > /tmp/f; F=/tmp/f; E=; N=/nope; X=keep
  readfsecret F P; echo "ok=$? P=$P"; readfsecret F X; echo "set=$? X=$X"
  readfsecret E Y; echo "empty=$?"; readfsecret N Z; echo "unreadable=$?"; readfsecret F; echo "syntax=$?"')
for e in "ok=0 P=s3 cr3t" "set=129 X=keep" "empty=128" "unreadable=1" "syntax=1"; do
  assert_contains "$out" "$e" "readfsecret: $e"
done
cv=$(in_img '. /c/common.sh; for v in 17.0.33 17.0.18.54 22.11.0-rc1 08.09 22.11.0; do printf "%s=%s\n" "$v" "$(check_version "$v")"; done')
assert_contains "$cv" "17.0.33=017000033000" "check_version 17.0.33"
assert_contains "$cv" "08.09=008009000000" "check_version: leading zeros are decimal"
assert_contains "$cv" "22.11.0-rc1=022011000000" "check_version ignores a -rc suffix"
lt() { [ "$(grep "^$1=" <<< "$cv" | cut -d= -f2)" \< "$(grep "^$2=" <<< "$cv" | cut -d= -f2)" ]; }
assert_cmd "check_version: 17.0.18.54 < 17.0.33" -- lt 17.0.18.54 17.0.33
assert_cmd_fails "control: 22.11.0 is not < 17.0.33" -- lt 22.11.0 17.0.33

docker rmi "$image" >/dev/null 2>&1 || true
finish
