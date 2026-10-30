# Workarounds for third-party defects
izPBX 22.17 works around a number of bugs and quirks of FreePBX 17, Asterisk 22, FOP2 and the Debian 12 packages. This file lists them, so that each one can be dropped when its upstream gets fixed. Check the list at every component update (see [maintainers.md](maintainers.md)): the **Remove when** line of each item is the concrete test that tells whether it is still needed.

Versions when the list was written: Asterisk 22.11.0, FreePBX framework 17.0.33 (core 17.0.18.54, backup 17.0.13, ucp 17.0.10, pm2 17.0.3.4), FOP2 2.31.53, Debian 12 (fail2ban 1.0.2, chrony 4.3, Node 18, PHP 8.2), MariaDB 10.11.19. Paths are relative to `izpbx-asterisk/`; `Pn-nn` are the checks in `tests/checks/` that cover each item.

Items marked **permanent** compensate the container itself (no systemd) or a Debian packaging choice, not a bug: they stay.

## FreePBX installer and framework

### The installer exits 1 even when it succeeds
- **Defect**: the 17.0.33 installer returns 1 even when it prints "You have successfully installed FreePBX".
- **izPBX**: ignores the exit code and looks for the success line in the install log.
- **Where**: `rootfs/usr/local/lib/izpbx/services/freepbx.sh`, `_fpbx_install_once`.
- **Tests**: P3-19, P3-21.
- **Remove when**: `php install -n ...` on an empty database returns 0.

### Installer race "Undefined property: FreePBX::$Certman" and a half install that a second run cannot repair
- **Defect**: the installer builds a module (certman, fax) while that module is still being loaded, and PHP stops. The failed attempt leaves tables and `freepbx.conf` behind, and a second run does not fix them (for example, voicemail registered without its tables).
- **izPBX**: up to 5 attempts (`IZPBX_FREEPBX_INSTALL_TRIES`). On a database that was empty before the install, the tables and `freepbx.conf`/`amportal.conf` are removed before each new attempt.
- **Where**: `freepbx.sh`, `freepbx_install` and `_fpbx_reset_attempt`.
- **Tests**: P3-30.
- **Remove when**: the installer never fails across many CI runs (with the `_fpbx_test_fail` hook off), or it becomes idempotent.

### The FreePBX file cache of another installation breaks the installer
- **Defect**: the `modulelist_modules` cache in `ASTSPOOLDIR/cache`, written by FreePBX 16 or by a failed attempt, stays valid for a few minutes. Its modules count as enabled whatever the database says, which causes the same crash as above.
- **izPBX**: removes `ASTSPOOLDIR/cache` before each install attempt.
- **Where**: `freepbx.sh`, `_fpbx_install_once`.
- **Tests**: P3-30.
- **Remove when**: the installer ignores the file cache on an empty database. The P3-30 fixture, with the cache made valid until 2100, migrates without the `rm`.

### The installer writes the database password into PHP without escaping it
- **Defect**: a password with `'`, `\\` or a final `\` produces a `freepbx.conf` that PHP cannot parse.
- **izPBX**: refuses to start with a clear error when `MYSQL_PASSWORD` has one of them.
- **Where**: `freepbx.sh`, `freepbx_install`.
- **Tests**: P3-21.
- **Remove when**: an install with `MYSQL_PASSWORD="a'b\\"` gives a `freepbx.conf` that `php -l` accepts.

### The installer takes the password only on the command line
- **Defect**: `--dbpass` puts the password in the process list. Running `install` through `require` fails, because its `#!` line comes before `namespace`.
- **izPBX**: `rootfs/usr/local/share/izpbx/freepbx-install.php` adds `--dbpass` from the environment and loads a copy of `install` without the shebang.
- **Tests**: P3-21.
- **Remove when**: the installer reads the password from the environment, a file or stdin.

