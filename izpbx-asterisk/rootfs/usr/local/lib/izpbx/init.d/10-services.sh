# shellcheck shell=bash
# izpbx-init step: which services run (the s6 run scripts apply the same
# rules through service.sh) and which program is /usr/sbin/sendmail:
# msmtp when MSMTP_ENABLED, Postfix's (diverted to sendmail.postfix at build)
# otherwise. POSTFIX_ENABLED=true turns msmtp off (20.16 rule).
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh

enabled=()
for svc in "${!SERVICE_VARS[@]}"; do service_is_enabled "$svc" && enabled+=("$svc"); done
log_info "services enabled: $(printf '%s\n' "${enabled[@]}" | sort | tr '\n' ' ')"

if [ "$MSMTP_ENABLED" == "true" ]; then
  ln -sfn /usr/bin/msmtp /usr/sbin/sendmail
  log_info "sendmail: msmtp"
else
  ln -sfn /usr/sbin/sendmail.postfix /usr/sbin/sendmail
  log_info "sendmail: postfix$([ "$POSTFIX_ENABLED" == "true" ] && echo " (POSTFIX_ENABLED=true turns msmtp off)")"
fi
