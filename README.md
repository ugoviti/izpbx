# Name
izPBX Cloud Native Telephony System

# Description
(TESTING PHASE) izPBX is a Cloud Native Telephony System powered by Asterisk Engine and FreePBX Management GUI

# Supported tags
* `16.9.X-BUILD, 16.9, 16, latest`
* `17.3.X-BUILD, 17.3, 17`

Where **X** is the patch version number, and **BUILD** is the build number (look into project [Tags](/repository/docker/izdock/httpd/tags/) page to discover the latest versions)

# Dockerfile
- https://github.com/ugoviti/izdock-izpbx/blob/master/izpbx-asterisk/Dockerfile


# Features
- CentOS 8 powered
- Small image footprint
- Built from scratch Asterisk engine
- FreePBX Engine as Web Management GUI
- Persistent storage for configuration data
- Automatic HTTPS Certificate management via Let's Encrypt service
- Send out emails via local postfix smtp daemon
- Security and bruteforce SIP attacks detection managed by fail2ban service
- First automatic installation managed when deploing the izpbx, subsequent updates managed by FreePBX Version Upgrade
- All Bootstrap configurations made via single `.env` file
- Many customizable variables to use (look inside `default.env` file)
- Two containers setup:
  - izpbx-asterisk (Asterisk Engine + FreePBX Frontend)
  - mariadb (Database Backend)

# How to use this image

Using docker-compose is the suggested method:

- Clone GIT repository:

```
git clone https://github.com/ugoviti/izdock-izpbx.git
```

- Create file: `/etc/docker/daemon.json`

```
{
  "userland-proxy": false
}
```

- Restart Docker Engine: `systemctl restart docker`

- Copy `default.env` in `.env` and edit the variables inside:

```
cp default.env .env
```

- Customize `.env` veriables, specially mysql passwords

- Start izpbx deploy with:

```
docker-compose up -d
```

# Environment default variables

```
## mandatory options
# WARNING: security passwords... please change the default
MYSQL_ROOT_PASSWORD=CHANGEM3
MYSQL_PASSWORD=CHANGEM3

# if the pbx is exposed to internet and want generate autoconfigure virtualhosting based on the following FQDN (default: none)
#APP_FQDN=pbx.example.com

# enable https protocols (default: true)
#HTTPS_ENABLED=true
# if the pbx is exposed to internet and want generate an SSL Let's Encrypt certificates (default: false)
#LETSENCRYPT_ENABLED=true
# redirect unencrypted http connetions to https (default: false)
#HTTP_REDIRECT_TO_HTTPS=true

# Cron notifications mail address (default: root@localhost)
#ROOT_MAILTO=

# persistent external data (comment if you want disable persistence of data) (default: /data)
APP_DATA=/data

## network ports
# freepbx configurations
APP_PORT_HTTP=80
APP_PORT_HTTPS=443
# asterisk configurations
APP_PORT_PJSIP=5060
APP_PORT_SIP=5160
APP_PORT_IAX=4569
APP_PORT_RTP_START=10000
APP_PORT_RTP_END=10100
APP_PORT_FOP=4445
# database configurations (WARNING: if you comment out, will expose database port outside the container)
APP_PORT_MYSQL=3306

# database configurations
MYSQL_SERVER=db
MYSQL_DATABASE=asterisk
MYSQL_USER=asterisk

# fail2ban (format: FAIL2BAN_SECTION_KEY=VALUE)
FAIL2BAN_ENABLED=true
FAIL2BAN_ASTERISK_ENABLED=true
FAIL2BAN_DEFAULT_SENDER=fail2ban@example.com
FAIL2BAN_DEFAULT_DESTEMAIL=security@example.com
FAIL2BAN_DEFAULT_IGNOREIP=127.0.0.0/8
FAIL2BAN_DEFAULT_BANTIME=300
FAIL2BAN_DEFAULT_FINDTIME=3600
FAIL2BAN_DEFAULT_MAXRETRY=10
FAIL2BAN_RECIDIVE_ENABLED=true
FAIL2BAN_RECIDIVE_BANTIME=1814400
FAIL2BAN_RECIDIVE_FINDTIME=15552000
FAIL2BAN_RECIDIVE_MAXRETRY=10

# freepbx advanced settings (prefix every FreePBX variable with FREEPBX_)
FREEPBX_FREEPBX_SYSTEM_IDENT=izPBX
FREEPBX_AS_DISPLAY_READONLY_SETTINGS=1
FREEPBX_AS_OVERRIDE_READONLY=1
FREEPBX_ENABLECW=0
FREEPBX_TONEZONE=it
FREEPBX_PHPTIMEZONE=Europe/Rome
#FREEPBX_BRAND_IMAGE_TANGO_LEFT=images/tango.png
#FREEPBX_BRAND_IMAGE_FREEPBX_FOOT=images/freepbx_small.png
#FREEPBX_BRAND_IMAGE_SPONSOR_FOOT=images/sangoma-horizontal_thumb.png
#FREEPBX_BRAND_FREEPBX_ALT_LEFT=FreePBX
#FREEPBX_BRAND_FREEPBX_ALT_FOOT=FreePBX®
#FREEPBX_BRAND_SPONSOR_ALT_FOOT=www.sangoma.com
#FREEPBX_BRAND_IMAGE_FREEPBX_LINK_LEFT=http://www.freepbx.org
#FREEPBX_BRAND_IMAGE_FREEPBX_LINK_FOOT=http://www.freepbx.org
#FREEPBX_BRAND_IMAGE_SPONSOR_LINK_FOOT=http://www.sangoma.com

# WORKAROUND @20200322 https://issues.freepbx.org/browse/FREEPBX-20559
FREEPBX_SIGNATURECHECK=0

# services
POSTFIX_ENABLED=true
CRON_ENABLED=true
HTTPD_ENABLED=true
IZPBX_ENABLED=true
FAIL2BAN_ENABLED=true
# FOP2 WIP
#FOP2_ENABLED=false
```

# FreePBX Best Practices

  * **Settings-->Advanced Settings**
    * CW Enabled by Default: **NO**
    * Country Indication Tones: **Italy**
    * Ringtime Default: **60 seconds*
    * Speaking Clock Time Format: **24H**
    * PHP Timezone: **Europe/Rome**
  * **Settings-->Asterisk Logfile Settings**
    * File Name: **security**
    * Security: **ON** (all others OFF)
  * **Admin-->Caller ID Lookup Sources
    * Source Description: **ContactManager**
    * Source type: **Contact Manager**
    * Cache Results: **No**
    * Contact Manager Group(s): **All selected**
  * **Admin-->Sound Languages-->Setttings
    * Global Language: **Italian**

# Quick reference

- **Where to get help**:
  [InitZero Corporate Support](https://www.initzero.it/)

- **Where to file issues**:
  [https://github.com/ugoviti/izdock-izpbx/issues](https://github.com/ugoviti/izdock-izpbx/issues)

- **Maintained by**:
  [Ugo Viti](https://github.com/ugoviti)

- **Supported architectures**:
  [`amd64`]

- **Supported Docker versions**:
  [the latest release](https://github.com/docker/docker-ce/releases/latest) (down to 1.6 on a best-effort basis)