### The installer ignores the directory options; `fwconsole chown` does not follow symlinks
- **Defect**: some paths are taken from `asterisk.conf` (the symlinks) whatever `--astetcdir` and similar options say.
- **izPBX**: passes the real `/data/...` paths, then writes the path settings again with `fwconsole setting` after the install and at every start.
- **Where**: `freepbx.sh`, `freepbx_dir`, `freepbx_dir_options`, `freepbx_fix_paths`.
- **Tests**: P3-19, P3-26.
- **Remove when**: right after the install, `fwconsole setting ASTETCDIR` already shows `/data/etc/asterisk`.

### `freepbx.conf` written root:root 0660
- **Defect**: `freepbx.conf` (a symlink to `/data`) is created root:root 0660, and `fwconsole chown` does not follow the symlink, so php-fpm and fwconsole (as asterisk) cannot read it.
- **izPBX**: changes the owner of the symlink targets to asterisk.
- **Where**: `freepbx.sh`, `_fpbx_install_once`.
- **Tests**: P3-19.
- **Remove when**: the file is readable by asterisk right after the install.

### `fwconsole` as root exits 1 even when it succeeds
- **Defect**: `ma install`, `reload` and similar commands return 1 as root even when they worked.
- **izPBX**: runs them as asterisk through `fwconsole_as_asterisk` (`freepbx.sh`).
- **Tests**: P0-10, P3-19.
- **Remove when**: `fwconsole reload; echo $?` as root prints 0. The umask 002 of the same function stays (P3-26).

### `fwconsole ma install X` exits 0 when it fails
- **Defect**: "Cannot find module" and other failures return 0. During a migration a missing module (setcid on pbx01) was skipped and its data lost.
- **izPBX**: reads the result from `fwconsole ma list`. During a migration it then tries `ma downloadinstall`, and stops if the module is still missing.
- **Where**: `freepbx.sh` (new installation); `services/migration.sh`, `_migration_module_enabled`, `migration_restore`.
- **Tests**: P4-36, P3-19.
- **Remove when**: `fwconsole ma install doesnotexist; echo $?` prints a value other than 0. Keeping the check is harmless.

### FreePBX needs `/etc/machine-id`
- **Defect**: without it `shell_exec` returns null, and the PHP 8.2 deprecation in `preg_replace` becomes an exception during the install.
- **izPBX**: writes a machine-id when it is missing.
- **Where**: `freepbx.sh`, `_fpbx_install_once`.
- **Remove when**: an install in a container without `/etc/machine-id` works.

### Notice "Sangoma Debian Repository GPG Key Expiring Soon"
- **Defect**: every install or upgrade of framework checks the key of the Sangoma apt repository, which izPBX does not use, and tries to write it in `/etc/apt/trusted.gpg.d` as asterisk. That fails and leaves the notice "in 0 days, on unknown".
- **izPBX**: the image has the key (`rootfs/etc/apt/trusted.gpg.d/freepbx.gpg`, valid until 2028-02-11, see `Dockerfile`), and the notice is removed at every start (`freepbx.sh`, `freepbx_notices_cleanup`).
- **Tests**: P3-37. It fails by itself within 30 days of the key expiry.
- **Remove when**: framework stops checking the apt key on systems without the Sangoma repository. **Before 2028-01-12**: replace the key with the current `http://deb.freepbx.org/gpg/aptly-pubkey.asc`, dearmored.

### Notice "Updated Asterisk Mini HTTP Server Bind Address to Localhost"
- **Defect**: on a new install, core moves the bind address from `::` to 127.0.0.1 and says it "updated" it, although nobody had configured it.
- **izPBX**: removes `core core_bindaddress_changed` on a new install and after the restore of a migration.
- **Where**: `freepbx.sh`, `freepbx_notices_cleanup`; `migration.sh`, `migration_restore`.
- **Tests**: P3-37.
- **Remove when**: a new install no longer has the notice in `fwconsole notifications --list`.

### `include` of `*-custom` contexts that nobody defines
- **Defect**: about 130 `include =>` lines of the FreePBX dialplan point at missing contexts, with one Asterisk WARNING each at every reload.
- **izPBX**: generates `freepbx_custom_fix_missing_contexts.conf` with those contexts empty.
- **Where**: `freepbx.sh`, `freepbx_missing_contexts`.
- **Tests**: P3-41.
- **Remove when**: `dialplan reload` on a new install, without that file, writes no "nonexistent context" warnings.

