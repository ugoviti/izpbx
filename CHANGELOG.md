# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


## [0.9.6] - 2020-07-01
### Added
- TFTPD Server support

### Changed
- updated `default.env` with APP_PORT_TFTP (don't forget to accordingly update your `.env` file)
- updated `docker-compose.yml` with APP_PORT_TFTP
- fix asterisk logs rotating

### Removed
- nothing


## [0.9.5] - 2020-06-25
### Added
- FOP2 automatic upgrade suppport

### Changed
- Asterisk 16.11.1

### Removed
- nothing


## [0.9.4] - 2020-05-15
### Added
- FOP2 license code management

### Changed
- updated `default.env`: added FOP2_LICENSE_NAME, FOP2_LICENSE_CODE (don't forget to accordingly update your `.env` file)

### Removed
- nothing


## [0.9.3] - 2020-04-30
### Added
- nothing

### Changed
- Asterisk 16.10.0

### Removed
- nothing


## [0.9.2] - 2020-04-30
### Added
- Persistent root home dir support (to keep bash and asterisk console history)
- Eye candy customizations for doker shell

### Changed
- nothing

### Removed
- nothing


## [0.9.1] - 2020-04-10
### Added
- nothing

### Changed
- fix typo

### Removed
- nothing


## [0.9.0] - 2020-04-08
### Added
- First Public Release

### Changed
- nothing

### Removed
- nothing
