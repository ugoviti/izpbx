# shellcheck shell=bash
# FOP2 (Flash Operator Panel 2), as cfgService_fop2 of 20.16:
# - install at the first start (no /usr/local/fop2/fop2.cfg, persisted under
#   APP_DATA): the Debian package for this architecture is downloaded over
#   HTTPS and installed (Makefile recipe) only if its sha256 matches
#   (versions.env, or FOP2_SHA256); otherwise the install is refused and the
#   service stays down;
# - fop2.cfg: AMI host/port/user/secret from FOP2_AMI_* or from the FreePBX
#   settings (ASTMANAGERHOST, ASTMANAGERPORT, AMPMGRUSER, AMPMGRPASS, read
#   from the database), the HTTPS certificates when HTTPD_HTTPS_ENABLED;
# - licensed interface (FOP2_LICENSE_IFACE, default the first one but lo) in
#   /etc/default/fop2 (Debian, design C13), used by the s6 run script;
# - license registration with FOP2_LICENSE_NAME/CODE, the code never shown in
#   the logs (masked in the output of fop2_server too).
# shellcheck source=../actions.sh
. /usr/local/lib/izpbx/actions.sh

: "${FOP2_DIR:=/usr/local/fop2}"
: "${FOP2_SRC:=/usr/src/fop2}"
: "${FOP2_DEFAULTS:=/etc/default/fop2}"
: "${FOP2_DOWNLOAD:=https://download2.fop2.com}"

# package name, version and sha256 for this architecture (the arm64 download
# of fop2.com is the armv7l build, see versions.env)
_fop2_package() {
  local ver sha arch
  case "$(uname -m)" in
    x86_64) arch=x86_64; ver=$FOP2_VER; sha=$(_izpbx_version FOP2_SHA256_X86_64) ;;
    aarch64) arch=armv7l; ver=$(_izpbx_version FOP2_VER_AARCH64); sha=$(_izpbx_version FOP2_SHA256_AARCH64) ;;
    *) log_error "fop2: no FOP2 package for $(uname -m)"; return 1 ;;
  esac
  [ -n "$FOP2_SHA256" ] && sha=$FOP2_SHA256
  printf '%s %s %s\n' "fop2-${ver}-debian-${arch}.tgz" "$ver" "$sha"
}

# fop2_fetch: download and verify the package, extract it into FOP2_SRC
fop2_fetch() {
  local pkg ver sha tmp
  read -r pkg ver sha < <(_fop2_package) || return 1
  if [ -z "$ver" ] || [ -z "$sha" ]; then
    log_warn "fop2: FOP2 version or sha256 not defined: install refused"
    return 1
  fi
  tmp=$(mktemp -d)
  if ! curl -fsSL --proto '=https' --retry 3 -o "$tmp/$pkg" "$FOP2_DOWNLOAD/$pkg"; then
    log_error "fop2: download of $FOP2_DOWNLOAD/$pkg failed"
    rm -rf "$tmp"; return 1
  fi
  if ! echo "$sha  $tmp/$pkg" | sha256sum -c - >/dev/null 2>&1; then
    log_error "fop2: sha256 of $pkg does not match ($sha): install refused"
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$FOP2_SRC" && mkdir -p "$FOP2_SRC"
  tar -xzf "$tmp/$pkg" -C "$FOP2_SRC" --strip-components 1
  rm -rf "$tmp"
  log_info "fop2: $pkg verified (sha256) and extracted"
}