### `fwconsole reload` copies the AGI scripts again with their own mode
- **Defect**: reload and `fwconsole chown` disagree on the file modes, so a restart is not idempotent.
- **izPBX**: runs `fwconsole chown` again after the reload at start, with `FREEPBX_FIX_PERMISSION=true`.
- **Where**: `rootfs/usr/local/lib/izpbx/freepbx-start.sh`.
- **Tests**: P3-26.
- **Remove when**: P3-26 passes without it.

### FREEPBX-21320: `zlib.output_compression`
- **Defect**: FreePBX breaks with zlib compression on.
- **izPBX**: `zlib.output_compression = Off` for every PHP SAPI (`rootfs/etc/php/8.2/mods-available/izpbx.ini`).
- **Remove when**: FREEPBX-21320 is fixed in framework 17. Low risk anyway: PHP's default is Off.

### The database password on the Asterisk verbose console
- **Defect**: FreePBX exports `AMPDBPASS` as a dialplan global, and `asterisk -vvv` on stdout would print it in `docker logs`.
- **izPBX**: sends the Asterisk console stdout to `/dev/null`. The full log keeps verbose 3.
- **Where**: `rootfs/etc/s6-overlay/s6-rc.d/asterisk/run`.
- **Tests**: P3-21.
- **Remove when**: never by default. Re-evaluate only if FreePBX stops exporting the database credentials to the dialplan.

## FreePBX modules

### `ASTMANAGERHOST` must be 127.0.0.1 (UCP)
- **Defect**: the Node 18 of Debian 12 resolves `localhost` to `::1`, while AMI listens only on IPv4. The UCP node server cannot connect, and pm2 restarts it in a loop. A legacy restore puts `localhost` back.
- **izPBX**: sets 127.0.0.1 after the install and after the restore.
- **Where**: `freepbx.sh`, `freepbx_izpbx_settings`; `migration.sh`, `migration_restore`.
- **Tests**: P0-14, P4-16.
- **Remove when**: with `ASTMANAGERHOST=localhost`, ucp stays online in `fwconsole pm2 --list` (Node ≥ 20, or AMI on `::` too).

### The UCP installer wants g++ and pkg-config
- **Defect**: the ucp/pm2 installer refuses to run without `g++ --version` and without `pkg-config --modversion icu-i18n`, although its node modules are pure JavaScript. The image has no compiler.
- **izPBX**: installs two stubs: `build/g++-stub`, and `build/pkg-config-stub` (ICU version filled in at build time). See `build/runtime.sh`.
- **Tests**: P0-14, P1-10.
- **Remove when**: `fwconsole ma install ucp` succeeds after removing `/usr/local/bin/g++` and `pkg-config` in a test container.

### pm2 only says "errored" when the UCP port is taken
- **Defect**: when the port is in use, UCP gives up after 15 restarts and nobody says why.
- **izPBX**: when ucp ends up "errored", it checks the port and names it, along with the `APP_PORT_UCP_*` variable to change.
- **Where**: `freepbx-start.sh`.
- **Tests**: P3-36.
- **Remove when**: pm2 or UCP report EADDRINUSE themselves. It is diagnostics only, so it can stay.

### msmtp has no `mailq`, and the dashboard turns red
- **Defect**: msmtp called as `mailq` exits 64. The dashboard (`Overview::checkmailq`) shows a critical "Unknown output from mailq".
- **izPBX**: with msmtp, `/usr/bin/mailq` points to `rootfs/usr/local/share/izpbx/msmtp-mailq`, which answers "Mail queue is empty".
- **Where**: `init.d/10-services.sh`.
- **Tests**: P3-35, P3-37.
- **Remove when**: the dashboard tolerates a failing `mailq`, or msmtp ships one that exits 0.

