# izPBX environment contract (20.16.22)

This is the behaviour of every environment variable read by the izPBX
**20.16.22** container, taken from `izpbx-asterisk/rootfs/entrypoint-hooks.sh`
and `izpbx-asterisk/rootfs/entrypoint.sh` at tag `20.16.22`, plus the
variables declared in that release's `Dockerfile` (`ENV`) and `default.env`.

The 22.17 entrypoint must keep this contract. Every intended difference is
listed in §13 of the design (`.specs/2026-10-23-release-22.17.0-freepbx17.md`)
and in the release notes. `tests/checks/P0-06.sh` checks that no variable read
by the old entrypoint is missing here.

How to read the tables:

- **Default**: the value used when the variable is unset. Unless noted,
  defaults come from `: ${VAR:=default}`, so an **empty** value behaves like an
  unset one and gets the default too. "image" means a Dockerfile `ENV`.
- **Effect**: the file, key or command the variable changes. Paths are inside
  the container. With `APP_DATA=/data`, `/etc/asterisk`, `/var/lib/asterisk`,
  `/var/spool/asterisk`, `/var/www`, `/etc/freepbx.conf` and the other
  persistent paths are symlinks into `/data`.
- **If empty**: what happens with an empty or unset value.
- Boolean variables only react to the exact string `true`. Any other value
  (`yes`, `1`, `TRUE`) counts as false.

## 1. Image and build metadata

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `APP_NAME` | image: `izpbx-asterisk` | Shown in the startup banner (`entrypoint.sh`). | `unknown` in the banner. |
| `APP_DESCRIPTION` | image: `izPBX Cloud Native Telephony System` | Startup banner. | `izPBX Cloud Telephony System` (hooks) / `unknown` (entrypoint). |
| `APP_VER` | image: build arg (`dev` locally) | Startup banner and `/root/.bashrc` banner. | `latest` (entrypoint) / `unknown` (bashrc). |
| `APP_VER_BUILD` | image: build arg | Banners. | `unknown`. |
| `APP_BUILD_COMMIT` | image: build arg | Banners. | `unknown`. |
| `APP_BUILD_DATE` | image: build arg (epoch) | Banners, converted to `YYYY-MM-DD`. | `unknown`. |
| `APP_CHART` | empty | Not used (Helm metadata placeholder). | No effect. |
| `APP_RELEASE` | empty | Not used (Helm metadata placeholder). | No effect. |
| `APP_NAMESPACE` | empty | Not used (Helm metadata placeholder). | No effect. |
| `ASTERISK_VER` | image: build arg (`20.21.0`) | `/root/.bashrc` banner. | `unknown` in the banner. |
| `FREEPBX_VER` | image: build arg (`16`) | Major FreePBX version available in the image; compared with the installed one to offer the major upgrade (§9). Not a FreePBX Advanced Setting (skipped by the `FREEPBX_*` loop). | Upgrade check skipped with a warning. |
| `APP_UID` | image: `1000` | UID of `APP_USR`, fixed at build time. | Build time only. |
| `APP_GID` | image: `1000` | GID of `APP_GRP`, fixed at build time. | Build time only. |
| `APP_USR` | image: `asterisk` | Owner of FreePBX/Asterisk files, `User` in `httpd.conf`, user for `fwconsole` and `runuser`. | Commands run as an empty user and fail. |
| `APP_GRP` | image: `asterisk` | Group of FreePBX/Asterisk files, `Group` in `httpd.conf`, group of `/etc/msmtprc`. | `chown` and `httpd.conf` broken; msmtp falls back to `asterisk`. |
| `FOP2_VER` | image: build arg (`2.31.53`) | FOP2 version downloaded on first install and target of `FOP2_AUTOUPGRADE`. | FOP2 install refused with an error. |
| `FOP2_SHA256` | image: sha256 of the FOP2 package | Checksum required before installing the FOP2 package. | FOP2 install refused with a warning. |
| `ZABBIX_VER` | image: `7.0` | Build time only (Zabbix repository). | Build time only. |
| `ZABBIX_REL` | image: `${ZABBIX_VER}-1` | Build time only. | Build time only. |

