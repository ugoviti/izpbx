#!/usr/bin/env bash
# P7-11: izpbx-deploy (docs/izpbx-deploy.md), run on the host (no container),
# with awk in POSIX mode (the image has mawk):
# - upgrade of a .env with a known base (3-way merge): untouched default
#   follows the new one, customized values kept at the place of the new
#   default.env (uncommented example, alternative, after the examples),
#   disabled variable stays disabled, renamed variable, removed untouched
#   variable dropped, removed customized commented "# REMOVED in", custom
#   variable with its comment in "### Custom", versions moved to the image;
# - dry-run by default (exit 2, nothing written), --apply with backups and
#   the mode of the file kept, a second upgrade changes nothing (exit 0);
# - --prune, --keep-version, version series change refused without --major,
#   2-way merge without base (values kept, listed), --major replaces a
#   compose.yml of an unknown version (20.16) with backup;
# - compose.yml: untouched replaced, edited merged (diff3), conflict refused
#   (exit 3, neither file written);
# - init (random passwords, 0600, refuses existing files), compose and env on stdout;
# - IZPBX_VERSION is the one of the image (APP_VER, rc too; default.env for dev),
#   an image older than IZPBX_VERSION of the .env refused (rc before its release);
# - the real files: history and keys.txt in step (tools/deploy-sync.sh --check), a .env without the variables of 22.17
#   upgraded with --major keeps every value.
source "$(dirname "$0")/../lib.sh"

work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
deploy="$REPO_DIR/izpbx-asterisk/rootfs/usr/local/sbin/izpbx-deploy"
realshare="$REPO_DIR/izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy"

# awk in POSIX mode: no gawk extension can slip in (the image runs mawk)
if command -v gawk >/dev/null; then
  mkdir -p "$work/bin"
  printf '#!/bin/sh\nexec gawk --posix "$@"\n' > "$work/bin/awk"; chmod +x "$work/bin/awk"
  export PATH="$work/bin:$PATH"
fi

# --- synthetic image files: release 1.0.0 (base) and 1.0.1 (the image)
share=$work/share
mkdir -p "$share/history"
cat > "$share/history/1.0.0.env" <<'EOF'
### A
## doc a
IZPBX_VERSION=1.0.0
MARIADB_VERSION=10.0
KEEP=1
CHANGED_DEFAULT=old
#OPTIONAL=example
#TZ=Europe/Rome
MYSQL_SERVER=127.0.0.1
#MYSQL_SERVER=db
MYSQL_ROOT_PASSWORD=x
GONE_UNTOUCHED=1
GONE_CUSTOM=1
OLDNAME=a
EOF
cat > "$share/default.env" <<'EOF'
### A
## doc a new
IZPBX_VERSION=1.0.1
MARIADB_VERSION=10.1
KEEP=1
CHANGED_DEFAULT=new
## new var doc
NEWVAR=yes
#OPTIONAL=example
#TZ=Europe/Rome
#MYSQL_SERVER=db
MYSQL_SERVER=127.0.0.1
MYSQL_ROOT_PASSWORD=x
NEWNAME=a
EOF
printf 'OLDNAME NEWNAME 1.0.1\n' > "$share/renames.tsv"
{ cat "$share/history/1.0.0.env" "$share/default.env" | sed -nE 's/^#?([A-Z_]+)=.*/\1/p'; echo ANCIENT; } | sort -u > "$share/keys.txt"
printf 'services:\n  a:\n    image: x:1.0.0\n  b:\n    ports:\n    - 1\n' > "$share/history/1.0.0.compose.yml"
printf 'services:\n  a:\n    image: x:1.0.1\n  b:\n    ports:\n    - 1\n' > "$share/compose.yml"

user_env() {
  cat <<'EOF'
### A
IZPBX_VERSION=1.0.0
MARIADB_VERSION=10.0
KEEP=2
CHANGED_DEFAULT=old
OPTIONAL=mine
TZ=Europe/Rome
MYSQL_SERVER=db
#MYSQL_ROOT_PASSWORD=x
GONE_UNTOUCHED=1
GONE_CUSTOM=2
OLDNAME=b
## my comment
MYCUSTOM=42
ANCIENT=1
EOF
}
expected() {
  cat <<'EOF'
### A
## doc a new
IZPBX_VERSION=1.0.1
MARIADB_VERSION=10.1
KEEP=2
CHANGED_DEFAULT=new
## new var doc
NEWVAR=yes
#OPTIONAL=example
OPTIONAL=mine
TZ=Europe/Rome
MYSQL_SERVER=db
#MYSQL_SERVER=127.0.0.1
#MYSQL_ROOT_PASSWORD=x
NEWNAME=b

### Custom
## variables not in default.env, kept by izpbx-deploy
## my comment
MYCUSTOM=42

### Removed
## variables no longer in default.env, commented by izpbx-deploy: delete them when not needed (or izpbx-deploy upgrade --prune)
# REMOVED in 1.0.1: GONE_CUSTOM=2
# REMOVED in 1.0.1: ANCIENT=1
EOF
}

