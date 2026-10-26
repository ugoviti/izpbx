#!/usr/bin/env bash
# P7-05: the release notes (§13 of the design) aligned with the code.
# A comparison script lists every difference the code allows:
# - the rules of the inventory mapping (migration-mapping.tsv: CATEGORY and
#   REGEX, or additions/ignore) and the ones migration_verify adds at runtime
#   (the variables and states of its loop);
# - the golden test rules: the file arms of izpbx-asterisk/tests/golden/map/files.sh and
#   the substitutions of izpbx-asterisk/tests/golden/map/httpd.sh;
# and requires for each one a row of the table below, whose keyword is in §13
# (when .specs is there) and in the CHANGELOG entry 22.17.0 (always). A row
# with "=" is a rule that compares the same content on both sides.
# Negative checks: a mapping rule with no row, and a keyword missing from the
# release notes, are reported.
source "$(dirname "$0")/../lib.sh"
share="$REPO_DIR/izpbx-asterisk/rootfs/usr/local/share/izpbx"
migration="$REPO_DIR/izpbx-asterisk/rootfs/usr/local/lib/izpbx/services/migration.sh"
golden="$REPO_DIR/izpbx-asterisk/tests/golden/map"
spec="$REPO_DIR/.specs/2026-10-23-release-22.17.0-freepbx17.md"
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"

# rule -> keyword of the release notes
cat > "$work/table" <<'EOF'
mapping:extensions tech=sip	chan_sip
mapping:trunks tech=sip	chan_sip
mapping:astdb value=SIP/	chan_sip
mapping:astdb (?<=/tech) value=sip$	chan_sip
mapping:astdb additions	astdb
mapping:astdb ^key=/(dundi|pbx)/	dundi
mapping:astdb ^key=/CustomDevstate/	CustomDevstate
mapping:modules ^module=phonebook 	phonebook
mapping:modules additions	infoservices
mapping:moh ^path=\.nomusic_reserved/	.nomusic_reserved
mapping:advanced_settings ignore	Advanced Settings
mapping:files ^path=usr/local/fop2/fop2\.cfg 	fop2.cfg
mapping:pjsip_endpoints ignore	PJSIP
runtime:commercial	commercial
runtime:IZPBX_MIGRATION_REMOVED_MODULES	speeddial
runtime:IZPBX_MIGRATE_IGNORE_MODULES	IZPBX_MIGRATE_IGNORE_MODULES
golden:/etc/httpd/conf.d/virtual.conf|/etc/httpd/conf/httpd.conf	Apache
golden:/etc/httpd/conf.d/phonebook.conf	Apache
golden:/etc/httpd/conf.d/phpMyAdmin_izpbx.conf	phpMyAdmin
golden:/etc/httpd/conf.d/phpMyAdmin.conf	phpMyAdmin
golden:/etc/msmtprc	msmtp
golden:/etc/fail2ban/jail.d/99-local.conf	fail2ban
golden:/etc/fail2ban/fail2ban.conf|/etc/zabbix/zabbix_agent2.conf	Zabbix
golden:/etc/php.d/99-timezone.ini	PHP
golden:/etc/chrony.conf	chrony
golden:/etc/izpbx/cron.env|/etc/timezone|/etc/dnsmasq.d/local.conf|/etc/zabbix/zabbix_agent2.d/local.conf	=
golden:/etc/aliases|/etc/postfix/*	Postfix
httpd:logs/ssl_error_log	${APACHE_LOG_DIR}
httpd:logs/ssl_access_log	${APACHE_LOG_DIR}
httpd:exec:/usr/libexec/httpd-ssl-pass-dialog	Apache
httpd:shmcb:/run/httpd/sslcache(	Apache
httpd:PROFILE=SYSTEM	HIGH:!aNULL
EOF

rules() { # mapping file -> every allowed difference, one per line
  awk -F '\t' '!/^#/ && NF >= 2 {print "mapping:" $1 " " $2}' "$1"
  grep -F -B 1 "printf 'modules" "$migration" | sed -n 's/.*for m in \(.*\); do$/\1/p' | grep -oE '\$\(migration_state [a-z_]+\)|\$\{?[A-Z_]+' |
    sed -E 's/^\$\(migration_state ([a-z_]+)\)$/\1/; s/^\$\{?//' | sed 's/^/runtime:/'
  sed -n '/^case "\$path" in$/,/^esac$/p' "$golden/files.sh" | sed -nE 's/^  ([^ *][^)]*)\)$/\1/p' | sed 's/^/golden:/'
  grep -oE "\-e 's\|[^|]+\|" "$golden/httpd.sh" | sed -E "s/^-e 's\|//; s/\|$//" | sed 's/^/httpd:/'
}
check() { # mapping file -> the rules with no row, then the keywords missing from the release notes
  local r k
  rules "$1" | while IFS= read -r r; do
    grep -qF -- "$r	" "$work/table" || printf 'no row: [%s]\n' "$r"
  done
  cut -f2 "$work/table" | sort -u | while IFS= read -r k; do
    [ "$k" != "=" ] || continue
    grep -qF -- "$k" "$work/changelog" || printf 'not in the CHANGELOG: [%s]\n' "$k"
    [ ! -s "$work/s13" ] || grep -qF -- "$k" "$work/s13" || printf 'not in §13: [%s]\n' "$k"
  done
}
awk '/^## \[22\.17\.0\]/ {e = 1} e && /^## \[20/ {exit} e' "$REPO_DIR/CHANGELOG.md" > "$work/changelog"
: > "$work/s13"
[ ! -f "$spec" ] || sed -n '/^## 13\./,/^## 14\./p' "$spec" > "$work/s13"
log "$(rules "$share/migration-mapping.tsv" | wc -l) allowed differences; §13 $( [ -s "$work/s13" ] && echo present || echo 'not here (CHANGELOG only)')"
assert_cmd "the mapping rules are found (chan_sip)" -- sh -c "grep -qx 'mapping:extensions tech=sip' <<EOF
$(rules "$share/migration-mapping.tsv")
EOF"
assert_eq 3 "$(rules "$share/migration-mapping.tsv" | grep -c '^runtime:')" "the 3 runtime sources of migration_verify are found"
assert_eq "" "$(check "$share/migration-mapping.tsv")" "every allowed difference has its entry in the release notes"

{ cat "$share/migration-mapping.tsv"; printf 'queues\t^strategy=\t\n'; } > "$work/mapping-new.tsv"
assert_contains "$(check "$work/mapping-new.tsv")" "no row: [mapping:queues ^strategy=]" "negative: a mapping rule with no entry is reported"
sed -i '/CustomDevstate/d' "$work/changelog"
assert_contains "$(check "$share/migration-mapping.tsv")" "not in the CHANGELOG: [CustomDevstate]" "negative: a keyword missing from the release notes is reported"
finish
