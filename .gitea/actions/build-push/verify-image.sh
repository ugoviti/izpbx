#!/bin/bash
# verify-image.sh: post-build checks run INSIDE the izpbx-asterisk image
# (design E1). The build-push action runs it as
#   docker run -i --rm --entrypoint "" -e ASTERISK_VER=... IMAGE bash -s < verify-image.sh
# Prints one OK/FAIL line per check, exit 1 if any check fails.
#   ASTERISK_VER  expected "asterisk -V" version (required)
#   PHP_MIN       minimum php8.2 Debian version (default below)
set -u

# minimum php8.2-* package version: the Debian 12 security update in the
# image when 22.17.0 was prepared; raise it with each php8.2 security update
PHP_MIN=${PHP_MIN:-8.2.35-1~deb12u1}
FAIL=0
ok() { echo "OK   $*"; }
ko() { echo "FAIL $*"; FAIL=1; }

[ -n "${ASTERISK_VER:-}" ] || { ko "ASTERISK_VER not set"; exit 1; }

# php8.2: every installed php8.2-* package at least PHP_MIN
pkgs=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' 'php8.2*' 2>/dev/null | awk '$1 == "ii" {print $2, $3}')
if [ -z "$pkgs" ]; then
  ko "no php8.2 package installed"
else
  old=$(while read -r p v; do dpkg --compare-versions "$v" ge "$PHP_MIN" || echo "$p $v"; done <<< "$pkgs")
  if [ -z "$old" ]; then ok "php8.2 $(awk '$1 == "php8.2-common" {print $2}' <<< "$pkgs") >= $PHP_MIN"
  else ko "php8.2 packages older than $PHP_MIN: $(echo $old)"; fi
fi

# Asterisk version
ast=$(asterisk -V 2>&1 || true)
if [ "$ast" == "Asterisk $ASTERISK_VER" ]; then ok "$ast"
else ko "asterisk -V: \"$ast\", expected \"Asterisk $ASTERISK_VER\""; fi

# Asterisk modules: removed in 22 (chan_sip, app_macro), required by izPBX
moddir=$(sed -n 's/^astmoddir *=> *//p' /etc/asterisk/asterisk.conf 2>/dev/null)
moddir=${moddir:-/usr/lib64/asterisk/modules}
for m in chan_sip app_macro; do
  if [ -e "$moddir/$m.so" ]; then ko "$m.so present in $moddir"; else ok "$m.so absent"; fi
done
for m in app_sla chan_dongle codec_g729; do
  if [ -f "$moddir/$m.so" ]; then ok "$m.so present"; else ko "$m.so missing in $moddir"; fi
done

# ionCube loaded in cli and fpm
for sapi in "php" "php-fpm8.2"; do
  if $sapi -v 2>/dev/null | grep -q 'with the ionCube PHP Loader'; then ok "ionCube loaded ($sapi)"
  else ko "ionCube not loaded ($sapi)"; fi
done

# allow_url_include Off in cli and fpm (ini files and fpm pool overrides)
off() { case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in ""|0|off|false|no|none) return 0 ;; esac; return 1; }
for sapi in "php" "php-fpm8.2"; do
  v=$($sapi -i 2>/dev/null | sed -n 's/^allow_url_include => \([^ ]*\) => .*/\1/p' | head -1)
  if off "$v"; then ok "allow_url_include=\"$v\" ($sapi)"; else ko "allow_url_include=\"$v\" ($sapi), must be Off"; fi
done
pool=$(grep -rhiE '^[[:space:]]*php_(admin_)?(flag|value)\[allow_url_include\]' /etc/php/8.2/fpm/pool.d 2>/dev/null | sed 's/.*=[[:space:]]*//' | head -1)
if off "$pool"; then ok "allow_url_include not enabled by the fpm pools"
else ko "allow_url_include=\"$pool\" in /etc/php/8.2/fpm/pool.d, must be Off"; fi

exit $FAIL