## 2. Paths, persistence and hooks

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `APP_DATA` | empty (`default.env`: `/data`) | Base of persistent storage. Each persistent directory (`/var/spool/cron`, `/home/asterisk`, `/etc/asterisk`, `/var/lib/asterisk`, `/var/spool/asterisk`, `/var/www`, `/var/log/httpd`, `/var/log/asterisk`, `/var/log/fail2ban`, `/var/lib/fail2ban`, `/usr/local/fop2`, `/root`, `/etc/dnsmasq.d`, `/var/lib/dnsmasq`, `/var/lib/tftpboot`) is moved to `<dir>.dist` and symlinked to `${APP_DATA}<dir>`; empty targets are seeded from `.dist`. `/etc/freepbx.conf` and `/etc/amportal.conf` are symlinked too. FreePBX paths in the DB (`AMPWEBROOT`, `ASTETCDIR`, …) are rebased on `APP_DATA`. `${APP_DATA}/.initialized` marks a completed install. | No persistence: warning, data lost on restart; FreePBX path settings are not rewritten. |
| `APP_CONF` | empty | Declared, not used. | No effect. |
| `APP_LOGS` | empty | Declared, not used. | No effect. |
| `APP_TEMP` | empty | Declared, not used. | No effect. |
| `APP_CUSTOM_SCRIPTS` | empty | Directory of user hooks: `pre-init/*.custom-inc` and `post-init/*.custom-inc` are sourced before and after the startup configuration. | Hooks disabled ("Custom Script Hooks: OFF"). |
| `UMASK` | empty | `umask` set right before `exec` of the main command (`entrypoint.sh`). | Default umask. |

## 3. System: timezone, hostname

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `TZ` | image: `UTC` | Validated (relative zoneinfo name, file must exist); `/etc/localtime`, `/etc/timezone`, `/etc/php.d/99-timezone.ini` (`date.timezone`). | `UTC`. An invalid value falls back to `UTC` with a warning. |
| `APP_FQDN` | image: empty | Kernel hostname and `HOSTNAME`; extra Apache vhost `ServerName`; self-signed cert CN; Let's Encrypt hostname; phonebook address; exported to `/etc/izpbx/cron.env`. | No FQDN vhost; cert CN `izpbx`; Let's Encrypt skipped with a warning. |
| `SERVERNAME` | `$HOSTNAME` | Apache `ServerName` in `httpd.conf`. | Hostname. |

## 4. Database

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `MYSQL_SERVER` | `db` (`default.env`: `127.0.0.1`) | DB host for install, `AMPDBHOST` in `/etc/freepbx.conf` (rewritten every start), `/etc/odbc.ini` `server`, phpMyAdmin host. | `db`. |
| `APP_PORT_MYSQL` | `3306` | DB port: install, `AMPDBPORT`, `/etc/odbc.ini` `Port`. Also the published port of the `db` service in `compose.yml`. | `3306`. |
| `MYSQL_DATABASE` | `asterisk` | Config DB: created on install, `AMPDBNAME`. | `asterisk`. |
| `MYSQL_DATABASE_CDR` | `asteriskcdrdb` | CDR DB: created on install, `--cdrdbname`, `/etc/odbc.ini` `database`, FreePBX setting `CDRDBNAME` (fixed every start). | `asteriskcdrdb`. |
| `MYSQL_USER` | `asterisk` | DB user created on install (`CREATE USER … '%'`, `GRANT ALL` on both DBs), `AMPDBUSER`. | `asterisk`. |
| `MYSQL_PASSWORD` | empty | Password of `MYSQL_USER`: install, `AMPDBPASS` (rewritten every start). A single quote or backslash aborts the first install. | Empty password. |
| `MYSQL_ROOT_USER` | `root` | Admin user used only on the first install. | `root`. |
| `MYSQL_ROOT_PASSWORD` | empty | Admin password for the first install (creates user and DBs). | DB creation skipped: `MYSQL_USER`/`MYSQL_PASSWORD` are used and the DBs must already exist with the grants. |
| `IZPBX_MYSQL_PASSWORD_FILE` | empty | File read into `MYSQL_PASSWORD` if that is empty (Docker secrets). | Not used. |
| `IZPBX_MYSQL_ROOT_PASSWORD_FILE` | empty | File read into `MYSQL_ROOT_PASSWORD` if that is empty. | Not used. |
| `MYSQL_RANDOM_ROOT_PASSWORD` | empty | Only in `default.env`, for the MariaDB container. Not read by izPBX. | No effect on izPBX. |
| `MYSQL_ALLOW_EMPTY_ROOT_PASSWORD` | empty | Only in `default.env`, for the MariaDB container. Not read by izPBX. | No effect on izPBX. |

