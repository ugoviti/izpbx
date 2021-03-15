result=0
# Generate SSL Certificates used for HTTPS
if [[ ! -z "$APP_FQDN" && "$LETSENCRYPT_ENABLED" == "true" ]]; then
  echo "--> Let's Encrypt $APP_FQDN"
  if [ -e "/etc/asterisk/keys/$APP_FQDN.pem" ]; then
    echo "----> certificate already exists..."
  else
    echo "----> generating HTTPS certificate"
    httpd -k start
    fwconsole certificates --generate --type=le --hostname=$APP_FQDN --country-code=$LETSENCRYPT_COUNTRY_CODE --state=$LETSENCRYPT_COUNTRY_STATE --email=$ROOT_MAILTO
    result=$?
    if [[ $result -eq 0 ]]; then
      fwconsole certificates --default=$APP_FQDN
      result=$?
    fi
    httpd -k stop
  fi
fi
exit $result