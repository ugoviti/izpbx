#!/usr/bin/env bash
# P3-28: the system tools the FreePBX 17 modules run (regression found by the
# user: the Backup page failed with file_get_contents(.../id_ecdsa.pub),
# ssh-keygen missing).
# - every binary the modules of the image look up with fpbx_which() is in the
#   image, but the documented exceptions: gs and pdfinfo (fax to PDF, not in
#   20.16 either), mailq (Postfix, at start), fwconsole (installed by FreePBX);
# - openssh-client (ssh-keygen, ssh, scp, sftp), rsync and ipset there;
# - new installation: the code of the Backup settings tab (showPage, as
#   php-fpm runs it) builds the page without error and makes the ECDSA key of
#   asterisk (ecdsa-sha2-nistp521, private key 0600);
# - controls: the binary check on the image with ssh-keygen removed reports
#   it; the Backup code without ssh-keygen fails with the error of the user.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-28
assert_cmd "image builds" -- t_build_image "$image"
exceptions="gs pdfinfo mailq fwconsole"
check_tools() { # [shell code run first] -> the binaries missing, space separated
  docker run --rm --entrypoint "" -e EXC="$exceptions" "$image" bash -c "${1:-:}"'
    cd /usr/src/freepbx/amp_conf/htdocs/admin
    for b in $(grep -rhoE "fpbx_which\([\"'"'"'][a-z0-9_-]+[\"'"'"']\)" . | grep -oE "[a-z0-9_-]+[\"'"'"']\)$" | tr -d "\"'"'"')" | sort -u) ssh-keygen ssh scp sftp rsync ipset; do
      [[ " $EXC " == *" $b "* ]] && continue
      command -v "$b" >/dev/null || printf "%s " "$b"
    done' 2>/dev/null
}
assert_eq "" "$(check_tools)" "every binary the modules look up is in the image (but $exceptions)"
assert_contains "$(check_tools 'rm -f "$(command -v ssh-keygen)";')" "ssh-keygen" "control: an image without ssh-keygen is reported"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"
db=$(t_run db docker.io/mariadb:10.11.19 --network "$net" --network-alias db -e MARIADB_ROOT_PASSWORD=rootpw \
  --health-cmd 'healthcheck.sh --connect --innodb_initialized' --health-interval 2s --health-retries 60)
t_wait_healthy "$db" 120 || die "MariaDB did not start"
c=$(t_run pbx "$image" --network "$net" -v "$(t_volume data):/data" -e APP_DATA=/data \
  -e MYSQL_SERVER=db -e MYSQL_PASSWORD=astpw -e MYSQL_ROOT_PASSWORD=rootpw)
assert_cmd "FreePBX installed: healthy" -- t_wait_healthy "$c" 1500
# the code of the Backup page that failed (Backup::showPage('settings'), the
# settings tab of config.php?display=backup), as php-fpm runs it: as asterisk.
# Through the web the admin of a new installation gets the first-run wizard
# instead of the page, so it is called directly.
settings() {
  docker exec -u asterisk "$c" php -r 'include "/etc/freepbx.conf"; $h = \FreePBX::Backup()->showPage("settings"); echo "\nlength ", strlen($h), "\n";' 2>&1
}
out=$(settings)
assert_cmd_fails "Backup settings: no error" -- grep -qiE 'Failed to open stream|Whoops|Exception' <<< "$out"
assert_cmd "Backup settings: the page is built" -- grep -qE '^length [1-9][0-9]+$' <<< "$out"
assert_cmd "the ECDSA key of asterisk exists" -- docker exec "$c" sh -c 'grep -q "^ecdsa-sha2-nistp521 " ~asterisk/.ssh/id_ecdsa.pub'
assert_eq "asterisk 600" "$(docker exec "$c" sh -c 'stat -c "%U %a" ~asterisk/.ssh/id_ecdsa')" "its private key: asterisk, 0600"
# control: without ssh-keygen the same code fails as the user saw
docker exec "$c" sh -c 'rm -f ~asterisk/.ssh/id_ecdsa ~asterisk/.ssh/id_ecdsa.pub; mv /usr/bin/ssh-keygen /usr/bin/ssh-keygen.off'
assert_contains "$(settings)" "id_ecdsa.pub): Failed to open stream" "control: without ssh-keygen the Backup page fails (the error of the user)"
docker exec "$c" mv /usr/bin/ssh-keygen.off /usr/bin/ssh-keygen
finish