### One AstDB WARNING per device at every "Apply Config"
- **Defect**: the queues module (17.0.4) deletes `queuehint`/`pausequeuehint` of every device at each reload, including keys that do not exist. Asterisk's `ast_db_del2` writes a WARNING for each.
- **izPBX**: a sed at build time turns that message into `ast_debug(1)`. A guard stops the build if the line is not found.
- **Where**: `build/asterisk.sh`.
- **Remove when**: the queues module checks before deleting, or Asterisk lowers the message. If the guard fails, Asterisk changed `main/db.c`: check whether the patch is still needed.

### The backup module creates its upload directory without `-p`
- **Defect**: on a new installation, uploading a backup to restore fails until `ASTSPOOLDIR/backup` exists.
- **izPBX**: creates it at install and at every start.
- **Where**: `freepbx.sh`, `freepbx_backup_dir`.
- **Tests**: P5-11.
- **Remove when**: the upload works on a new installation without that directory.

### Guard on UCP's own patch of `asterisk-manager` (not an izPBX workaround)
- **izPBX**: the build fails if `ami.js` lacks the upstream CR/LF patch (`build/node-modules.sh`).
- **Remove when**: UCP drops its postinstall patch: the build fails here, so drop the guard.

## FreePBX backup/restore and the 16 → 17 migration

### The legacy restore does not undo the escapes of the database dump
- **Defect**: backup 17.0.13, `Handlers/Restore/Legacy.php`, loads the dump of FreePBX 16 into SQLite. Its regexes (`'/\\n/'`, `'/\\r/'`, `'/\\"/'`) look for the real characters instead of the escapes, so CR, `"`, `'` and `\` come back as the literal `\r`, `\"`, `\'`, `\\`. Seen on pbx01:
  - calendar error 500, because a recurring event has an unreadable `DTSTART`;
  - `\r` in the emails of the outbound routes;
  - `\\n` in the voicemail email body;
  - `\\;` in the paging headers;
  - apostrophes in names.

  The outbound route emails, the voicemail email body and the paging headers are default FreePBX values, so **every** migration has these values.
- **izPBX**: after the restore, loads the snapshot dump into a scratch database (`izpbx_fpbx16_repair`) and puts back every value of FreePBX 17 that, with the escapes undone, equals the value of the same column in FreePBX 16. It saves the tables in the snapshot first, and leaves alone what was changed after the migration. On demand: `izpbx-migrate repair-escapes --check|--apply`.
- **Where**: `migration.sh`, `migration_repair_escapes`; `rootfs/usr/local/share/izpbx/migration-repair-escapes.php`.
- **Tests**: P4-39.
- **Remove when**: `Legacy.php` undoes the escapes. To test, migrate without this step, then `izpbx-migrate repair-escapes --check` must say "no value damaged".
- **Not covered**: a legacy FreePBX 16 backup restored **by hand** from the FreePBX 17 GUI, outside the izPBX migration, still gets the damaged values.

### The legacy restore fails on active modules whose tables are missing
- **Defect**: the restore asks every module active on FreePBX 17 for its data, and stops with `no such table: cidlookup` when FreePBX 16 had removed that module.
- **izPBX**: passes `--ignoremodules` with the modules that were not enabled on 16 and lack their tables in the dump.
- **Where**: `migration.sh`, `migration_restore`.
- **Tests**: P4-36.
- **Remove when**: that restore ends with "Restore completed successfully" without `--ignoremodules`.

### The restore does not bring back the module states of the 16
- **Defect**: the new install puts back default modules that the 16 had disabled or uninstalled.
- **izPBX**: disables or uninstalls them as they were on the 16.
- **Where**: `migration.sh`, `migration_modules_align`.
- **Tests**: P4-36.
- **Remove when**: the restore restores the module states.

### The restore puts `ENABLE_ARI` back to the FreePBX 17 default
- **izPBX**: on purpose it only reports it, in the log and in `report.txt`.
- **Where**: `migration.sh`, `migration_report`.
- **Tests**: P4-34.
- **Remove when**: after migrating a fixture with `ENABLE_ARI=1`, the value is still 1.

### The restore does not bring back the audio files
- **Defect**: `sounds/custom`, `sounds/<lang>` and the music on hold categories are not restored.
- **izPBX**: copies them from the snapshot.
- **Where**: `migration.sh`, `migration_audio`.
- **Tests**: P4-10, P4-33.

