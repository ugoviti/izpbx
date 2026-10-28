#!/usr/bin/env bash
# P4-40: STIR/SHAKEN (issue #100). res_stir_shaken and res_pjsip_stir_shaken
# are built (bundled libjwt, linked static: no libjwt at runtime).
# - default: the image has build/stir_shaken.conf instead of the Asterisk
#   sample (all comments), both services off: no STIR/SHAKEN WARNING at start
#   nor at a reload (negative: with a file of comments only, as the sample,
#   the two WARNINGs); the certificate cache belongs to asterisk.
# - end to end with two Asterisk of the image on a Docker network: "a"
#   attests its outgoing calls to "b" (EC P-256 key, certificate with a
#   TNAuthList signed by a test CA, served by the HTTP server of "a"), "b"
#   verifies them: STIR_SHAKEN(0,verify_result) = success, attestation A, the
#   certificate in the cache. Negatives: "b" trusting another CA ->
#   cert_not_trusted; an outgoing endpoint without stir_shaken_profile ->
#   missing_identity_hdr.
source "$(dirname "$0")/../lib.sh"

image=izpbx-asterisk:p4-40
cache=/var/lib/asterisk/keys/stir_shaken/cache
assert_cmd "image builds" -- t_build_image "$image"

for m in res_stir_shaken res_pjsip_stir_shaken; do
  assert_cmd "$m.so is installed" -- docker run --rm --entrypoint "" "$image" test -f "/usr/lib64/asterisk/modules/$m.so"
done
assert_cmd_fails "libjwt is linked static (no libjwt.so needed)" -- \
  sh -c "docker run --rm --entrypoint '' '$image' ldd /usr/lib64/asterisk/modules/res_stir_shaken.so | grep -q libjwt"
assert_eq "asterisk asterisk" "$(docker run --rm --entrypoint "" "$image" stat -c '%U %G' "$cache")" \
  "the certificate cache directory belongs to asterisk"

net="$TEST_PROJECT-net"
docker network create --label "izpbx.test=$TEST_PROJECT" "$net" >/dev/null
t_on_cleanup "docker network rm $net >/dev/null 2>&1"

# Asterisk of the image as user asterisk, after an optional shell command
ast() { # name [command] -> container
  t_run "$1" "$image" --network "$net" --network-alias "$1" --entrypoint "" -- \
    bash -c "${2:-:}; exec asterisk -f -U asterisk -G asterisk"
}
up() { t_wait_for 60 -- docker exec "$1" asterisk -rx "core waitfullybooted" || die "Asterisk $1 did not start"; }
cli() { docker exec "$1" asterisk -rx "$2"; }
running() { cli "$1" "module show like $2" | grep -E "^$2\.so " | grep -q ' Running '; }
put() { # container file (content on stdin)
  docker exec -i "$1" sh -c "cat > '$2' && chown asterisk:asterisk '$2'"
}
ss_log() { # container -> STIR/SHAKEN WARNING and ERROR lines, after a reload
  cli "$1" "module reload res_stir_shaken.so" >/dev/null
  sleep 1
  docker exec "$1" sh -c 'grep -hE "(WARNING|ERROR).*res_stir_shaken" /var/log/asterisk/messages*' 2>/dev/null || true
}

## the default
a=$(ast a); up "$a"
assert_cmd "res_stir_shaken is Running" -- running "$a" res_stir_shaken
assert_cmd "res_pjsip_stir_shaken is Running" -- running "$a" res_pjsip_stir_shaken
assert_contains "$(docker exec "$a" cat /etc/asterisk/stir_shaken.conf)" "global_disable=yes" "stir_shaken.conf: the izPBX default"
assert_eq "" "$(ss_log "$a")" "default: no STIR/SHAKEN WARNING at start and reload"
s=$(ast sample "echo '; comments only, as the Asterisk sample' > /etc/asterisk/stir_shaken.conf"); up "$s"
assert_contains "$(ss_log "$s")" "service disabled" "negative: with comments only, as the Asterisk sample, the WARNINGs"
docker rm -f "$s" >/dev/null

## certificates: a test STI-CA, the SP certificate with TNAuthList (SPC 1234),
## a second CA that signed nothing
docker exec "$a" sh -ec '
  d=/etc/asterisk/keys/ss; mkdir -p $d; cd $d
  for ca in ca other; do
    openssl ecparam -name prime256v1 -genkey -noout -out $ca.key
    openssl req -x509 -new -key $ca.key -sha256 -days 30 -subj "/CN=izPBX test STI-CA $ca" \
      -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign -out $ca.pem
  done
  openssl ecparam -name prime256v1 -genkey -noout -out priv.pem
  openssl req -new -key priv.pem -subj "/CN=SHAKEN 1234" -out sp.csr
  printf "basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\n1.3.6.1.5.5.7.1.26=DER:30:08:A0:06:16:04:31:32:33:34\n" > ext.cnf
  openssl x509 -req -in sp.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 30 -sha256 -extfile ext.cnf -out cert.pem 2>/dev/null
  cp cert.pem /var/lib/asterisk/static-http/cert.pem
  chown -R asterisk:asterisk $d /var/lib/asterisk/static-http/cert.pem; chmod 600 priv.pem' || die "certificates not generated"
