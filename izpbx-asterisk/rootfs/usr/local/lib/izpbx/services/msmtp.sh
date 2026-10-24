# shellcheck shell=bash
# msmtp as sendmail (the default MTA: /usr/sbin/sendmail is linked in
# init.d/10-services.sh), as cfgService_msmtp of 20.16. Debian difference:
# the CA bundle is /etc/ssl/certs/ca-certificates.crt (design C6). The file
# holds the SMTP password: 0640 root:asterisk (voicemail-to-email runs as
# asterisk).
# shellcheck source=../env.sh
. /usr/local/lib/izpbx/env.sh

: "${MSMTP_CONF:=/etc/msmtprc}"
: "${MSMTP_CA_FILE:=/etc/ssl/certs/ca-certificates.crt}"

cfg_msmtp() {
  local home tls=off
  home=$(getent passwd "$APP_USR" | cut -d: -f6)
  [ "$SMTP_STARTTLS" == "true" ] && tls=on
  install -m 0640 -o root -g "$APP_GRP" /dev/null "$MSMTP_CONF"
  echo "defaults
tls      $tls
tls_starttls   $tls
$([ "$tls" == on ] && echo "tls_trust_file $MSMTP_CA_FILE")
logfile  ${home}/msmtp.log
account  default

$([ -n "$SMTP_RELAYHOST" ] && echo "host     ${SMTP_RELAYHOST}")
$([ -n "$SMTP_RELAYHOST_PORT" ] && echo "port     ${SMTP_RELAYHOST_PORT}")
$([ -n "$SMTP_MAIL_FROM" ] && echo "from     ${SMTP_MAIL_FROM}")

$([ -n "$SMTP_RELAYHOST_USERNAME" ] && echo "auth     on" || echo "auth     off")
$([ -n "$SMTP_RELAYHOST_USERNAME" ] && echo "user     ${SMTP_RELAYHOST_USERNAME}")
$([ -n "$SMTP_RELAYHOST_PASSWORD" ] && echo "password ${SMTP_RELAYHOST_PASSWORD}")
" > "$MSMTP_CONF"
  log_info "msmtp: relay ${SMTP_RELAYHOST:-<none>}$([ -n "$SMTP_RELAYHOST_USERNAME" ] && echo " as $SMTP_RELAYHOST_USERNAME")"
}