## 5. Services (supervisord)

Each `<NAME>_ENABLED` sets `autostart=` in `${SUPERVISOR_DIR}/<name>.ini` and,
when `true`, runs the service configuration described in the next sections.

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `IZPBX_ENABLED` | `true` | FreePBX + Asterisk (`izpbx.ini`): ODBC, install/upgrade, Advanced Settings, SIP settings. | `true`. |
| `ASTERISK_ENABLED` | `false` | Plain Asterisk without FreePBX (`asterisk.ini`). | `false`. |
| `HTTPD_ENABLED` | `true` | Apache (`httpd.ini`) and its configuration (§6). | `true`. |
| `CRON_ENABLED` | `true` | crond; fixes owner/permissions of `/var/spool/cron` (root 700). | `true`. |
| `FAIL2BAN_ENABLED` | `true` | fail2ban (§8). | `true`. |
| `MSMTP_ENABLED` | `true` | msmtp as sendmail (§7). Forced to `false` when `POSTFIX_ENABLED=true`. | `true`. |
| `POSTFIX_ENABLED` | `false` | Postfix (§7), overrides msmtp. | `false`. |
| `DNSMASQ_ENABLED` | `false` | dnsmasq. Forced to `true` when `DHCP_ENABLED` or `TFTP_ENABLED` is `true`. | `false`. |
| `DHCP_ENABLED` | `false` | DHCP in dnsmasq (§10). | `false`. |
| `TFTP_ENABLED` | `false` | TFTP in dnsmasq (§10). | `false`. |
| `NTP_ENABLED` | `false` | chronyd (§11). | `false`. |
| `ZABBIX_ENABLED` | `false` | Zabbix agent 2 (§12). | `false`. |
| `FOP2_ENABLED` | `false` | FOP2 (§13). | `false`. |
| `PMA_ENABLED` | `false` | phpMyAdmin Apache config (§6). | `false`: config disabled (renamed `-disabled`). |
| `PHONEBOOK_ENABLED` | `true` | `/pb` remote XML phonebook (§6). | `true`. |

## 6. Web server, HTTPS, phpMyAdmin, phonebook

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `APP_PORT_HTTP` | image: `80` | `Listen` in `httpd.conf`, port of the vhosts in `conf.d/virtual.conf`. | Broken `Listen`. |
| `APP_PORT_HTTPS` | image: `443` | `Listen … https` and SSL vhost port in `virtual.conf`. | Broken HTTPS config (only with HTTPS enabled). |
| `HTTPD_ALLOW_FROM` | empty | `Require ip …` (space separated) in every vhost `<Directory>` and in `/pb`. | `Require all granted`. |
| `HTTPD_REDIRECT_HTTP_TO_HTTPS` | `false` | `mod_rewrite` redirect to HTTPS (except ACME challenges) in the HTTP vhosts. | No redirect. |
| `HTTPD_HTTPS_ENABLED` | `false` | Adds `Listen ${APP_PORT_HTTPS} https` and an SSL vhost to `virtual.conf`; creates a 10-year self-signed cert if the files are missing or the CN is `izpbx` while `APP_FQDN` is set; FOP2 SSL paths; phonebook URL scheme; exported to `cron.env`. | HTTP only. |
| `HTTPD_HTTPS_CERT_FILE` | `/etc/asterisk/keys/default.crt` | `SSLCertificateFile` of the default SSL vhost, `ssl_certificate_file` in `fop2.cfg`. | Default path. |
| `HTTPD_HTTPS_KEY_FILE` | `/etc/asterisk/keys/default.key` | `SSLCertificateKeyFile`, `ssl_certificate_key_file` in `fop2.cfg`. | Default path. |
| `HTTPD_HTTPS_CHAIN_FILE` | empty | `SSLCertificateChainFile` of the default SSL vhost. | Directive omitted. |
| `LETSENCRYPT_ENABLED` | empty | With `HTTPD_HTTPS_ENABLED=true` and `APP_FQDN`: `fwconsole certificates --generate --type=le` (or `--updateall` if the cert exists), sets it as FreePBX default, SSL vhost uses `/etc/asterisk/keys/integration/*`; exported to `cron.env` for the daily renewal. | Self-signed / provided certificate. |
| `LETSENCRYPT_COUNTRY_CODE` | empty | `--country-code` of the certificate request. | Request skipped with a warning. |
| `LETSENCRYPT_COUNTRY_STATE` | empty | `--state` of the certificate request. | Request skipped with a warning. |
| `LETSENCRYPT_EMAIL` | `$SMTP_MAIL_TO` | `--email` of the certificate request. | `SMTP_MAIL_TO`; if that is empty too, request skipped. |
| `PMA_ALIAS` | `/admin/pma` | `Alias` in `phpMyAdmin_izpbx.conf`. | `/admin/pma`. |
| `PMA_ALLOW_FROM` | `127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16` | `Require ip …` in `phpMyAdmin_izpbx.conf`. | Default private networks. |
| `PMA_CONFIG` | `/etc/phpMyAdmin/config.inc.php` | phpMyAdmin config where `'localhost'` is replaced with `MYSQL_SERVER`. | Default path. |
| `PHONEBOOK_ADDRESS` | `http(s)://${APP_FQDN}` or `http(s)://<first IP>` | Base URL used by the phonebook `menu.xml`. | Computed as in Default. |
| `APP_PORT_AMI` | image: `8088` | Default of `FREEPBX_HTTPBINDPORT` (Asterisk HTTP/ARI port). | `FREEPBX_HTTPBINDPORT` empty: not applied. |

