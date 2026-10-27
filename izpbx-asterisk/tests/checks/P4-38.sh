#!/usr/bin/env bash
# P4-38: expected differences of the verification M7 seen migrating a
# production PBX (izpbx-inventory --diff with migration-mapping.tsv):
# - astdb /registrar/contact/... (contacts of the registered PJSIP phones,
#   they register again) and /DEVICE/<n>/default_user (written again by
#   FreePBX 17 from the devices table) are no difference;
# - AMPUSER/<ext>/device lists the devices in a fixed order in the inventory
#   ("99201&201" and "201&99201" are the same record);
# - the name of a WebRTC device ("WebRTC <user>") is not compared, on both
#   sides (rule with the 4th field "both"); its extension still is;
# - FOP2 not enabled: its files are not compared (rule added by
#   migration_verify), and a category that only had left out records is not
#   "missing after";
# - negatives: a missing extension, a missing WebRTC device and a changed
#   AMPUSER device list are still differences.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-38
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"
map=/usr/local/share/izpbx/migration-mapping.tsv

inv() { # name -> JSON on stdin is written to $work/name.json
  cat > "$work/$1.json"
}
diffinv() { # before after [extra mapping lines]
  printf '%s' "${3:-}" > "$work/extra.tsv"
  docker run --rm --entrypoint "" -v "$work:/w" "$image" sh -c \
    "cat $map /w/extra.tsv > /tmp/m.tsv; izpbx-inventory --diff /w/$1.json /w/$2.json --mapping /tmp/m.tsv"
}
inv before <<'EOF'
{"categories": {
  "astdb": ["key=/AMPUSER/201/device value=201&99201",
            "key=/DEVICE/238/default_user value=izadmin",
            "key=/registrar/contact/256;@c020 value={\"via_addr\":\"10.1.0.217\"}"],
  "extensions": ["extension=201 name=Ann tech=pjsip voicemail=default",
                 "extension=99266 name=WebRTC Lucio Tavanti tech=pjsip voicemail=NULL"],
  "files": ["path=usr/local/fop2/fop2.lic sha256=87ebbb814e707d66"]}}
EOF
inv after <<'EOF'
{"categories": {
  "astdb": ["key=/AMPUSER/201/device value=201&99201",
            "key=/DEVICE/238/default_user value=238",
            "key=/registrar/contact/256;@ffff value={\"via_addr\":\"10.1.0.217\"}"],
  "extensions": ["extension=201 name=Ann tech=pjsip voicemail=default",
                 "extension=99266 name=WebRTC Greta Tappeti tech=pjsip voicemail=NULL"]}}
EOF
fop2rule=$'files\t^path=usr/local/fop2/\t\n'
out=$(diffinv before after "$fop2rule") && rc=0 || rc=$?
log "diff:"; sed 's/^/    | /' <<< "$out" >&2
assert_eq 0 "$rc" "registrar contacts, default_user, WebRTC names and FOP2 disabled: no difference"
assert_cmd_fails "control: with FOP2 enabled its files are compared" -- diffinv before after

# negatives
jq '.categories.extensions = [.categories.extensions[1]]' "$work/after.json" | inv noext
assert_contains "$(diffinv before noext "$fop2rule" || true)" "extensions: - extension=201 name=Ann" "negative: a missing extension is reported"
jq '.categories.extensions = [.categories.extensions[0]]' "$work/after.json" | inv nowebrtc
assert_contains "$(diffinv before nowebrtc "$fop2rule" || true)" "extensions: - extension=99266 name=WebRTC tech=pjsip" "negative: a missing WebRTC device is reported (without its name)"
jq '.categories.astdb[0] = "key=/AMPUSER/201/device value=201"' "$work/after.json" | inv nodev
assert_contains "$(diffinv before nodev "$fop2rule" || true)" "astdb: - key=/AMPUSER/201/device value=201&99201" "negative: a device missing from the list of a user is reported"

# the inventory writes the device list of a user in a fixed order
docker run --rm --entrypoint "" "$image" sh -c '
  mkdir -p /r/var/lib/asterisk
  php -r "\$d = new PDO(\"sqlite:/r/var/lib/asterisk/astdb.sqlite3\"); \$d->exec(\"CREATE TABLE astdb (key VARCHAR(256), value VARCHAR(256))\");
    \$d->exec(\"INSERT INTO astdb VALUES (\\\"/AMPUSER/201/device\\\", \\\"99201&201\\\"), (\\\"/AMPUSER/202/device\\\", \\\"202\\\")\");"
  izpbx-inventory --root /r | jq -r ".categories.astdb[]"' > "$work/astdb.txt"
assert_eq "key=/AMPUSER/201/device value=201&99201
key=/AMPUSER/202/device value=202" "$(sort "$work/astdb.txt")" "inventory: device lists sorted (99201&201 -> 201&99201)"
finish
