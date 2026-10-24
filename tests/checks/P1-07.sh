#!/usr/bin/env bash
# P1-07: Asterisk addons. codec_g729.so and chan_dongle.so are installed and,
# with Asterisk running, "module show" reports them Running (chan_dongle with
# a minimal dongle.conf, as the image ships none, like 20.16); "core show
# translation" has g729 <-> ulaw; sngrep -V = 1.9.0.
source "$(dirname "$0")/../lib.sh"

dir="$REPO_DIR/izpbx-asterisk"
image=izpbx-asterisk:p1-07
sngrep_ver=$(sed -n 's/^SNGREP_VER=//p' "$dir/versions.env")

assert_cmd "image builds" -- t_build_image "$image"
for m in codec_g729.so chan_dongle.so; do
  assert_cmd "$m is installed" -- docker run --rm --entrypoint "" "$image" test -f "/usr/lib64/asterisk/modules/$m"
done

c=$(t_run ast "$image" --entrypoint "" -- asterisk -f -U asterisk -G asterisk)
t_wait_for 60 -- docker exec "$c" asterisk -rx "core show uptime" || die "Asterisk did not start"
printf '[general]\ninterval=15\n\n[defaults]\ncontext=from-trunk\ngroup=0\n' \
  | docker exec -i -u asterisk "$c" sh -c 'cat > /etc/asterisk/dongle.conf'
docker exec "$c" asterisk -rx "module load chan_dongle.so" >/dev/null

running() { docker exec "$c" asterisk -rx "module show like $1" | grep -E "^$1\.so " | grep -q ' Running '; }
assert_cmd "codec_g729 is Running" -- running codec_g729
assert_cmd "chan_dongle is Running" -- running chan_dongle
assert_cmd "dongle show devices answers" -- docker exec "$c" asterisk -rx "dongle show devices"
paths=$(docker exec "$c" asterisk -rx "core show translation paths g729")
assert_contains "$paths" "To ulaw:8000       : (g729@8000)->(slin@8000)->(ulaw@8000)" "translation g729 -> ulaw"
assert_contains "$(docker exec "$c" asterisk -rx "core show translation paths ulaw")" "(ulaw@8000)->(slin@8000)->(g729@8000)" "translation ulaw -> g729"
assert_eq "sngrep - $sngrep_ver" "$(docker exec "$c" sngrep -V | head -1)" "sngrep version"

# negative: a module that is not loaded is not reported as Running
docker exec "$c" asterisk -rx "module unload chan_dongle.so" >/dev/null
assert_cmd_fails "control: an unloaded chan_dongle is not Running" -- running chan_dongle

finish