## 7. Mail: msmtp, Postfix, root alias

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `SMTP_MAIL_FROM` | `izpbx@localhost.localdomain` | msmtp `from`; Postfix `sender_canonical_maps` and `header_checks` (rewrite From); default of `FAIL2BAN_DEFAULT_SENDER`. | Default address. |
| `SMTP_MAIL_TO` | `$ROOT_MAILTO`, then `root@localhost.localdomain` | `root:` alias in `/etc/aliases` (Postfix); default of `LETSENCRYPT_EMAIL` and `FAIL2BAN_DEFAULT_DESTEMAIL`. | `ROOT_MAILTO`, then default address. |
| `ROOT_MAILTO` | `$SMTP_MAIL_TO` | Legacy name of `SMTP_MAIL_TO`. | Follows `SMTP_MAIL_TO`. |
| `SMTP_RELAYHOST` | empty | msmtp `host`; Postfix `relayhost=[host]:port` (via `RELAYHOST`). | msmtp has no host; Postfix delivers directly (warning about DNS). |
| `SMTP_RELAYHOST_PORT` | empty (Postfix: `25`) | msmtp `port`; Postfix relay port (via `RELAYHOST_PORT`). | msmtp default port; Postfix `25`. |
| `SMTP_RELAYHOST_USERNAME` | empty | msmtp `auth on` + `user`; Postfix SASL (`/etc/postfix/sasl_passwd`, 600 root) when the password is set too. | No authentication. |
| `SMTP_RELAYHOST_PASSWORD` | empty | msmtp `password` (`/etc/msmtprc` 640 root:asterisk); Postfix SASL password. | No password. |
| `SMTP_STARTTLS` | `true` | msmtp `tls`/`tls_starttls on` with CA bundle; Postfix `smtp_use_tls=yes`. | `true`. Any other value: TLS off in msmtp, unchanged in Postfix. |
| `SMTP_ALLOWED_SENDER_DOMAINS` | empty | Postfix `allowed_senders` map and restriction class (via `ALLOWED_SENDER_DOMAINS`). | No sender restriction. |
| `SMTP_MESSAGE_SIZE_LIMIT` | `0` | Postfix `message_size_limit` (via `MESSAGE_SIZE_LIMIT`). | `0` (unlimited). |
| `SMTP_MYNETWORKS` | empty | Postfix `mynetworks`. | `127.0.0.0/8` (no open relay). |
| `RELAYHOST` | `$SMTP_RELAYHOST` | Postfix relay host (alias kept for old setups). | Follows `SMTP_RELAYHOST`. |
| `RELAYHOST_PORT` | `$SMTP_RELAYHOST_PORT`, then `25` | Postfix relay port. | `25`. |
| `RELAYHOST_USERNAME` | `$SMTP_RELAYHOST_USERNAME` | Postfix SASL user. | Follows `SMTP_RELAYHOST_USERNAME`. |
| `RELAYHOST_PASSWORD` | `$SMTP_RELAYHOST_PASSWORD` | Postfix SASL password. | Follows `SMTP_RELAYHOST_PASSWORD`. |
| `ALLOWED_SENDER_DOMAINS` | `$SMTP_ALLOWED_SENDER_DOMAINS` | Postfix allowed senders. | Follows `SMTP_ALLOWED_SENDER_DOMAINS`. |
| `MESSAGE_SIZE_LIMIT` | `$SMTP_MESSAGE_SIZE_LIMIT` | Postfix `message_size_limit`. | Follows `SMTP_MESSAGE_SIZE_LIMIT`. |

