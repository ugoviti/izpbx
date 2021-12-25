# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [18.16.2] - 2021-12-24
### Added
- Added `iproute` package (used by SIP Settings when binding interface to SIP channel driver)

## [18.16.1] - 2021-12-15
### Changed
- Updated engine to Asterisk 18.9.0 LTS (https://www.asterisk.org/asterisk-news/asterisk-18-9-0-now-available/)
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
- Updated database to MariaDB 10.6.5
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
