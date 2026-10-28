# Services Management and logs

### Command to restart whole izPBX deploy
`docker compose restart izpbx`

### Command to restart izPBX container only
`docker restart izpbx`

### Command to restart DB container only
`docker restart izpbx-db`

### If you want to restart single services inside `izpbx` container
The services are supervised by s6-overlay; `izpbx-service` controls them and waits until they are up (or down):

```
docker exec -it izpbx izpbx-service restart asterisk
docker exec -it izpbx izpbx-service status httpd
```

Actions: `start`, `stop`, `restart`, `status`. Available services (the enabled ones run):
  - `asterisk` (Asterisk Engine and FreePBX)
  - `httpd` and `php-fpm` (web interface, UCP, `/pb` phonebook)
  - `cron`
  - `fail2ban`
  - `fop2`
  - `dnsmasq` (DHCP and TFTP)
  - `ntp`
  - `postfix`
  - `zabbix` (Zabbix agent 2)

### Logs
`docker compose logs -f izpbx` shows one line per event, the phases separated by a `----` line (a phase with nothing to say has none), a summary at the end of the initialization (time and slowest phases, services, web address, warnings and errors of the start repeated) and a `ready` line when Asterisk answers (Asterisk version, PJSIP endpoints, trunks registered):

```
---- 18 freepbx --------------------------------------------------------
INFO         freepbx: running the FreePBX 17.0.33 installer
OK           freepbx: FreePBX 17.0.33 installed
WARN       migration: ENABLE_ARI was enabled in FreePBX 16 and is '0' now
ERR             fop2: install of the package failed
INFO       migration: custom dialplan converted for Asterisk 22: 6 change(s)
                      - CHANGE extensions_custom.conf:40: MacroExit() => Return()
OUT              ntp: Selected source 172.232.209.103 (2.pool.ntp.org)
```

The first column is the level: `INFO`, `OK` (a step done), `WARN`, `ERR`, `OUT` (output of the programs izPBX runs: Asterisk, FOP2, chrony, php-fpm, Zabbix agent...); `-` lines are details of the line above. Colors highlight warnings and errors: `IZPBX_LOG_COLOR=false` (or `NO_COLOR=1`) turns them off. `IZPBX_LOG_FORMAT=logfmt` or `json` writes one record per line (time, level, component, msg) for log collectors. Find the problems with `docker compose logs --no-log-prefix izpbx | grep -E '^(WARN|ERR) '`; `S6_VERBOSITY=2` adds the start and stop lines of every service.

## STIR/SHAKEN
Asterisk signs outgoing calls (attestation) and verifies the `Identity` header of incoming ones (verification) with `res_stir_shaken` and `res_pjsip_stir_shaken`. It is used by carriers in the US and Canada; FreePBX has no page for it, so it is configured in files. The image ships `/etc/asterisk/stir_shaken.conf` with both services off (`global_disable=yes`).

1. Put the certificates under `/etc/asterisk/keys/` (persistent in `/data/etc/asterisk`), owned by `asterisk`; the private key must be `0600`.
2. Configure `/etc/asterisk/stir_shaken.conf`, for example:
   ```
   [attestation]
   private_key_file=/etc/asterisk/keys/stir_shaken/private.pem
   public_cert_url=https://certs.example.com/shaken.pem
   attest_level=C

   [15551234567]
   type=tn
   attest_level=A

   [verification]
   ca_file=/etc/asterisk/keys/stir_shaken/sti-ca.pem
   failure_action=continue

   [carrier]
   type=profile
   endpoint_behavior=on
   ```
   `endpoint_behavior`: `attest` (outgoing), `verify` (incoming), `on` (both). All the options: [res_stir_shaken](https://docs.asterisk.org/Asterisk_22_Documentation/API_Documentation/Module_Configuration/res_stir_shaken/).
3. Set the profile on the trunk (the PJSIP endpoint has the name of the trunk) in `/etc/asterisk/pjsip.endpoint_custom_post.conf`:
   ```
   [mycarrier](+)
   stir_shaken_profile=carrier
   ```
4. Apply with `fwconsole reload` and check with `asterisk -rx "stir_shaken show eprofiles"`.

In the dialplan (eg. `extensions_custom.conf`) `${STIR_SHAKEN(count)}`, `${STIR_SHAKEN(0,verify_result)}` (`success` or the reason of the failure) and `${STIR_SHAKEN(0,attestation)}` give the result of the verification; `failure_action=reject_request` rejects the calls that fail it.

A `/data` of an earlier release keeps its `stir_shaken.conf` (the Asterisk sample, comments only), and Asterisk logs `Stir/Shaken ... service disabled` at every start and reload: harmless, it goes away once the file is configured, or with the default of the image: `docker exec izpbx cp /etc/asterisk.dist/stir_shaken.conf /etc/asterisk/`. A `/data` created by the first 20.16 releases may also lack the certificate cache, and a `[verification]` does not load without it (`cert_cache_dir ... was not writable`): `docker exec izpbx install -d -o asterisk -g asterisk /var/lib/asterisk/keys/stir_shaken/cache`.