d=$work/d
newdir() { rm -rf "$d"; mkdir -p "$d"; }
dep() { IZPBX_DEPLOY_DIR=$d IZPBX_DEPLOY_SHARE=$share "$deploy" "$@"; }
rc_of() { local rc=0; dep "$@" > "$work/out" 2>&1 || rc=$?; echo "$rc"; }

# --- 3-way merge, dry-run then --apply
newdir; user_env > "$d/.env"; chmod 0640 "$d/.env"; cp "$share/history/1.0.0.compose.yml" "$d/compose.yml"
sum_before=$(cat "$d/.env" "$d/compose.yml" | md5sum)
assert_eq 2 "$(rc_of upgrade)" "dry-run with changes: exit 2"
assert_eq "$sum_before" "$(cat "$d/.env" "$d/compose.yml" | md5sum)" "dry-run: nothing written"
assert_eq "" "$(find "$d" -name '*.bak' -o -name '.izpbx-deploy.*' | head -1)" "dry-run: no backup, no temporary file left"
out=$(cat "$work/out")
assert_contains "$out" "default changed: CHANGED_DEFAULT old -> new" "summary: default changed"
assert_contains "$out" "renamed (old new): OLDNAME" "summary: renamed"
assert_contains "$out" "custom variables, in the '### Custom' section: MYCUSTOM" "summary: custom"
assert_contains "$out" "after the restart run mariadb-upgrade" "summary: mariadb-upgrade reminder"
assert_contains "$out" "#MYSQL_ROOT_PASSWORD=*****" "diff: password values masked"
assert_eq "" "$(grep -F 'PASSWORD=x' "$work/out" || true)" "diff: no password value"
assert_eq 0 "$(rc_of upgrade --apply)" "--apply: exit 0"
assert_eq "$(expected)" "$(cat "$d/.env")" "3-way merge: the expected .env"
assert_eq 640 "$(stat -c %a "$d/.env")" "--apply: mode of .env kept"
assert_eq "$(cat "$share/compose.yml")" "$(cat "$d/compose.yml")" "untouched compose.yml replaced"
assert_eq 2 "$(find "$d" -name '*.bak' | wc -l)" "--apply: one backup per file"
assert_eq "$(user_env)" "$(cat "$d"/.env.*.bak)" "backup: the old .env"
assert_eq "" "$(find "$d" -name '.izpbx-deploy.*' | head -1)" "--apply: no temporary file left"
assert_eq 0 "$(rc_of upgrade)" "second upgrade: nothing to do, exit 0"
assert_contains "$(cat "$work/out")" "up to date" "second upgrade: up to date"
assert_eq 0 "$(rc_of upgrade --apply)" "second upgrade --apply: exit 0"
assert_eq 2 "$(find "$d" -name '*.bak' | wc -l)" "second upgrade --apply: no new backup"

# --- --prune, --no-backup
newdir; user_env > "$d/.env"
assert_eq 0 "$(rc_of upgrade --only env --prune --apply --no-backup)" "--prune --apply"
assert_eq "" "$(grep -E 'REMOVED|GONE_|ANCIENT' "$d/.env" || true)" "--prune: removed variables deleted"
assert_eq "" "$(find "$d" -name '*.bak' | head -1)" "--no-backup: no backup"
user_env > "$d/.env"; dep upgrade --only env --apply --no-backup >/dev/null
dep upgrade --only env --prune --apply --no-backup >/dev/null
assert_eq "" "$(grep -E 'REMOVED|Removed' "$d/.env" || true)" "--prune: earlier '# REMOVED in' lines deleted"

# --- --keep-version
newdir; user_env > "$d/.env"
dep upgrade --only env --keep-version --apply --no-backup >/dev/null
assert_eq "IZPBX_VERSION=1.0.0 MARIADB_VERSION=10.0" "$(grep -E '^(IZPBX|MARIADB)_VERSION=' "$d/.env" | xargs)" "--keep-version: versions of the .env kept"

