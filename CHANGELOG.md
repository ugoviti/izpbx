# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
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
