# Name
izPBX Cloud Native Telephony System

# Description
izPBX is a Cloud Native Telephony System powered by Asterisk Engine and FreePBX Management GUI

# Supported tags
* `16.9.X-BUILD, 16.9, 16, latest`
* `17.3.X-BUILD, 17.3, 17` (testing branch - not supported)

Where **X** is the patch version number, and **BUILD** is the build number (look into project [Tags](https://hub.docker.com/r/izdock/izpbx-asterisk/tags) page to discover the latest versions)

# Dockerfile
- https://github.com/ugoviti/izdock-izpbx/blob/master/izpbx-asterisk/Dockerfile

# Features
- 60 secs install from zero to a running full features PBX system.
- Really fast initial bootstrap to deploy a full stack Asterisk+FreePBX system
- Small image footprint
- Persistent storage mode for configuration data (define APP_DATA variable to enable)
- CentOS 8 64bit powered
- Asterisk PBX Engine (compiled from scratch)
- G729, Motif coded compiled
- FreePBX WEB Management GUI (with predownloaded modules for quicker initial deploy)
- First automatic installation managed when deploing the izpbx, subsequent updates managed by FreePBX Version Upgrade
- izpbx scripts (into container shell digit izpbx+TAB to discover)
- tcpdump and sngrep utility to debug VoIP packets
- fail2ban as security monitor to block SIP and HTTP brute force attacks
- supervisord as services management with monitoring and automatic restart
- postfix MTA daemon for sending mails (notifications, voicemails and FAXes)
- cron daemon
- Apache 2.4 and PHP 7.3
- Automatic Let's Encrypt HTTPS Certificate management for exposed PBXs to internet
- Logrotating of services logs
- FOP2 Operator Panel
- Asterisk Zabbix agent for active health monitoring
- All Bootstrap configurations made via single `.env` file
- Many customizable variables to use (look inside `default.env` file)
- Two containers setup:
  - izpbx-asterisk: Asterisk Engine + FreePBX Frontend (antipattern docker design but needed for the PBX ecosystem)
  - mariadb: Database Backend

# How to use this image

Using docker-compose is the suggested method:

- Clone GIT repository:

```
git clone https://github.com/ugoviti/izdock-izpbx.git
```

- Create file: `/etc/docker/daemon.json` (needed to manage SIP/RTP UDP traffic without nat of docker gateway)

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

Note: by default, to handle correctly SIP NAT and SIP-RTP UDP traffic, the izpbx container will use the `network_mode: host`, so the containers will be exposed directly to the outside without using docker internal network range. Modify docker-compose.yml to disable host network mode, and enable bridged network mode for the izpbx container.

# Deploy upgrade path

1. Verify your current running version
2. Upgrade the version of izpbx changing image tag into `docker-compose.yml` (verify for changes upstream in official repository and merge the differences)

Upgrading izpbx deploy must follow that path:

- 16.9.0 --> 16.9.x (initial release. no upgrade path right now)

# FreePBX upgrade path

FreePBX will be installed into persistent data dir only on first bootstrap (when no installations already exist).
Later container updates will not upgrade FreePBX. After initial install, Upgrading FreePBX Core and Modules is possibile only via official upgrade source path: menù **Admin-->Modules Admin: Check Online** select **FreePBX Upgrader**
Only asterisk core is upgraded on container upgrade.


# Environment default variables

```
## mandatory options
# WARNING: security passwords... please change the default
MYSQL_ROOT_PASSWORD=CHANGEM3
MYSQL_PASSWORD=CHANGEM3

# cron notifications mail address (default: root@localhost)
#ROOT_MAILTO=

# enable if the pbx is exposed to internet and want autoconfigure virtualhosting based on the following FQDN (default: none)
#APP_FQDN=sip.example.com

# enable https protocols (default: true)
# place your custom SSL certs in $APP_DATA/etc/pki/izpbx (use filename 'izpbx.crt' for public key and 'izpbx.key' for the private)
#HTTPD_HTTPS_ENABLED=true

# redirect unencrypted http connetions to https (default: false)
#HTTPD_REDIRECT_HTTP_TO_HTTPS=false

# enable if the pbx is exposed to internet and want generate an SSL Let's Encrypt certificates (default: false)
#LETSENCRYPT_ENABLED=false

# by default everyone can connect to HTTP/HTTPS WEB interface, comment out to restrict the access and enhance the security
#HTTPD_ALLOW_FROM=127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

# enable persistent external data storage (comment if you want disable persistence of data) (default: /data)
APP_DATA=/data

# database configurations
# WARNING: if the docker-compose use "network_mode: bridge" specify: db
#MYSQL_SERVER=db
# WARNING: if the docker-compose use "network_mode: host" specify: 127.0.0.1 or the address of the external database
MYSQL_SERVER=127.0.0.1
MYSQL_DATABASE=asterisk
MYSQL_USER=asterisk

## network ports
# webserver and freepbx ports
APP_PORT_HTTP=80
APP_PORT_HTTPS=443
# asterisk ports
APP_PORT_PJSIP=5060
APP_PORT_SIP=5160
APP_PORT_IAX=4569
APP_PORT_RTP_START=10000
APP_PORT_RTP_END=10200
APP_PORT_FOP2=4445
APP_PORT_ZABBIX=10050
# database port
APP_PORT_MYSQL=3306

# fail2ban (format: FAIL2BAN_SECTION_KEY=VALUE)
FAIL2BAN_ENABLED=true
FAIL2BAN_ASTERISK_ENABLED=true
#FAIL2BAN_ASTERISK_LOGPATH=/var/log/asterisk/security
#FAIL2BAN_DEFAULT_SENDER=fail2ban@example.com
#FAIL2BAN_DEFAULT_DESTEMAIL=security@example.com
FAIL2BAN_DEFAULT_IGNOREIP=127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
FAIL2BAN_DEFAULT_BANTIME=300
FAIL2BAN_DEFAULT_FINDTIME=3600
FAIL2BAN_DEFAULT_MAXRETRY=10
FAIL2BAN_RECIDIVE_ENABLED=true
FAIL2BAN_RECIDIVE_BANTIME=1814400
FAIL2BAN_RECIDIVE_FINDTIME=15552000
FAIL2BAN_RECIDIVE_MAXRETRY=10

## freepbx advanced settings (prefix every FreePBX variable with FREEPBX_)
# modules enabled on first startup
#FREEPBX_MODULES_EXTRA=soundlang callrecording cdr conferences customappsreg featurecodeadmin infoservices logfiles music manager arimanager filestore recordings announcement asteriskinfo backup callforward callwaiting daynight calendar certman cidlookup contactmanager donotdisturb fax findmefollow iaxsettings miscapps miscdests ivr parking phonebook presencestate printextensions queues cel timeconditions pm2
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

# WORKAROUND @20200322 https://issues.freepbx.org/browse/FREEPBX-20559 : fwconsole setting SIGNATURECHECK 0
FREEPBX_SIGNATURECHECK=0

## zabbix configuration
#ZABBIX_SERVER=127.0.0.1

# fop2 configuration (https://www.fop2.com/docs/)
#FOP2_LICENSE_CODE=<put here your license code>
## the following variables are not mandatory, you can leave commented
#FOP2_AMI_HOST=localhost
#FOP2_AMI_PORT=5038
#FOP2_AMI_USERNAME=admin
#FOP2_AMI_PASSWORD=amp111

# services
POSTFIX_ENABLED=true
CRON_ENABLED=true
HTTPD_ENABLED=true
IZPBX_ENABLED=true
FAIL2BAN_ENABLED=true
#ZABBIX_ENABLED=true
#FOP2_ENABLED=true
```

# FreePBX Configuration Best Practices

* **Settings-->Advanced Settings**
  * CW Enabled by Default: **NO**
  * Country Indication Tones: **Italy**
  * Ringtime Default: **60 seconds**
  * Speaking Clock Time Format: **24H**
  * PHP Timezone: **Europe/Rome**
  
* **Settings-->Asterisk Logfile Settings**
  * Security Settings-->Allow Anonymous Inbound SIP Calls: **No**
  * Security Settings-->Allow SIP Guests: **No**

* **Settings-->Asterisk SIP Settings**
  * File Name: **security**
  * Security: **ON** (all others OFF)
  
* **Settings-->Filestore-->Local**
  * Path Name: **Local Storage**
  * Path: **__ASTSPOOLDIR__/backup**

* **Admin-->Backup & Restore**
  * Basic Information-->Backup Name: **Daily Backup**
  * Notifications-->Email Type: **Failure**
  * Storage-->Storage Location: **Local Storage**
  * Schedule and Maintinence-->Enabled: **Yes**
  * Schedule and Maintinence-->Scheduling: Every: **Day** Minute: **00** Hour: **00**
  * Maintinence-->Delete After Runs: **0**
  * Maintinence-->Delete After Days: **14**
  
* **Admin-->Caller ID Lookup Sources**
  * Source Description: **ContactManager**
  * Source type: **Contact Manager**
  * Cache Results: **No**
  * Contact Manager Group(s): **All selected**
  
* **Admin-->Sound Languages-->Setttings**
  * Global Language: **Italian**

# Trobleshooting

- FreePBX is slow to reload
  - enter into container and run:
    `docker exec -it izpbx bash`
    `fwconsole setting SIGNATURECHECK 0`

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
