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
