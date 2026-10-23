#!/usr/bin/env bash
# P0-14: node-gyp at runtime. UCP and pm2 install without a C/C++ toolchain:
# - the izPBX image has no gcc/cc/make/c++, only the g++ stub
#   (build/g++-stub: answers "--version" for the UCP install check, fails
#   any compilation);
# - on the prototype with the toolchain removed (tests/proto/fpbx17-notc)
#   plus the stub, FreePBX 17 installs pm2 and ucp, their node_modules hold
#   no native addon, and with ASTMANAGERHOST=127.0.0.1 "fwconsole pm2 --list"
#   shows ucp online and stable (same PID, no restarts, 20 s).
# ucp needs its AMI user ucp_events, created only if the manager module is
# already installed (P3: init must check it).
# Negative: without the stub the ucp install fails ("gcc-c++ is not
# installed"); with ASTMANAGERHOST=localhost node 18 connects to ::1, AMI
# listens on IPv4 only, and ucp restarts in a loop.
source "$(dirname "$0")/../lib.sh"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
proto_image=izpbx-proto/fpbx17-notc:17.0.33
proto_dir="$TESTS_DIR/proto/fpbx17-notc"
# shellcheck source=../proto/proto.sh
source "$TESTS_DIR/proto/proto.sh"
stub="$REPO_DIR/izpbx-asterisk/build/g++-stub"
image=izpbx-asterisk:p0-14

# --- the izPBX image
assert_cmd "image builds" -- docker build -q -t "$image" "$REPO_DIR/izpbx-asterisk"
for t in gcc cc make c++ cpp; do
  assert_cmd_fails "image: no $t" -- docker run --rm --entrypoint "" "$image" sh -c "command -v $t"
done
assert_cmd "image: g++ --version answers (stub)" -- docker run --rm --entrypoint "" "$image" g++ --version
assert_cmd_fails "image: g++ cannot compile" -- docker run --rm --entrypoint "" "$image" sh -c 'echo "int main(){return 0;}" | g++ -x c++ -o /tmp/a -'
docker rmi "$image" >/dev/null 2>&1 || true

# --- prototype without toolchain
assert_cmd "base prototype image builds" -- docker build -q -t izpbx-proto/fpbx17:17.0.33 "$TESTS_DIR/proto/fpbx17"
proto_pre_install() {
  docker exec "$pbx" sh -c '! command -v gcc && ! command -v make && ! command -v c++' >/dev/null || return 1
  docker cp "$stub" "$pbx:/usr/local/bin/g++" && docker exec "$pbx" chmod 755 /usr/local/bin/g++
}
assert_cmd "FreePBX 17 installs on the prototype without toolchain" -- proto_up
fc() { docker exec -u asterisk "$pbx" fwconsole "$@"; }
enabled() { fc ma list | grep -cE "^\| $1 +\| [0-9.]+ +\| Enabled" >/dev/null; }
assert_cmd "pm2 installed and enabled" -- enabled pm2
assert_cmd "ucp installed and enabled" -- enabled ucp
native=$(docker exec "$pbx" sh -c 'find /var/www/html/admin/modules/ucp/node /var/www/html/admin/modules/pm2/node -name "*.node" -o -name binding.gyp' | wc -l)
assert_eq 0 "$native" "no native addon or binding.gyp in the ucp/pm2 node_modules"

# ucp creates its AMI user (ucp_events) through the manager module, which
# the prototype installs after ucp: reinstall ucp once manager is there
fc ma install ucp >/dev/null 2>&1 || true
fc reload >/dev/null 2>&1 || true
assert_contains "$(docker exec "$pbx" asterisk -rx 'manager show users')" "ucp_events" "AMI user ucp_events exists after reinstalling ucp"

ucp_state() { # -> "status pid restarts"
  fc pm2 --list 2>/dev/null | awk -F'|' '$2 ~ /^ *ucp *$/ {gsub(/ /,""); print $4, $3, $5}'
}
stable_online() { # ucp online, then same PID and restarts after 20 s
  local a b
  t_wait_for 90 -- sh -c "docker exec -u asterisk $pbx fwconsole pm2 --list | grep -E '^\| ucp +\| [0-9]+ +\| online'" || return 1
  a=$(ucp_state); sleep 20; b=$(ucp_state)
  log "ucp: $a -> $b"
  [ "${a%% *}" == online ] && [ "$a" == "$b" ]
}
fc setting ASTMANAGERHOST localhost >/dev/null
fc pm2 --restart=ucp >/dev/null 2>&1
assert_cmd_fails "control: with ASTMANAGERHOST=localhost ucp is not stable" -- stable_online
fc setting ASTMANAGERHOST 127.0.0.1 >/dev/null
fc pm2 --restart=ucp >/dev/null 2>&1
assert_cmd "with ASTMANAGERHOST=127.0.0.1 ucp is online and stable" -- stable_online

# negative: without the stub the ucp (re)install fails on its g++ check
docker exec "$pbx" rm -f /usr/local/bin/g++
out=$(fc ma install ucp 2>&1 || true)
assert_contains "$out" "gcc-c++ is not installed" "control: without the stub the ucp install refuses to run"
finish
