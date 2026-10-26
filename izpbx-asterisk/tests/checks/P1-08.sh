#!/usr/bin/env bash
# P1-08: build/freepbx.sh. In the image, for every module of
# build/freepbx-modules.txt: modules/<name> holds the pinned version and
# modules/_cache/<name>-<ver>.tgz.gpg exists, has the pinned sha256 and carries
# a valid signature from a key the framework trusts (fingerprints read from
# GPG.class.php); framework >= 17.0.33. Negative: a module missing from the
# mirror, or a wrong sha256, makes the build fail; a tampered package fails
# the signature check.
source "$(dirname "$0")/../lib.sh"

dir="$REPO_DIR/izpbx-asterisk"
image=izpbx-asterisk:p1-08
list="$dir/build/freepbx-modules.txt"
assert_cmd "image builds" -- t_build_image "$image"
n=$(grep -cvE '^(#|$)' "$list")
[ "$n" -ge 40 ] || die "module list has only $n entries"

# runs inside the image: verify every listed module, print "ok <name>" per module
verify='set -u; f=/usr/src/freepbx; m=$f/amp_conf/htdocs/admin/modules
trusted=$(grep -oE "'"'"'[0-9A-F]{40}'"'"'" $f/amp_conf/htdocs/admin/libraries/BMO/GPG.class.php | tr -d "'"'"'" | sort -u)
g=$(mktemp -d); gpg --homedir $g -q --import $f/amp_conf/htdocs/admin/libraries/BMO/*.key 2>/dev/null
echo "framework $(grep -m1 -oE "<version>[^<]+" $f/module.xml | cut -d">" -f2)"
while read -r name ver sha; do
  case "$name" in ""|"#"*) continue;; esac; p=$m/_cache/$name-$ver.tgz.gpg
  [ -f $m/$name/module.xml ] || { echo "nodir $name"; continue; }
  grep -q "<version>$ver</version>" $m/$name/module.xml || { echo "badver $name"; continue; }
  [ -f $p ] || { echo "nopkg $name"; continue; }
  [ -z "$sha" ] || [ "$(sha256sum < $p | cut -d" " -f1)" = "$sha" ] || { echo "badsha $name"; continue; }
  s=$(gpg --homedir $g --batch --status-fd 1 --output /dev/null --decrypt $p 2>/dev/null | awk "\$2==\"VALIDSIG\"{print \$NF}")
  if [ -n "$s" ] && grep -qx "$s" <<< "$trusted"; then echo "ok $name"; else echo "badsig $name"; fi
done'
out=$(docker run --rm --entrypoint "" -i -v "$list:/list:ro" "$image" bash -c "$verify < /list")
assert_eq "$n" "$(grep -c '^ok ' <<< "$out")" "all $n modules: directory, version, .tgz.gpg, sha256 and trusted signature"
bad=$(grep -vE '^(ok|framework) ' <<< "$out" || true)
assert_eq "" "$bad" "no module with a missing directory/package or a bad version/sha256/signature"
fw=$(sed -n 's/^framework //p' <<< "$out")
assert_eq "17.0.33" "$(printf '%s\n' 17.0.33 "$fw" | sort -V | head -1)" "framework $fw >= 17.0.33"

# negative: the same check on a tampered package (one byte changed) fails its signature
tamper='m=/usr/src/freepbx/amp_conf/htdocs/admin/modules/_cache; p=$(ls $m/core-*.tgz.gpg); sz=$(stat -c %s $p)
printf "\x00" | dd of=$p bs=1 seek=$((sz / 2)) conv=notrunc 2>/dev/null; '
out=$(docker run --rm --entrypoint "" -i -v "$list:/list:ro" "$image" bash -c "$tamper $verify < /list")
assert_contains "$out" "badsha core" "control: a tampered package is detected (sha256)"
# (core listed without its sha256, so only the signature can catch it)
work=$(mktemp -d); t_on_cleanup "t_rmtree $work"
awk '$1 == "core" { print $1, $2; next } 1' "$list" > "$work/nosha.list"
out=$(docker run --rm --entrypoint "" -i -v "$work/nosha.list:/list:ro" "$image" bash -c "$tamper $verify < /list")
assert_contains "$out" "badsig core" "control: a tampered package fails the GPG signature check"

# negative: build of the freepbx stage with a broken module list
cp -a "$dir/." "$work/"
echo "izpbxnonexistent 17.0.1 $(printf '0%.0s' {1..64})" >> "$work/build/freepbx-modules.txt"
assert_cmd_fails "control: a module missing from the mirror fails the build" -- docker build -q --target freepbx "$work"
cp "$list" "$work/build/freepbx-modules.txt"
sed -i '/^core /s/ [0-9a-f]\{64\}$/ '"$(printf 'f%.0s' {1..64})"'/' "$work/build/freepbx-modules.txt"
assert_cmd_fails "control: a wrong module sha256 fails the build" -- docker build -q --target freepbx "$work"

docker rmi "$image" >/dev/null 2>&1 || true
finish
