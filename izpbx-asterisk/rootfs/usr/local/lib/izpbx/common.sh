#!/bin/bash
# izPBX shared helpers, sourced by izpbx-init and the other izPBX scripts:
#   . /usr/local/lib/izpbx/common.sh
#
# izpbx_strict                    set -Eeuo pipefail + ERR trap logging file:line
# log_info / log_ok / log_warn / log_error / log_detail "component: message"
#                                 one log line on stderr (format below)
# log_section TITLE               separator line between phases
# izpbx_log_redirect NAME [DROP]  output of the commands that follow labeled NAME
# die MSG...                      log_error and exit 1
# sedEscape / phpSquote / sqlEscape / sqlIdent   escaping of untrusted values
# readfsecret FILEVAR TARGETVAR   read a secret file (docker secrets) into a variable
# set_line_secret FILE RE PREFIX VAR   write a secret into a file, never on a command line
# check_version VER               zero-padded number to compare versions
#
# Every function is self-contained, so tests can source this file alone.

[ -n "${IZPBX_COMMON_LOADED:-}" ] && return 0
IZPBX_COMMON_LOADED=1

## logging
# The messages are "component: text". IZPBX_LOG_FORMAT chooses the output:
# - text (default), for the docker console: a status mark, the level word on
#   warnings and errors, the component right aligned so that every message
#   starts in the same column ("component: text" stays one string, for grep):
#      *               freepbx: FreePBX 17.0.33 installed         info
#      +               freepbx: ...                               ok (a step done)
#      !  WARNING    migration: ENABLE_ARI was enabled ...        warning
#     !!  ERROR           fop2: install of the package failed     error
#                               - CHANGE extensions_custom.conf   detail: under the
#                                 line before (log_detail, or a text starting with 2 spaces)
#      |                chrony: Selected source ...               output of another program
#     ---- 18 freepbx ---------------------------------------     log_section
#   ANSI colors on the mark and the level (red errors, yellow warnings, dim
#   details and program output), off with IZPBX_LOG_COLOR=false or NO_COLOR;
# - logfmt / json, for log collectors (Loki, ELK): one record per line with
#   time, level, component and msg; no colors.
# Warnings and errors (not their details) are also appended to the file
# IZPBX_LOG_ISSUES when set: izpbx-init repeats them in its final summary.
IZPBX_LOG_WIDTH=20 # level word + component
izpbx_log_color() { [ "${IZPBX_LOG_COLOR:-true}" == "true" ] && [ -z "${NO_COLOR:-}" ] && [ "${IZPBX_LOG_FORMAT:-text}" == "text" ]; }
_izpbx_log_quote() { # logfmt/json string: backslash, quote, control characters
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '"%s"' "$s"
}
# _izpbx_log_emit LEVEL COMPONENT TEXT DETAIL(0|1)
# LEVEL: info ok warning error section external
_izpbx_log_emit() {
  local level=$1 comp=$2 msg=$3 detail=$4 mark word line c='' cm='' pad n ts
  if [ "$detail" == 1 ]; then msg=${msg#"${msg%%[! ]*}"}; fi
  if [ -n "${IZPBX_LOG_ISSUES:-}" ] && [ "$detail" == 0 ] && { [ "$level" == warning ] || [ "$level" == error ]; }; then
    printf '%s\t%s\n' "$level" "${comp:+$comp: }$msg" >> "$IZPBX_LOG_ISSUES" 2>/dev/null || true
  fi
  case ${IZPBX_LOG_FORMAT:-text} in
    logfmt|json)
      printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
      local extra=''
      case $level in
        ok) level=info ;;
        section) level=info extra=section ;;
        external) level=info extra=external ;;
      esac
      if [ "${IZPBX_LOG_FORMAT}" == json ]; then
        line="{\"time\":\"$ts\",\"level\":\"$level\",\"component\":$(_izpbx_log_quote "${comp:-izpbx}"),\"msg\":$(_izpbx_log_quote "$msg")"
        [ "$extra" != external ] || line+=',"source":"external"'
        [ "$extra" != section ] || line+=',"section":true'
        [ "$detail" == 0 ] || line+=',"detail":true'
        line+='}'
      else
        line="time=$ts level=$level component=${comp:-izpbx} msg=$(_izpbx_log_quote "$msg")"
        [ "$extra" != external ] || line+=' source=external'
        [ "$extra" != section ] || line+=' section=true'
        [ "$detail" == 0 ] || line+=' detail=true'
      fi ;;
    *)
      case $level in
        info) mark=' *' word='' c='36' ;;
        ok) mark=' +' word='' c='1;32' ;;
        warning) mark=' !' word=WARNING c='1;33' cm='33' ;;
        error) mark='!!' word=ERROR c='1;31' cm='1;31' ;;
        external) mark=' |' word='' c='2' cm='2'
          # the level a program writes in its own line
          if [[ "$msg" =~ (^|[^[:alpha:]])(ERROR|FATAL|CRITICAL|[Ee]rror|[Ff]ailed)([^[:alpha:]]|$) ]]; then cm='31'
          elif [[ "$msg" =~ (^|[^[:alpha:]])(WARNING|WARN|[Ww]arning)([^[:alpha:]]|$) ]]; then cm='33'; fi ;;
        section)
          line="---- $msg "; [ -n "$msg" ] || line='' # no title: closing line
          n=$(( 72 - ${#line} )); [ "$n" -gt 4 ] || n=4
          printf -v pad '%*s' "$n" ''; line+=${pad// /-}
          izpbx_log_color && line=$'\e[1;36m'"$line"$'\e[0m'
          _izpbx_log_write "$line"; return 0 ;;
      esac
      if [ "$detail" == 1 ]; then
        mark='  ' word='' comp='' c='' msg="- $msg"
        case $level in error|warning) ;; *) cm='2' ;; esac
      fi
      # mark, then "WORD " and the padding so that "component: " ends at the
      # same column on every line
      word=${word:+$word }
      # "component:" takes its length + 1; without a component the space after
      # the colon is padding too
      n=$(( IZPBX_LOG_WIDTH + 1 - ${#word} - ${#comp} ))
      [ -z "$comp" ] || n=$((n - 2))
      [ "$n" -ge 0 ] || n=0
      printf -v pad '%*s' "$n" ''
      comp=${comp:+$comp: }
      if izpbx_log_color; then
        local on1='' on2='' off1='' off2=''
        [ -z "$c" ] || { on1=$'\e['"$c"'m' off1=$'\e[0m'; }
        [ -z "$cm" ] || { on2=$'\e['"$cm"'m' off2=$'\e[0m'; }
        line="$on1$mark $word$off1$pad$on2$comp$msg$off2"
      else
        line="$mark $word$pad$comp$msg"
      fi ;;
  esac
  _izpbx_log_write "$line"
}
# a line on stderr; inside the output labeled by izpbx_log_redirect it is
# marked (\x1f), so that izpbx_log_tag prints it as it is, in order
_izpbx_log_write() {
  # (no redirection on the test: it would change fd 2 while it runs)
  if [ -n "${IZPBX_LOG_TAG_PID:-}" ] && [ /proc/self/fd/2 -ef "/proc/$IZPBX_LOG_TAG_PID/fd/0" ]; then
    printf '\x1f%s\n' "$1" >&2
  else
    printf '%s\n' "$1" >&2
  fi
}
izpbx_log() { # level message...: "component: text" split, a text starting with 2 spaces is a detail
  local level=$1 msg comp='' detail=0; shift; msg="$*"
  [ "$level" != detail ] || { level=info detail=1; }
  if [[ "$msg" =~ ^([A-Za-z0-9_.-]+):\ (.*)$ ]]; then comp=${BASH_REMATCH[1]} msg=${BASH_REMATCH[2]}; fi
  [[ "$msg" != "  "* ]] || detail=1
  _izpbx_log_emit "$level" "$comp" "$msg" "$detail"
}
log_info() { izpbx_log info "$@"; }
log_ok() { izpbx_log ok "$@"; }
log_warn() { izpbx_log warning "$@"; }
log_error() { izpbx_log error "$@"; }
log_detail() { izpbx_log detail "$@"; }
log_section() { _izpbx_log_emit section "" "$*" 0; }
die() { log_error "$@"; exit 1; }

# izpbx_log_tag NAME [DROP]: stdin -> log lines of the program NAME; empty
# lines, the lines matching the regex DROP and the timestamp at the start of
# a line (docker has its own) left out; lines of izPBX (\x1f) printed as they are
_IZPBX_LOG_TS='^(\[?[0-9]{2,4}[-/][0-9A-Za-z]{2,3}[-/][0-9]{2,4}[ T][0-9:.,]+(Z|[+-][0-9:]{4,5})?\]?:?[[:space:]]+)'
izpbx_log_tag() {
  local name=$1 drop=${2:-} line
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == $'\x1f'* ]]; then printf '%s\n' "${line:1}" >&2; continue; fi
    line=${line%$'\r'}
    [ -n "${line//[[:space:]]/}" ] || continue
    if [ -n "$drop" ] && [[ "$line" =~ $drop ]]; then continue; fi
    if [[ "$line" =~ $_IZPBX_LOG_TS ]]; then line=${line:${#BASH_REMATCH[1]}}; fi
    _izpbx_log_emit external "$name" "$line" 0
  done
}
# izpbx_log_redirect NAME [DROP]: stdout and stderr of this shell (and of the
# commands it runs, or execs) through izpbx_log_tag NAME. Called again, it
# replaces the previous label, after the lines of the previous one are
# written (the original output is kept in IZPBX_LOG_OUT).
izpbx_log_redirect() {
  if [ -n "${IZPBX_LOG_OUT:-}" ]; then izpbx_log_redirect_end; else exec {IZPBX_LOG_OUT}>&2; fi
  exec > >(izpbx_log_tag "$1" "${2:-}") 2>&1
  # exported: the izPBX scripts run from here mark their lines too
  export IZPBX_LOG_TAG_PID=$!
}
# izpbx_log_redirect_end: back to the original output, after the labeled one
# is written: its filter ends at once, unless a daemon started meanwhile keeps
# the output open (then at most 1 second, and the daemon keeps that label)
izpbx_log_redirect_end() {
  local i
  [ -n "${IZPBX_LOG_OUT:-}" ] || return 0
  exec 1>&"$IZPBX_LOG_OUT" 2>&"$IZPBX_LOG_OUT"
  if [ -n "${IZPBX_LOG_TAG_PID:-}" ]; then
    for ((i = 0; i < 20; i++)); do kill -0 "$IZPBX_LOG_TAG_PID" 2>/dev/null || break; sleep 0.05; done
  fi
  IZPBX_LOG_TAG_PID=
}

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

## secrets on the command line: set_line_secret FILE REGEX LINE_PREFIX VARNAME
# Replace each line of FILE matching the extended REGEX with LINE_PREFIX and
# the value of the variable VARNAME, read by awk from the environment: the
# secret is never an argument of a process (sed would show it, P3-21). The
# file keeps its inode, owner and mode. Return 1 if FILE cannot be written.
set_line_secret() {
  local file=$1 re=$2 prefix=$3 tmp
  tmp=$(mktemp) || return 1
  IZPBX_SECRET_VALUE=${!4} awk -v re="$re" -v prefix="$prefix" \
    '$0 ~ re {print prefix ENVIRON["IZPBX_SECRET_VALUE"]; next} {print}' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  cmp -s "$tmp" "$file" || cat "$tmp" > "$file" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
}

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