# _fop2_make_install: the "install" recipe of the package Makefile run by
# bash, without make (no build tools in the runtime image, P0-14): it is a
# single shell command, the make variables are replaced as make would.
# UPDATE_DIALPLAN=0 (the FreePBX dialplan is written by
# generate_override_contexts.pl, only with FreePBX); the service management
# of the package is disabled by no-op commands first in PATH (s6 runs fop2:
# no init script registration, no "apachectl graceful" starting Apache
# outside s6, no package installs, no crontab).
_fop2_make_install() {
  local stubs cmd
  stubs=$(mktemp -d)
  for cmd in apachectl apache2ctl systemctl update-rc.d apt-get yum crontab; do
    printf '#!/bin/sh\nexit 0\n' > "$stubs/$cmd"; chmod 755 "$stubs/$cmd"
  done
  awk '/^install:/ {f = 1; next} f && /^\t@echo "Done!"/ {exit} f' "$FOP2_SRC/Makefile" |
    sed -e 's/^\t//' -e '1s/^@//' -e 's/\$\$/$/g' -e 's/\$(INSTALL)/install/g' \
        -e 's|\$(prefix)|/usr/local|g' -e 's/\$(UPDATE_DIALPLAN)/0/g' -e 's|\${CHKCONFIG}|/sbin/chkconfig|g' \
    > "$stubs/install.sh"
  ( cd "$FOP2_SRC" && PATH="$stubs:$PATH" bash "$stubs/install.sh" ) >/dev/null 2>&1
  local rc=$?
  rm -rf "$stubs"
  return $rc
}

# the dialplan contexts of FOP2 (extensions_override_fop2.conf) and its tables
# in the FreePBX database (FOP2 Manager): run by izpbx-init, Asterisk and AMI
# are down, so its "Unable to connect to remote asterisk" and "Unable to
# connect to manager localhost:5038" lines are expected (Asterisk loads the
# dialplan when it starts): the output goes to a file, the log gets one line,
# or its last lines on a failure (it stops only when it cannot write a file)
FOP2_OVERRIDE_LOG=/tmp/fop2-override-contexts.log
_fop2_override_contexts() {
  if izpbx_dry_run; then izpbx_record "$FOP2_DIR/generate_override_contexts.pl -write"; return 0; fi
  if "$FOP2_DIR/generate_override_contexts.pl" -write > "$FOP2_OVERRIDE_LOG" 2>&1; then
    log_info "fop2: dialplan contexts and FOP2 Manager tables written (output in $FOP2_OVERRIDE_LOG)"
  else
    log_warn "fop2: generate_override_contexts.pl failed, last lines of $FOP2_OVERRIDE_LOG:"
    tail -n 8 "$FOP2_OVERRIDE_LOG" | while IFS= read -r line; do log_warn "  $line"; done
  fi
}

# fop2_install: download, verify and install the package
fop2_install() {
  fop2_fetch || return 1
  _fop2_make_install || { log_error "fop2: install of the package failed"; return 1; }
  if [ -e /etc/freepbx.conf ] && [ -x "$FOP2_DIR/generate_override_contexts.pl" ]; then
    _fop2_override_contexts
  fi
  log_ok "fop2: installed in $FOP2_DIR"
}

# FreePBX setting from the database (empty without FreePBX)
_fop2_setting() { izpbx_sql_query "SELECT value FROM freepbx_settings WHERE keyword='$(sqlEscape "$1")'" 2>/dev/null || true; }

