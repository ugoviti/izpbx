#!/usr/bin/env bash
# P7-10: image versions in .env (request of the user): compose.yml reads
# IZPBX_VERSION and MARIADB_VERSION, with an explicit version as default (the
# one of default.env), never 'latest': a new release changes .env only.
# - default.env sets both, compose.yml requires them (no version written in it);
# - docker compose config --images: with default.env its IZPBX_VERSION and MARIADB_VERSION; with
#   an old .env without one of them: a clear error; other values in .env and
#   MARIADB_VERSION=10.11.20 in .env change the images;
# - negative: 'latest' nowhere in the images of compose.yml and in default.env.
# The release tool moving them is P7-09.
source "$(dirname "$0")/../lib.sh"
cli=docker.io/library/docker:27.5.1-cli
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
compose="$DEPLOY_FILES/compose.yml" env="$DEPLOY_FILES/default.env"

iv=$(sed -n 's/^IZPBX_VERSION=//p' "$env"); mv=$(sed -n 's/^MARIADB_VERSION=//p' "$env")
assert_cmd "default.env: IZPBX_VERSION of 22.17 ($iv)" -- grep -qE '^22\.17\.[0-9]+$' <<< "$iv"
assert_cmd "default.env: MARIADB_VERSION an explicit version ($mv)" -- grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$mv"
assert_cmd "compose.yml: izpbx image from IZPBX_VERSION, required" -- grep -qF 'image: docker.io/izdock/izpbx-asterisk:${IZPBX_VERSION:?' "$compose"
assert_cmd "compose.yml: db image from MARIADB_VERSION, required" -- grep -qF 'image: docker.io/mariadb:${MARIADB_VERSION:?' "$compose"
assert_cmd_fails "compose.yml: no version written" -- grep -qE '(izpbx-asterisk|mariadb):[$]?[{]?[A-Z_]*:?-?[0-9]' "$compose"

images() { # .env content on stdin -> the images of compose.yml
  cp "$compose" "$work/compose.yml"; cat > "$work/.env"
  docker run --rm -v "$work:/w:ro" -w /w "$cli" docker compose -f compose.yml config --images 2>&1 | sort
}
want="docker.io/izdock/izpbx-asterisk:$iv
docker.io/mariadb:$mv"
assert_eq "$want" "$(images < "$env")" "default.env: izPBX $iv, MariaDB $mv"
assert_contains "$(grep -vE '^IZPBX_VERSION=' "$env" | images)" "required variable IZPBX_VERSION is missing a value: set IZPBX_VERSION in .env (izpbx-deploy upgrade adds it)" "old .env without IZPBX_VERSION: a clear error"
assert_contains "$(grep -vE '^MARIADB_VERSION=' "$env" | images)" "required variable MARIADB_VERSION is missing a value" "old .env without MARIADB_VERSION: a clear error"
assert_eq "docker.io/izdock/izpbx-asterisk:22.17.999
docker.io/mariadb:10.11.999" "$(sed -e 's/^IZPBX_VERSION=.*/IZPBX_VERSION=22.17.999/' -e 's/^MARIADB_VERSION=.*/MARIADB_VERSION=10.11.999/' "$env" | images)" ".env changes the images"

assert_cmd_fails "negative: no latest in the images of compose.yml" -- grep -qE '^ *image: .*latest' "$compose"
assert_cmd_fails "negative: no latest in default.env" -- grep -qE '^(IZPBX|MARIADB)_VERSION=.*latest' "$env"
sed 's/^IZPBX_VERSION=.*/IZPBX_VERSION=latest/' "$env" > "$work/latest.env"
assert_cmd "control: the check finds latest when it is there" -- grep -qE '^(IZPBX|MARIADB)_VERSION=.*latest' "$work/latest.env"
finish
