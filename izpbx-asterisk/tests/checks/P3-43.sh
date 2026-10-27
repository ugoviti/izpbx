#!/usr/bin/env bash
# P3-43: the log of the docker console (request of the user: lines too dense,
# errors not standing out; then fixed width levels, no empty sections, a
# "ready" line). common.sh writes every message with a level label and
# aligned columns, "component: text" kept as one string:
# - text: "INFO", "OK" done, "WARN", "ERR", "- " detail under the line before
#   (log_detail or a text starting with two spaces), "----" section lines;
#   the component right aligned (the texts start in one column); ANSI colors
#   on by default, off with IZPBX_LOG_COLOR=false and with NO_COLOR;
# - logfmt and json: one record per line (time, level, component, msg),
#   valid JSON, no colors;
# - izpbx_log_tag: the output of another program labeled "OUT  name:", its
#   empty lines, the lines matching DROP and the leading timestamps left out,
#   the izPBX lines written meanwhile kept as they are and in order; the
#   section of a redirect written only before its first line; an izPBX line
#   written right after the redirect, on a busy host, labeled once (it was
#   labeled twice: "asterisk:  *  asterisk: starting under s6");
# - a container start: a section per init step that says something and no
#   empty one, the output of the services labeled (zabbix without its "using
#   plugin" lines), no s6 "starting" lines (S6_VERBOSITY=1), the summary with
#   the services and the warnings of the start repeated (APP_RUNAS: a warning
#   of 01-legacy), the "ready" line at the end; negative:
#   IZPBX_LOG_COLOR=false leaves no ANSI code in the log, S6_VERBOSITY=2
#   brings the s6 lines back.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p3-43
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

cat > "$work/demo.sh" <<'EOF'
set -Eeuo pipefail
. /usr/local/lib/izpbx/common.sh
log_section "18 freepbx"
log_info "freepbx: running the installer"
log_ok "freepbx: FreePBX installed"
log_warn "migration: ENABLE_ARI was enabled"
log_error "fop2: install failed"
log_info "migration:   CHANGE a.conf:1: x => y"
log_detail "migration: CHANGE a.conf:2: z"
log_info "no component here"
EOF
lib() { docker run --rm --entrypoint "" -v "$work:/w:ro" "$@" "$image" bash /w/demo.sh 2>&1; }

expected='---- 18 freepbx --------------------------------------------------------
INFO         freepbx: running the installer
OK           freepbx: FreePBX installed
WARN       migration: ENABLE_ARI was enabled
ERR             fop2: install failed
                      - CHANGE a.conf:1: x => y
                      - CHANGE a.conf:2: z
INFO                  no component here'
assert_eq "$expected" "$(lib -e IZPBX_LOG_COLOR=false)" "text: level labels, aligned components, details, section"
color=$(lib)
assert_contains "$color" $'\e[1;31mERR \e[0m' "colors: error label in red"
assert_contains "$color" "fop2: install failed" "colors: 'component: text' stays one string"
assert_cmd_fails "NO_COLOR: no ANSI code" -- grep -q $'\e' <<< "$(lib -e NO_COLOR=1)"
json=$(lib -e IZPBX_LOG_FORMAT=json)
assert_eq 8 "$(jq -c . <<< "$json" | wc -l)" "json: 8 valid records"
assert_eq "error fop2 install failed" "$(jq -r 'select(.level == "error") | "\(.level) \(.component) \(.msg)"' <<< "$json")" "json: level, component, msg"
assert_eq 2 "$(jq -r 'select(.detail) | .msg' <<< "$json" | wc -l)" "json: the details flagged"
logfmt=$(lib -e IZPBX_LOG_FORMAT=logfmt)
assert_cmd "logfmt: one record per line" -- grep -qE '^time=[0-9T:+-]+ level=warning component=migration msg="ENABLE_ARI was enabled"$' <<< "$logfmt"
assert_cmd_fails "logfmt: no ANSI code" -- grep -q $'\e' <<< "$logfmt"

cat > "$work/tag.sh" <<'EOF'
set -Eeuo pipefail
. /usr/local/lib/izpbx/common.sh
izpbx_log_redirect empty "" "20 empty"
izpbx_log_redirect zabbix "using plugin '" "21 zabbix"
printf '2026/10/27 19:31:33.535201 Starting Zabbix Agent 2 (7.0.32)\n\n'
printf "2026/10/27 19:31:33.537868 using plugin 'Ceph' (built-in)\n"
log_info "zabbix: an izPBX line"
printf '[27-Oct-2026 19:31:33] NOTICE: fpm is running\n' >&2
printf '2026-10-27T18:31:33Z Selected source 1.2.3.4\n'
izpbx_log_redirect_end
log_ok "izpbx-init: done"
EOF
expected='---- 21 zabbix ---------------------------------------------------------
OUT           zabbix: Starting Zabbix Agent 2 (7.0.32)
INFO          zabbix: an izPBX line
OUT           zabbix: NOTICE: fpm is running
OUT           zabbix: Selected source 1.2.3.4
OK        izpbx-init: done'
assert_eq "$expected" "$(docker run --rm --entrypoint "" -v "$work:/w:ro" -e IZPBX_LOG_COLOR=false "$image" bash /w/tag.sh 2>&1)" \
  "program output: labeled, timestamps, empty and dropped lines left out, izPBX lines in order, no empty section"

