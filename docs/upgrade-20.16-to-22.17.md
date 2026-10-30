# Upgrade from 20.16 to 22.17

izPBX 22.17 moves from FreePBX 16 / Asterisk 20 on Rocky Linux to **FreePBX 17 / Asterisk 22 on Debian 12** (PHP 8.2 with php-fpm, services supervised by s6-overlay, amd64 and arm64 images). A volume created by izPBX 20.16 is migrated by the container itself, but only when you ask for it: it is not a plain image update.

The short version:

1. update to izPBX **20.16.22** (the last 20.16, see the README of the [`release/20.16`](https://github.com/ugoviti/izpbx/tree/release/20.16) branch) and upgrade all FreePBX modules;
2. switch the image to 22.17 (`izpbx-deploy upgrade --major --apply`) and run the **checks** from the host, in the directory of `compose.yml` (`docker compose run --rm --no-deps --entrypoint izpbx-preflight izpbx`): fix what they report. The container runs the same checks by itself at every start on a 20.16 volume; running them first lets you read the report while 20.16 is still up;
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
| `IZPBX_MIGRATE_ACCEPT_CUSTOM_DIALPLAN` | `false` | `true` migrates even if the custom dialplan uses what Asterisk 22 no longer has and the migration cannot convert |

### Before the migration

- **izPBX 20.16.22 with every module upgraded**: the migration needs a FreePBX 16 framework 16.0.26 or later (`fwconsole ma upgradeall` on 20.16.22). An installation whose first start never completed is refused: complete it on 20.16 first.
- **Custom dialplan**: Asterisk 22 has no `Macro()` and no chan_sip. The migration converts by itself, in your `*_custom.conf` files and in the files they `#include` (eg. `qhd/on-call.conf`, copied with its directory): `Macro(name,args)` to `Gosub(macro-name,s,1(args))` and `MacroExit()` to `Return()` (as FreePBX 17 does with its own macros, so a `[macro-dialout-trunk-predial-hook]` keeps working), a `Return()` at the end of a `[macro-*]` extension that had none, `SIPAddHeader(Alert-Info: x)` to `Set(__ALERT_INFO=x)` and other headers to `Set(HASH(__SIPHEADERS,Header)=value)`, `MessageSend(sip:` to `MessageSend(pjsip:`. The checks list every change, the report keeps them (`dialplan-<time>.txt`), the files of 20.16 stay in the snapshot. What cannot be converted blocks: `${MACRO_EXTEN}` and the other `MACRO_` variables, `Monitor()` (use `MixMonitor()`), `ImportVar()`, `SetAMAFlags()`, `NoCDR()`, chan_sip functions (`SIP_HEADER`, `SIPDtmfMode`, ...) and `SIP/` channels: rewrite them **before** the migration. `izpbx-dialplan-convert --check FILE...` shows the conversion of any file.
- **chan_sip**: Asterisk 22 has no chan_sip. Extensions and trunks on chan_sip are converted to PJSIP during the migration. izPBX 20.16 ran chan_sip on `APP_PORT_SIP` (5160): when the 16 had chan_sip extensions or trunks, the migration adds a PJSIP transport on that port and the converted trunks use it, so providers and phones that send to 5160 keep working. New 22.17 installations have no such transport.
- **Modules with no FreePBX 17 release** block the migration: remove them on 20.16 (`fwconsole ma remove <module>`) or list them in `IZPBX_MIGRATE_IGNORE_MODULES`. Known exceptions that do not block: `phonebook` (installed by default by izPBX 20.16) and `speeddial` (installations born on FreePBX 15): their entries and system speed dials go to Contact Manager (see below).
- **Commercial modules** are migrated: reactivate them with their license after the migration (the report lists them).
- **FOP2** is reinstalled from its Debian package at the first start (it needs Internet access); its configuration, license and settings database are kept.
- **Without Internet access** the migration completes: the FreePBX 17 modules of the image install offline, the system prompts of every language come from the snapshot. FOP2 and modules that are not in the image need Internet (they are downloaded from the FreePBX repositories): without it the migration stops naming them, and the next start with Internet resumes it. A *new installation* without Internet starts without the system prompts: FreePBX downloads them (Admin > Sound Languages) once the PBX can reach the Internet.
- **Free space**: about 1.2 times the size of the databases, `var/www`, `var/lib/asterisk` and `var/spool/asterisk` (the recordings are hardlinked, they take no extra space). The checks compute it.
- **Database privileges**: the migration drops and recreates the FreePBX database. Keep `MYSQL_ROOT_PASSWORD` in `.env`, or give `MYSQL_USER` all privileges on it (the checks print the exact `GRANT`). The CDR database is not touched.

### 1. Switch the image and run the checks

Switch to the 22.17 image (always an explicit version: `latest` stays on 20.16 for now) with `izpbx-deploy`, on the host, in the directory of `compose.yml` (eg. `/opt/izpbx`). The image `22.17` is the last 22.17.x release: it adds `IZPBX_VERSION` (its exact version) and the new variables of 22.17 to `.env` (your values stay) and replaces the 20.16 `compose.yml` with the one of 22.17 (it reads the version from `.env`: `izpbx-asterisk:${IZPBX_VERSION}`). The old files stay next to the new ones (`.env.YYYYmmdd-HHMMSS.bak`, `compose.yml.YYYYmmdd-HHMMSS.bak`): move the local changes of your 20.16 `compose.yml` (networks, ports, volumes) to `compose.override.yml`. Without `--apply` it only shows the changes; `--major` is needed because 20.16 -> 22.17 is a new version series (see [izpbx-deploy](izpbx-deploy.md)):

<!-- test:run -->
```sh
docker run --rm --pull always -v "$PWD:/deploy" docker.io/izdock/izpbx-asterisk:22.17 izpbx-deploy upgrade --major --apply
```

Check the summary it prints: the values of your `.env` that differ from the new `default.env` are listed (they are kept).

```sh
docker compose pull izpbx
```

Then run the checks **on the host, in the directory of `compose.yml`** (eg. `/opt/izpbx`): `docker compose run` starts a one-off container of the 22.17 image (`--rm`: removed when it ends) with the same `.env`, volume and database as the `izpbx` service, and runs `izpbx-preflight` in it instead of the PBX (`--entrypoint`; `--no-deps`: the database container is not touched). The checks only read the databases and the files: they can run while izPBX 20.16 is still up.

<!-- test:run -->
```sh
docker compose run --rm --no-deps --entrypoint izpbx-preflight izpbx
```

Every line is `<RESULT> <check>: <message>`. `OK` passed; `INFO` is what the migration will do (chan_sip conversion, commercial modules, MeetMe conferences moved to ConfBridge); `REMOVED` is a known exception left out on purpose; `BLOCK` stops the migration, and the message says how to fix it or which variable accepts it. The exit status is 0 when nothing blocks. The report is also saved in `data/izpbx/.izpbx-migration/preflight-<time>.txt`.

You do not have to run them by hand: izPBX 22.17 runs the same checks by itself at every start on a 20.16 volume, before changing anything. Without `IZPBX_MIGRATE_FREEPBX=true`, or when a check blocks, the container stays in maintenance mode and the report is in `docker compose logs izpbx` and in the same `preflight-<time>.txt`; with the opt-in and nothing blocking, the migration starts. Running them by hand first only lets you read the report before stopping 20.16.

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
5. what the restore does not bring back: the system and custom prompts and the music on hold, astdb keys (hints and dial strings of the ex chan_sip extensions on PJSIP), the transport on `APP_PORT_SIP`, custom crontab lines, FOP2, `dongle.conf`, the phonebook;
6. the inventory again, compared with the one before: any unexpected difference stops the start in maintenance mode, with the differences in the log and in `data/izpbx/.izpbx-migration/verify-<time>.txt`.
7. FreePBX 17 reloads the migrated configuration (`fwconsole reload`, which also writes the dialplan and the hints): a file it refuses stops the start in maintenance mode too, with the error in the log.

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
- **ARI**: the restore puts `ENABLE_ARI` back to the FreePBX 17 default; the report says so when it was enabled on 20.16: enable it again in Advanced Settings if you use ARI.
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
sed -i 's|^IZPBX_VERSION=.*|IZPBX_VERSION=20.16.22|' .env
docker compose up -d izpbx
```

Calls recorded and voicemail left while on 22.17 stay in the spool.

### Other changes in 22.17

- `ASTERISK_VER`, `FREEPBX_VER`, `FOP2_VER`, `ZABBIX_VER` are no longer build arguments: the versions come from `izpbx-asterisk/versions.env` (in the image: `/usr/src/izpbx/versions.env`). `FOP2_SHA256` and `ZABBIX_REL` no longer exist: the build verifies a sha256 per architecture.
- The 20.16 entrypoint variables `APP_RUNAS`, `MULTISERVICE`, `CMD_OVERRIDE`, `ENTRYPOINT_TINI` are ignored, with a warning at start if set (s6 starts the services). `UMASK` still applies, to the initialization and to every service.
- `FREEPBX_MODULES_EXTRA` no longer contains `phonebook` (no FreePBX 17 release).
- Debian paths for Apache, cron, PHP and phpMyAdmin: relevant only for custom scripts in `APP_CUSTOM_SCRIPTS`. `PMA_CONFIG` defaults to `/etc/phpmyadmin/config.inc.php`.
- The Asterisk built-in HTTP server (ARI, WebSocket, WebRTC) listens on `127.0.0.1` only, the FreePBX 17 default: set `FREEPBX_HTTPBINDADDRESS=0.0.0.0` (and `FREEPBX_HTTPTLSBINDADDRESS=0.0.0.0`) to reach it from the network, behind a firewall.
- `APP_PORT_UCP_HTTP` / `APP_PORT_UCP_HTTPS` set the ports of the UCP node server (FreePBX `NODEJSBINDPORT` / `NODEJSHTTPSBINDPORT`); with `network_mode: host` they must be free on the host.
- The image versions are in `.env` (`IZPBX_VERSION`, `MARIADB_VERSION`), read by `compose.yml`.
- Image tags: `22.17.X` (every release), `22.17`, `22`; `latest` stays on 20.16 for now. Images for amd64 and arm64 (20.16 is amd64 only).