## 8. fail2ban

`FAIL2BAN_<SECTION>_<KEY>=<value>` (any variable with this prefix) sets
`<key>=<value>` in section `[<section>]` of `/etc/fail2ban/jail.d/99-local.conf`
(case-insensitive match, commented keys are re-enabled). Values have single
quotes removed. `DEFAULT LOGTARGET` in `/etc/fail2ban/fail2ban.conf` is always
set to `/var/log/fail2ban/fail2ban.log`. Keys that are not in the file are
ignored.

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `FAIL2BAN_DEFAULT_SENDER` | `$SMTP_MAIL_FROM` | `[DEFAULT] sender`. | `SMTP_MAIL_FROM`. |
| `FAIL2BAN_DEFAULT_DESTEMAIL` | `$SMTP_MAIL_TO` | `[DEFAULT] destemail`. | `SMTP_MAIL_TO`. |
| `FAIL2BAN_DEFAULT_BANACTION` | file default (`default.env` example: `iptables-allports[blocktype=DROP]`) | `[DEFAULT] banaction`. | Key written empty if the variable is set but empty; file value if unset. |
| `FAIL2BAN_DEFAULT_IGNOREIP` | file default (`default.env`: private networks) | `[DEFAULT] ignoreip`. | As above. |
| `FAIL2BAN_DEFAULT_BANTIME` | file default (`default.env`: `300`) | `[DEFAULT] bantime`. | As above. |
| `FAIL2BAN_DEFAULT_FINDTIME` | file default (`default.env`: `3600`) | `[DEFAULT] findtime`. | As above. |
| `FAIL2BAN_DEFAULT_MAXRETRY` | file default (`default.env`: `10`) | `[DEFAULT] maxretry`. | As above. |
| `FAIL2BAN_ASTERISK_ENABLED` | file default (`default.env`: `true`) | `[ASTERISK] enabled`. | As above. |
| `FAIL2BAN_ASTERISK_LOGPATH` | file default (`/var/log/asterisk/security`) | `[ASTERISK] logpath`. | As above. |
| `FAIL2BAN_RECIDIVE_ENABLED` | file default (`default.env`: `true`) | `[RECIDIVE] enabled`. | As above. |
| `FAIL2BAN_RECIDIVE_BANTIME` | file default (`default.env`: `1814400`) | `[RECIDIVE] bantime`. | As above. |
| `FAIL2BAN_RECIDIVE_FINDTIME` | file default (`default.env`: `15552000`) | `[RECIDIVE] findtime`. | As above. |
| `FAIL2BAN_RECIDIVE_MAXRETRY` | file default (`default.env`: `10`) | `[RECIDIVE] maxretry`. | As above. |

`FAIL2BAN_ENABLED` (§5) also matches the prefix: it becomes a line with
section `ENABLED` and no key, which matches nothing.

## 9. FreePBX

### Install, modules, upgrades

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `FREEPBX_MODULES_CORE` | `framework core dashboard sipsettings voicemail` | Declared on first install, not used by the install loop (installed by the FreePBX installer). | No effect. |
| `FREEPBX_MODULES_PRE` | `userman pm2` | Modules installed first, from the local repo, on the first install. | Defaults (empty = default, `:=`). |
| `FREEPBX_MODULES_EXTRA` | 40 modules (soundlang … ucp, see `entrypoint-hooks.sh`) | Modules installed after `PRE`, from the local repo, on the first install. | Defaults. |
| `FREEPBX_MODULES_DISABLED` | empty | Declared, not used. | No effect. |
| `FREEPBX_AUTOUPDATE_MODULES_FIRSTDEPLOY` | empty | `fwconsole ma upgradeall` at the end of the first install. | No module upgrade. |
| `FREEPBX_AUTOUPGRADE_CORE` | empty (`default.env`: `true`) | When the installed FreePBX major is exactly one below `FREEPBX_VER`: `fwconsole versionupgrade` on start. | Upgrade only reported. |
| `FREEPBX_AUTOUPGRADE_MODULES` | empty (`default.env`: `true`) | **Not read** by the 20.16.22 entrypoint (skipped by the `FREEPBX_AUTOUPGRADE_*` filter). | No effect. |
| `FREEPBX_FIX_PERMISSION` | `true` (`default.env`: `false`) | `fwconsole chown` on every start. | `true`. |
| `FREEPBX_VER_INSTALLED` | computed | Major FreePBX version found on the volume (`fwconsole -V`, else `admin.version` in the DB). Internal, but a `FREEPBX_VER*` name: skipped by the Advanced Settings loop. | Computed. |