# an izPBX line right after the redirect, 200 scripts at once (a busy start)
cat > "$work/race.sh" <<'EOF'
. /usr/local/lib/izpbx/common.sh
izpbx_log_redirect asterisk
log_info "asterisk: starting"
izpbx_log_redirect_end
EOF
race=$(docker run --rm --entrypoint "" -v "$work:/w:ro" -e IZPBX_LOG_COLOR=false "$image" \
  bash -c 'for i in $(seq 200); do bash /w/race.sh </dev/null & done; wait' 2>&1 | sort | uniq -c | sed 's/^ *//')
assert_eq "200 INFO        asterisk: starting" "$race" "a line right after the redirect labeled once (200 parallel runs)"

# --- a container start
start() { # name [docker args]
  local n=$1; shift
  t_run "$n" "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=false -e HTTPD_ENABLED=false -e FAIL2BAN_ENABLED=false \
    -e ZABBIX_ENABLED=true -e ZABBIX_SERVER=127.0.0.1 -e APP_RUNAS=true "$@"
}
c=$(start plain -e IZPBX_LOG_COLOR=false)
t_wait_for 120 -- sh -c "docker logs '$c' 2>&1 | grep -q 'izpbx-init: done'" || die "izpbx-init did not finish"
t_wait_for 30 -- sh -c "docker logs '$c' 2>&1 | grep -q 'zabbix: Starting Zabbix Agent'" || log "zabbix agent output not seen"
logs=$(docker logs "$c" 2>&1)
assert_cmd "a section for a step that says something" -- grep -qx -- '---- 01 legacy -*' <<< "$logs"
assert_cmd "section of the last step" -- grep -qx -- '---- 40 letsencrypt -*' <<< "$logs"
assert_cmd "letsencrypt: its state" -- grep -qE '^INFO +letsencrypt: disabled' <<< "$logs"
assert_cmd_fails "no empty section (a step section followed by another section)" -- \
  awk '/^---- / && prev ~ /^---- [0-9]/ {bad = 1} /^(OK|INFO|WARN|ERR|OUT|---- )/ {prev = $0} END {exit !bad}' <<< "$logs"
assert_cmd "summary: done" -- grep -qE '^OK +izpbx-init: done in [0-9]+s( \(slowest: .*\))?$' <<< "$logs"
assert_cmd "summary: services" -- grep -qE 'izpbx-init: services: .*zabbix' <<< "$logs"
assert_cmd "summary: the warnings of the start counted" -- grep -qE '^WARN +izpbx-init: [1-9] warning\(s\), 0 error\(s\) during the start:$' <<< "$logs"
assert_cmd "summary: and repeated as a detail" -- grep -qE '^ +- legacy: APP_RUNAS' <<< "$logs"
assert_cmd "zabbix output labeled" -- grep -qE '^OUT +zabbix: Starting Zabbix Agent 2' <<< "$logs"
assert_cmd_fails "zabbix: no OpenSSL and configuration file lines" -- grep -qE 'zabbix: (OpenSSL library|using configuration file)' <<< "$logs"
assert_cmd "ready line after the summary" -- t_wait_for 60 -- sh -c "docker logs '$c' 2>&1 | grep -qE '^---- .* ready in [0-9]+s -+$'"
assert_cmd_fails "zabbix: no 'using plugin' lines" -- grep -q 'using plugin' <<< "$logs"
assert_cmd_fails "no line per disabled service (the summary lists the enabled ones)" -- grep -qE 'php-fpm: disabled$' <<< "$logs"
assert_cmd_fails "no s6 'starting' lines (S6_VERBOSITY=1)" -- grep -q 's6-rc: info: service' <<< "$logs"
assert_cmd_fails "IZPBX_LOG_COLOR=false: no ANSI code in the log" -- grep -q $'\e' <<< "$logs"
docker rm -f "$c" >/dev/null

c=$(start s6 -e S6_VERBOSITY=2)
t_wait_for 120 -- sh -c "docker logs '$c' 2>&1 | grep -q 'izpbx-init: done'" || die "izpbx-init did not finish"
logs=$(docker logs "$c" 2>&1)
assert_cmd "negative: S6_VERBOSITY=2 brings the s6 lines back" -- grep -q 's6-rc: info: service izpbx-init' <<< "$logs"
assert_cmd "default: colors in the log" -- grep -q $'\e\\[1;36m---- 01 legacy' <<< "$logs"
finish
