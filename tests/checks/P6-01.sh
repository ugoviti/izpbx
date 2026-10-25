#!/usr/bin/env bash
# P6-01: "verify image" of the build-push action rewritten for Debian (E1).
# The step runs .gitea/actions/build-push/verify-image.sh inside the image
# (php8.2 minimum version, asterisk -V, no chan_sip/app_macro, app_sla,
# chan_dongle and codec_g729 present, ionCube in cli and fpm,
# allow_url_include Off) with ASTERISK_VER from versions.env; the check runs
# it the same way, without the registry:
# - green on the good image;
# - negative checks: red on images built on purpose without app_sla, with
#   allow_url_include=On for php-fpm only, with allow_url_include on in an
#   fpm pool, and with an expected Asterisk version that is not the image's.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p6-01
assert_cmd "image builds" -- t_build_image "$image"
action="$REPO_DIR/.gitea/actions/build-push/action.yml"
script="$REPO_DIR/.gitea/actions/build-push/verify-image.sh"
ast=$(sed -n 's/^ASTERISK_VER=//p' "$REPO_DIR/izpbx-asterisk/versions.env")

assert_cmd "the action runs verify-image.sh inside the image" -- \
  grep -qF 'bash -s < "$SCRIPT"' "$action"
assert_cmd "the action reads ASTERISK_VER from versions.env" -- \
  grep -qF 'izpbx-asterisk/versions.env' "$action"
assert_cmd_fails "the action has no rpm check left" -- grep -q 'rpm ' "$action"

verify() { # image [ASTERISK_VER]
  docker run -i --rm --entrypoint "" -e ASTERISK_VER="${2:-$ast}" "$1" bash -s < "$script"
}
out=$(verify "$image") && rc=0 || rc=$?
assert_eq 0 "$rc" "green on the good image"
for line in "OK   Asterisk $ast" "OK   app_sla.so present" "OK   chan_dongle.so present" \
            "OK   codec_g729.so present" "OK   chan_sip.so absent" "OK   app_macro.so absent" \
            "OK   ionCube loaded (php)" "OK   ionCube loaded (php-fpm8.2)" \
            'OK   allow_url_include="Off" (php-fpm8.2)' "OK   php8.2 "; do
  assert_contains "$out" "$line" "good image: ${line#OK   }"
done

# images built on purpose with one defect each
bad() { # tag dockerfile-lines...
  local tag=$1 dir; shift
  dir=$(mktemp -d)
  { echo "FROM $image"; printf '%s\n' "$@"; } > "$dir/Dockerfile"
  local rc=0; docker build -q -t "$tag" "$dir" >/dev/null || rc=$?
  rm -f "$dir/Dockerfile"; rmdir "$dir"
  t_on_cleanup "docker rmi $tag >/dev/null 2>&1"
  return $rc
}
negative() { # message tag expected-FAIL-line [ASTERISK_VER]
  local out rc
  out=$(verify "$2" "${4:-}") && rc=0 || rc=$?
  assert_ne 0 "$rc" "control: red on $1"
  assert_contains "$out" "$3" "control: $1 reported"
}
assert_cmd "image without app_sla builds" -- \
  bad izpbx-asterisk:p6-01-nosla 'RUN rm /usr/lib64/asterisk/modules/app_sla.so'
negative "the image without app_sla" izpbx-asterisk:p6-01-nosla "FAIL app_sla.so missing"
assert_cmd "image with allow_url_include=On (fpm) builds" -- \
  bad izpbx-asterisk:p6-01-urlinc 'RUN echo allow_url_include=On > /etc/php/8.2/fpm/conf.d/99-test.ini'
negative "allow_url_include=On for php-fpm" izpbx-asterisk:p6-01-urlinc 'FAIL allow_url_include="On" (php-fpm8.2)'
assert_cmd "image with allow_url_include in an fpm pool builds" -- \
  bad izpbx-asterisk:p6-01-pool 'RUN printf "[x]\nphp_admin_flag[allow_url_include] = on\n" > /etc/php/8.2/fpm/pool.d/zz-test.conf'
negative "allow_url_include on in an fpm pool" izpbx-asterisk:p6-01-pool 'FAIL allow_url_include="on" in /etc/php/8.2/fpm/pool.d'
negative "an Asterisk version that is not the image's" "$image" "FAIL asterisk -V" 22.0.0
finish
