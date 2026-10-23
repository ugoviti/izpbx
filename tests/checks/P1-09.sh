#!/usr/bin/env bash
# P1-09: build/extras.sh.
# - ionCube $IONCUBE_VER for PHP 8.2: "php -v" (cli) and "php-fpm8.2 -v"
#   report it, conf.d/00-ioncube.ini enabled for cli, fpm and apache2;
# - izsynth installed and executable ("-h" exits 0, version $IZSYNTH_VER),
#   every command it needs (curl md5sum file iconv soxi sox lame) present;
# - zabbix-agent2: asterisk.conf + scripts/asterisk.sh in zabbix_agent2.d,
#   not group/other writable, the configuration validates and, with Asterisk
#   running, "check.asterisk[version]" answers with the Asterisk version;
#   zabbix-agent2 is the $ZABBIX_VER.x of repo.zabbix.com (not Debian's 6.0).
# Negative: "php -n" (no ini files) shows no ionCube; an unknown agent key
# is ZBX_NOTSUPPORTED; a command that does not exist is reported missing.
source "$(dirname "$0")/../lib.sh"

dir="$REPO_DIR/izpbx-asterisk"
image=izpbx-asterisk:p1-09
v() { sed -n "s/^$1=//p" "$dir/versions.env"; }
ioncube=$(v IONCUBE_VER); izsynth=$(v IZSYNTH_VER); asterisk=$(v ASTERISK_VER)
img() { docker run --rm --entrypoint "" "$image" bash -c "$1"; }

assert_cmd "image builds" -- docker build -q -t "$image" "$dir"

# --- ionCube
assert_contains "$(img 'php -v')" "with the ionCube PHP Loader v$ioncube" "php -v (cli): ionCube $ioncube"
assert_contains "$(img 'php-fpm8.2 -v')" "with the ionCube PHP Loader v$ioncube" "php-fpm8.2 -v: ionCube $ioncube"
for sapi in cli fpm apache2; do
  assert_cmd "ionCube enabled for $sapi" -- img "grep -qx 'zend_extension=ioncube_loader_lin_8.2.so' /etc/php/8.2/$sapi/conf.d/00-ioncube.ini"
done
assert_eq "0" "$(img 'php -n -v | grep -c ionCube || true')" "control: php -n (no ini files) has no ionCube"

# --- izsynth
assert_cmd "izsynth is executable" -- img 'test -x /usr/local/bin/izsynth'
assert_contains "$(img 'izsynth -h')" "version: $izsynth" "izsynth -h answers with version $izsynth"
missing() { img "for c in $*; do command -v \$c >/dev/null || echo \$c; done"; }
assert_eq "" "$(missing curl md5sum file iconv soxi sox lame)" "every command izsynth needs is installed"
assert_eq "izpbx-nosuch-cmd" "$(missing curl izpbx-nosuch-cmd)" "control: a missing command is reported"

# --- zabbix-agent2 templates
z=/etc/zabbix/zabbix_agent2.d
assert_cmd "asterisk.conf and scripts/asterisk.sh installed" -- img "test -f $z/asterisk.conf && test -x $z/scripts/asterisk.sh"
assert_eq "" "$(img "find $z -perm /022")" "templates not group/other writable"
zbx=$(sed -n 's/^ZABBIX_VER=//p' "$dir/versions.env")
assert_contains "$(img 'dpkg-query -W -f "\${Version}" zabbix-agent2')" "1:$zbx." "zabbix-agent2 $zbx.x from repo.zabbix.com"
assert_cmd "zabbix_agent2 configuration validates" -- img 'zabbix_agent2 -c /etc/zabbix/zabbix_agent2.conf -T'
c=$(t_run ast "$image" --entrypoint "" -- asterisk -f -U asterisk -G asterisk)
# "core waitfullybooted": before full boot (slow under arm64 emulation) the
# agent script gets "No such command 'core show version'"
t_wait_for 120 -- docker exec "$c" asterisk -rx "core waitfullybooted" || die "Asterisk did not start"
key() { docker exec "$c" zabbix_agent2 -c /etc/zabbix/zabbix_agent2.conf -t "$1" 2>&1; }
assert_contains "$(key 'check.asterisk[version]')" "Asterisk $asterisk" "check.asterisk[version] answers Asterisk $asterisk"
assert_contains "$(key 'izpbx.nosuch.key')" "ZBX_NOTSUPPORTED" "control: an unknown key is not supported"

docker rmi "$image" >/dev/null 2>&1 || true
finish
