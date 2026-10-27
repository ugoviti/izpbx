#!/usr/bin/env bash
# P4-37: izpbx-dialplan-convert, the custom dialplan of FreePBX 16 made valid
# for Asterisk 22 (found migrating a production PBX: its predial hook used
# Macro/MacroExit and every outbound call would have been hung up).
# - Macro(name,args) -> Gosub(macro-name,s,1(args)), also with nested
#   parentheses in the arguments; MacroExit() -> Return();
# - an extension of a [macro-*] context that ends without Return/Goto/Hangup
#   gets "exten => NAME,n,Return()" right after its last line (also with
#   "same =>" lines); one that ends with Return is left as it is; contexts
#   that are not macro- are not touched;
# - SIPAddHeader(Alert-Info: v) -> Set(__ALERT_INFO=v), other headers ->
#   Set(HASH(__SIPHEADERS,H)=v); MessageSend(sip: -> MessageSend(pjsip:;
#   comments are kept, commented code is not changed;
# - --check changes nothing; the converted file keeps owner and mode, and
#   Asterisk 22 loads it (dialplan show of the converted contexts);
# - negatives: ${MACRO_EXTEN}, Monitor(), SIPDtmfMode() and a SIP/ channel
#   are reported UNCONVERTED with exit 3, MixMonitor() is not.
source "$(dirname "$0")/../lib.sh"
image=izpbx-asterisk:p4-37
work=$(mktemp -d)
t_on_cleanup "t_rmtree '$work'"
assert_cmd "image builds" -- t_build_image "$image"

cat > "$work/extensions_custom.conf" <<'EOF'
[messages]
exten => _X.,1,MessageSend(sip:${EXTEN},"${CALLERID(name)}"${MESSAGE(from)})

[macro-masq]
exten => s,1,Set(CALLERID(num)=${ARG1}) ; keep this comment
exten => s,n,MacroExit()

[macro-dialout-trunk-predial-hook]
exten => s,1,GotoIf($["${CALLERID(dnid)}" = "882"]?masq,1)
exten => s,n,MacroExit()
exten => masq,1,Set(SITE=88888)
exten => masq,n,Macro(masq,${CUT(SITE,-,1)},x)
;exten => masq,n,Macro(commented,1)

[macro-same]
exten => s,1,NoOp(first)
 same => n,Macro(masq,1)

[macro-ends]
exten => s,1,Goto(from-internal,${ARG1},1)

[from-401]
exten => _XXX,1,SIPAddHeader(Alert-Info: citofono)
exten => _XXX,n,SIPAddHeader(X-Custom:value)
include => from-internal

[not-a-macro]
exten => s,1,NoOp(no Return added here)
EOF
cp "$work/extensions_custom.conf" "$work/orig.conf"
conv() { docker run --rm --entrypoint "" -v "$work:/w" -w /w "$image" izpbx-dialplan-convert "$@"; }

out=$(conv --check extensions_custom.conf) && rc=0 || rc=$?
log "check:"; sed 's/^/    | /' <<< "$out" >&2
assert_eq 0 "$rc" "--check: exit 0, everything convertible"
assert_eq 9 "$(grep -c '^CHANGE ' <<< "$out")" "--check: 9 changes listed"
assert_cmd "--check writes nothing" -- cmp -s "$work/orig.conf" "$work/extensions_custom.conf"

docker run --rm --entrypoint "" -v "$work:/w" "$image" sh -c 'chown 1000:1001 /w/extensions_custom.conf && chmod 640 /w/extensions_custom.conf'
conv extensions_custom.conf >/dev/null
f="$work/extensions_custom.conf"
sed 's/^/    | /' "$f" >&2
assert_cmd "MessageSend to pjsip:" -- grep -qF 'exten => _X.,1,MessageSend(pjsip:${EXTEN},"${CALLERID(name)}"${MESSAGE(from)})' "$f"
assert_cmd "MacroExit -> Return, comment kept" -- grep -qF 'exten => s,1,Set(CALLERID(num)=${ARG1}) ; keep this comment' "$f"
assert_eq 3 "$(grep -c "^exten => s,n,Return()$" "$f")" "both MacroExit() are Return() (plus the one added in macro-same)"
assert_cmd "Macro with nested parentheses -> Gosub" -- grep -qF 'exten => masq,n,Gosub(macro-masq,s,1(${CUT(SITE,-,1)},x))' "$f"
assert_cmd "commented Macro untouched" -- grep -qF ';exten => masq,n,Macro(commented,1)' "$f"
assert_eq "exten => masq,n,Gosub(macro-masq,s,1(\${CUT(SITE,-,1)},x))
exten => masq,n,Return()" "$(grep -A1 '^exten => masq,n,Gosub' "$f")" "Return() added right after the last line of an extension ending without it"
assert_eq " same => n,Gosub(macro-masq,s,1(1))
exten => s,n,Return()" "$(grep -A1 'same => n,Gosub' "$f")" "Return() added after a same => line"
assert_eq 0 "$(sed -n '/^\[macro-ends\]/,/^\[/p' "$f" | grep -c 'Return()')" "an extension ending with Goto gets no Return"
assert_eq 0 "$(sed -n '/^\[not-a-macro\]/,$p' "$f" | grep -c 'Return()')" "a context that is not macro- is not touched"
assert_cmd "Alert-Info -> __ALERT_INFO" -- grep -qF 'exten => _XXX,1,Set(__ALERT_INFO=citofono)' "$f"
assert_cmd "other header -> __SIPHEADERS" -- grep -qF 'exten => _XXX,n,Set(HASH(__SIPHEADERS,X-Custom)=value)' "$f"
assert_eq "1000:1001 640" "$(stat -c '%u:%g %a' "$f")" "owner and mode kept"
assert_eq 0 "$(conv extensions_custom.conf | grep -c '^CHANGE ' || true)" "a second run changes nothing"

# Asterisk 22 loads the converted file
c=$(t_run ast "$image" -e IZPBX_ENABLED=false -e ASTERISK_ENABLED=true)
t_wait_for 120 -- docker exec "$c" asterisk -rx 'core show uptime' >/dev/null || die "Asterisk did not start"
docker cp "$f" "$c:/etc/asterisk/extensions.conf" >/dev/null
docker exec "$c" asterisk -rx 'dialplan reload' >/dev/null
show=$(docker exec "$c" asterisk -rx 'dialplan show macro-dialout-trunk-predial-hook')
assert_contains "$show" 'Gosub(macro-masq,s,1(${CUT(SITE,-,1)},x))' "Asterisk loads the converted hook"
assert_contains "$show" "3. Return()" "and its added Return()"

# negatives: what cannot be converted
printf '[x]\nexten => s,1,NoOp(${MACRO_EXTEN})\nexten => s,n,Monitor(wav,foo)\nexten => s,n,SIPDtmfMode(rfc2833)\nexten => s,n,Dial(SIP/trunk/123)\nexten => s,n,MixMonitor(foo.wav)\n' > "$work/bad.conf"
out=$(conv --check bad.conf) && rc=0 || rc=$?
log "negatives:"; sed 's/^/    | /' <<< "$out" >&2
assert_eq 3 "$rc" "negative: exit 3"
assert_eq 4 "$(grep -c '^UNCONVERTED bad.conf:' <<< "$out")" "negative: MACRO_EXTEN, Monitor, SIPDtmfMode, SIP/ reported"
assert_cmd_fails "MixMonitor is not Monitor" -- grep -q 'bad.conf:6:' <<< "$out"
finish
