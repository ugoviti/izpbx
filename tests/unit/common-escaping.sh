#!/bin/bash
# Unit tests of common.sh, run inside a container (see tests/checks/P3-01.sh):
#   common-escaping.sh sed-php   in the izpbx image (sed, php)
#   common-escaping.sh sql       in a MariaDB container (server running)
# Prints one "FAIL ..." line per wrong round trip and "broken=N" for the
# unescaped controls; exit 1 if any escaped round trip is wrong.
# shellcheck source=../../izpbx-asterisk/rootfs/usr/local/lib/izpbx/common.sh
. /c/common.sh
vals=( '/' '&' "'" '\' '|' $'\n' '`' $'a/b&c\'d\\e|f\ng`h' '$(id)' '%s%n' $'\\\'' 'x\' )
fail=0 broken=0
show() { printf '%q' "$1"; }
check() { # name value result
  [ "$3" == "$2" ] || { echo "FAIL $1: $(show "$2") -> $(show "$3")"; fail=1; }
}
# command substitution drops trailing newlines: a "." sentinel keeps them.
# sedEscape keeps trailing newlines (exact round trip); with phpSquote,
# sqlEscape and sqlIdent the caller's "$(...)" drops them (documented in
# common.sh), so the expected value is the value without trailing newlines
nonl() { local s=$1; while [[ "$s" == *$'\n' ]]; do s=${s%$'\n'}; done; printf '%s' "$s"; }
case "$1" in
  sed-php)
    for v in "${vals[@]}"; do
      r=$(printf X | sed "s/X/$(sedEscape "$v")/"; printf .); check "sedEscape (/)" "$v" "${r%.}"
      r=$(printf X | sed "s|X|$(sedEscape "$v")|"; printf .); check "sedEscape (|)" "$v" "${r%.}"
      r=$(php -r "echo '$(phpSquote "$v")', '.';"); check phpSquote "$(nonl "$v")" "${r%.}"
      # controls: the same values without escaping
      r=$(printf X | sed "s/X/$v/" 2>/dev/null; printf .); [ "${r%.}" == "$v" ] || broken=$((broken + 1))
      r=$(php -r "echo '$v', '.';" 2>/dev/null); [ "${r%.}" == "$v" ] || broken=$((broken + 1))
    done ;;
  sql)
    q() { mariadb -uroot -N -B --raw -e "$1"; }
    q "CREATE DATABASE IF NOT EXISTS t"
    for v in "${vals[@]}"; do
      w=$(nonl "$v")
      r=$(q "SELECT '$(sqlEscape "$v")'"; printf .); r=${r%.}; check sqlEscape "$w" "${r%$'\n'}"
      [ -n "$w" ] || continue  # an identifier cannot be empty
      q "CREATE TABLE t.\`$(sqlIdent "$v")\` (i int)" || { echo "FAIL sqlIdent: cannot create $(show "$v")"; fail=1; continue; }
      r=$(q "SELECT table_name FROM information_schema.tables WHERE table_schema='t'"; printf .); r=${r%.}
      check sqlIdent "$w" "${r%$'\n'}"
      q "DROP TABLE t.\`$(sqlIdent "$v")\`"
      r=$(q "SELECT '$v'" 2>/dev/null; printf .); r=${r%.}; [ "${r%$'\n'}" == "$v" ] || broken=$((broken + 1))
      q "CREATE TABLE t.\`$v\` (i int)" 2>/dev/null && { q "DROP TABLE t.\`$v\`" 2>/dev/null || q "DROP DATABASE t; CREATE DATABASE t"; } || broken=$((broken + 1))
    done ;;
  *) echo "usage: $0 sed-php|sql" >&2; exit 2 ;;
esac
echo "broken=$broken"
exit "$fail"
