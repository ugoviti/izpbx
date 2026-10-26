# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [22.17.0] - Unreleased
New major release: **FreePBX 17** and **Asterisk 22** LTS on **Debian 12**. Volumes of izPBX 20.16 (FreePBX 16) are migrated by the container, opt-in: read [Upgrade from 20.16 to 22.17](README.md#upgrade-from-2016-to-2217) before switching image.
### Security
- FreePBX 16 reaches end of life on 2027-01-01: FreePBX `17` (framework `17.0.33`) on PHP `8.2` (PHP 7.4 is end of life)
- Base image `debian:bookworm-slim` pinned by digest; every downloaded source and binary (Asterisk, s6-overlay, FreePBX, ionCube, FOP2, npm, addons) is fetched over HTTPS only and verified with the sha256 of `izpbx-asterisk/versions.env`, per architecture where it differs
- Third-party repositories (Zabbix) trusted only by the pinned key fingerprint
- The runtime image has no compiler toolchain
- PHP hardening applied to both php-fpm and the CLI: `allow_url_include=Off`, `display_errors=Off`, `display_startup_errors=Off`, `session.upload_progress.enabled=0`
- Removed the `SECLEVEL=1` OpenSSL workaround and `gpg --refresh-keys`
- `MYSQL_PASSWORD` and `MYSQL_ROOT_PASSWORD` can be read from files (`IZPBX_MYSQL_PASSWORD_FILE`, `IZPBX_MYSQL_ROOT_PASSWORD_FILE`, docker secrets); no password in the logs or in the process list
- The security fixes of 20.16.22 (XML phonebook `/pb`, `zabbix` sudoers, SMTP password files, FOP2 license in the logs) are kept
### Changed
- Base OS **Debian 12** instead of Rocky Linux 8: the internal paths of Apache, cron, PHP, phpMyAdmin, msmtp (CA bundle), fail2ban (Apache logs), chrony, Postfix (Debian defaults) and Zabbix agent are different (relevant only for custom scripts in `APP_CUSTOM_SCRIPTS`); `PMA_CONFIG` defaults to `/etc/phpmyadmin/config.inc.php`
- PBX engine Asterisk `22.11.0` LTS (pjproject `2.17`), FreePBX `17`, PHP `8.2` through **php-fpm** (Apache `mpm_event` + `proxy_fcgi`)
- Services supervised by **s6-overlay** `3.2.3.2` instead of supervisord: a oneshot `izpbx-init` prepares the container, then every service starts; `izpbx-service restart <name>` restarts one; ordered shutdown (`fwconsole stop`) within the `docker stop` timeout
- New `HEALTHCHECK` (`izpbx-healthcheck`)
- New shell banner and prompt (`docker exec -it izpbx bash`): the izPBX logo, the versions and the live state of the PBX (health, calls, endpoints, trunk registrations), a two-line prompt with the health and the calls; own lines in `/root/.bashrc.local`; `NO_COLOR` honored
- Apache TLS ciphers: the Debian `HIGH:!aNULL` instead of the RHEL crypto policy (`PROFILE=SYSTEM`); Apache logs in `${APACHE_LOG_DIR}`
- `ASTERISK_VER`, `FREEPBX_VER`, `FOP2_VER`, `ZABBIX_VER` are no longer build arguments: every version comes from `izpbx-asterisk/versions.env` (in the image: `/usr/src/izpbx/versions.env`); `build/check-updates.sh` reports newer upstream releases
- `FREEPBX_MODULES_EXTRA` default without `phonebook` (no FreePBX 17 release)
- `FREEPBX_AUTOUPGRADE_CORE` does not migrate FreePBX 16 to 17: use `IZPBX_MIGRATE_FREEPBX`
- `APP_PORT_SIP` (5160, chan_sip in 20.16) is a PJSIP transport, created only by the migration when the 20.16 had chan_sip extensions or trunks; new installations have no transport on 5160
- Updated FOP2 `2.31.53` (Debian package), ionCube loader `15.5.1` for PHP 8.2, Zabbix agent 2 `7.0`, npm `10.9.9` on the Node.js 18 of Debian 12, sngrep `1.9.0`, bcg729 `1.1.2`; MariaDB `10.11.19` LTS unchanged
- Image for **amd64** only: arm64 comes in a later release (the build scripts already support it)
- Image tags `22.17.0`, `22.17`, `22`; **`latest` stays on 20.16** for now: use an explicit tag. `compose.yml` uses `22.17.0`; `default.env` lists every configurable variable
- SLA runs with `app_sla` (MeetMe stays disabled); conferences use ConfBridge
- The `izpbx-*` tools of 20.16 reviewed for 22.17: `izpbx-blfmonitor` (PJSIP channels, `-T` for the technology, pid file, options also with `start`/`stop`), `izpbx-callstats` (English headers), `izpbx-trunkrotate ROUTE TRUNK...` (no password in the script: the izPBX `MYSQL_*` settings), `izpbx-hangup-stucked-calls [-n] [SECONDS]`, `izpbx-check-iax2 [MIN]`, `izpbx-mtrstats HOST`. Renamed and made generic: `izpbx-rtrt-enumrewrite` → `izpbx-enumrewrite DOMAIN`, `izpbx-rtrt-freepbx2ldap` → `izpbx-freepbx2ldap` (settings in `/etc/izpbx/freepbx2ldap.conf`), `izpbx-reboot-portech`/`-gxw4024`/`-kirkettone` → `izpbx-reboot-device {portech|grandstream-gxw|kirk} HOST...` (password from `IZPBX_DEVICE_PASSWORD`)
- CI: lint (shellcheck, hadolint) on every push and pull request, migration, new installation and maintenance tests in Docker-in-Docker, weekly rebuild of both `release/20.16` and `main`, dev builds tagged `dev-22.17`
### Removed
- **chan_sip**: extensions and trunks are PJSIP (converted by the migration)
- `Macro()`, `Monitor()`, `ImportVar()`, `SetAMAFlags()`, `NoCDR()` no longer exist in Asterisk 22: custom dialplan must use `GoSub()` and `MixMonitor()`, rewritten **before** the migration
- Variables of the 20.16 entrypoint `APP_RUNAS`, `MULTISERVICE`, `CMD_OVERRIDE`, `ENTRYPOINT_TINI`: ignored, with a warning at start if set (s6 starts the services); `UMASK` stays and applies to the initialization and to every service
- `FOP2_SHA256` and `ZABBIX_REL`: the build verifies a sha256 per architecture from `versions.env`
- The FreePBX `phonebook` module (no FreePBX 17 release): its entries are migrated to Contact Manager
- Workarounds of older releases: `php74.patch`, the RHEL/microdnf and Asterisk 18 branches, `chan_local`
- `compose-dev-20.16.yml` (the 22.17 one is `compose-dev-22.17.yml`)
- `izpbx-check-oooh323` (Asterisk 22 has no `chan_ooh323`) and `izpbx-system-mkswap` (a swap file is set up on the host, not in the container)
- `pbx_lua` is no longer built: FreePBX writes the dialplan in `extensions*.conf`, a Lua dialplan (`extensions.lua`) is not supported (its sample loaded a `demo` context with hints on `SIP/1000` and `SIP/1001`)
### Migration
- izPBX 22.17 on a volume of izPBX 20.16 (FreePBX 16) without `IZPBX_MIGRATE_FREEPBX=true` starts in **maintenance mode**: no service, healthcheck unhealthy, `/data` and the databases untouched. The same happens when a check blocks the migration
- New variables: `IZPBX_MIGRATE_FREEPBX` (opt-in), `IZPBX_MIGRATE_IGNORE_MODULES` (modules with no FreePBX 17 release to leave out), `IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN` (accept custom dialplan with applications Asterisk 22 no longer has)
- `izpbx-preflight` runs the read-only checks before migrating (framework 16.0.26 or later, modules with a FreePBX 17 release, custom dialplan, free space, database privileges, complete first install): `docker compose run --rm --no-deps --entrypoint izpbx-preflight izpbx`
- The migration: inventory of FreePBX 16, snapshot (verified database dumps, directories moved, spool hardlinked), FreePBX 17 installed and a FreePBX backup of the 16 restored, chan_sip converted to PJSIP, then custom prompts and music on hold, astdb keys, voicemail and recordings, custom crontab lines, FOP2 with its license, certificates, `dongle.conf`; the inventory after is compared with the one before and any unexpected difference stops in maintenance mode. Expected, and accepted: chan_sip to PJSIP, `astdb` keys FreePBX 17 adds and runtime states (dundi, pbx, `CustomDevstate`), the default modules of the new installation (eg. `infoservices`), modules with no FreePBX 17 release (phonebook, `speeddial`, `IZPBX_MIGRATE_IGNORE_MODULES`) and commercial modules (their state depends on the license), Advanced Settings (AMI credentials, versions), the AMI keys of `fop2.cfg`, the `.nomusic_reserved` file of the music on hold. Each phase is resumed after an interruption; the CDR database is not touched
- `ENABLE_ARI` is back to the FreePBX 17 default after the migration (the restore resets it): the final report says so when it was enabled on 20.16; enable it again in Advanced Settings if you use ARI
- Commercial modules are migrated and listed in the final report (`/data/.izpbx-migration/report.txt`), to reactivate with their license
- `phonebook` and `speeddial` (installations born on FreePBX 15) have no FreePBX 17 release: their entries and system speed dials go to the Contact Manager group "Phonebook (izPBX 20.16)" (dialed with `*10<code>`), also exported to CSV
- The snapshot stays in `/data/.izpbx-migration/` until you remove it (its size is logged at every start); `izpbx-rollback` goes back to izPBX 20.16 from it

## [20.16.22] - 2026-10-22
### Security
- **PHP CVE-2026-109618 and CVE-2026-109619 ("PHP2Shell", unauthenticated RCE)**: rebuilt on Rocky Linux 8 AppStream `php-7.4.33-8` (RHSA-2026:87080). All previous izPBX images are affected: upgrade as soon as possible
- Updated PBX engine to Asterisk `20.21.0` LTS: fixes the Asterisk security advisories published after 20.15.2 (PJSIP, AMI, ARI)
- FreePBX modules are predownloaded at build time using the same mirror query of FreePBX Module Admin: the static `modules-16.0.xml` file listed older releases (ex. Contact Manager 16.0.27 instead of 16.0.29, vulnerable to GHSA-j82w-j6cr-56m6). Module download failures now stop the build
- Fixed unauthenticated SQL injection in the XML phonebook (`/pb`) via the `cgroup` parameter
- Fixed path traversal and reflected XSS in the XML phonebook (`/pb`) via the `ph` parameter
- Fixed privilege escalation from the `zabbix` user to root: sudo now allows `/usr/sbin/asterisk` only as the `asterisk` user
- PHP hardening: `allow_url_include=Off`, `display_errors=Off`, `display_startup_errors=Off`, `session.upload_progress.enabled=0`, `memory_limit=512M`
- Apache rejects request bodies bigger than 128M (`LimitRequestBody`)
- Database passwords are not printed in the container logs anymore and are not visible in the process list during startup (`MYSQL_PWD`)
- FOP2 license code is not printed in the container logs anymore
- `/etc/msmtprc` and `/etc/postfix/sasl_passwd` (SMTP passwords) are not world readable anymore
- FOP2 is downloaded only over HTTPS and verified with a sha256 checksum (`FOP2_SHA256`); removed the `install_fop2.sh` automatic installer
- Build: removed `--nogpgcheck`, repository GPG keys are pinned by fingerprint and release RPMs are signature verified, every source tarball is verified with a sha256 checksum, all downloads use HTTPS, unpinned `master`/`main` sources are pinned to a commit
### Changed
- Updated FOP2 to `2.31.53`, sngrep to `1.9.0`, bcg729 to `1.1.2`, ionCube loader pinned to `15.5.1`
- Updated Database engine to MariaDB `10.11.19` LTS
- chan_dongle is now built from the maintained fork https://github.com/wdoekes/asterisk-chan-dongle
- PHP `date.timezone` follows the container `TZ` variable (it was hard-coded to `Europe/Rome`)
- Postfix relays mail only from localhost by default (`SMTP_MYNETWORKS` to allow other networks)
- chrony accepts commands only from localhost
- `hep.conf` is not forced anymore to `enabled = yes` at every start: use the new `HEP_ENABLED` variable
- New `LETSENCRYPT_EMAIL` variable (default `SMTP_MAIL_TO`) used for Let's Encrypt certificates requests
- `HOSTNAME` (Apache ServerName, postfix, zabbix) is set to `APP_FQDN` when defined
- Removed Asterisk 18 development compose files (Asterisk 18 is EOL)
- CI: the built image is verified (PHP fixed release, Asterisk version, `allow_url_include`) and a weekly rebuild publishes OS security updates into the private registry
### Fixed
- Let's Encrypt certificates were never renewed by the daily cron job
- Installation didn't stop when the MySQL database was unreachable
- Let's Encrypt certificate request failures were reported as successful, and the request used `SMTP_MAIL_FROM` as contact email
- `SMTP_MAIL_TO` changes were not applied to the root mail alias
- Postfix SMTP relay authentication didn't work (missing port and wrong `sasl_passwd` lookup key)
- Database settings reconfigured at startup were written into a non persistent copy of `/etc/freepbx.conf` (`sed -i` replaced the symlink to the persistent file)
- `MYSQL_PASSWORD` containing a single quote or a backslash (not supported by the FreePBX installer) is now rejected at startup with a clear error
- Container restarts created nested symlinks into `*.dist` directories and overwrote the original `*.dist` files
- phpMyAdmin configuration was duplicated at every container restart
- Passwords and values containing special characters (`/ & ' \ |`) broke the FreePBX, FOP2 and dnsmasq configuration
- Invalid dnsmasq configuration when `DHCP_DOMAIN` is defined
- Asterisk documentation directory was resynchronized at every start
- HTTPS self-signed certificate was not regenerated when only the key or only the certificate was missing
- FreePBX install retried only 4 times instead of 5
- Invalid `TZ` values left a broken `/etc/localtime`
- Other minor fixes in entrypoint scripts (quoting, redirections, exit codes)

## [20.16.21] - 2025-10-14
### Changed
- Updated PBX engine to Asterisk `20.15.2` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.15.2.md)
### Fixed
- Fix missing libwebsockets package
- Enabled asterisk build option G711_NEW_ALGORITHM
- Revert FreePBX framework to 16.0.40 due to an issue in 16.0.41 preventing initial setup completion