### Advanced Settings (`FREEPBX_<KEY>`)

Every other variable whose name starts with `FREEPBX_` is a FreePBX Advanced
Setting: on every start, `fwconsole setting <KEY> <value>` runs when the
current value differs (`true`/`false` are compared as `1`/`0`). Empty values
are never applied. Names excluded from this loop: `FREEPBX_MODULES_*`,
`FREEPBX_AUTOUPGRADE_*`, `FREEPBX_AUTOUPDATE_MODULES_FIRSTDEPLOY`,
`FREEPBX_FIX_PERMISSION*`, `FREEPBX_VER*`.

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `FREEPBX_HTTPBINDPORT` | `$APP_PORT_AMI` | `HTTPBINDPORT` (Asterisk built-in HTTP server port). | Not applied. |
| `FREEPBX_FREEPBX_SYSTEM_IDENT` | unset (`default.env`: `izPBX`) | `FREEPBX_SYSTEM_IDENT`. | Not applied. |
| `FREEPBX_AS_DISPLAY_READONLY_SETTINGS` | unset (`default.env`: `1`) | `AS_DISPLAY_READONLY_SETTINGS`. | Not applied. |
| `FREEPBX_AS_OVERRIDE_READONLY` | unset (`default.env`: `1`) | `AS_OVERRIDE_READONLY`. | Not applied. |
| `FREEPBX_ENABLECW` | unset (`default.env`: `0`) | `ENABLECW` (call waiting default for new extensions). | Not applied. |
| `FREEPBX_TONEZONE` | unset (`default.env`: `it`) | `TONEZONE`. | Not applied. |
| `FREEPBX_PHPTIMEZONE` | unset (`default.env`: `Europe/Rome`) | `PHPTIMEZONE`. | Not applied. |
| `FREEPBX_BRAND_IMAGE_TANGO_LEFT` | unset | `BRAND_IMAGE_TANGO_LEFT`. | Not applied. |
| `FREEPBX_BRAND_IMAGE_FREEPBX_FOOT` | unset | `BRAND_IMAGE_FREEPBX_FOOT`. | Not applied. |
| `FREEPBX_BRAND_IMAGE_SPONSOR_FOOT` | unset | `BRAND_IMAGE_SPONSOR_FOOT`. | Not applied. |
| `FREEPBX_BRAND_FREEPBX_ALT_LEFT` | unset | `BRAND_FREEPBX_ALT_LEFT`. | Not applied. |
| `FREEPBX_BRAND_FREEPBX_ALT_FOOT` | unset | `BRAND_FREEPBX_ALT_FOOT`. | Not applied. |
| `FREEPBX_BRAND_SPONSOR_ALT_FOOT` | unset | `BRAND_SPONSOR_ALT_FOOT`. | Not applied. |
| `FREEPBX_BRAND_IMAGE_FREEPBX_LINK_LEFT` | unset | `BRAND_IMAGE_FREEPBX_LINK_LEFT`. | Not applied. |
| `FREEPBX_BRAND_IMAGE_FREEPBX_LINK_FOOT` | unset | `BRAND_IMAGE_FREEPBX_LINK_FOOT`. | Not applied. |
| `FREEPBX_BRAND_IMAGE_SPONSOR_LINK_FOOT` | unset | `BRAND_IMAGE_SPONSOR_LINK_FOOT`. | Not applied. |
| `FREEPBX_RSSFEEDS` | unset | `RSSFEEDS`. | Not applied (so it cannot be cleared from the environment). |
| `FREEPBX_SIGNATURECHECK` | unset | `SIGNATURECHECK`. | Not applied. |

### SIP settings and ports

