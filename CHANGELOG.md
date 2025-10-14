# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
