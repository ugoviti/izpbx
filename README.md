# Name
[<img src="https://www.initzero.it/images/initzero-logo-izpbx-48x48.png">](https://www.initzero.it) izPBX Cloud Native Telephony System

# Description
izPBX is a Turnkey Cloud Native Telephony System powered by Asterisk Engine and FreePBX Management GUI

# Supported tags

Production Branch (Asterisk 16 + FreePBX 15):
* `latest`, `0`, `0.9`, `0.9.X`, `0.9.X-BUILD`, `0.9.X-COMMIT`

Development Branches:
* `dev-16`, `dev-16.10`, `dev-16.10.X-BUILD`, `dev-16.10.X-COMMIT`
* `dev-17`, `dev-17.4`, `dev-17.4.X-BUILD`, `dev-17.4.X-COMMIT`

Where **X** is the patch version number, **COMMIT** is the GIT commit ID, and **BUILD** is the build number (look into project [Tags](https://hub.docker.com/r/izdock/izpbx-asterisk/tags) page to discover the latest versions)

# Dockerfile
- https://github.com/ugoviti/izdock-izpbx/blob/master/izpbx-asterisk/Dockerfile

# Features
- 60 secs install from zero to a running turnkey PBX system.
- Really fast initial bootstrap to deploy a full features Asterisk+FreePBX system
- CentOS 8 64bit powered
- Small image footprint
- Asterisk PBX Engine (compiled from scratch)
- FreePBX WEB Management GUI (with predownloaded modules for quicker initial deploy)
- Automatic installation managed when deploying izpbx for the first time, successive updates will be managed by FreePBX Official Version Upgrade
- Persistent storage mode for configuration and not volatile data
- Fail2ban as security monitor to block SIP and HTTP brute force attacks
- FOP2 Operator Panel (optional)
- Integrated Asterisk Zabbix agent for active health monitoring
- Misc `izpbx-*` scripts (like `izpbx-callstats`)
- izsynth utility - TTS/Text To Speech synthesizer, background music overlay assembler and audio file converter for PBX and Home Automation Systems
- tcpdump and sngrep utility to debug VoIP calls
- supervisord as services management with monitoring and automatic restart when services fail
- postfix MTA daemon for sending mails (notifications, voicemails and FAXes)
- Integrated cron daemon for running scheduled tasks
- Apache 2.4 and PHP 7.3 (mpm_prefork+mod_php configuration mode)
- Automatic Let's Encrypt HTTPS Certificate management for exposed PBXs to internet
- Custom commercial SSL Certificates support
- Logrotating of services logs
- All Bootstrap configurations made via single central `.env` file
- Many customizable variables to use (look inside `default.env` file)
- Two containers setup: (antipattern docker design but needed by the FreePBX ecosystem to works)
  - izpbx-asterisk: Asterisk Engine + FreePBX Frontend + others services
  - mariadb: Database Backend

# Targets of this project
- On-Premise fast, automatic a repeatable deploy of "small" PBX Systems (by default max 50 concurrent calls)

# Limits of this project
- On the Cloud single deploy for every VM. No multi containers setup works out of the box right now (caused by technical limits of how Docker and SIP UDP RTP traffic works)
- Docker Antipattern Design (FreePBX was not designed to run as containerized app, and its ecosystem requires numerous modules to function)
  
# How to use this image
Using **docker-compose** is the suggested method:

- Install your prefered Linux OS into VM or Baremetal Server

- Install Docker Runtime and docker-compose utility from https://www.docker.com/get-started for your Operating System.

- Update or create file `/etc/docker/daemon.json` with:  
(useful to avoid docker proxy NAT of packets. Needed to make SIP/RTP UDP traffic works without troubles)
```
{
  "userland-proxy": false
}
```

- Restart Docker Engine: `systemctl restart docker`

- Clone GIT repository or download latest release from: https://git.initzero.it/initzero/izdock-izpbx/releases and unpack it into a directory (ex. `/opt/izpbx`)

- Copy `default.env` file in `.env`: `cp default.env .env`

- Customize `.env` variables, specially the security section of mysql passwords

- Start izpbx deploy with: `docker-compose up -d`

- Wait 60 seconds and point your web browser to the IP address of your docker host and follow initial startup guide

Note: by default, to handle correctly SIP NAT and SIP-RTP UDP traffic, the izpbx container will use the `network_mode: host`, so the izpbx container will be exposed directly to the outside network without using docker internal network range.  
Modify docker-compose.yml and comment `#network_mode: host` if you need to run multiple izpbx deploy in the same host (not tested. there will be problems with RTP traffic).

# Restart services

### Command to restart Asterisk PBX
`docker restart izpbx`

### Command to restart MariaDB Database
`docker restart izpbx-db`

### If you want restart single services inside `izpbx` container
Enter the container:  
`docker exec -it izpbx bash`

Restart Asterisk+FreePBX Framework:  
`supervisorctl restart izpbx`

To restart the others available services use `supervisorctl restart SERVICE`

Available services:  
  - `asterisk`
  - `cron`
  - `fail2ban`
  - `fop2`
  - `httpd`
  - `izpbx`
  - `postfix`
  - `zabbix-agent`

# Tested systems and host compatibility
Tested Docker Runtime:
  - moby-engine 19.03
  - docker-ce 19.03
  - docker-compose 1.25

Tested Host Operating Systems:
  - CentOS 7
  - CentOS 8
  - Fedora Core 31
  - Debian 10

# Container deploy upgrade path

1. Upgrade the version of izpbx deploy changing image tag into **docker-compose.yml** file (from git releases page, verify if upstream docker compose was updated)

2. Upgrade the deploy with: 
```
docker-compose pull
docker-compose up -d
```

3. Open FreePBX Web URL and verify if exist modules updates from FreePBX Menù: **Admin-->Modules Admin: Check Online**

## FreePBX major release upgrade path
FreePBX will be installed into persistent data dir only on first bootstrap (when no installations already exist).

Later container updates will not upgrade FreePBX (just Asterisk engine will be updated).  
After initial deploy, upgrading FreePBX Core and Modules and Major Release (es. from 15.x to 16.x) is possible **only** via **official FreePBX upgrade method**:
  - FreePBX Menù: **Admin-->Modules Admin: Check Online** select **FreePBX Upgrader**

So, only Asterisk core engine will be updated on container image update.

# Environment default variables
```
# database configurations
# WARNING: security passwords... please change the default
MYSQL_ROOT_PASSWORD=CHANGEM3
MYSQL_PASSWORD=CHANGEM3

# WARNING: if the docker-compose use "network_mode: bridge" specify: db
#MYSQL_SERVER=db
# WARNING: if the docker-compose use "network_mode: host" specify: 127.0.0.1 or the address of a remote database
MYSQL_SERVER=127.0.0.1
MYSQL_DATABASE=asterisk
MYSQL_USER=asterisk

# enable persistent data storage (comment if you want disable persistence of data) (default: /data)
APP_DATA=/data

# cron notifications mail address (default: root@localhost)
#ROOT_MAILTO=

#SMTP SmartHost configuration. Specify DNS name or IP address for the SMTP RelayHost (default: none)
#SMTP_RELAYHOST=
#SMTP_RELAYHOST_USERNAME=
#SMTP_RELAYHOST_PASSWORD=
#SMTP_ALLOWED_SENDER_DOMAINS=
#SMTP_MESSAGE_SIZE_LIMIT=

# enable if the pbx is exposed to internet and want autoconfigure virtualhosting based on the following FQDN (default: none)
#APP_FQDN=sip.example.com

# enable https protocols (default: true)
# place your custom SSL certs in $APP_DATA/etc/pki/izpbx (use filename 'izpbx.crt' for public key and 'izpbx.key' for the private)
# by default izpbx will use a self-signed certificate
#HTTPD_HTTPS_ENABLED=true

# redirect unencrypted http connetions to https (default: false)
#HTTPD_REDIRECT_HTTP_TO_HTTPS=false

# auto generate Let's Encrypt SSL certificates if the pbx is exposed to internet and want enable https protocol (default: false)
#LETSENCRYPT_ENABLED=false

# by default everyone can connect to HTTP/HTTPS WEB interface, comment out to restrict the access and enhance the security (default: 0.0.0.0/0)
#HTTPD_ALLOW_FROM=127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

## fop2 configuration (https://www.fop2.com/docs/)
#FOP2_LICENSE_NAME=<put here your corporation name>
#FOP2_LICENSE_CODE=<put here your license code>
#FOP2_LICENSE_IFACE=docker0

# the following variables are not mandatory, you can leave commented (FOP2_AMI_PASSWORD will be a random hash)
#FOP2_AMI_HOST=localhost
#FOP2_AMI_PORT=5038
#FOP2_AMI_USERNAME=admin
#FOP2_AMI_PASSWORD=amp111

## zabbix configuration
#ZABBIX_SERVER=monitor.example.com

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
#FREEPBX_RSSFEEDS=

# WORKAROUND @20200322 https://issues.freepbx.org/browse/FREEPBX-20559 : fwconsole setting SIGNATURECHECK 0
FREEPBX_SIGNATURECHECK=0

## network ports
# webserver and freepbx ports
APP_PORT_HTTP=80
APP_PORT_HTTPS=443
# asterisk ports
APP_PORT_PJSIP=5160
APP_PORT_SIP=5060
APP_PORT_IAX=4569
APP_PORT_RTP_START=10000
APP_PORT_RTP_END=10200
APP_PORT_FOP2=4445
APP_PORT_ZABBIX=10050
# database port
APP_PORT_MYSQL=3306

# container services
POSTFIX_ENABLED=true
CRON_ENABLED=true
HTTPD_ENABLED=true
IZPBX_ENABLED=true
FAIL2BAN_ENABLED=true
#FOP2_ENABLED=true
#ZABBIX_ENABLED=true
```

# Zabbix Agent Configuration
Consult official repository page for installation and configuration of Asterisk Zabbix Template:
- https://github.com/ugoviti/zabbix-templates/tree/master/asterisk

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

- Start from scratch and cleanup the configurations
  - Simply remove the `data` directory created by deploy, and start over to make a new clean and empty installation
    
# TODO / Future Development
- Hylafax+ Server + IAXModem
- macOS host support? (edit docker-compose.yml and comment localtime volume?)
- Windows host support (need to use docker volume instead local directory path?)
- Kubernetes deploy via Helm Chart (major problems for RTP UDP ports range... needs further investigation)

# Quick reference
- **Developed and maintained by**:
  [Ugo Viti](https://github.com/ugoviti)

- **Where to file issues**:
  [https://github.com/ugoviti/izdock-izpbx/issues](https://github.com/ugoviti/izdock-izpbx/issues)

- **Where to get commercial help**:
  [InitZero Support](https://www.initzero.it/)
  
- **Supported architectures**:
  [`amd64`]

- **Supported Docker versions**:
  [the latest release](https://github.com/docker/docker-ce/releases/latest) (down to 1.6 on a best-effort basis)

- **License**:
  [GPL v3](https://github.com/ugoviti/izdock-izpbx/blob/master/LICENSE)