# the FOP2 license code never goes to the logs, not even inside fop2_server output;
# left out too: the lines of fop2_server telling the running server about the
# license, which does not run yet during izpbx-init ("Could not connect to
# socket /var/run/fop2.ctl" and the Perl error that follows it)
_fop2_mask() {
  local line code=$FOP2_LICENSE_CODE
  while IFS= read -r line; do
    [[ "$line" == "Could not connect to socket /var/run/fop2.ctl"* || "$line" == "Can't use an undefined value as a symbol reference"* ]] && continue
    [ -n "$code" ] && line=${line//"$code"/********}
    printf '%s\n' "$line"
  done
}
_fop2_license() { # fop2_server options...
  if izpbx_dry_run; then
    local args=("$@")
    izpbx_record "$FOP2_DIR/fop2_server ${args[*]//"$FOP2_LICENSE_CODE"/********}"
    return 0
  fi
  "$FOP2_DIR/fop2_server" "$@" 2>&1 | _fop2_mask >&2 || true
}

# _fop2_reactivate OPTIONS...: the license file is there but the license
# server does not know this host (new interface or MAC address): reactivate
# it. A warning only if the reactivation fails, with what fop2_server said.
_fop2_reactivate() {
  local out line
  if izpbx_dry_run; then _fop2_license --reactivate "$@"; return 0; fi
  out=$("$FOP2_DIR/fop2_server" --reactivate "$@" 2>&1 | _fop2_mask) || true
  if grep -qi 'success' <<< "$out"; then
    log_ok "fop2: license not found for this host, reactivated"
  else
    log_warn "fop2: license not found for this host and its reactivation failed (FOP2 runs in demo mode)"
    while IFS= read -r line; do [ -z "${line//[[:space:]]/}" ] || log_detail "fop2: $line"; done <<< "$out"
  fi
}

cfg_fop2() {
  local f=$FOP2_DIR/fop2.cfg opts=(--rp=http) cur
  if [ ! -e "$f" ]; then
    log_info "fop2: not installed, installing FOP2 $FOP2_VER"
    fop2_install || { log_error "fop2: install failed, the service stays down"; return 0; }
  fi
  : "${FOP2_AMI_HOST:=$(_fop2_setting ASTMANAGERHOST)}"
  : "${FOP2_AMI_PORT:=$(_fop2_setting ASTMANAGERPORT)}"
  : "${FOP2_AMI_USERNAME:=$(_fop2_setting AMPMGRUSER)}"
  : "${FOP2_AMI_PASSWORD:=$(_fop2_setting AMPMGRPASS)}"
  [ -n "$FOP2_AMI_HOST" ] && sed "s|^manager_host.*=.*|manager_host=$(sedEscape "$FOP2_AMI_HOST")|" -i "$f"
  [ -n "$FOP2_AMI_PORT" ] && sed "s|^manager_port.*=.*|manager_port=$(sedEscape "$FOP2_AMI_PORT")|" -i "$f"
  [ -n "$FOP2_AMI_USERNAME" ] && sed "s|^manager_user.*=.*|manager_user=$(sedEscape "$FOP2_AMI_USERNAME")|" -i "$f"
  [ -n "$FOP2_AMI_PASSWORD" ] && set_line_secret "$f" '^manager_secret.*=' 'manager_secret=' FOP2_AMI_PASSWORD
  if [ "$HTTPD_HTTPS_ENABLED" == "true" ]; then
    sed "s|^ssl_certificate_file.*=.*|ssl_certificate_file=$(sedEscape "$HTTPD_HTTPS_CERT_FILE")|" -i "$f"
    sed "s|^ssl_certificate_key_file.*=.*|ssl_certificate_key_file=$(sedEscape "$HTTPD_HTTPS_KEY_FILE")|" -i "$f"
  fi

  # licensed interface
  [ -n "$FOP2_LICENSE_IFACE" ] || FOP2_LICENSE_IFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {sub(/@.*/, "", $2); print $2; exit}')
  if [ -n "$FOP2_LICENSE_IFACE" ]; then
    echo "OPTIONS=\"-d -i ${FOP2_LICENSE_IFACE}\"" > "$FOP2_DEFAULTS"
    opts+=(--iface "$FOP2_LICENSE_IFACE")
  fi

  if [ "$FOP2_AUTOUPGRADE" == "true" ]; then
    cur=$("$FOP2_DIR/fop2_server" -v 2>/dev/null | awk '{print $3}')
    if [ "$(check_version "$cur")" -lt "$(check_version "$FOP2_VER")" ]; then
      log_info "fop2: upgrading from $cur to $FOP2_VER"
      fop2_fetch && _fop2_make_install
    fi
  fi

  if [ ! -e "$FOP2_DIR/fop2.lic" ]; then
    if [ -z "$FOP2_LICENSE_CODE" ]; then
      log_info "fop2: not licensed (no FOP2_LICENSE_CODE): demo mode"
    else
      log_info "fop2: registering the license for '${FOP2_LICENSE_NAME}' (code ******** hidden) on ${FOP2_LICENSE_IFACE}"
      _fop2_license --register --name "$FOP2_LICENSE_NAME" --code "$FOP2_LICENSE_CODE" "${opts[@]}"
      _fop2_license --getinfo "${opts[@]}"
    fi
  elif [ "$FOP2_AUTOACTIVATION" == "true" ]; then
    if "$FOP2_DIR/fop2_server" --getinfo "${opts[@]}" 2>/dev/null | grep -q '^Not Found'; then
      _fop2_reactivate "${opts[@]}"
    fi
  fi
  log_info "fop2: configured (AMI ${FOP2_AMI_HOST:-unchanged}:${FOP2_AMI_PORT:-unchanged})"
}
