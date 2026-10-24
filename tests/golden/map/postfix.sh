#!/usr/bin/env bash
# Comparable view of the Postfix files (P3-07), the same for 20.16 (Rocky)
# and 22.17 (Debian):
#   map/postfix.sh POSTCONF_CMD DIR
# DIR is a tree with etc/postfix and etc/aliases; POSTCONF_CMD runs
# "postconf -c <dir>/etc/postfix -h KEY..." (the Debian binary of the image,
# so unset keys print the same upstream defaults on both sides).
# Compared: the parameters cfgService_postfix sets (and the transports that
# Debian's "Local only" install changes), the submission line of master.cf,
# the text of sasl_passwd, allowed_senders, sender_canonical_maps,
# header_checks, the root and postmaster aliases (spaces normalized).
set -Eeuo pipefail
pc=$1 dir=$2
KEYS="inet_protocols inet_interfaces myhostname myorigin mydestination default_transport relay_transport
relayhost smtp_sasl_auth_enable smtp_sasl_password_maps smtp_sasl_security_options mynetworks smtp_use_tls
smtpd_restriction_classes allowed_domains_only smtpd_recipient_restrictions maillog_file mailbox_size_limit
message_size_limit sender_canonical_maps smtp_header_checks alias_maps"
echo "== main.cf"
for k in $KEYS; do printf '%s = %s\n' "$k" "$($pc "$k" 2>/dev/null || echo '<unset>')"; done
echo "== master.cf"
grep -E '^submission[[:space:]]' "$dir/etc/postfix/master.cf" | awk '{$1=$1}1' || echo "submission off"
for f in sasl_passwd allowed_senders sender_canonical_maps header_checks; do
  echo "== $f"
  if [ -f "$dir/etc/postfix/$f" ]; then cat "$dir/etc/postfix/$f"; else echo "<missing>"; fi
done
echo "== aliases"
grep -E '^(root|postmaster):' "$dir/etc/aliases" | awk '{$1=$1}1' | sort