# --- version series change, no base
newdir; user_env | sed 's/^IZPBX_VERSION=.*/IZPBX_VERSION=0.9.3/' > "$d/.env"
assert_eq 3 "$(rc_of upgrade)" "series 0.9 -> 1.0 refused without --major"
assert_contains "$(cat "$work/out")" "--major" "refusal names --major"
newdir; user_env | grep -v '^IZPBX_VERSION=' > "$d/.env"
printf 'services:\n  a:\n    image: x:20.16\n' > "$d/compose.yml"
assert_eq 3 "$(rc_of upgrade)" "no IZPBX_VERSION (20.16) refused without --major"
assert_eq 0 "$(rc_of upgrade --major --apply)" "no IZPBX_VERSION: --major --apply"
assert_eq "$(cat "$share/compose.yml")" "$(cat "$d/compose.yml")" "--major: compose.yml of an unknown version (20.16) replaced"
assert_cmd "--major: the 20.16 compose.yml in the backup" -- grep -q 'x:20.16' "$(ls "$d"/compose.yml.*.bak)"
rm -f "$d"/*.bak
assert_contains "$(cat "$work/out")" "2-way merge" "no base: 2-way merge"
assert_contains "$(cat "$work/out")" "differ from default.env 1.0.1, check them: CHANGED_DEFAULT KEEP" "no base: the values that differ are listed"
assert_eq "CHANGED_DEFAULT=old IZPBX_VERSION=1.0.1 KEEP=2" "$(grep -E '^(KEEP|CHANGED_DEFAULT|IZPBX_VERSION)=' "$d/.env" | sort | xargs)" "no base: values of the .env kept, IZPBX_VERSION added"

# --- the version of the image (APP_VER): a series tag (1.0) writes its exact version
newdir
APP_VER=1.0.5 IZPBX_DEPLOY_DIR=$d IZPBX_DEPLOY_SHARE=$share "$deploy" init >/dev/null
assert_eq "IZPBX_VERSION=1.0.5" "$(grep '^IZPBX_VERSION=' "$d/.env")" "init: IZPBX_VERSION from APP_VER of the image"
assert_eq "IZPBX_VERSION=1.0.1" "$(APP_VER=dev IZPBX_DEPLOY_SHARE=$share "$deploy" env | grep '^IZPBX_VERSION=')" "APP_VER dev: IZPBX_VERSION of default.env"
newdir; user_env > "$d/.env"
APP_VER=1.0.2-rc1 IZPBX_DEPLOY_DIR=$d IZPBX_DEPLOY_SHARE=$share "$deploy" upgrade --only env --apply --no-backup >/dev/null
assert_eq "IZPBX_VERSION=1.0.2-rc1" "$(grep '^IZPBX_VERSION=' "$d/.env")" "upgrade: IZPBX_VERSION of a release candidate image"
# --- no downgrade: an image older than IZPBX_VERSION of the .env
newdir; user_env | sed 's/^IZPBX_VERSION=.*/IZPBX_VERSION=1.0.9/' > "$d/.env"
assert_eq 3 "$(rc_of upgrade)" "image 1.0.1 older than IZPBX_VERSION=1.0.9: refused"
assert_contains "$(cat "$work/out")" "--pull always" "downgrade refusal: pull the image again"
assert_eq 0 "$(rc_of upgrade --only env --keep-version --apply --no-backup)" "downgrade: --keep-version goes on"
assert_eq "IZPBX_VERSION=1.0.9" "$(grep '^IZPBX_VERSION=' "$d/.env")" "--keep-version: IZPBX_VERSION kept"
newdir; user_env | sed 's/^IZPBX_VERSION=.*/IZPBX_VERSION=1.0.1/' > "$d/.env"
rc=0; APP_VER=1.0.1-rc3 IZPBX_DEPLOY_DIR=$d IZPBX_DEPLOY_SHARE=$share "$deploy" upgrade >/dev/null 2>&1 || rc=$?
assert_eq 3 "$rc" "image 1.0.1-rc3 older than 1.0.1: refused"
user_env | sed 's/^IZPBX_VERSION=.*/IZPBX_VERSION=1.0.1-rc3/' > "$d/.env"
assert_ne 3 "$(rc_of upgrade)" "image 1.0.1 newer than 1.0.1-rc3: not refused"

# --- compose.yml edited: merge, conflict
newdir; user_env > "$d/.env"
printf 'services:\n  a:\n    image: x:1.0.0\n  b:\n    ports:\n    - 1\n    - 2\n' > "$d/compose.yml"
assert_eq 0 "$(rc_of upgrade --apply --no-backup)" "edited compose.yml: merged"
assert_eq "$(printf 'services:\n  a:\n    image: x:1.0.1\n  b:\n    ports:\n    - 1\n    - 2')" "$(cat "$d/compose.yml")" "edited compose.yml: local change and new image together"
newdir; user_env > "$d/.env"
printf 'services:\n  a:\n    image: x:local\n  b:\n    ports:\n    - 1\n' > "$d/compose.yml"
sum_before=$(cat "$d/.env" "$d/compose.yml" | md5sum)
assert_eq 3 "$(rc_of upgrade --apply)" "compose.yml conflict: exit 3"
assert_eq "$sum_before" "$(cat "$d/.env" "$d/compose.yml" | md5sum)" "compose.yml conflict: neither file written"
assert_contains "$(cat "$work/out")" "compose.override.yml" "conflict: points to compose.override.yml"
assert_eq 0 "$(rc_of upgrade --only env --apply --no-backup)" "conflict: --only env still upgrades the .env"

