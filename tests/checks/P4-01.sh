#!/usr/bin/env bash
# P4-01: izpbx-inventory and --diff (design §9) on the 20.16.22 fixture
# (tests/fixtures/out/20.16.22, made by P0-04): its dumps in a MariaDB, its
# data tree as --root.
# - the inventory holds the T5 elements (extensions, trunks, routes, IVR,
#   queue, ring group, time condition, voicemail boxes and messages, astdb,
#   custom prompts, MoH, modules, FOP2 and dongle files);
# - two inventories of the same fixture are identical; the diff of the
#   fixture with itself is empty (exit 0);
# - an extension removed: the diff reports it (exit 1);
# - mapping: an extension moved from sip to pjsip is a difference, not with
#   the rule "extensions<TAB>tech=sip<TAB>tech=pjsip"; "ignore" skips a category.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-01
fx="$TESTS_DIR/fixtures/out/20.16.22"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"
assert_cmd "20.16.22 fixture available" -- "$TESTS_DIR/fixtures/make-fixture.sh" -v 20.16.22 ${TEST_REUSE_FIXTURES:+--reuse}
mkdir -p "$work/root" "$work/inv"
tar -C "$work/root" -xzf "$fx/data.tar.gz" 2>/dev/null || die "cannot unpack the fixture"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
for f in asterisk asteriskcdrdb; do gzip -dc "$fx/$f.sql.gz" | docker exec -i "$db" mariadb -uroot || die "cannot load $f"; done
docker exec "$db" mariadb -uroot -e "CREATE USER asterisk@'%' IDENTIFIED BY 'astpw'; GRANT ALL ON asterisk.* TO asterisk@'%'; GRANT ALL ON asteriskcdrdb.* TO asterisk@'%'"
sql() { docker exec "$db" mariadb -uroot asterisk -e "$1"; }
inv() { docker run --rm --entrypoint "" --network "$net" -v "$work/root:/fx:ro" -v "$work/inv:/inv" \
          -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw "$image" izpbx-inventory "$@"; }
cats() { jq -r ".categories.$2 | length" "$work/inv/$1"; }

inv --root /fx > "$work/inv/a.json"
inv --root /fx > "$work/inv/b.json"
for c in extensions trunks inbound_routes outbound_routes ivrs queues ringgroups timeconditions voicemail_boxes \
         voicemail_messages astdb recordings sounds_custom moh modules users_ucp files; do
  n=$(cats a.json "$c")
  assert_cmd "inventory: $c ($n records)" -- test "${n:-0}" -gt 0
done
assert_cmd "two inventories of the same fixture are identical" -- cmp -s "$work/inv/a.json" "$work/inv/b.json"
out=$(inv --diff /inv/a.json /inv/b.json) && rc=0 || rc=$?
assert_eq 0 "$rc" "diff of the fixture with itself: exit 0"
assert_eq "no differences" "$out" "diff of the fixture with itself: empty"

sql "DELETE FROM devices WHERE id='1003'; DELETE FROM users WHERE extension='1003'"
inv --root /fx > "$work/inv/c.json"
out=$(inv --diff /inv/a.json /inv/c.json) && rc=0 || rc=$?
assert_eq 1 "$rc" "an extension removed: exit 1"
assert_contains "$out" "extensions: - extension=1003" "an extension removed: reported"

sql "UPDATE devices SET tech='pjsip' WHERE id='1001'"
inv --root /fx > "$work/inv/d.json"
assert_cmd_fails "sip -> pjsip without mapping: a difference" -- inv --diff /inv/c.json /inv/d.json
printf '# expected changes of the migration\nextensions\ttech=sip\ttech=pjsip\n' > "$work/inv/map"
out=$(inv --diff /inv/c.json /inv/d.json --mapping /inv/map) && rc=0 || rc=$?
assert_eq 0 "$rc" "sip -> pjsip with the mapping rule: no difference"
printf 'extensions\tignore\n' > "$work/inv/ignore"
assert_cmd "a category set to ignore is not compared" -- inv --diff /inv/a.json /inv/c.json --mapping /inv/ignore
finish
