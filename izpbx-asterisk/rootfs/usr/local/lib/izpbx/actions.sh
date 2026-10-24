# shellcheck shell=bash
# Actions with effects outside the generated files (database, FreePBX
# settings, commands), so that the dry-run mode can record them instead of
# running them (design R3: golden tests compare the generated files and the
# recorded calls with 20.16):
#   izpbx_dry_run                true in dry-run (izpbx-init --dry-run or IZPBX_DRY_RUN=true)
#   izpbx_record WORDS...        append one line to IZPBX_DRY_RUN_LOG
#   izpbx_do CMD...              run CMD, or record it in dry-run
#   fpbx_setting KEY VALUE       fwconsole setting KEY VALUE, or record it
#   izpbx_sql SQL                write statement on the FreePBX DB, or record it
#   izpbx_sql_query SQL          read query on the FreePBX DB (runs in dry-run too)
# shellcheck source=common.sh
. /usr/local/lib/izpbx/common.sh
# shellcheck source=env.sh
. /usr/local/lib/izpbx/env.sh

: "${IZPBX_DRY_RUN:=false}"
: "${IZPBX_DRY_RUN_LOG:=/run/izpbx/dry-run.log}"

izpbx_dry_run() { [ "$IZPBX_DRY_RUN" == "true" ]; }

izpbx_record() {
  mkdir -p "$(dirname "$IZPBX_DRY_RUN_LOG")"
  printf '%s\n' "$*" >> "$IZPBX_DRY_RUN_LOG"
}

izpbx_do() {
  if izpbx_dry_run; then izpbx_record "$@"; return 0; fi
  "$@"
}

fpbx_setting() { izpbx_do fwconsole setting "$1" "$2"; }

# the password goes through the environment, not the command line
_izpbx_mariadb() {
  MYSQL_PWD="$MYSQL_PASSWORD" mariadb -h "$MYSQL_SERVER" -P "$APP_PORT_MYSQL" \
    -u "$MYSQL_USER" --connect-timeout=5 --batch --skip-column-names "$MYSQL_DATABASE" -e "$1"
}

izpbx_sql() {
  if izpbx_dry_run; then izpbx_record "sql: $1"; return 0; fi
  _izpbx_mariadb "$1"
}

izpbx_sql_query() { _izpbx_mariadb "$1"; }