# --- init, compose, env
newdir
assert_eq 0 "$(rc_of init)" "init: exit 0"
assert_eq 600 "$(stat -c %a "$d/.env")" "init: .env 0600"
assert_eq "$(cat "$share/compose.yml")" "$(cat "$d/compose.yml")" "init: compose.yml of the image"
assert_eq 1 "$(rc_of init)" "init: refuses existing files"
assert_eq 1 "$(rc_of upgrade --env-file missing.env)" "upgrade: missing env file is an error"
assert_eq 0 "$(rc_of init --only env --env-file izpbx2.env)" "init --env-file izpbx2.env"
assert_file "$d/izpbx2.env" "init --env-file: file written"
assert_eq "$(cat "$share/compose.yml")" "$(IZPBX_DEPLOY_SHARE=$share "$deploy" compose)" "compose: on stdout"
IZPBX_DEPLOY_SHARE=$realshare "$deploy" env > "$work/e1"; IZPBX_DEPLOY_SHARE=$realshare "$deploy" env > "$work/e2"
p1=$(sed -n 's/^MYSQL_PASSWORD=//p' "$work/e1"); r1=$(sed -n 's/^MYSQL_ROOT_PASSWORD=//p' "$work/e1")
assert_eq 32 "${#p1}" "env: random MYSQL_PASSWORD"
assert_ne "$p1" "$r1" "env: two different passwords"
assert_ne "$p1" "$(sed -n 's/^MYSQL_PASSWORD=//p' "$work/e2")" "env: new passwords on every run"
assert_eq "" "$(grep PleaseCHANGEM3 "$work/e1" || true)" "env: no default password"

# --- the real files
assert_eq "" "$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$realshare/default.env" | sort | uniq -d | xargs)" "default.env: no variable active twice (a new .env would be reported as duplicated)"
assert_cmd "history and keys.txt in step with default.env and the tags (deploy-sync --check)" -- "$REPO_DIR/izpbx-asterisk/tools/deploy-sync.sh" --check
d=$work/real; mkdir -p "$d"
grep -vE '^(IZPBX_VERSION|MARIADB_VERSION)=|^#?(IZPBX_LOG_|IZPBX_MIGRATE_|HEP_ENABLED)' "$realshare/default.env" |
  sed -e 's/^MYSQL_PASSWORD=.*/MYSQL_PASSWORD=s3cret/' -e 's/^#TZ=.*/TZ=Europe\/Rome/' > "$d/.env"
printf 'MY_VAR=1\n' >> "$d/.env"
cp "$realshare/compose.yml" "$d/compose.yml"
rc=0; IZPBX_DEPLOY_DIR=$d IZPBX_DEPLOY_SHARE=$realshare "$deploy" upgrade --major --apply > "$work/out" 2>&1 || rc=$?
assert_eq 0 "$rc" "real .env without the 22.17 variables: --major --apply"
assert_eq "MYSQL_PASSWORD=s3cret" "$(grep '^MYSQL_PASSWORD=' "$d/.env")" "real .env: password kept"
assert_eq "TZ=Europe/Rome" "$(grep '^TZ=' "$d/.env")" "real .env: TZ kept"
assert_cmd "real .env: IZPBX_LOG_FORMAT example added" -- grep -qx '#IZPBX_LOG_FORMAT=text' "$d/.env"
assert_cmd "real .env: MY_VAR in the custom section" -- grep -qx 'MY_VAR=1' "$d/.env"
assert_eq "$(grep -E '^[A-Z]' "$realshare/default.env" | grep -v '^MYSQL_PASSWORD=' | sort)" \
  "$(grep -E '^[A-Z]' "$d/.env" | grep -vE '^(MYSQL_PASSWORD|TZ|MY_VAR)=' | sort)" "real .env: every other active value as in default.env"
rc=0; IZPBX_DEPLOY_DIR=$d IZPBX_DEPLOY_SHARE=$realshare "$deploy" upgrade > "$work/out" 2>&1 || rc=$?
assert_eq 0 "$rc" "real .env: second upgrade changes nothing"
d=$work/fresh; mkdir -p "$d"
IZPBX_DEPLOY_DIR=$d IZPBX_DEPLOY_SHARE=$realshare "$deploy" init >/dev/null
rc=0; IZPBX_DEPLOY_DIR=$d IZPBX_DEPLOY_SHARE=$realshare "$deploy" upgrade > "$work/out" 2>&1 || rc=$?
assert_eq 0 "$rc" "real files: a deploy just written by init is up to date"
finish