assert_contains "$(docker exec "$a" openssl x509 -in /etc/asterisk/keys/ss/cert.pem -noout -text)" "1.3.6.1.5.5.7.1.26" \
  "the SP certificate has the TNAuthList extension"

## a: attests the calls to b, serves its certificate on http://a:8088/static/
put "$a" /etc/asterisk/http.conf <<'EOF'
[general]
enabled=yes
bindaddr=0.0.0.0
bindport=8088
enablestatic=yes
EOF
put "$a" /etc/asterisk/stir_shaken.conf <<'EOF'
[attestation]
private_key_file=/etc/asterisk/keys/ss/priv.pem
public_cert_url=http://a:8088/static/cert.pem
attest_level=A

[15551234567]
type=tn

[out]
type=profile
endpoint_behavior=attest
EOF
put "$a" /etc/asterisk/pjsip.conf <<'EOF'
[udp]
type=transport
protocol=udp
bind=0.0.0.0:5060

[b]
type=endpoint
context=from-b
disallow=all
allow=ulaw
aors=b
stir_shaken_profile=out

[b]
type=aor
contact=sip:b:5060

[plain]
type=endpoint
context=from-b
disallow=all
allow=ulaw
aors=plain

[plain]
type=aor
contact=sip:b:5060
EOF
# originate Local/<number>@out-<endpoint>: the caller id of the attestation
put "$a" /etc/asterisk/extensions.conf <<'EOF'
[out-b]
exten => _X.,1,Set(CALLERID(all)=Test <15551234567>)
 same => n,Dial(PJSIP/${EXTEN}@b,5)

[out-plain]
exten => _X.,1,Set(CALLERID(all)=Test <15551234567>)
 same => n,Dial(PJSIP/${EXTEN}@plain,5)

[from-b]
EOF

## b: verifies the calls of a
b=$(ast b); up "$b"
docker exec "$a" cat /etc/asterisk/keys/ss/ca.pem | put "$b" /etc/asterisk/ca.pem
docker exec "$a" cat /etc/asterisk/keys/ss/other.pem | put "$b" /etc/asterisk/other.pem
verifier() { # ca_file
  put "$b" /etc/asterisk/stir_shaken.conf <<EOF
[verification]
ca_file=$1
failure_action=continue
; test only: plain HTTP on port 8088 and the private addresses of the Docker network
relax_x5u_port_scheme_restrictions=yes
x5u_permit=0.0.0.0/0.0.0.0

[in]
type=profile
endpoint_behavior=verify
EOF
}
verifier /etc/asterisk/ca.pem
put "$b" /etc/asterisk/pjsip.conf <<'EOF'
[udp]
type=transport
protocol=udp
bind=0.0.0.0:5060

[a]
type=endpoint
context=from-a
disallow=all
allow=ulaw
stir_shaken_profile=in

[a]
type=identify
endpoint=a
match=a
EOF
# the result of every call in the astdb of b: family ss, key = dialed number
put "$b" /etc/asterisk/extensions.conf <<'EOF'
[from-a]
exten => _X.,1,Set(N=${STIR_SHAKEN(count)})
 same => n,GotoIf($[${N} > 0]?result)
 same => n,Set(DB(ss/${EXTEN})=0||)
 same => n,Hangup()
 same => n(result),Set(DB(ss/${EXTEN})=${N}|${STIR_SHAKEN(0,verify_result)}|${STIR_SHAKEN(0,attestation)})
 same => n,Hangup()
EOF
# restart: Asterisk reads the new configuration
docker restart "$a" "$b" >/dev/null
up "$a"; up "$b"
assert_contains "$(cli "$a" "stir_shaken show tn 15551234567")" "15551234567" "a: the TN is loaded"
assert_contains "$(cli "$b" "stir_shaken show verification")" "/etc/asterisk/ca.pem" "b: the verification uses the test CA"

call() { # endpoint number -> result stored by b
  cli "$b" "database del ss $2" >/dev/null 2>&1 || true
  cli "$a" "channel originate Local/$2@out-$1 application Wait 1" >/dev/null
  t_wait_for 20 -- sh -c "docker exec '$b' asterisk -rx 'database get ss $2' | grep -q '^Value:'" || true
  cli "$b" "database get ss $2" | sed -n 's/^Value: //p'
}
res=$(call b 100)
log "call with attestation: $res"
assert_eq "1|success|A" "$res" "b verifies the call of a: success, attestation A"
assert_cmd "the certificate is in the cache of b" -- docker exec "$b" sh -c "ls $cache/*.pem"

# negative: b trusts another CA (cache emptied, so the certificate is checked again)
verifier /etc/asterisk/other.pem
cli "$b" "database deltree STIR_SHAKEN" >/dev/null 2>&1 || true
docker exec "$b" find "$cache" -type f -delete
cli "$b" "module reload res_stir_shaken.so" >/dev/null
res=$(call b 101)
log "call with an untrusted certificate: $res"
# a failed verification carries no attestation level
assert_eq "1|cert_not_trusted|" "$res" "negative: a certificate of another CA is not trusted"

# negative: no stir_shaken_profile on the outgoing endpoint, no Identity header
res=$(call plain 102)
log "call without profile: $res"
assert_eq "1|missing_identity_hdr|" "$res" "negative: without stir_shaken_profile on a, b finds no Identity header"

finish
