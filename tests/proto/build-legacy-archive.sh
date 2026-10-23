#!/usr/bin/env bash
# Variant B prototype (P0-10): build a FreePBX "legacy" backup archive, which
# the FreePBX 17 Backup module restores, from the raw data of a 20.16.x
# fixture (DB dump + /data tar).
#
#   tests/proto/build-legacy-archive.sh FIXTURE_DIR OUT.tar.gz [--drop-table TABLE]
#
# Archive layout (what Handlers/Restore/Legacy.php reads):
#   manifest                   JSON: pbx_version, fpbx_db, fpbx_cdrdb, file_list
#   astdb                      JSON: family -> key -> value (from astdb.sqlite3)
#   mysql-2.sql                config DB, one INSERT per line (the restore parses
#                              the dump line by line into SQLite)
#   etc/asterisk/*_custom*.conf  restored because file_list has etc/asterisk
# The CDR database is not in the archive: the migration leaves it untouched.
# --drop-table removes a table from the dump (negative tests).

TEST_ID=legacy-archive
fixture=$(cd "${1:?usage: $0 FIXTURE_DIR OUT.tar.gz}" && pwd)
out=${2:?usage: $0 FIXTURE_DIR OUT.tar.gz}
drop=
[ "${3:-}" == "--drop-table" ] && drop=${4:?--drop-table needs a table}
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

mf() { sed -n "s/^$1=//p" "$fixture/manifest.txt"; }
dbname=$(mf db_config); dbname=${dbname:-asterisk}
cdrname=$(mf db_cdr); cdrname=${cdrname:-asteriskcdrdb}

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
mkdir -p "$work/arc/etc/asterisk"

db=$(t_run db docker.io/mariadb:10.11.19 -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
gzip -dc "$fixture/asterisk.sql.gz" | docker exec -i "$db" mariadb -uroot || die "cannot load the config dump"
[ -z "$drop" ] || docker exec "$db" mariadb -uroot -e "DROP TABLE \`$dbname\`.\`$drop\`"
docker exec "$db" mariadb-dump -uroot --skip-extended-insert --skip-dump-date --skip-comments \
  --no-create-db --single-transaction "$dbname" > "$work/arc/mysql-2.sql"
version=$(docker exec "$db" mariadb -uroot -N -B -e "SELECT value FROM \`$dbname\`.admin WHERE variable='version'")
[ -n "$version" ] || die "no admin.version in the dump"

tar -C "$work" -xzf "$fixture/data.tar.gz" ./var/lib/asterisk/astdb.sqlite3 2>/dev/null || die "no astdb.sqlite3 in data.tar.gz"
tar -C "$work/arc" -xzf "$fixture/data.tar.gz" --wildcards './etc/asterisk/*_custom*.conf' 2>/dev/null || true

python3 -I - "$work" "$version" "$dbname" "$cdrname" <<'PY'
import json, sqlite3, sys
work, version, dbname, cdrname = sys.argv[1:5]
astdb = {}
for key, value in sqlite3.connect(work + '/var/lib/asterisk/astdb.sqlite3').execute('SELECT key, value FROM astdb'):
    parts = key.strip('/').split('/', 1)
    if len(parts) == 2:
        astdb.setdefault(parts[0], {})[parts[1]] = value
json.dump(astdb, open(work + '/arc/astdb', 'w'))
manifest = {
    'pbx_version': version, 'fpbx_db': dbname, 'fpbx_cdrdb': cdrname,
    'name': 'izpbx-migration', 'hostname': 'izpbx', 'emailaddr': '', 'ctime': 0,
    'mysql_count': 1, 'astdb_count': len(astdb), 'file_count': 0,
    'file_list': {'etc': {'asterisk': {}}},
}
json.dump(manifest, open(work + '/arc/manifest', 'w'))
PY

tar -C "$work/arc" -czf "$out" .
log "archive $out: FreePBX $version, $(wc -l < "$work/arc/mysql-2.sql") SQL lines, $(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$work/arc/astdb") astdb families"
