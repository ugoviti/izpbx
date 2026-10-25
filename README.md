# Name
[<img src="https://www.initzero.it/images/initzero-logo-izpbx-48x48.png">](https://www.initzero.it) izPBX Cloud Native VoIP Telephony System

# Description
izPBX is a Turnkey Cloud Native VoIP Telephony System powered by Asterisk Engine and FreePBX Management GUI

# Supported tags

## Production Branch:
* `22.17`, `22.17.X`, `22.17.X-BUILD`, `22` (Asterisk 22 LTS + FreePBX 17, Debian 12, amd64 and arm64)

## Maintenance Branch (security fixes only, until 2027-01-01):
* `20.16`, `20.16.X`, `20.16.X-BUILD`, `20`, `latest` (Asterisk 20 LTS + FreePBX 16): `latest` stays here for now, use an explicit tag. To move from 20.16 to 22.17 see [Upgrade from 20.16 to 22.17](#upgrade-from-2016-to-2217)

## End of Life Branches (no more updates, don't use in production):
* `18.16`, `18.16.X`, `18.16.X-BUILD`,`18` (Asterisk 18 LTS + FreePBX 16)
* `18.15`, `18.15.X`, `18.15.X-BUILD` (Asterisk 18 LTS + FreePBX 15)
* `16.15`, `16.15.X`, `16.15.X-BUILD` (Asterisk 16 LTS + FreePBX 15)

## Development Branches:
* Asterisk 22 LTS + FreePBX 17: `dev-22.17`

## Version notes:
Tags format: **Z.Y.X-[BUILD]**

where:  
  * **Z** = Asterisk release (PBX engine)
  * **Y** = FreePBX release (PBX GUI)
  * **X** = izPBX release (this project)
  * **BUILD** = Build number

Look into project [Tags](https://hub.docker.com/r/izdock/izpbx-asterisk/tags) page to discover the latest versions

# Dockerfile
- https://github.com/ugoviti/izpbx/blob/main/izpbx-asterisk/Dockerfile

# Targets of this project
Cloud and On-Premise, Fast, Automatic and Repeatable deploy of VoIP PBX systems

# Features
- Fast initial bootstrap to deploy a full-featured PBX system (60 secs install time from zero to a running turnkey PBX system)
- Built-in PBX Engine based on Asterisk® project (compiled from scratch)
- Built-in WEB Management GUI based on FreePBX® project (with default predownloaded modules for quicker initial deploy)
- No vendor lock-in, you can migrate to and away from izPBX simply by importing/exporting FreePBX Backups
- Based on Rocky Linux 8 64bit OS (RHEL derivative with long term support)
- Small container image footprint (~450 MB vs 2300 MB of official FreePBX ISO distro file)
- Multi-Tenant PBX System Support (look into **Advanced Production Configuration Examples** section)
- Automatic Remote XML PhoneBook support for compatible VoIP Phones
- Persistent storage mode for configuration and non-volatile data
- Fail2ban as security monitor to block SIP and HTTP brute force attacks
- FOP2 Operator Panel
- Integrated Asterisk Zabbix agent for services health monitoring
- Misc `izpbx-*` tools scripts (like `izpbx-callstats`)
- `izsynth` utility - TTS/Text To Speech synthesizer, background music overlay assembler and audio file converter for PBX and Home Automation Systems
- `tcpdump` and `sngrep` utility to debug VoIP calls
- supervisord as services management with monitoring and automatic restart when services fail
- postfix MTA daemon for sending mails (notifications, voicemails and FAXes)
- Integrated cron daemon for running scheduled tasks
- Integrated TFTP and DHCP server powered by DNSMasq for autoprovisioning VoIP Phones
- Integrated NTP Server
- Apache 2.4 and PHP 7.4 (mpm_prefork+mod_php configuration mode)
- Automatic Let's Encrypt HTTPS certificate management for exposed PBXs to Internet
- Custom commercial SSL Certificates support
- Logrotating of service logs
- All configurations made via single central `.env` file
- Many customizable variables to use (look inside `default.env` file)
- Only two containers setup: (**Antipattern container design** but needed by the FreePBX ecosystem to work)
  - **izpbx** (izpbx-asterisk container: Asterisk Engine + FreePBX Frontend + other services)
  - **izpbx-db** (mariadb container: Database Backend)

# Screenshots
#### izPBX Dashboard (FreePBX):
![izpbx-dashboard](https://raw.githubusercontent.com/ugoviti/izpbx/main/izpbx-asterisk/screenshots/izpbx-dashboard.png)

#### izPBX Operator Panel (FOP2):
![izpbx-izpbx-operator-panel](https://raw.githubusercontent.com/ugoviti/izpbx/main/izpbx-asterisk/screenshots/izpbx-operator-panel.png)

#### izPBX Monitoring Dashboard (Zabbix):
![izpbx-zabbix-dashboard](https://raw.githubusercontent.com/ugoviti/izpbx/main/izpbx-asterisk/screenshots/izpbx-zabbix-dashboard.png)

#### izPBX CLI (Asterisk):
![izpbx-console](https://raw.githubusercontent.com/ugoviti/izpbx/main/izpbx-asterisk/screenshots/izpbx-cli.png)
  
# Deploy izPBX
Using **docker compose** is the suggested method:

- Install your preferred Linux OS into a VM or Baremetal Server

- Install Docker Runtime with `docker compose` plugin for your Operating System from https://www.docker.com/get-started
  - RHEL8 based distro Quick&Dirty commands (skip if you use other distribution):
```
sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install docker-ce docker-compose-plugin -y
sudo systemctl enable --now docker
```

- Create a `compose.yml`, or clone git repository, or download the latest tarball release from: https://github.com/ugoviti/izpbx/releases and unpack it into a directory (ex. `/opt/izpbx`), faster method with git:
  - `git clone https://github.com/ugoviti/izpbx.git /opt/izpbx`
  - `cd /opt/izpbx`

- Checkout into latest official release:
  - `git checkout tags/$(git tag | sort --version-sort | tail -1)`

- Copy default configuration file `default.env` into `.env`:
  - `cp default.env .env`

- Customize `.env` variables, especially the security section of default passwords:
  - `vim .env`

- Deploy and start izpbx using `docker compose` command:
  - `docker compose up -d`

- Wait for the pull to finish (~60 seconds with fast internet connections), then point your web browser to the IP address of your docker host and follow the initial setup guide

**Security:** by default the web interface (FreePBX, UCP and the `/pb` phonebook) accepts connections from any address (`HTTPD_ALLOW_FROM` not defined). If izPBX is reachable from the Internet, restrict `HTTPD_ALLOW_FROM` to trusted networks or put the web interface behind a VPN, and always use the latest izPBX release: it includes the latest PHP and Asterisk security fixes (ex. 20.16.22 fixes PHP CVE-2026-109618 and CVE-2026-109619).
Note that `MYSQL_PASSWORD` can't contain single quotes (`'`) or backslashes (`\`): they are not supported by the FreePBX installer.

**Note:** by default, to correctly handle SIP NAT and SIP-RTP UDP traffic, the izpbx container will use the `network_mode: host`, so the izpbx container will be exposed directly to the outside network without using docker internal network range (**network_mode: host** will prevent multiple izpbx containers from running inside the same host).  
Modify compose.yml and comment `#network_mode: host` if you want to run multiple izpbx containers in the same host (not production tested. There will be problems with RTP traffic).
Another available option is to disable `network_mode: host` and use **macvlan** network mode used for running izPBX into multi-tenant mode.

## Customizing compose.yml

If you need to customize the default `compose.yml`, don't edit it, but create an **override** file:

- `compose.override.yml`

and specify the options you want to override, for example:

```
services:
  db:
    image: docker.io/mariadb:10.11.19
  izpbx:
    image: docker.io/izdock/izpbx-asterisk:20.16.22
```

and start the deploy with the same command `docker compose up -d`

## Alternative deploy method via 'docker run' command (not suggested)
If you want to test izPBX without using docker compose command, you can use the following docker commands:

1. Start MySQL:  
`docker run --rm -ti -v ./data/db:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=CHANGEM3 -e MYSQL_PASSWORD=CHANGEM3 --name izpbx-db mariadb:10.11.19`

2. Start izPBX:  
`docker run --rm -ti --network=host --privileged --cap-add=NET_ADMIN -v ./data/izpbx:/data -e MYSQL_ROOT_PASSWORD=CHANGEM3 -e MYSQL_PASSWORD=CHANGEM3 -e MYSQL_SERVER=127.0.0.1 -e MYSQL_DATABASE=asterisk -e MYSQL_USER=asterisk -e APP_DATA=/data --name izpbx izpbx-asterisk:latest`

# Upgrade izPBX

> From izPBX 20.16.x (FreePBX 16) to 22.17.x (FreePBX 17) see [Upgrade from 20.16 to 22.17](#upgrade-from-2016-to-2217): it is not a plain image update.

1. Upgrade the version of izpbx by downloading a new tgz release, or changing image tag into **compose.yml** file (from git releases page, verify if upstream docker compose was updated), or if you cloned directly from GIT, use the following commands as quick method:
```
cd /opt/izpbx
git checkout main
git pull
git fetch --tags --all -f
git checkout tags/$(git tag | sort --version-sort | tail -1)
```

2. Upgrade the **izpbx** deploy with:  
(NB. **First** verify if `compose.yml` and `default.env` were updated and make the same changes in your `.env` file)
```
docker compose pull
docker compose up -d
```

3. If the mariadb database version was changed, remember to update the tables schema with the command  
  `source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD`

4. Open FreePBX Web URL and verify if any module updates exist from FreePBX Menu: **Admin --> Modules Admin --> Check Online --> Upgrade all --> Process**

That's all

### Upgrade path to a major FreePBX release
FreePBX will be installed into persistent data dir on initial deploy only (when no installations already exist).

Successive container updates on the same release (example from 18.15.1 to 18.15.2) will not upgrade the FreePBX Framework (only Asterisk engine will be updated).  

If you want to upgrade FreePBX Framework/Core to a major release (example from 15 to 16), you have 2 options:  
  
1. Automatic upgrade using izPBX container release (example, switching from 18.15.x to 18.16.x release)
2. Manual upgrade using **FreePBX Upgrader** tool

### method 1: Automatic upgrade using izPBX container release (suggested)
* Make sure before switching izPBX to a new major release, all FreePBX modules are updated to the latest release
* Make sure you made a full backup of `data` dir (IMPORTANT!)
* Make sure you enabled `FREEPBX_AUTOUPGRADE_CORE=true` in the `.env` file (not for FreePBX 16 to 17: see [Upgrade from 20.16 to 22.17](#upgrade-from-2016-to-2217))
* Deploy the latest version of izPBX (ex. 18.15.x for FreePBX 15, 18.16.x for FreePBX 16, etc...)
* izPBX should detect the old FreePBX version installed and start the upgrade process
* From the **FreePBX / Modules Admin** page, check if all modules have been updated and enable again the disabled modules

### method 2: Manual upgrade using FreePBX Upgrader tool
* Make sure before switching izPBX to a new major release, all FreePBX modules are updated to the latest release
* Make sure you made a full backup of `data` dir (IMPORTANT!)
* Make sure you disabled `FREEPBX_AUTOUPGRADE_CORE=false` in the `.env` file
* Deploy the latest version of izPBX (ex. 18.15.x for FreePBX 15, 18.16.x for FreePBX 16, etc...)
* izPBX should start with the old FreePBX release but with all dependencies installed and ready to complete the upgrade
* Open FreePBX Menu: **Admin --> Modules Admin --> Check Online** select **FreePBX Upgrader --> Process**
* Follow these instructions: https://wiki.freepbx.org/display/FOP/Non+Distro+-+Upgrade+to+FreePBX+16
* From the **FreePBX / Modules Admin** page, check if all modules have been updated and enable again the disabled modules

# Upgrade from 20.16 to 22.17

izPBX 22.17 moves from FreePBX 16 / Asterisk 20 on Rocky Linux to **FreePBX 17 / Asterisk 22 on Debian 12** (PHP 8.2 with php-fpm, services supervised by s6-overlay, amd64 and arm64 images). A volume created by izPBX 20.16 is migrated by the container itself, but only when you ask for it: it is not a plain image update.

The short version:

1. update to izPBX **20.16.22** and upgrade all FreePBX modules;
2. switch the image to 22.17 and run the **checks** (`izpbx-preflight`): fix what they report;
3. **back up** `data/` and the databases;
4. set `IZPBX_MIGRATE_FREEPBX=true` and start the container: it migrates, verifies the result and starts;
5. keep the **snapshot** in `data/izpbx/.izpbx-migration/` until you are sure: `izpbx-rollback` goes back to 20.16 from it.

### The migration is opt-in

izPBX 22.17 started on a volume of FreePBX 16 **without** `IZPBX_MIGRATE_FREEPBX=true` goes in **maintenance mode**: no service is started, the healthcheck reports unhealthy, `/data` and the databases are not changed, and the log says what to do. To keep running FreePBX 16 go back to the izPBX 20.16.x image that created the data. The same happens when a check blocks the migration.

`FREEPBX_AUTOUPGRADE_CORE` does not start the migration from FreePBX 16 to 17: only `IZPBX_MIGRATE_FREEPBX=true` does.

Variables of the migration (in `.env`):

| Variable | Default | Meaning |
|---|---|---|
| `IZPBX_MIGRATE_FREEPBX` | `false` | `true` migrates a FreePBX 16 volume to FreePBX 17 at the next start |
| `IZPBX_MIGRATE_IGNORE_MODULES` | empty | modules with no FreePBX 17 release to leave out (space separated): their data is **not** migrated |
| `IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN` | `false` | `true` migrates even if the custom dialplan uses applications Asterisk 22 no longer has |

### Before the migration

- **izPBX 20.16.22 with every module upgraded**: the migration needs a FreePBX 16 framework 16.0.26 or later (`fwconsole ma upgradeall` on 20.16.22). An installation whose first start never completed is refused: complete it on 20.16 first.
- **Custom dialplan**: Asterisk 22 has no `Macro()`, `Monitor()`, `ImportVar()`, `SetAMAFlags()`, `NoCDR()`. Rewrite them in your `*_custom.conf` files **before** the migration (`GoSub()` instead of `Macro()`, `MixMonitor()` instead of `Monitor()`). The checks list file and line of every use.
- **chan_sip**: Asterisk 22 has no chan_sip. Extensions and trunks on chan_sip are converted to PJSIP during the migration. izPBX 20.16 ran chan_sip on `APP_PORT_SIP` (5160): when the 16 had chan_sip extensions or trunks, the migration adds a PJSIP transport on that port and the converted trunks use it, so providers and phones that send to 5160 keep working. New 22.17 installations have no such transport.
- **Modules with no FreePBX 17 release** block the migration: remove them on 20.16 (`fwconsole ma remove <module>`) or list them in `IZPBX_MIGRATE_IGNORE_MODULES`. Known exceptions that do not block: `phonebook` (installed by default by izPBX 20.16) and `speeddial` (installations born on FreePBX 15): their entries and system speed dials go to Contact Manager (see below).
- **Commercial modules** are migrated: reactivate them with their license after the migration (the report lists them).
- **FOP2** is reinstalled from its Debian package at the first start (it needs Internet access); its configuration, license and settings database are kept.
- **Free space**: about 1.2 times the size of the databases, `var/www`, `var/lib/asterisk` and `var/spool/asterisk` (the recordings are hardlinked, they take no extra space). The checks compute it.
- **Database privileges**: the migration drops and recreates the FreePBX database. Keep `MYSQL_ROOT_PASSWORD` in `.env`, or give `MYSQL_USER` all privileges on it (the checks print the exact `GRANT`). The CDR database is not touched.

### 1. Switch the image and run the checks

Set the 22.17 image in `compose.yml` (always an explicit tag: `latest` stays on 20.16 for now) and pull it:

<!-- test:run -->
```sh
sed -i 's|izpbx-asterisk:20\.16\.[0-9]*|izpbx-asterisk:22.17.0|' compose.yml
```

```sh
docker compose pull izpbx
```

The checks only read the databases and the files: they can run while izPBX 20.16 is still up.

<!-- test:run -->
```sh
docker compose run --rm --no-deps --entrypoint izpbx-preflight izpbx
```

Every line is `<RESULT> <check>: <message>`. `OK` passed; `INFO` is what the migration will do (chan_sip conversion, commercial modules, MeetMe conferences moved to ConfBridge); `REMOVED` is a known exception left out on purpose; `BLOCK` stops the migration, and the message says how to fix it or which variable accepts it. The exit status is 0 when nothing blocks. The report is also saved in `data/izpbx/.izpbx-migration/preflight-<time>.txt`.

### 2. Back up

Stop izPBX and save the databases and `data/izpbx`:

<!-- test:run -->
```sh
docker compose stop izpbx
docker compose exec -T db sh -c 'mariadb-dump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --events --databases "$MYSQL_DATABASE" "$MYSQL_DATABASE_CDR"' | gzip > izpbx-20.16-db.sql.gz
tar -czf izpbx-20.16-data.tar.gz data/izpbx
```

### 3. Migrate

Enable the migration and start izPBX 22.17:

<!-- test:run -->
```sh
echo "IZPBX_MIGRATE_FREEPBX=true" >> .env
docker compose up -d izpbx
```

Follow it with `docker compose logs -f izpbx` (lines `migration: ...`), or wait until the container is healthy:

<!-- test:run -->
```sh
until docker compose ps --format '{{.Health}}' izpbx | grep -qx healthy; do sleep 10; done
```

What the container does, each phase recorded in `data/izpbx/.izpbx-migration/state`:

1. the checks again (a blocking problem: maintenance mode, nothing changed);
2. an inventory of FreePBX 16 (extensions, trunks, routes, queues, voicemail, recordings, astdb, ...);
3. the **snapshot** in `data/izpbx/.izpbx-migration/<time>/`: verified dumps of the databases, the FreePBX 16 directories moved there, the spool hardlinked;
4. FreePBX 17 installed with the modules of the 16, and a FreePBX backup of the 16 restored into it (chan_sip converted to PJSIP);
5. what the restore does not bring back: custom prompts and music on hold, astdb keys, the transport on `APP_PORT_SIP`, custom crontab lines, FOP2, `dongle.conf`, the phonebook;
6. the inventory again, compared with the one before: any unexpected difference stops the start in maintenance mode, with the differences in the log and in `data/izpbx/.izpbx-migration/verify-<time>.txt`.

A migration interrupted at any point (container killed, host restarted) resumes at the next start from the last completed phase. The migration of a large PBX (thousands of recordings, millions of CDR rows) takes minutes, not hours: nothing is copied but the databases.

### After the migration

The final report:

<!-- test:run -->
```sh
docker compose exec izpbx cat /data/.izpbx-migration/report.txt
```

- **Commercial modules**: reactivate the ones the report lists with their license.
- **Phonebook and speed dials**: the entries of the `phonebook` module of FreePBX 16 are in the Contact Manager group **"Phonebook (izPBX 20.16)"**; a system speed dial keeps its code and is dialed with the Contact Manager speed dial code: `*10<code>` (eg. `*1011`). Everything is also exported to `phonebook.csv` in the snapshot. The personal speed dials of the `speeddial` module have no FreePBX 17 equivalent: they are listed in `speeddials-users.csv` in the snapshot.
- **Phones and providers** on chan_sip keep sending to `APP_PORT_SIP` (5160): nothing to change on their side.
- `IZPBX_MIGRATE_FREEPBX=true` can stay in `.env`: once completed, the next starts are normal starts.
- **The snapshot** stays in `data/izpbx/.izpbx-migration/` and every start logs its size. Remove it when you no longer need to go back to 20.16 (eg. `rm -rf data/izpbx/.izpbx-migration/<time>`).

### Rollback to 20.16

As long as the snapshot is there, `izpbx-rollback` puts FreePBX 16 back: the database dump of the 16 is imported again and its directories go back in place (the FreePBX 17 database and directories are kept in `data/izpbx/.izpbx-migration/rollback-<time>/`). Stop izPBX and run it in a one-off container of the 22.17 image:

<!-- test:run -->
```sh
docker compose stop izpbx
docker compose run --rm --no-deps --entrypoint izpbx-rollback izpbx
```

Then remove `IZPBX_MIGRATE_FREEPBX=true` from `.env`, set the 20.16 image back and start it:

```sh
sed -i '/^IZPBX_MIGRATE_FREEPBX=/d' .env
sed -i 's|izpbx-asterisk:22\.17\.0|izpbx-asterisk:20.16.22|' compose.yml
docker compose up -d izpbx
```

Calls recorded and voicemail left while on 22.17 stay in the spool.

### Other changes in 22.17

- `ASTERISK_VER`, `FREEPBX_VER`, `FOP2_VER`, `ZABBIX_VER` are no longer build arguments: the versions come from `izpbx-asterisk/versions.env` (in the image: `/usr/src/izpbx/versions.env`). `FOP2_SHA256` and `ZABBIX_REL` no longer exist: the build verifies a sha256 per architecture.
- The 20.16 entrypoint variables `APP_RUNAS`, `MULTISERVICE`, `CMD_OVERRIDE`, `ENTRYPOINT_TINI` are ignored, with a warning at start if set (s6 starts the services). `UMASK` still applies, to the initialization and to every service.
- `FREEPBX_MODULES_EXTRA` no longer contains `phonebook` (no FreePBX 17 release).
- Debian paths for Apache, cron, PHP and phpMyAdmin: relevant only for custom scripts in `APP_CUSTOM_SCRIPTS`. `PMA_CONFIG` defaults to `/etc/phpmyadmin/config.inc.php`.
- Image tags: `22.17.0`, `22.17`, `22`; `latest` stays on 20.16 for now. arm64 images are available.

# Advanced Production Configuration Examples

### Multi-Tenant VoIP PBX with dedicated Databases

#### Objective
- Run many izPBX instances into single docker host (you must allocate an external static IP for every izPBX backend/frontend)
- Dedicated Database for every izPBX instances

#### Configuration
Create a directory where you want to deploy izpbx data and create `compose.yml` and `.env` files:

Example:
```
mkdir yourgreatpbx
cd yourgreatpbx
vim compose.yml
vim .env
```

NOTE:
- Modify `compose.yml` according to your environment needs:
  - `parent:` (must be your ethernet card)
  - `subnet:` (must match your intranet network range)
  - `ipv4_address:` (every izPBX frontend must have a different external IP)
- Modify `.env` according to your environment needs:
  - `MYSQL_SERVER=db` (you can't use localhost here)

```yaml
networks:
  izpbx-0-ext:
    driver: macvlan
    driver_opts:
      parent: eth0
    ipam:
      config:
      - subnet: 10.1.1.0/24
        #ip_range: "10.1.1.221/30"
        #gateway: 10.1.1.1
  izpbx-1:
    driver: bridge

services:
  db:
    image: mariadb:10.11.19
    ## WARNING: if you upgrade image tag enter the container and run mysql_upgrade:
    ## source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD
    command: --sql-mode=ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
    restart: unless-stopped
    env_file:
    - .env
    environment:
    - MYSQL_ROOT_PASSWORD
    - MYSQL_DATABASE
    - MYSQL_USER
    - MYSQL_PASSWORD
    ## database configurations 
    volumes:
    - ./data/db:/var/lib/mysql
    networks:
      izpbx-1:

  izpbx:
    #hostname: ${APP_FQDN}
    image: izdock/izpbx-asterisk:20.16.22
    restart: unless-stopped
    depends_on:
    - db
    env_file:
    - .env
    volumes:
    - ./data/izpbx:/data
    cap_add:
    - SYS_ADMIN
    - NET_ADMIN
    privileged: true
    networks:
      izpbx-0-ext:
        ipv4_address: 10.1.1.221
      izpbx-1:
```

Repeat the procedure for every izPBX you want to deploy. Remember to create a dedicated directory for every izpbx deploy.

#### Deploy
Enter every directory containing configuration files and run:
- `docker compose up -d`

### Multi-Tenant VoIP PBX with shared global Database and single compose.yml file

#### Objective
- Run many izPBX instances into single docker host (you must allocate an external static IP for every izPBX backend/frontend)
- Single Global Shared Database used by all izPBX instances

#### Configuration
Create a directory where you want to deploy all izpbx data and create `compose.yml` and a `PBXNAME.env` file for every izpbx deploy:

Example:
```
mkdir izpbx
cd izpbx
vim compose.yml
vim izpbx1.env
vim izpbx2.env
vim izpbx3.env
```
etc...

NOTE:
- Modify `compose.yml` according to your environment needs, changing:
  - `parent:` (must be your ethernet card)
  - `subnet:` (must match your intranet network range)
  - `ipv4_address:` (every izPBX frontend must have a different external IP)
- Remember to modify every `PBXNAME.env` file and set different variables for `MYSQL` (for best security use a different password for every deploy), example:
  - `MYSQL_SERVER=db` (all deploys will use the same db server)
  - `MYSQL_DATABASE=izpbx1_asterisk`
  - `MYSQL_DATABASE_CDR=izpbx1_asteriskcdrdb`
  - `MYSQL_USER=izpbx1_asterisk`
  - `MYSQL_PASSWORD=izpbx1_AsteriskPasswordV3ryS3cur3`
  - so on...

```yaml
networks:
  izpbx-0-ext:
    driver: macvlan
    driver_opts:
      parent: enp0s13f0u3u1u3
    ipam:
      config:
      - subnet: 10.1.1.0/24
  izpbx-1:
    driver: bridge

services:
  db:
    image: mariadb:10.11.19
    ## WARNING: if you upgrade image tag enter the container and run mysql_upgrade:
    ## source .env ; docker exec -it izpbx-db mysql_upgrade -u root -p$MYSQL_ROOT_PASSWORD
    command: --sql-mode=ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
    restart: unless-stopped
    env_file:
    - db.env
    environment:
    - MYSQL_ROOT_PASSWORD
    - MYSQL_DATABASE
    - MYSQL_USER
    - MYSQL_PASSWORD
    ## database configurations 
    volumes:
    - ./data/db:/var/lib/mysql
    networks:
      izpbx-1:

  izpbx1:
    #hostname: ${APP_FQDN}
    image: izdock/izpbx-asterisk:20.16.22
    restart: unless-stopped
    depends_on:
    - db
    env_file:
    - izpbx1.env
    volumes:
    - ./data/izpbx1:/data
    cap_add:
    - NET_ADMIN
    privileged: true
    networks:
      izpbx-0-ext:
        ipv4_address: 10.1.1.221
      izpbx-1:

  izpbx2:
    #hostname: ${APP_FQDN}
    image: izdock/izpbx-asterisk:20.16.22
    restart: unless-stopped
    depends_on:
    - db
    env_file:
    - izpbx2.env
    volumes:
    - ./data/izpbx2:/data
    cap_add:
    - NET_ADMIN
    privileged: true
    networks:
      izpbx-0-ext:
        ipv4_address: 10.1.1.222
      izpbx-1:

  izpbx3:
    #hostname: ${APP_FQDN}
    image: izdock/izpbx-asterisk:20.16.22
    restart: unless-stopped
    depends_on:
    - db
    env_file:
    - izpbx3.env
    volumes:
    - ./data/izpbx3:/data
    cap_add:
    - NET_ADMIN
    privileged: true
    networks:
      izpbx-0-ext:
        ipv4_address: 10.1.1.223
      izpbx-1:
```

#### Deploy
Enter the directory containing configuration files and run:
- `docker compose up -d`

# Services Management

### Command to restart whole izPBX deploy
`docker compose restart izpbx`

### Command to restart izPBX container only
`docker restart izpbx`

### Command to restart DB container only
`docker restart izpbx-db`

### If you want to restart single services inside `izpbx` container
Enter the container:  
`docker exec -it izpbx bash`

Restart izpbx service (Asterisk Engine):  
`supervisorctl restart izpbx`

To restart other available services use `supervisorctl restart SERVICE`

Available services:  
  - `asterisk`
  - `cron`
  - `fail2ban`
  - `fop2`
  - `httpd`
  - `izpbx`
  - `dnsmasq` (DHCP and TFTP)
  - `ntp`
  - `postfix`
  - `zabbix-agent`

# Tested systems and host compatibility
Tested Docker Runtime:
  - docker-ce >= 20.0
  - docker-compose-plugin >= 2.0

Tested Host Operating Systems:
  - RHEL 6/7/8/9 based distro
  - Fedora Core >30
  - Debian 10
  - Ubuntu 20.04

# Environment default variables
Consult the `default.env` file: 
  - https://github.com/ugoviti/izpbx/blob/main/default.env

# Zabbix Agent Configuration
Consult official repository page for installation and configuration of Asterisk Zabbix Template in your Zabbix Server:
- https://github.com/ugoviti/zabbix-templates/tree/main/asterisk

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
  * Schedule and Maintenance-->Enabled: **Yes**
  * Schedule and Maintenance-->Scheduling: Every: **Day** Minute: **00** Hour: **00**
  * Maintenance-->Delete After Runs: **0**
  * Maintenance-->Delete After Days: **14**

* **Admin-->Contact Manager**
  * External
    * Add New Group
      * Name: **PhoneBook**
      * Type: **External**
  
* **Admin-->Caller ID Lookup Sources**
  * Source Description: **ContactManager**
  * Source type: **Contact Manager**
  * Cache Results: **No**
  * Contact Manager Group(s): **All selected**
  
* **Admin-->Sound Languages-->Settings**
  * Global Language: **Italian**

# Configuring VoIP XML PhoneBook Lookup

- Visit **http://IZPBX_ADDRESS/pb/** to learn about the supported Phones and XML Address Books.

- Configure **Contact Manager** as reported above (create a new contact manager group name like **PhoneBook**)

## Define every PhoneBook you want to use
- Open your VoIP Phone GUI (example for Yealink Phones):
  - **Directory-->Remote Phone Book**
    - Index 1 (URL for Extensions PhoneBook)
      - RemoteURL: **http://IZPBX_ADDRESS/pb/yealink/ext**
      - Display Name: **Extensions**
    - Index 2 (URL for Corporate PhoneBook)
      - RemoteURL: **http://IZPBX_ADDRESS/pb/yealink/PhoneBook**
      - Display Name: **Corporate**

For Yealink / Fanvil phones you can use a single Phonebook Menu: **http://IZPBX_ADDRESS/pb/yealink/menu**

# FAQ / Troubleshooting
- FOP2 specific version upgrade/downgrade (get latest release number from https://www.fop2.com/download.php):
  automatic upgrade:
  ```
  FOP2_VER=2.31.53
  FOP2_SHA256=63b6a0ec011a41eaf7f70fda63282df501f27a67ac6ad8eec76e978f7025ace3 # sha256 of the downloaded release
  curl -fSL --connect-timeout 30 -o /tmp/fop2.tgz https://download2.fop2.com/fop2-$FOP2_VER-centos-x86_64.tgz
  echo "$FOP2_SHA256  /tmp/fop2.tgz" | sha256sum -c - && tar xzf /tmp/fop2.tgz -C /usr/src
  cd /usr/src/fop2
  make install
  supervisorctl restart fop2
  ```

  for manual downgrade just copy the fop2_server binary:
  ```
  cp /usr/src/fop2/server/fop2_server /usr/local/fop2/fop2_server
  supervisorctl restart fop2
  ```

- FOP2 useful commands:
    NB. define interface name to associate the license, for example: `eth0`
    - enter into izpbx container: `docker exec -it izpbx bash`
    - register the license: `/usr/local/fop2/fop2_server --rp=http --register --iface eth0 --name "Company Name" --code "LICENSECODE"`
    - get license details: `/usr/local/fop2/fop2_server --rp=http --getinfo --iface eth0`
    - reactivate the license: `/usr/local/fop2/fop2_server --rp=http --reactivate --iface eth0`
    - revoke the license: `/usr/local/fop2/fop2_server --rp=http --revoke --iface eth0`

- FOP2 is running in Demo mode because the license is invalid
  - FOP2 suffers from a bug in the licensing model (already reported many times to the FOP2 support without an official solution)
    to work around that problem, normally it is required to **reactivate** the license, but sometimes it doesn't work, so the only solution is to contact the FOP2 support team

- FreePBX is slow to reload (https://issues.freepbx.org/browse/FREEPBX-20559)
  - As temporary WORKAROUND enter into izpbx container shell and run:  
    `docker exec -it izpbx bash`  
    `fwconsole setting SIGNATURECHECK 0`

- Factory Reset izPBX (WARNING! your persistent storage will be wiped!):
  - `docker compose down`
  - `rm -rf data`
  - `docker compose up -d`
    
# TODO / Future Development
- Add ARM version compatible with Raspberry PI 
- Kubernetes deploy via Helm Chart (major problems for RTP UDP ports range... needs further investigation, no valid solutions right now)
- Hylafax+ Server + IAXModem (used for sending FAXes. Receiving FAXes via mail is already possible using FreePBX FAX Module)
- macOS host support? (edit `compose.yml` and comment localtime volume?)
- Windows host support (need to use docker volume instead local directory path?)

# BUGS and Limits of this project
- izPBX was developed with container antipattern design in mind.
  - FreePBX was not designed to run as containerized app, and its ecosystem requires numerous modules to work
  - FreePBX module updates are managed by FreePBX Admin Modules Pages itself not by izPBX container updates
- izPBX must be deployed by 1 instance for every VM or Baremetal host
  - No multi deploy works out of the box by default when using `network_mode: host`
  - Look **Advanced Production Configuration Examples** section for Multi-Tenant Solutions
- By default `network_mode: host` is used, so the PBX network is exposed directly in the host interface (no internal container network is used), so the default UDP RTP port range can be set from `10000` to `20000`.
  - If you plan to disable `network_mode: host`, tune the port range (forwarding 10000 ports with the docker stack causes high CPU usage and longer startup times), for example for 50 concurrent calls:  
`APP_PORT_RTP_START=10000`  
`APP_PORT_RTP_END=10200`  
for best security, fine-tune the ports range based on your needs by not using standard port ranges!  
- Unpredictable network interface order when running in Multi-Tenant mode. As workaround, network interfaces must be named in lexical order. refs:
  - https://gist.github.com/jfellus/cfee9efc1e8e1baf9d15314f16a46eca
  - https://github.com/moby/moby/issues/20179
- By default FreePBX uses Signature Checking for module packages, but this causes very long delays when reloading FreePBX, so by default it has been disabled. refs:
  - https://issues.freepbx.org/browse/FREEPBX-20559
- No commercial FreePBX modules can be installed
  - sysadmin rpm module is missing. Looking for a solution
- Missing good EndPoint Manager for automatic phone provisioning
  - Looking for a valid solution
  
# Quick reference
- **Developed and maintained by**:
  [Ugo Viti](https://github.com/ugoviti/izpbx) @ InitZero S.r.l.

- **Where to file issues**:
  [https://github.com/ugoviti/izpbx/issues](https://github.com/ugoviti/izpbx/issues)

- **Where to get commercial help**:
  email: [support@initzero.it](mailto:support@initzero.it) - web: [InitZero Support](https://www.initzero.it/)
  
- **Supported architectures**:
  [`amd64`]

- **Supported Docker versions**:
  [the latest release](https://github.com/docker/docker-ce/releases/latest) (down to 1.6 on a best-effort basis)

- **License**:
  [GPL v3](https://github.com/ugoviti/izpbx/blob/main/LICENSE)
