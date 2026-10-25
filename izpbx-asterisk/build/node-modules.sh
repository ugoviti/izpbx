#!/bin/bash
# Stage "runtime": the Node packages of the FreePBX modules pm2 and ucp,
# installed in the module tree of the image (P4-33, D36). Their installers run
# "npm install --only=production" again on a new installation and in the
# migration: with node_modules already complete npm needs no network, so a
# PBX without Internet access installs and migrates. Pure JavaScript (P0-14:
# no native addon), from registry.npmjs.org over HTTPS with the integrity of
# the registry; the versions resolved are in each package-lock.json.
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
modules=/usr/src/freepbx/amp_conf/htdocs/admin/modules
export npm_config_cache=/usr/src/download-cache/npm

# runtime npm: no request that needs the network besides the packages themselves
cat > "$(npm config get globalconfig)" <<'NPMRC'
audit=false
fund=false
update-notifier=false
NPMRC

for m in pm2 ucp; do
  [ -f "$modules/$m/node/package.json" ] || build_die "$m: no node/package.json in the module tree"
  build_log "$m: npm install (production)"
  (cd "$modules/$m/node" && npm install --omit=dev --no-audit --no-fund --loglevel=error) || build_die "$m: npm install failed"
done
[ -x "$modules/pm2/node/node_modules/pm2/bin/pm2" ] || build_die "pm2: node_modules/pm2/bin/pm2 missing"
# the ucp postinstall (lib/asterisk-manager-patch.js) strips CR/LF from the AMI values
grep -qF "replace(/[\\r\\n]/g, '')" "$modules/ucp/node/node_modules/asterisk-manager/lib/ami.js" ||
  build_die "ucp: the asterisk-manager CR/LF patch is not applied"