Applied on every start through `sipsettings->setConfig()` when the current
value differs.

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `APP_PORT_PJSIP` | image: `5060` | `udpport-0.0.0.0` and `tcpport-0.0.0.0` (PJSIP transports). | Broken PHP call (`setConfig('k',)`), setting not changed. |
| `APP_PORT_SIP` | image: `5160` | `bindport` (chan_sip). | As above. |
| `APP_PORT_RTP_START` | image: `10000` | `rtpstart`. | As above. |
| `APP_PORT_RTP_END` | image: `10200` (`default.env`: `20000`) | `rtpend`. | As above. |
| `APP_PORT_IAX` | image: `4569` | Not applied (IAX settings code is disabled); published port only. | No effect. |
| `APP_PORT_WEBRTC` | image: `8089` | Published port only (`compose.yml`). | No effect. |
| `APP_PORT_UCP_HTTP` | image: `8001` | Published port only. | No effect. |
| `APP_PORT_UCP_HTTPS` | image: `8003` | Published port only. | No effect. |
| `APP_PORT_DHCP` | image: `67` | Published port only. | No effect. |
| `APP_PORT_TFTP` | image: `69` | Published port only. | No effect. |
| `APP_PORT_NTP` | image: `123` | Published port only. | No effect. |
| `APP_PORT_FOP2` | image: `4445` | Published port only. | No effect. |
| `APP_PORT_ZABBIX` | image: `10050` | Published port only. | No effect. |
| `HEP_ENABLED` | empty | `enabled = yes/no` in `/etc/asterisk/hep.conf` (Homer capture), only if the variable is set and the file exists. | `hep.conf` untouched. |

## 10. DHCP and TFTP (dnsmasq)

All keys are edited in `/etc/dnsmasq.d/local.conf` (persistent).

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `DHCP_POOL_START` | empty | First address of `dhcp-range`. | With `DHCP_ENABLED=true`: warning, range not set. |
| `DHCP_POOL_END` | empty | Last address of `dhcp-range`. | As above. |
| `DHCP_POOL_LEASE` | `72h` (inline `:-`) | Lease time in `dhcp-range`. | `72h`. |
| `DHCP_DOMAIN` | empty | `local=/<domain>/`, `domain=`, `dhcp-option=option:domain-name`. | Unchanged. |
| `DHCP_DNS` | empty | `dhcp-option=6`. | Unchanged. |
| `DHCP_GW` | empty | `dhcp-option=3`. | Unchanged. |
| `DHCP_NTP` | empty | `dhcp-option=option:ntp-server` (only if still commented). | Unchanged. |

`TFTP_ENABLED=true` enables `dhcp-option=66`, `enable-tftp` and
`tftp-root=/var/lib/tftpboot`.

## 11. NTP (chronyd)

`/etc/chrony.conf` is rewritten on every start with `bindcmdaddress 127.0.0.1`.

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `NTP_SERVERS` | empty | One `pool <server> iburst` line per server. | `pool 2.pool.ntp.org iburst`. |
| `NTP_ALLOW_FROM` | empty | One `allow <subnet>` per subnet (NTP server for clients). | No client allowed. |

## 12. Zabbix agent 2

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `ZABBIX_SERVER` | `127.0.0.1` | `Server=` in `zabbix_agent2.d/local.conf`. | `127.0.0.1`. |
| `ZABBIX_SERVER_ACTIVE` | `$ZABBIX_SERVER` | `ServerActive=`. | `ZABBIX_SERVER`. |
| `ZABBIX_HOSTNAME` | `$HOSTNAME` | `Hostname=`, or `HostnameItem=system.hostname` when equal to the hostname. | Hostname item. |
| `ZABBIX_HOSTMETADATA` | `izPBX` | `HostMetadata=`. | `izPBX`. |
| `ZABBIX_USR` | `zabbix` | Declared, not used. | No effect. |
| `ZABBIX_GRP` | `zabbix` | Declared, not used. | No effect. |

`LogFile`, `Hostname`, `Server`, `ServerActive` are commented out in the main
`zabbix_agent2.conf`.

