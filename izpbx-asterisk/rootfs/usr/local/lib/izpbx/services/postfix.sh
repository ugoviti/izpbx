# shellcheck shell=bash
# Postfix configured from the environment, as cfgService_postfix of 20.16
# (relay with SASL auth, mynetworks, allowed sender domains, From rewrite,
# size limit, root alias, submission port). Debian differences: the package
# is installed "Local only" (build/base.sh), so the transports, myorigin and
# mydestination are set back to the upstream defaults that 20.16 had on
# Rocky; only the "submission" line of master.cf is enabled (Debian also has
# a commented "submissions").
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh

: "${POSTFIX_DIR:=/etc/postfix}"
: "${ALIASES_FILE:=/etc/aliases}"

cfg_postfix() {
  local d=$POSTFIX_DIR domain
  postconf -e inet_protocols=ipv4 inet_interfaces=localhost
  # upstream defaults (20.16 on Rocky), not the "Local only" ones of Debian
  postconf -e default_transport=smtp relay_transport=relay 'myorigin=$myhostname' \
    'mydestination=$myhostname, localhost.$mydomain, localhost'
  if [ -n "$HOSTNAME" ]; then postconf -e "myhostname=$HOSTNAME"; else postconf -# myhostname; fi

  rm -f "$d/sasl_passwd" "$d/sasl_passwd.db"
  if [ -n "$RELAYHOST" ]; then
    log_info "postfix: relay [$RELAYHOST]:$RELAYHOST_PORT"
    postconf -e "relayhost=[$RELAYHOST]:$RELAYHOST_PORT"
    if [ -n "$RELAYHOST_USERNAME" ] && [ -n "$RELAYHOST_PASSWORD" ]; then
      log_info "postfix: relay authentication as $RELAYHOST_USERNAME"
      # the key matches the relayhost value [host]:port; root only
      ( umask 077; printf '[%s]:%s %s:%s\n' "$RELAYHOST" "$RELAYHOST_PORT" "$RELAYHOST_USERNAME" "$RELAYHOST_PASSWORD" > "$d/sasl_passwd"
        postmap "hash:$d/sasl_passwd" )
      chown root:root "$d/sasl_passwd" "$d/sasl_passwd.db"
      chmod 600 "$d/sasl_passwd" "$d/sasl_passwd.db"
      postconf -e smtp_sasl_auth_enable=yes "smtp_sasl_password_maps=hash:$d/sasl_passwd" \
        smtp_sasl_security_options=noanonymous
    else
      log_info "postfix: relay without authentication"
      postconf -# smtp_sasl_auth_enable smtp_sasl_password_maps smtp_sasl_security_options
    fi
  else
    log_info "postfix: no relay, direct delivery (the DNS must be set up)"
    postconf -# relayhost smtp_sasl_auth_enable smtp_sasl_password_maps smtp_sasl_security_options
  fi

  # relaying only from localhost unless SMTP_MYNETWORKS (no open relay in the LAN)
  postconf -e "mynetworks=${SMTP_MYNETWORKS:-127.0.0.0/8}"
  [ "$SMTP_STARTTLS" == "true" ] && postconf -e smtp_use_tls=yes

  rm -f "$d/allowed_senders" "$d/allowed_senders.db"
  if [ -n "$ALLOWED_SENDER_DOMAINS" ]; then
    log_info "postfix: allowed sender domains: $ALLOWED_SENDER_DOMAINS"
    : > "$d/allowed_senders"
    # shellcheck disable=SC2086 # space separated list
    for domain in $ALLOWED_SENDER_DOMAINS; do printf '%s\tOK\n' "$domain" >> "$d/allowed_senders"; done
    postmap "$d/allowed_senders"
    postconf -e smtpd_restriction_classes=allowed_domains_only \
      "allowed_domains_only=permit_mynetworks, reject_non_fqdn_sender reject" \
      "smtpd_recipient_restrictions=reject_non_fqdn_recipient, reject_unknown_recipient_domain, reject_unverified_recipient, check_sender_access hash:$d/allowed_senders, reject"
  else
    postconf -# smtpd_restriction_classes
    postconf -e "smtpd_recipient_restrictions=reject_non_fqdn_recipient,reject_unknown_recipient_domain,reject_unverified_recipient"
  fi

  # submission (587)
  sed -i -E 's/^#(submission[[:space:]])/\1/' "$d/master.cf"
  # no chroot, as the other services (build/runtime.sh)
  postconf -F 'submission/inet/chroot = n'

  # root alias: the value is written as it is (no sed replacement to escape)
  [ -f "$ALIASES_FILE" ] || echo "postmaster: root" > "$ALIASES_FILE"
  if ! grep -qxF "root: ${SMTP_MAIL_TO}" "$ALIASES_FILE"; then
    { grep -v '^root:' "$ALIASES_FILE" || true; printf 'root: %s\n' "$SMTP_MAIL_TO"; } > "$ALIASES_FILE.new"
    mv "$ALIASES_FILE.new" "$ALIASES_FILE"
  fi
  newaliases

  postconf -e "maillog_file = /dev/stdout" "mailbox_size_limit = 0" "message_size_limit = ${MESSAGE_SIZE_LIMIT}"

  rm -f "$d/sender_canonical_maps" "$d/header_checks"
  if [ -n "$SMTP_MAIL_FROM" ]; then
    echo "/.+/ $SMTP_MAIL_FROM" > "$d/sender_canonical_maps"
    echo "/From:.*/ REPLACE From: $SMTP_MAIL_FROM" > "$d/header_checks"
    postconf -e "sender_canonical_maps = regexp:$d/sender_canonical_maps" \
      "smtp_header_checks = regexp:$d/header_checks"
  fi
  # integrity check (queue directories and permissions) before the service
  # starts, not in its run script (a stop during the check left it behind)
  postfix check
}