### The restore leaves the sound language at "en"
- **Defect**: language and formats of `soundlang_settings` come back as the FreePBX 17 defaults. After the first Apply Config, calls speak English and the custom prompts are not found.
- **izPBX**: writes them again from the dump.
- **Where**: `migration.sh`, `migration_soundlang`.
- **Remove when**: an "it" fixture migrated without this step keeps "it".

### The restore does not bring back every astdb family
- **Defect**: CustomPresence, RINGGROUP and TRUNK are missing.
- **izPBX**: adds the missing keys from the astdb of the snapshot.
- **Where**: `migration.sh`, `migration_astdb`.
- **Tests**: P4-11.

### The chan_sip → PJSIP conversion of the restore leaves `SIP/` in the astdb
- **Defect**: hints and dial strings still say `SIP/1001`, and `tech=sip`, so BLF stops working.
- **izPBX**: rewrites them to `PJSIP/` and `pjsip`.
- **Where**: `migration.sh`, `migration_astdb`; `share/izpbx/migration-mapping.tsv`.
- **Tests**: P4-35.

### The restore brings back only `*_custom.conf`
- **Defect**: the files included by the custom dialplan (for example `qhd/on-call.conf`) and `dongle.conf` are not restored.
- **izPBX**: copies them from the snapshot.
- **Where**: `migration.sh`, `migration_confs`.
- **Tests**: P4-37.
- **Status**: **permanent** while the archive is the legacy format.

### FreePBX 17 refuses the `:` comment lines in `voicemail.conf`
- **Defect**: some 20.16.x samples have `: Storage database:`. FreePBX 17 cannot parse them, so every reload fails.
- **izPBX**: turns those lines into `;` comments. `migration_reload` puts the PBX in maintenance mode if a file is still refused.
- **Where**: `migration.sh`, `migration_confs`, `migration_reload`.
- **Tests**: P4-35.
- **Remove when**: `fwconsole reload` accepts a `voicemail.conf` with `: Storage database:`. Keep `migration_reload` anyway.

### Asterisk 22 removed `Macro()`, chan_sip and other applications
- **izPBX**: `rootfs/usr/local/bin/izpbx-dialplan-convert` converts the custom dialplan:
  - `Macro` → `Gosub`, `MacroExit` → `Return`;
  - `SIPAddHeader` → `Set(__ALERT_INFO…)` / `HASH(__SIPHEADERS…)`;
  - `MessageSend(sip:` → `pjsip:`.

  What it cannot convert, preflight reports and blocks.
- **Tests**: P4-37, P4-03, P0-05.
- **Status**: **permanent** while 20.16 volumes can still be migrated (upstream removal, not a bug).

### phonebook and speeddial have no FreePBX 17 release
- **izPBX**: moves the entries to Contact Manager (group "Phonebook (izPBX 20.16)", speed dial `*10<code>`) and writes CSV exports.
- **Where**: `migration.sh`, `migration_phonebook`; `share/izpbx/migration-phonebook.php`.
- **Tests**: P4-31, P4-32, P4-26.
- **Remove when**: the modules come out for FreePBX 17 (unlikely).

## Asterisk

### codec_opus does not load without its XML documentation
- **Defect**: the binary Digium module refuses to load when its doc in `/var/lib/asterisk/documentation` (persisted on `/data`) is missing or old.
- **izPBX**: copies `documentation`, `rest-api` and `static-http` from the image at every start.
- **Where**: `rootfs/usr/local/lib/izpbx/persistence.sh`, `PERSIST_SYNC_DIRS`.
- **Tests**: P4-17.
- **Remove when**: codec_opus loads without its XML. The copy of `rest-api`/`static-http` stays.

### `app_voicemail_odbc` unregisters `VoiceMail()`
- **Defect**: built together with `app_voicemail`, at a reload it fails and removes the `VoiceMail()` application.
- **izPBX**: not built (`build/asterisk-menuselect.txt`).
- **Tests**: P5-08.