## 13. FOP2

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `FOP2_AMI_HOST` | FreePBX `ASTMANAGERHOST` | `manager_host` in `/usr/local/fop2/fop2.cfg`. | Read from FreePBX. |
| `FOP2_AMI_PORT` | FreePBX `ASTMANAGERPORT` | `manager_port`. | Read from FreePBX. |
| `FOP2_AMI_USERNAME` | FreePBX `AMPMGRUSER` | `manager_user`. | Read from FreePBX. |
| `FOP2_AMI_PASSWORD` | FreePBX `AMPMGRPASS` | `manager_secret`. | Read from FreePBX. |
| `FOP2_LICENSE_NAME` | empty | `--name` for `fop2_server --register/--revoke`. | Registration with an empty name. |
| `FOP2_LICENSE_CODE` | empty | Registers the license when `fop2.lic` is missing (code masked in the log). | Demo mode. |
| `FOP2_LICENSE_IFACE` | first non-`lo` interface | `--iface` of license commands, `OPTIONS` in `/etc/sysconfig/fop2`, `command=… -i <iface>` in `fop2.ini`. | First interface. |
| `FOP2_AUTOUPGRADE` | `false` | Upgrades FOP2 to `FOP2_VER` when the installed version is older. | `false`. |
| `FOP2_AUTOACTIVATION` | `false` | When the license is "Not Found": `--reactivate`, then revoke + register. | `false`. |

## 14. Legacy entrypoint (`entrypoint.sh`)

| Variable | Default | Effect | If empty |
|---|---|---|---|
| `APP_RUNAS` | `false` | `true`: main command run with `runuser -p -u $APP_USR`. | `false`. |
| `MULTISERVICE` | `false` | `true`: main command replaced by `runsvdir -P /etc/service`. | `false`. |
| `CMD_OVERRIDE` | empty | Replaces the main command (split on whitespace). | Image `CMD` (supervisord). |
| `ENTRYPOINT_TINI` | `false` | `true`: main command wrapped by `tini -g --`. | `false`. |

## 15. Internal names (not configurable)

These names are read by the old entrypoint but are set by the script itself,
by the OS or by the shell. Setting them in the environment is not supported;
some of them (marked †) would still change behaviour because the script uses
`:=` defaults.

| Name | What it is |
|---|---|
| `HOSTNAME` | Shell/kernel hostname; set from `APP_FQDN`. |
| `OS_RELEASE` † | `ID` from `/etc/os-release`; picks Debian/Alpine/RHEL paths. |
| `SUPERVISOR_DIR` † | supervisord include directory (`/etc/supervisord.d` on RHEL). |
| `HTTPD_CONF_DIR` † | Apache config directory (`/etc/httpd`). |
| `PMA_CONF_APACHE` † | phpMyAdmin Apache config file. |
| `PMA_DIR` †, `PMA_CONF` † | phpMyAdmin paths (Debian/Alpine branches only). |
| `PHP_CONF` † | php.ini path (Debian/Alpine branches only, unused). |
| `NRPE_CONF` †, `NRPE_CONF_LOCAL` † | Nagios NRPE paths (Debian branch only, unused). |
| `ZABBIX_CONF` †, `ZABBIX_CONF_LOCAL` † | Zabbix agent config files. |
| `FOP2_LICENSE_OPTS` | Options assembled for `fop2_server` license commands. |
| `FOP2_LICENSE_STATUS` | Output of `fop2_server --getinfo`. |
| `FOP2_VER_CUR` | Installed FOP2 version. |
| `FPBX_OPTS` | Path options for the FreePBX installer. |
| `FRAMEWORK_VERSION` | Installed framework version (16.0.41 workaround). |
| `SKIP_MYSQL_INIT` | Set when `MYSQL_ROOT_PASSWORD` is empty. |
| `INSTALL_STATUS` | `KO` after 5 failed install attempts. |
| `UPGRADABLE` | Difference between `FREEPBX_VER` and the installed major. |
| `RETVAL`, `RET`, `CERTOK` | Exit codes. |
| `CERT_CN`, `CERT_SUBJ` | Self-signed certificate CN and subject. |
| `PHONEBOOK_PROTO` | `http`/`https` for the phonebook address. |
| `SERVICE_VAR`, `SERVICE_ENABLED`, `SERVICE_DAEMON`, `SERVICE` | Locals of `chkService` (`<NAME>_DAEMON` overrides the supervisord program name). |
| `USR_HOME` | Home of `APP_USR` (msmtp log). |
| `HOOK`, `HOOKDIR` | Custom hooks stage and directory. |
| `CMD` | Main command array (`entrypoint.sh`). |
| `IP`, `FROM`, `F`, `NF` | Loop variables and awk fields. |
| `APP`, `DOMAIN`, `NAME`, `VERSION_ID` | Written into `/root/.bashrc` (banner, prompt; `NAME`/`VERSION_ID` from `/etc/os-release`). |
| `FREEPBX_AUTOUPGRADE_`, `FREEPBX_MODULES_` | Name prefixes in the Advanced Settings filter, not variables. |
