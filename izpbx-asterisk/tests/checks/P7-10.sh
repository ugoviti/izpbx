#!/usr/bin/env bash
# P7-10: image versions in .env (request of the user): compose.yml reads
# IZPBX_VERSION and MARIADB_VERSION, with an explicit version as default (the
# one of default.env), never 'latest': a new release changes .env only.
# - default.env sets both, and the defaults of compose.yml are the same values;
# - docker compose config --images: with default.env 22.17.0 and 10.11.19; with
#   an old .env without the variables the same; IZPBX_VERSION=22.17.1 and
#   MARIADB_VERSION=10.11.20 in .env change the images;
# - negative: 'latest' nowhere in the images of compose.yml and in default.env.
# The release tool moving them is P7-09.
source "$(dirname "$0")/../lib.sh"
cli=docker.io/library/docker:27.5.1-cli
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
compose="$REPO_DIR/compose.yml" env="$REPO_DIR/default.env"

iv=$(sed -n 's/^IZPBX_VERSION=//p' "$env"); mv=$(sed -n 's/^MARIADB_VERSION=//p' "$env")
assert_eq 22.17.0 "$iv" "default.env: IZPBX_VERSION"
assert_eq 10.11.19 "$mv" "default.env: MARIADB_VERSION"
assert_cmd "compose.yml: izpbx image from IZPBX_VERSION, default = default.env" -- grep -qF "image: docker.io/izdock/izpbx-asterisk:\${IZPBX_VERSION:-$iv}" "$compose"
assert_cmd "compose.yml: db image from MARIADB_VERSION, default = default.env" -- grep -qF "image: docker.io/mariadb:\${MARIADB_VERSION:-$mv}" "$compose"

images() { # .env content on stdin -> the images of compose.yml
  cp "$compose" "$work/compose.yml"; cat > "$work/.env"
  docker run --rm -v "$work:/w:ro" -w /w "$cli" docker compose -f compose.yml config --images 2>&1 | sort
}
want="docker.io/izdock/izpbx-asterisk:22.17.0
docker.io/mariadb:10.11.19"
assert_eq "$want" "$(images < "$env")" "default.env: izPBX 22.17.0, MariaDB 10.11.19"
assert_eq "$want" "$(grep -vE '^(IZPBX|MARIADB)_VERSION=' "$env" | images)" "old .env without the variables: the same"
assert_eq "docker.io/izdock/izpbx-asterisk:22.17.1
docker.io/mariadb:10.11.20" "$(sed -e 's/^IZPBX_VERSION=.*/IZPBX_VERSION=22.17.1/' -e 's/^MARIADB_VERSION=.*/MARIADB_VERSION=10.11.20/' "$env" | images)" ".env changes the images"

assert_cmd_fails "negative: no latest in the images of compose.yml" -- grep -qE '^ *image: .*latest' "$compose"
assert_cmd_fails "negative: no latest in default.env" -- grep -qE '^(IZPBX|MARIADB)_VERSION=.*latest' "$env"
sed 's/^IZPBX_VERSION=.*/IZPBX_VERSION=latest/' "$env" > "$work/latest.env"
assert_cmd "control: the check finds latest when it is there" -- grep -qE '^(IZPBX|MARIADB)_VERSION=.*latest' "$work/latest.env"
finish