### Digium commercial modules with missing libraries
- **izPBX**: `res_digium_phone`, `res_pjsip_config_sangoma`, `res_mwi_external` and `res_mwi_external_ami` are not built (`build/asterisk-menuselect.txt`).
- **Tests**: P1-06.
- **Remove when**: they are needed and their libraries are packaged.

### Daemons that ignore SIGTERM while they start
- **Defect**: Asterisk 22 and fail2ban 1.0.2 ignore a TERM received while starting; FOP2 2.31 does not stop on TERM without a configuration. `docker stop` would end in a SIGKILL.
- **izPBX**: `service_run` repeats TERM every second and sends KILL after `SERVICE_STOP_GRACE`.
- **Where**: `rootfs/usr/local/lib/izpbx/service.sh`.
- **Tests**: P2-07, P0-15, P2-05.
- **Remove when**: a TERM in the first second stops each daemon. It costs nothing to keep.

### format_mp3 source
- **Defect**: the Digium svn addon lacks `#define ASTMM_LIBC ASTMM_REDIRECT`.
- **izPBX**: adds it, as `contrib/scripts/get_mp3_source.sh` does (`build/asterisk.sh`). It is a no-op when the define is already there.

### Addons that ignore `DESTDIR` or the module directory
- **izPBX**: installs `chan_dongle.so` by hand and moves addon modules into the right directory (`build/addons.sh`).
- **Tests**: P1-07.
- **Remove when**: chan-dongle honours `DESTDIR`.

## FOP2

### The FOP2 Makefile assumes make, systemd and Apache on the host
- **izPBX**: runs only the `install:` recipe with bash, with stubs for `apachectl`, `systemctl`, `update-rc.d`, `apt-get`, `yum` and `crontab`.
- **Where**: `services/fop2.sh`, `_fop2_make_install`.
- **Tests**: P3-13, P4-14.
- **Check**: at every FOP2 update, verify that the extraction of the recipe still works.

### arm64: the "Debian 12 ARM64" download link gives the 32-bit build
- **Defect**: the "Debian 12 - ARM64 (aarch64)" button of fop2.com/download.php (`file.php?file=24`) downloads `fop2-2.31.48-debian-armv7l.tgz`, a 32-bit armhf binary that does not start on the arm64 image (no `/lib/ld-linux-armhf.so.3`). The native package, same version as amd64, is `fop2-<ver>-debian12-aarch64.tgz` (`file.php?file=25`).
- **izPBX**: one `FOP2_VER`, the arm64 file name built from it with its own sha256 `FOP2_SHA256_AARCH64` (`versions.env`, `fop2.sh` `_fop2_package`, `tools/make-updates.sh`).
- **Tests**: P1-11 (aarch64 binary, `fop2_server -v` on the arm64 image).
- **Remove when**: never needed as code; check the file name at every FOP2 update (make-updates proposes an empty sha256 if `debian12-aarch64` is renamed).

### FOP2 tools run before Asterisk and fop2_server print errors
- **izPBX**: the output of `generate_override_contexts.pl` goes to `/tmp/fop2-override-contexts.log`, and `_fop2_mask` filters the `fop2.ctl` lines along with the license code.
- **Where**: `fop2.sh`.
- **Status**: cosmetic; the license masking stays.

### `temp/par-root` removed before every start
- **izPBX**: `rm -rf /usr/local/fop2/temp/par-root` (`rootfs/etc/s6-overlay/s6-rc.d/fop2/run`).
- **Note**: the reason is not documented (probably the stale PAR extraction cache after an update). Verify it at the next FOP2 update.

## Debian packages and services

### chrony: "Wrong permissions on /run/chrony"
- **izPBX**: `/run/chrony` owned by `_chrony`, mode 0750 (`rootfs/etc/s6-overlay/s6-rc.d/ntp/run`).
- **Tests**: P3-11.
- **Status**: **permanent** (no systemd-tmpfiles in the container).

### fail2ban: "'allowipv6' not defined"
- **izPBX**: `allowipv6 = auto` in `rootfs/etc/fail2ban/fail2ban.d/izpbx.local`.
- **Tests**: P3-42.
- **Remove when**: Debian ships fail2ban ≥ 1.1. The negative case of P3-42 shows the warning gone.

