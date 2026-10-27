# shellcheck shell=bash
# izpbx-init step: which services run (the s6 run scripts apply the same
# rules through service.sh) and which program is /usr/sbin/sendmail:
# msmtp when MSMTP_ENABLED, Postfix's (diverted to sendmail.postfix at build)
# otherwise. POSTFIX_ENABLED=true turns msmtp off (20.16 rule). /usr/bin/mailq
# follows: Postfix's through sendmail, or with msmtp, which has no queue,
# an empty queue (P3-35: the FreePBX dashboard runs mailq).
# shellcheck source=../service.sh
. /usr/local/lib/izpbx/service.sh

enabled=()
for svc in "${!SERVICE_VARS[@]}"; do service_is_enabled "$svc" && enabled+=("$svc"); done
log_info "services: enabled: $(printf '%s\n' "${enabled[@]}" | sort | paste -sd ' ')"

if [ "$MSMTP_ENABLED" == "true" ]; then
  ln -sfn /usr/bin/msmtp /usr/sbin/sendmail
  ln -sfn /usr/local/share/izpbx/msmtp-mailq /usr/bin/mailq
  log_info "sendmail: via msmtp (no local queue)"
else
  ln -sfn /usr/sbin/sendmail.postfix /usr/sbin/sendmail
  ln -sfn ../sbin/sendmail /usr/bin/mailq
  log_info "sendmail: via postfix$([ "$POSTFIX_ENABLED" == "true" ] && echo " (POSTFIX_ENABLED=true turns msmtp off)")"
fi
