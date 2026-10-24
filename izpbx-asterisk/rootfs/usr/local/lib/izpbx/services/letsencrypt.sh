# shellcheck shell=bash
# Let's Encrypt certificates through FreePBX and the environment of the cron
# jobs, as cfgService_letsencrypt and cfgCronEnv of 20.16:
# - cfg_cronenv: /etc/izpbx/cron.env (0600 root) with the variables the daily
#   renewal job reads (/etc/cron.daily/freepbx-le-renew: cron does not get
#   the container environment);
# - cfg_letsencrypt: with HTTPD_HTTPS_ENABLED and LETSENCRYPT_ENABLED, update
#   the existing certificate of APP_FQDN or request a new one with
#   "fwconsole certificates" (Apache must answer the ACME challenge: it is
#   started for the request and stopped after, before the s6 services).
#   Without FreePBX (no fwconsole yet) the request is skipped with a warning.
# shellcheck source=../actions.sh
. /usr/local/lib/izpbx/actions.sh

: "${CRON_ENV:=/etc/izpbx/cron.env}"
: "${CERTKEYLOC:=/etc/asterisk/keys}"

cfg_cronenv() {
  mkdir -p "$(dirname "$CRON_ENV")"
  ( umask 077
    {
      echo "# izPBX environment for cron jobs (automatically generated at container startup: don't edit)"
      printf 'export HTTPD_HTTPS_ENABLED=%q\n' "$HTTPD_HTTPS_ENABLED"
      printf 'export LETSENCRYPT_ENABLED=%q\n' "$LETSENCRYPT_ENABLED"
      printf 'export APP_FQDN=%q\n' "$APP_FQDN"
    } > "$CRON_ENV" )
  chown root:root "$CRON_ENV"
  chmod 0600 "$CRON_ENV"
  log_info "cron: environment of the cron jobs in $CRON_ENV"
}

_le_missing() {
  if [ -z "$APP_FQDN" ]; then echo APP_FQDN
  elif [ -z "$LETSENCRYPT_COUNTRY_CODE" ]; then echo LETSENCRYPT_COUNTRY_CODE
  elif [ -z "$LETSENCRYPT_COUNTRY_STATE" ]; then echo LETSENCRYPT_COUNTRY_STATE
  elif [ -z "$LETSENCRYPT_EMAIL" ]; then echo "LETSENCRYPT_EMAIL (default: SMTP_MAIL_TO)"
  fi
}

cfg_letsencrypt() {
  local missing ok=1
  missing=$(_le_missing)
  if [ -n "$missing" ]; then
    log_warn "letsencrypt: skipping the certificate request, $missing is not defined"
    return 0
  fi
  if ! command -v fwconsole >/dev/null; then
    log_warn "letsencrypt: FreePBX (fwconsole) not installed yet, certificate request skipped"
    return 0
  fi
  log_info "letsencrypt: certificate for $APP_FQDN"
  izpbx_do apache2ctl start
  if [ -e "$CERTKEYLOC/$APP_FQDN.pem" ]; then
    log_info "letsencrypt: certificate for $APP_FQDN exists, updating all certificates"
    izpbx_do fwconsole certificates --updateall && ok=0
  fi
  if [ "$ok" -ne 0 ]; then
    izpbx_do fwconsole certificates -n --generate --type=le --hostname="$APP_FQDN" \
      --country-code="$LETSENCRYPT_COUNTRY_CODE" --state="$LETSENCRYPT_COUNTRY_STATE" \
      --email="$LETSENCRYPT_EMAIL" && ok=0
  fi
  if [ "$ok" -eq 0 ]; then
    izpbx_do fwconsole certificates --default="$APP_FQDN"
    log_info "letsencrypt: default FreePBX certificate is $CERTKEYLOC/$APP_FQDN.pem"
  else
    log_error "letsencrypt: certificate request for $APP_FQDN failed"
  fi
  izpbx_do apache2ctl stop
}