### fail2ban does not start: Debian sshd jail and missing log files
- **izPBX**: removes `jail.d/defaults-debian.conf` (`build/runtime.sh`) and creates the log files of the enabled jails (`services/fail2ban.sh`, `_fail2ban_logfiles`).
- **Tests**: P3-09, P2-03.
- **Remove when**: fail2ban tolerates a missing log file. The sshd part is **permanent**.

### The Debian Apache page hides FreePBX
- **izPBX**: removes it at build time and from the webroot when it is identical to the package's page (`build/runtime.sh`; `services/httpd.sh`, `httpd_remove_default_page`).
- **Tests**: P3-27.
- **Status**: **permanent**.

### `LimitRequestBody` is not applied to php-fpm requests
- **izPBX**: `Redirect 413` for a `Content-Length` over 128 MB (`services/httpd.sh`, `cfg_httpd`).
- **Tests**: P5-11.
- **Remove when**: a 140 MB POST to a `.php` page gets 413 with only `LimitRequestBody` set.

### Postfix: `start-fg`, chroot and the "Local only" defaults of Debian
- **Defect**: `postfix start-fg` leaves processes behind when it is not PID 1.
- **izPBX**: `master -s` directly, `chroot = n`, the upstream defaults back (`rootfs/etc/s6-overlay/s6-rc.d/postfix/run`, `build/runtime.sh`, `services/postfix.sh`).
- **Tests**: P2-07, P3-07.
- **Remove when**: `start-fg` works without PID 1. The rest is **permanent**.

### Other Debian packaging items (permanent)
- **dnsmasq**: `conf-dir` enabled by hand (`build/runtime.sh`). Tests: P3-10.
- **apache2 logrotate**: Debian's rotation reloads with `invoke-rc.d`, replaced by `rootfs/etc/logrotate.d/httpd`. Tests: P2-06.
- **phpMyAdmin**: the `blowfish_secret` made at package install is removed, and each container writes its own. Tests: P3-14.
- **Zabbix repository**: a key bundle (only the pinned fingerprint is imported), a separate arm64 path, and a version guard (`build/base.sh`). Tests: P1-05, P1-09.

## MariaDB and compose.yml

### `--log-warnings=1`
- **Defect**: an "Aborted connection" note for every `fwconsole` run, which closes without saying goodbye; hundreds during a migration.
- **Where**: `compose.yml` (`izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy`).
- **Tests**: P3-42.
- **Remove when**: with the default `log_warnings`, `fwconsole ma list` writes nothing in the database log.

### `--expire-logs-days=0`
- **Defect**: the official image warns about `expire_logs_days` although it writes no binlog.
- **Where**: `compose.yml` (`izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy`).
- **Tests**: P3-42.

### `--sql-mode` without `STRICT_TRANS_TABLES`
- **Note**: inherited from 20.16 and not commented: FreePBX has historically not been compatible with strict mode.
- **Remove when**: install, migration and the P5 checks pass with the default `sql_mode`.

## Open points
- **`max_input_vars`**: FreePBX sets 5000 in `admin/.htaccess` inside `<IfModule php7_module>`, which has no effect with php-fpm. The prototype moved it to the fpm pool (`tests/proto/fpbx17-fpm`), but the image's pool (`rootfs/etc/php/8.2/fpm/pool.d/asterisk.conf`) does not set it. To check: large FreePBX forms (many extensions or routes) could be truncated at 1000 variables.
- **Undocumented reasons**: `/etc/machine-id` (the reason is only in `tests/proto/fpbx17/proto-install.sh`), FOP2 `par-root`, `sql-mode`: add a comment in the code.
- **`FREEPBX_SIGNATURECHECK`** (FREEPBX-20559, from 2020) in `default.env` (`izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy`): only a commented example from the FreePBX 15 days. It can be removed.
- **Already removed** in 22.17 (P1-12, P3-22 check they do not come back): `php74.patch`, `SECLEVEL=1`, `gpg --refresh-keys`, microdnf, `chan_local`, `Encoding.php`, FREEPBX-21703, FREEPBX-22983.
