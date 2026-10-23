#!/usr/bin/env bash
# P1-10: runtime without toolchain (P0-14: only the g++ stub for the UCP
# install check). In the final image: no gcc, cc, make, c++, cpp; g++ cannot
# compile; no *-dev package (npm comes from the registry tarball, not from
# Debian, whose npm pulls node-gyp -> libnode-dev, libssl-dev, libuv1-dev);
# npm runs as asterisk with the pinned version. The image size stays within
# 5% of the one recorded in tests/expected/image-size.txt and not above
# 20.16.22. Negative: the builder stage does have -dev packages and gcc; the
# size check fails against a smaller limit.
source "$(dirname "$0")/../lib.sh"

dir="$REPO_DIR/izpbx-asterisk"
image=izpbx-asterisk:p1-10
sizes="$TESTS_DIR/expected/image-size.txt"
npm_ver=$(sed -n 's/^NPM_VER=//p' "$dir/versions.env")
devpkgs() { docker run --rm --entrypoint "" "$1" sh -c 'dpkg-query -W -f "\${Package}\n" | grep -E -- "-dev(:|$)" || true'; }

assert_cmd "image builds" -- docker build -q -t "$image" "$dir"
for t in gcc cc make c++ cpp; do
  assert_cmd_fails "no $t" -- docker run --rm --entrypoint "" "$image" sh -c "command -v $t"
done
assert_cmd_fails "g++ is only the stub (cannot compile)" -- docker run --rm --entrypoint "" "$image" sh -c 'echo "int main(){return 0;}" | g++ -x c++ -o /tmp/a -'
assert_eq "" "$(devpkgs "$image")" "no -dev package"
assert_eq "$npm_ver" "$(docker run --rm --entrypoint "" -u asterisk "$image" npm --version)" "npm $npm_ver runs as asterisk"
assert_contains "$(docker run --rm --entrypoint "" "$image" node -v)" "v18." "Node.js is Debian 12's 18.x"

# negative: the same checks see the toolchain of the builder stage
assert_cmd "builder stage builds" -- docker build -q --target builder -t "$image-builder" "$dir"
assert_ne "" "$(devpkgs "$image-builder")" "control: the builder stage has -dev packages"
assert_cmd "control: the builder stage has gcc" -- docker run --rm --entrypoint "" "$image-builder" sh -c 'command -v gcc'
docker rmi "$image-builder" >/dev/null 2>&1 || true

# size
ref=izdock/izpbx-asterisk:20.16.22
docker image inspect "$ref" >/dev/null 2>&1 || docker pull -q "$ref" >/dev/null
size=$(docker image inspect -f '{{.Size}}' "$image")
recorded=$(awk '$1 == "22.17" {print $2}' "$sizes")
limit=$(awk '$1 == "20.16.22" {print $2}' "$sizes")
assert_eq "$limit" "$(docker image inspect -f '{{.Size}}' "$ref")" "recorded 20.16.22 size matches $ref"
log "size: $size bytes (recorded $recorded, 20.16.22 $limit)"
within() { awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d <= b * 0.05) }'; }
assert_cmd "size within 5% of the recorded $recorded bytes" -- within "$size" "$recorded"
assert_cmd "size $size <= 20.16.22 ($limit)" -- test "$size" -le "$limit"
assert_cmd_fails "control: the size check fails against a smaller limit" -- test "$size" -le "$((size / 2))"

docker rmi "$image" >/dev/null 2>&1 || true
finish