## [20.16.20] - 2025-03-19
### Changed
- Updated PBX engine to Asterisk `20.12.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.11.0.md)
- Updated Database engine to MariaDB `10.11.11` LTS (https://mariadb.com/kb/en/mariadb-10-11-11-release-notes/)
### Fixed
- Fix [XBOW-025-157] SQL Injection in Phonebook Directory Extension Path in izPBX project

## [20.16.19] - 2025-01-04
### Fixed
- Fix segfault on x86_64 systems caused by missing Intel Core2 Penryn and Core i7 instruction sets in codec_g729 (solve https://github.com/ugoviti/izpbx/issues/82)
- Added apparmor=unconfined to docker compose to fix cron problems on ubuntu server with apparmour enabled (solve https://github.com/ugoviti/izpbx/issues/88)

## [20.16.18] - 2024-12-30
### Fixed
- Fix userman and pm2 errors on initial FreePBX deploy

## [20.16.17] - 2024-12-28
### Changed
- Updated PBX engine to Asterisk `20.11.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.11.0.md)
- Updated FOP2 to `2.31.45` (https://www.fop2.com/download.php)
- Updated Database engine to MariaDB `10.11.10` LTS (https://mariadb.com/kb/en/mariadb-10-11-10-release-notes/)

## [20.16.16] - 2024-08-09
### Changed
- Updated PBX engine to Asterisk `20.9.2` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.9.2.md)

## [20.16.15] - 2024-07-24
### Changed
- Updated PBX engine to Asterisk `20.9.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.9.0.md)
- Updated FOP2 to `2.31.43` (https://www.fop2.com/download.php)
- Updated sngrep to `1.8.2` (https://github.com/irontec/sngrep/releases/tag/v1.8.2)
- Fix msmtp starttls support

## [20.16.14] - 2024-06-07
### Changed
- Added ARM64/AARCH64 CPU support (thank you to @Andreas)
- This is the first release supporting ARM64 architecture, consider this a "beta" feature
- Updated zabbix-agent to `7.0` release cycle

## [20.16.13] - 2024-05-28
### Changed
- Updated PBX engine to Asterisk `20.8.1` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.8.1.md)
- Updated Database engine to MariaDB `10.11.8` LTS (https://mariadb.com/kb/en/mariadb-10-11-8-release-notes/)
- Updated FOP2 to `2.31.41` (https://www.fop2.com/download.php)
- Renamed all `docker-compose*.yml` files to `compose*.yml`
- Updated README.md file replaced `docker-compose` commmand with `docker compose` plugin system

## [20.16.12] - 2024-04-10
### Changed
- Updated PBX engine to Asterisk `20.7.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.7.0.md)
- Updated Database engine to MariaDB `10.11.7` LTS (https://mariadb.com/kb/en/mariadb-10-11-7-release-notes/)
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`
- Updated sngrep to `1.8.1` (https://github.com/irontec/sngrep/releases/tag/v1.8.1)
- Updated FOP2 to `2.31.40` (https://www.fop2.com/download.php)
- Added custom script hooks to the main entrypoint (thaks to @hobbit378)
  - define an external `APP_CUSTOM_SCRIPTS` variable as base path where to put your custom scripts
- Added function to read MYSQL passwords from secret files generated with 'docker secret' or 'podman secret' (thaks to @hobbit378)
  WARNING: need further testing
  NOTE. external secrets are supported only in swarm mode, you must tweak docker-compose.override.yml to make secrets working in your setup
  create the docker secret using the following commands:
  - echo YourSuperSecretPASSWORD | docker secret create MYSQL_PASSWORD_FILE -
  - echo YourSuperSecretPASSWORD | docker secret create MYSQL_ROOT_PASSWORD_FILE -
- Updated `default.env` with: (NOTE: don't forget to accordingly update your `.env` file)
  - added: `#APP_CUSTOM_SCRIPTS=/data/scripts`
  - added: `#IZPBX_MYSQL_PASSWORD_FILE=/run/secrets/IZPBX_MYSQL_PASSWORD`
  - added: `#IZPBX_MYSQL_ROOT_PASSWORD_FILE=/run/secrets/IZPBX_MYSQL_ROOT_PASSWORD`

## [20.16.11] - 2024-01-05
### Changed
- Updated PBX engine to Asterisk `20.5.2` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.5.2.md)
- Updated Database engine to MariaDB `10.11.6` LTS (https://mariadb.com/kb/en/mariadb-10-11-6-release-notes/)
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`
- Updated sngrep to `1.8.0` (https://github.com/irontec/sngrep/releases/tag/v1.8.0)
- Updated FOP2 to `2.31.38` (https://www.fop2.com/download.php)

## [20.16.10] - 2023-10-21
### Changed
- Updated PBX engine to Asterisk `20.5.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.5.0.md)
- Updated Database engine to MariaDB `10.11.5` LTS (https://mariadb.com/kb/en/mariadb-10-11-5-release-notes/)
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`
- Updated `default.env` with: (NOTE: don't forget to accordingly update your `.env` file)
  - changed: `#FOP2_AUTOUPGRADE=false`
  - added: `#FOP2_AUTOACTIVATION=false`
  - added: `FREEPBX_FIX_PERMISSION=false`
### Fixed
- disabled using eth0 as default interface when registering fop2 and the FOP2_LICENSE_IFACE var is not set
- fixed /etc/sysconfig/fop2 file contents

## [20.16.9] - 2023-08-04
### Changed
- Updated PBX engine to Asterisk `20.4.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.4.0.md)
- Updated Database engine to MariaDB `10.11.4` LTS (https://mariadb.com/kb/en/mariadb-10-11-4-release-notes/)
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`

## [20.16.8] - 2023-07-17
### Changed
- Updated PBX engine to Asterisk `20.3.1` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.3.1.md)
- Updated FOP2 to `2.31.35` (https://www.fop2.com/download.php)

## [20.16.7] - 2023-06-24
### Changed
- Updated PBX engine to Asterisk `20.3.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.3.0.md)
- Updated zabbix-agent to `6.4` and switched to zabbix-agent2
- Reworked entrypoint.sh and entrypoint-hooks.sh scripts

## [20.16.6] - 2023-05-14
### Changed
- Updated PBX engine to Asterisk `20.2.1` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.2.1)
- Updated sngrep to `1.7.0` (https://github.com/irontec/sngrep/releases/tag/v1.7.0)

## [20.16.5] - 2023-03-14
### Added
- Added 'msmtp' as an additional and default MTA service alternative to postfix (thanks to @hobbit378)
- New dynamic phonebook XML system (thanks to @Giacomo "Baso" Martinelli)
  - Supported phones system:
    - Yealink / Fanvil
    - Gigaset
### Changed
- Updated PBX engine to Asterisk `20.2.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.2.0)
- Updated database engine to MariaDB `10.6.12` LTS (https://mariadb.com/kb/en/mariadb-10612-release-notes/)
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`
- Updated `default.env` with: (NOTE: don't forget to accordingly update your `.env` file)
  - added: `#SMTP_RELAYHOST_PORT=25`
  - added: `#MSMTP_ENABLED=true`

## [20.16.4] - 2023-02-04
### Changed
- Updated PBX engine to Asterisk `20.1.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.1.0)
### Fixed
- Fixed unable to use custom MySQL port than 3006 (partial fix #40. FreePBX related problem: ref. https://issues.freepbx.org/browse/FREEPBX-24066)

## [20.16.3] - 2022-12-06
### Changed
- Updated PBX engine to Asterisk `20.0.1` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.0.1)
- Updated FOP2 to `2.31.34` (https://www.fop2.com/download.php)
- Created a special FIX/Workaround for lowering FreePBX WARNINGS about missing custom contexts
  - the new config file `freepbx_custom_fix_missing_contexts.conf` was created containing empty default contexts
- Changed Asterisk modules build config:
  - enabled modules:
    - res_stasis_mailbox
    - res_ari_mailboxes
  - disabled modules:
    - app_jack
    - res_geolocation

## [20.16.2] - 2022-11-27
### Fixed
- changed base image from rockylinux:8-minimal to rockylinux:8

## [20.16.1] - 2022-11-22
### Fixed
- fixed missing codec_g729 build for Asterisk 20

## [20.16.0] - 2022-11-19
### Added
- FOP2 certificate management for HTTPS/WSS SSL WebSockets
### Changed
- Updated PBX engine to Asterisk `20.0.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-20.0.0)
  - enabled modules:
    - app_statsd
    - app_saycounted
    - chan_sip
    - res_config_sqlite3
    - res_phoneprov
    - res_pjsip_phoneprov_provider
    - res_pjsip_geolocation
  - disabled modules:
    - res_adsi
    - res_monitor
    - res_pktccops
