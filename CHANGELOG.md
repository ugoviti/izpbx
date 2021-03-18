# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [18.15.5] - 2021-03-18
### Changed
- Enhanced let's encrypt management and enabling automatic daily renew check via cronjob (/etc/cron.daily/freepbx-le-renew)
- Apache config rework
- Minor entrypoint improvements

## [18.15.4] - 2021-03-17
### Changed
- Enanched let's encrypt certificate generation using fwconsole tool (thanks to @alenas)
- New version of asterisk.sh zabbix agent script with better active calls detection (now will be ignored the calls in Ringing state)
- Container shell enhancements
- Added new variables into `default.env` (update your `.env` copy):
  - ZABBIX_HOSTNAME
  - ZABBIX_HOSTMETADATA

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
  - SMTP_STARTTLS=true

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
  - APP_PORT_AMI=8088

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
  - PMA_ALIAS=/admin/pma
  - PMA_ALLOW_FROM=127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

## [0.9.9] - 2020-09-20
### Changed
- new configuration variable: SMTP_MAIL_FROM for setting the From address of outgoing emails

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
  - APP_PORT_DHCP=67
  - #DHCP_ENABLED=true
  - #DHCP_POOL_START=10.1.1.10
  - #DHCP_POOL_END=10.1.1.250
  - #DHCP_POOL_LEASE=72h
  - #DHCP_DOMAIN=izpbx.local
  - #DHCP_DNS=10.1.1.1
  - #DHCP_GW=10.1.1.1
  - #DHCP_NTP=10.1.1.1
- updated `docker-compose.yml` with
  - NB. don't forget to accordingly update your `docker-compose.yml` file with the following lines:
  - ${APP_PORT_DHCP}:${APP_PORT_DHCP}/udp
- renamed TFTPD_ENABLED into TFTP_ENABLED
### Removed
- tftp-server by kernel.org replaced with dnsmasq service

## [0.9.6] - 2020-07-01
### Added
- TFTPD Server support
### Changed
- updated `default.env` with APP_PORT_TFTP (don't forget to accordingly update your `.env` file)
- updated `docker-compose.yml` with APP_PORT_TFTP
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
- updated `default.env`: added FOP2_LICENSE_NAME, FOP2_LICENSE_CODE (don't forget to accordingly update your `.env` file)

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
