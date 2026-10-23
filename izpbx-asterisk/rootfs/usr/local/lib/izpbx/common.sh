#!/bin/bash
# izPBX shared helpers, sourced by izpbx-init and the other izPBX scripts:
#   . /usr/local/lib/izpbx/common.sh
#
# izpbx_strict                    set -Eeuo pipefail + ERR trap logging file:line
# izpbx_log LEVEL MSG...          "izpbx: LEVEL: MSG" on stderr (log_info/log_warn/log_error)
# die MSG...                      log_error and exit 1
# sedEscape / phpSquote / sqlEscape / sqlIdent   escaping of untrusted values
# readfsecret FILEVAR TARGETVAR   read a secret file (docker secrets) into a variable
# check_version VER               zero-padded number to compare versions
#
# Every function is self-contained, so tests can source this file alone.

[ -n "${IZPBX_COMMON_LOADED:-}" ] && return 0
IZPBX_COMMON_LOADED=1

## logging
izpbx_log() { local level=$1; shift; printf 'izpbx: %s: %s\n' "$level" "$*" >&2; }
log_info() { izpbx_log info "$@"; }
log_warn() { izpbx_log warning "$@"; }
log_error() { izpbx_log error "$@"; }
die() { log_error "$@"; exit 1; }

## strict mode: every failing command stops the script and says where
# (functions and subshells inherit the trap thanks to -E)
izpbx_on_error() { # rc file line command
  izpbx_log error "${2}:${3}: '${4}' exited with status ${1}"
}
izpbx_strict() {
  set -Eeuo pipefail
  trap 'izpbx_on_error "$?" "${BASH_SOURCE[0]:-$0}" "$LINENO" "$BASH_COMMAND"' ERR
}

## escaping (values from environment variables may contain any character).
# Pure bash: no subprocess, and newlines are kept. Note: the caller's
# "$(...)" drops trailing newlines of the result, so with phpSquote,
# sqlEscape and sqlIdent a value loses its trailing newlines (as values read
# with "$(<file)" do); sedEscape encodes them as \n and keeps them.
# REPLACEMENT part of a sed 's' command using '/' or '|' as delimiter
sedEscape() {
  local s=${1//\\/\\\\}
  s=${s//\//\\/}; s=${s//&/\\&}; s=${s//|/\\|}; s=${s//$'\n'/\\n}
  printf '%s' "$s"
}
# inside a PHP single quoted string: '...'
phpSquote() { local s=${1//\\/\\\\}; printf '%s' "${s//\'/\\\'}"; }
# inside a SQL single quoted string literal: '...' (backslash escapes on,
# the MariaDB default: no NO_BACKSLASH_ESCAPES in sql_mode)
sqlEscape() { local s=${1//\\/\\\\}; printf '%s' "${s//\'/\\\'}"; }
# SQL identifier between backticks: `...`
sqlIdent() { printf '%s' "${1//\`/\`\`}"; }

## secrets: readfsecret FILEVAR TARGETVAR
# FILEVAR holds the path of the secret file, TARGETVAR receives its content.
# Return: 0 ok, 1 syntax error or unreadable file, 128 FILEVAR empty,
# 129 TARGETVAR already set (an explicit value wins over the file).
readfsecret() {
  if [ $# -lt 2 ]; then
    log_error "readfsecret: not enough parameters"
    return 1
  elif [ -z "${!1:-}" ]; then
    log_warn "readfsecret: '$1' (path of the secret file) is empty"
    return 128
  elif [ -n "${!2:-}" ]; then
    log_warn "readfsecret: '$2' is already set, not overwritten by the file in '$1'"
    return 129
  elif [ -r "${!1}" ]; then
    local -n _izpbx_target=$2
    _izpbx_target="$(<"${!1}")"
  else
    log_error "readfsecret: cannot read the secret file '${!1}' ('$1')"
    return 1
  fi
  [ -n "${!2}" ] || log_warn "readfsecret: '$2' is empty (empty secret file '${!1}')"
  return 0
}

## versions: check_version 17.0.18.54 -> 017000018054 (up to 4 numeric parts,
# a non numeric suffix such as "-rc1" is ignored)
check_version() {
  local v=${1%%[!0-9.]*} a b c d
  IFS=. read -r a b c d _ <<< "$v"
  printf '%03d%03d%03d%03d' "$((10#${a:-0}))" "$((10#${b:-0}))" "$((10#${c:-0}))" "$((10#${d:-0}))"
}