- Updated database engine to MariaDB `10.6.11` LTS (https://mariadb.com/kb/en/mariadb-10611-release-notes/)
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`
- Updated zabbix-agent to `6.2` and switched to zabbix-agent2
- Now the initial deploy include the latest release of framework (at build time of izpbx release) so you don't need to update any FreePBX modules after the deploy
- Pre downloading all upgradable base system modules also (core, etc..) to avoid upgrading after initial deploy
- Various entrypoint enhancements
- Testing upgrade baseimage to Rocky Linux 9 and Asterisk 20
  - EL9 problems: ilbc 3.0.4, libsrtp 2.3.0, python 2, libtermcap, unbound
### Fixed
- exit from install phase if all 5 retries fails

## [18.16.14] - 2022-10-21
### Changed
- Updated PBX engine to Asterisk `18.15.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-18.15.0)
- Updated FOP2 to `2.31.33` (https://www.fop2.com/download.php)
- Updated database engine to MariaDB `10.6.10` LTS (https://mariadb.com/kb/en/mariadb-10610-release-notes/)
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`
- Updated `default.env` with: (NOTE: don't forget to accordingly update your `.env` file)
  - changed: `APP_PORT_SIP=5061` to `APP_PORT_SIP=5160`
### Fixed
- fixed codec_opus build (xmlstarlet was missing in RL8 repos)

## [18.16.13] - 2022-09-22
### Changed
- Updated PBX engine to Asterisk `18.14.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-18.14.0)
- Updated sngrep to `1.6.0` (https://github.com/irontec/sngrep/releases/tag/v1.6.0)
- Disabled asterisk module `res_geolocation`
### Fixed
- Fix crond high cpu usage caused by missing ulimit setings into docker-compose.yml

## [18.16.12] - 2022-08-09
### Changed
- Updated `default.env` with: (NOTE: don't forget to accordingly update your `.env` file)
  - added: `#FAIL2BAN_DEFAULT_BANACTION=iptables-allports[blocktype=DROP]`

## [18.16.11] - 2022-07-21
### Fixed
- Removed 'MultiViews' option from Apache config that broken FreePBX GQL/REST API

## [18.16.10] - 2022-07-18
### Added
- Added Asterisk chan_dongle support (https://github.com/shalzz/asterisk-chan-dongle)
### Changed
- OS packages updates

## [18.16.9] - 2022-06-29
### Changed
- Updated PBX engine to Asterisk `18.13.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-18.13.0)
- Updated database engine to MariaDB `10.6.8` LTS (https://mariadb.com/kb/en/mariadb-1068-release-notes/)
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`

## [18.16.8] - 2022-05-14
### Changed
- Updated PBX engine to Asterisk `18.12.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-18.12.0)
- Updated sngrep to `1.5.0`
- Updated zabbix-agent to `6.0`

## [18.16.7] - 2022-03-31
### Changed
- Updated PBX engine to Asterisk `18.11.1` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-18.11.1)
- updated `default.env` with the following variables: (NOTE: don't forget to update your custom `.env` file)
  - changed default value for `APP_PORT_SIP` from `5160` to `5061`

## [18.16.6] - 2022-03-12
### Changed
- Updated PBX engine to Asterisk `18.10.1` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-18.10.1)
- Updated SpanDSP to `3.0.0-6ec23e5a7e`
- Updated database engine to MariaDB `10.6.7` LTS (https://mariadb.com/kb/en/mariadb-1067-release-notes/)
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`

## [18.16.5] - 2022-02-12
### Changed
- Updated PBX engine to Asterisk `18.10.0` LTS (https://downloads.asterisk.org/pub/telephony/asterisk/releases/ChangeLog-18.10.0)

## [18.16.4] - 2022-02-03
### Fixes
- Updated FOP2 to 2.31.32 (this release fixes a long-standing FOP2 license issue when running inside a Docker container, where the license became invalid and needed to be reactivated on every restart.)
- FOP2: added new option `--rp=http` on fop2_server commands to bypass fop2 license problems when running inside a container
- FOP2: better license handling

## [18.16.3] - 2022-01-22
### Changed
- Updated FOP2 to 2.31.31
- Portability enhancements: `MYSQL_ROOT_PASSWORD` is no longer mandatory.
  If for security reasons it isn't defined in the `.env` file, the `MYSQL_PASSWORD` will be used instead
  WARNING: you must manual pre provision the `asterisk` and `asteriskcdrdb` databases must exist and`MYSQL_USER` must have permissions to use them, otherwise the install step will fail.
- by default do not update FOP2 on izPBX new release, you must enable `FOP2_AUTOUPGRADE=true` in `.env` to upgrade FOP2 (require valid license file)
### Added
- updated `default.env` with the following variables: (NOTE: don't forget to update your custom `.env` file)
  - added: `FOP2_AUTOUPGRADE` (default: `false`)

## [18.16.2] - 2021-12-24
### Added
- Added `iproute` package (used by SIP Settings when binding interface to SIP channel driver)

## [18.16.1] - 2021-12-15
### Changed
- Updated PBX engine to Asterisk 18.9.0 LTS (https://www.asterisk.org/asterisk-news/asterisk-18-9-0-now-available/)
- Let's Encrypt: changed used address from `SMTP_MAIL_TO` to `SMTP_MAIL_FROM` when requesting a certificate

## [18.16.0] - 2021-12-04
### Changed
- MAJOR CHANGE: Updated GUI to FreePBX 16 (see README.md for upgrade instructions)
- MAJOR CHANGE: chan_pjsip is now the default sip channel driver
- MAJOR CHANGE: Updated PHP from 7.2 to 7.4 (NOTE: before switching to this release remember to upgrade all FreePBX modules to avoid warnings about unsupported PHP version)
- disabled Asterisk module: app_voicemail_imap
- updated sngrep to 1.4.10
- updated `default.env` with: (NOTE: don't forget to accordingly update your `.env` file)
  - added: `FREEPBX_AUTOUPGRADE_CORE=true`
  - renamed: `FREEPBX_FIRSTRUN_AUTOUPDATE` to `FREEPBX_AUTOUPGRADE_MODULES`
  - changed: `APP_PORT_PJSIP=5060`
  - changed: `APP_PORT_SIP=5160`
  - disabled: `FREEPBX_SIGNATURECHECK=0`
### Added
- PHP 7.4 IonCube Loader support for commercial modules support (still not usable, missing sysadmin rpm package)
### Removed
- removed Asterisk 16 build support

## [18.15.24] - 2021-11-20
### Changed
- enabled FreePBX modules autoupdate on first deploy
- enabled FreePBX modules by default:
  - bulkhandler
  - speeddial
  - weakpasswords
  - ucp
### Added
- updated `default.env` with the following variables: (NOTE: don't forget to update your custom `.env` file)
  - `FREEPBX_FIRSTRUN_AUTOUPDATE=true`
  - `APP_PORT_WEBRTC=8089`
  - `APP_PORT_UCP_HTTP=8001`
  - `APP_PORT_UCP_HTTPS=8003`

## [18.15.23] - 2021-11-11
### Changed
- Updated engine to Asterisk 18.8.0 LTS
- Updated database engine to MariaDB 10.6.5
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`
  
## [18.15.22] - 2021-10-21
### Changed
- Updated Asterisk to 18.7.1 LTS
  
## [18.15.21] - 2021-09-24
### Fixed
- moved the `[ASTRUNDIR]=/var/run/asterisk` outside persistent `/data` storage to avoid problems between startups
### Changed
- Updated mariadb from 10.5.12 to 10.6.4
  - after the deploy don't forget to upgrade mariadb database with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`
- updated `default.env` with the following variables: (NOTE: don't forget to update your custom `.env` file)
  - default value for `HTTPD_HTTPS_ENABLED` from `true` to `false`

## [18.15.20] - 2021-09-19
### Changed
- updated `default.env` with the following new variables: (NOTE: don't forget to update your custom `.env` file)
  - `HTTPD_HTTPS_CERT_FILE`
  - `HTTPD_HTTPS_KEY_FILE`
  - `HTTPD_HTTPS_CHAIN_FILE`
- automatically recreate default self-signed certificate to match Common Name of `APP_FQDN` variable
- enhancements on self-signed certificate management
- changed default https certs dir from `/etc/pki/izpbx` to `/etc/asterisk/keys` (remember to delete the old `/etc/pki/izpbx` directory because it's not used anymore)
- use default FreePBX SSL certs (NOTE: this will change default certificates for exposed https servers)

## [18.15.19] - 2021-09-07
### Fixed
- disabled postfix by default to avoid mail loops and port conflicts when not correctly configured
### Changed
- updated `default.env` with the following variables: (NOTE: don't forget to update your custom `.env` file)
  - from `POSTFIX_ENABLED=true` to `#POSTFIX_ENABLED=true`

## [18.15.18] - 2021-09-02
### Fixed
- faster container startup time
### Added
- chronyd (NTP) service support
### Changed
- updated `default.env` with the following variables: (NOTE: don't forget to update your custom `.env` file)
  - `NTP_SERVERS`
  - `NTP_ALLOW_FROM`
  - `APP_PORT_NTP`
  - `NTP_ENABLED`
- updated `docker-compose.yml` with the following lines: (NOTE: don't forget to update your custom `docker-compose.yml` file)
  - `${APP_PORT_NTP}:${APP_PORT_NTP}/udp`

## [18.15.17] - 2021-08-31
### Fixed
- fixed timezone problem causing TimeConditions not working (Asterisk doesn't honour the `TZ` var)

## [18.15.16] - 2021-08-30
### Changed
- ATTENTION: changed default variabile value: `TZ=UTC`
  (change or add into .env file, your right TimeZone location to avoid breaking asterisk's CDR and Time Conditions. ex. `TZ=Europe/Rome`)
- ATTENTION: removed from docker-compose.yml the mounting of volume `/etc/localtime:/etc/localtime:ro`, so `TZ` variabile is used instead
### Fixed
- Fixed APP_PORT_HTTP wrong sostitution

## [18.15.15] - 2021-08-20
### Changed
- Updated Asterisk to 18.6.0 LTS
### Fixed
- Fixed `APP_PORT_AMI` variable

## [18.15.14] - 2021-08-11
### Changed
- Switched base OS image from CentOS 8 to RockyLinux 8
- Updated Asterisk to 18.5.1 LTS
- Updated MariaDB to 10.5.12
### Fixed
- FOP2 upgrade scripts workaround

## [18.15.13] - 2021-05-25
### Added
- ATTENTION: Added new variable into `default.env` (remember to update your `.env` copy):
  - `TZ=empty` (not set by default)
### Changed
- Updated Asterisk to 18.5.0 LTS
- Updated Zabbix Agent to 5.4
- Updated FOP2 to 2.31.30
- Updated sngrep to 1.4.9

## [18.15.12] - 2021-05-16
### Changed
- Updated to Asterisk 18.4.0 LTS
- Updated to MariaDB 10.5.10
### Fixed
- Enached behavior of izpbx supervisor event handler
- Fixed container restart on daily logrotate

## [18.15.11] - 2021-04-17
### Changed
- Added Multi-Tenant support by configuring custom docker-compose.yml file (this is the first release supporting that feature, other refinements will follow)
### Fixed
- Create custom mysql user if not exist (useful for multi-tenant installations)

## [18.15.10] - 2021-04-15
### Added
- Support for Remote Yealink XML PhoneBook, default URL (look README.md for configuring info):
  - http://izpbxip/pb (PhoneBook Menu)
  - http://izpbxip/pb/yealink/ext (Extensions PhoneBook)
  - http://izpbxip/pb/yealink/cm (Contact Manager Shared PhoneBook)
- ATTENTION: Added new variable into `default.env` (remember to update your `.env` copy):
  - `PHONEBOOK_ENABLED="true"`
  - `PHONEBOOK_ADDRESS=`
- Added `php-ldap` package
### Fixed
- Fixed missing LDAP support for UserManager
- Fixed `SMTP_ALLOWED_SENDER_DOMAINS` default var

## [18.15.9] - 2021-04-14
### Fixed
- Fixed codec_opus not enabled

## [18.15.8] - 2021-04-07
### Changed
- Based on Asterisk 18.3.0 LTS

## [18.15.7] - 2021-03-30
### Removed
- ATTENTION: (Breaking Change) removed/deprecated a variables into `default.env` (remember to update your `.env` copy):
  - `ROOT_MAILTO`
### Added
- ATTENTION: Added new variable into `default.env` (remember to update your `.env` copy):
  - `SMTP_MAIL_TO`
- Added `iptables` package
- Added `conntrack-tools` package (you can use `conntrack -L` to list active connections and `conntrack -F` to purge)
### Fixed
- Fail2ban stopped working because was missing `iptables` package (thanks to @fa-at-pulsit)
### Changed
- defaulted `ROOT_MAILTO` to `SMTP_MAIL_TO` var content (anyway you can continue to use ROOT_MAILTO var in your old .env for legacy purpose)
- by default fail2ban now use `$SMTP_MAIL_FROM` as sender and `$SMTP_MAIL_TO` as recipient address

## [18.15.6] - 2021-03-25
### Changed
- Removed shipped libresample archive used for building, and using now the official centos repository package
- Fixed /etc/aliases management
- Enhanced first deployment
- Allow custom 'asterisk' and 'asteriskcdrdb' DB name during initial deploy
- Added new variables into `default.env` (update your `.env` copy):
  - `MYSQL_DATABASE_CDR`
### Added
- Added opusfile-devel as build deps
### Fixed
- Restored missing codec_opus support
- Fixed missing asterisk documentation (/data/var/lib/asterisk/documentation/thirdparty/) that prevent loading extra codecs (like codec_opus)

## [18.15.5] - 2021-03-18
### Changed
- Enhanced let's encrypt management and enabling automatic daily renew check via cronjob (/etc/cron.daily/freepbx-le-renew)
- Apache config rework
- Minor entrypoint improvements
- Added new variables into `default.env` (update your `.env` copy):
  - `LETSENCRYPT_COUNTRY_CODE`
  - `LETSENCRYPT_COUNTRY_STATE`

## [18.15.4] - 2021-03-17
### Changed
- Enhanced let's encrypt certificate generation using fwconsole tool (thanks to @alenas)
- New version of asterisk.sh zabbix agent script with better active calls detection (now will be ignored the calls in Ringing state)
- Container shell enhancements
- Added new variables into `default.env` (update your `.env` copy):
  - `ZABBIX_HOSTNAME`
  - `ZABBIX_HOSTMETADATA`

## [18.15.3] - 2021-03-14
### Changed
- Updated mariadb from 10.5.8 to 10.5.9
  - upgrade tables with: `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`
- Misc optimizations on first installation
- Zabbix agent script update with new features

## [18.15.2] - 2021-03-11
### Changed
- Based on Asterisk 18.2.2 LTS
### Added
- Added support for postfix TLS and relayhost port (close #9)
- Added new variables into `default.env` (update your `.env` copy):
  - `SMTP_STARTTLS=true`

## [18.15.1] - 2021-02-17
### Changed
- Disabled ports in docker-compose.yml if 'network_mode: host' is used
- Changed default from APP_PORT_RTP_END=10200 to APP_PORT_RTP_END=20000

## [18.15.0] - 2021-01-28
### Changed
- Based on Asterisk 18.2.0 LTS
- First 18.15.x official release
- Switched default PBX engine from Asterisk 16 LTS to Asterisk 18 LTS
- New Versioning template: 
  - izPBX 18.15.x = Latest release with Asterisk 18 LTS + FreePBX 15
  - izPBX 0.9.x   = Latest release with Asterisk 16 LTS + FreePBX 15 (not more supported)
### Fixed
- Chown freepbx and asterisk files every time on startup to avoid permission denied errors

## [0.9.14] - 2021-01-21
### Changed
- Asterisk 16.16.0
- Asterisk 18.2.0

## [0.9.13] - 2020-12-22
### Fixed
- Fixed SMTP SASL authentication problem

## [0.9.12] - 2020-11-26
### Changed
- Asterisk 16.15.0
- FOP2 2.31.29
- sngrep 1.4.8
### Added
- Asterisk 18.1.0 build in dev branch
- Added perl-DBI, perl-DBD-mysql used by fop2 recording_fop2.pl

## [0.9.11] - 2020-10-28
### Changed
- Asterisk 16.14.0
- enabled compile flag `--enable app_mysql` used by MySQL cidlookup
- implemented the $APP_DATA/.initialized file to detect an already installed system
- docker logs small refactoring
- fix FOP2 registering when missing default eth0 interface
- fix missing `/var/run/asterisk` needed by last FreePBX update
### Added
- updated `default.env` with
  - `APP_PORT_AMI=8088`

## [0.9.10] - 2020-09-23
### Changed
- defined release immutable image tag into docker-compose.yml
- upgrade mariadb from 10.4 to 1.5.5. remember to upgrade database schema with:
  - $ docker exec -it izpbx-db bash
  - $ mysql_upgrade -u root -p
### Added
- added phpMyAdmin support
- updated `default.env` with
  - NB. don't forget to accordingly update your `.env` file with the following lines:
  - `PMA_ALIAS=/admin/pma`
  - `PMA_ALLOW_FROM=127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16`

## [0.9.9] - 2020-09-20
### Changed
- new configuration variable: `SMTP_MAIL_FROM` for setting the From address of outgoing emails

## [0.9.8] - 2020-09-07
### Changed
- Asterisk 16.13.0
- FOP2 2.31.28
- added glibc-langpack-en to fix missing locale messages

## [0.9.7] - 2020-07-14
### Added
- DNSMASQ (DHCP+TFTP) service support
### Changed
- updated `default.env` with
  - NB. don't forget to accordingly update your `.env` file with the following lines:
  - `APP_PORT_DHCP=67`
  - `#DHCP_ENABLED=true`
  - `#DHCP_POOL_START=10.1.1.10`
  - `#DHCP_POOL_END=10.1.1.250`
  - `#DHCP_POOL_LEASE=72h`
  - `#DHCP_DOMAIN=izpbx.local`
  - `#DHCP_DNS=10.1.1.1`
  - `#DHCP_GW=10.1.1.1`
  - `#DHCP_NTP=10.1.1.1`
- updated `docker-compose.yml` with
  - NB. don't forget to accordingly update your `docker-compose.yml` file with the following lines:
  - `${APP_PORT_DHCP}:${APP_PORT_DHCP}/udp`
- renamed `TFTPD_ENABLED` into `TFTP_ENABLED`
### Removed
- tftp-server by kernel.org replaced with dnsmasq service

## [0.9.6] - 2020-07-01
### Added
- TFTPD Server support
### Changed
- updated `default.env` with `APP_PORT_TFTP` (don't forget to accordingly update your `.env` file)
- updated `docker-compose.yml` with `APP_PORT_TFTP`
- fix asterisk logs rotating

## [0.9.5] - 2020-06-25
### Added
- FOP2 automatic upgrade suppport
### Changed
- Asterisk 16.11.1

## [0.9.4] - 2020-05-15
### Added
- FOP2 license code management
### Changed
- updated `default.env`: added `FOP2_LICENSE_NAME`, `FOP2_LICENSE_CODE` (don't forget to accordingly update your `.env` file)

## [0.9.3] - 2020-04-30
### Changed
- Asterisk 16.10.0

## [0.9.2] - 2020-04-30
### Added
- Persistent root home dir support (to keep bash and asterisk console history)
- Eye candy customizations for doker shell

## [0.9.1] - 2020-04-10
### Changed
- fix typo

## [0.9.0] - 2020-04-08
### Added
- First Public Release
