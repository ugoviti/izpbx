#!/usr/bin/env bash
# P3-39: HEP_ENABLED (Homer capture), as 20.16: at every start "enabled" of
# /etc/asterisk/hep.conf becomes yes with HEP_ENABLED=true, no with any other
# value; hep.conf is not touched when the variable is unset. Lost in 22.17
# (declared in env.sh, applied by nobody), found checking the variables that
# nothing reads.
# - HEP_ENABLED=true: "enabled = yes", logged;
# - HEP_ENABLED=false: "enabled = no" on a file that had yes;
# - negative: unset → the file is the one of the image, byte for byte.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-39
assert_cmd "image builds" -- t_build_image "$image"

hep() { # name [docker run args...] -> the "enabled" line of hep.conf after izpbx-init
  local c
  c=$(t_run "$1" "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=false "${@:2}")
  t_wait_for 120 -- sh -c "docker logs '$c' 2>&1 | grep -q 'izpbx-init: done'" || die "izpbx-init did not finish in $1"
  docker exec "$c" grep '^enabled' /etc/asterisk/hep.conf
}
image_sum=$(docker run --rm --entrypoint "" "$image" sha256sum /etc/asterisk/hep.conf | cut -d' ' -f1)
assert_contains "$(docker run --rm --entrypoint "" "$image" grep '^enabled' /etc/asterisk/hep.conf)" "enabled = no" "the image has enabled = no"

assert_eq "enabled = yes" "$(hep on -e HEP_ENABLED=true)" "HEP_ENABLED=true: enabled = yes"
assert_cmd "HEP_ENABLED=true: logged" -- sh -c "docker logs '$TEST_PROJECT-on' 2>&1 | grep -q 'HEP capture enabled = yes'"

# a persistent hep.conf with yes, then HEP_ENABLED=false
vol=$(t_volume etc)
docker run --rm --entrypoint "" -v "$vol:/x" "$image" sh -c 'cp -a /etc/asterisk/. /x/ && sed -i "s/^enabled =.*/enabled = yes/" /x/hep.conf'
assert_eq "enabled = no" "$(hep off -v "$vol:/etc/asterisk" -e HEP_ENABLED=false)" "HEP_ENABLED=false: enabled = no on a file that had yes"
assert_eq "enabled = no" "$(hep other -v "$vol:/etc/asterisk" -e HEP_ENABLED=yes)" "HEP_ENABLED=yes (not true): no, as every boolean of 20.16"

c=$(t_run unset "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=false)
t_wait_for 120 -- sh -c "docker logs '$c' 2>&1 | grep -q 'izpbx-init: done'" || die "izpbx-init did not finish"
assert_eq "$image_sum" "$(docker exec "$c" sha256sum /etc/asterisk/hep.conf | cut -d' ' -f1)" "negative: HEP_ENABLED unset → hep.conf untouched"
finish
