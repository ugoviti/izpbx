# izpbx-deploy: generate and upgrade compose.yml and .env from the image

> Available from izPBX 22.17.0. For izPBX 20.16 see the [`release/20.16`](https://github.com/ugoviti/izpbx/tree/release/20.16) branch.

`izpbx-deploy` creates and updates the `compose.yml` and `.env` of an izPBX deploy straight from the published image: no `git clone`, no `cp default.env .env`, no manual comparison of `default.env` between versions. The image carries the `compose.yml` and `default.env` of its own version, so the files always match the image that runs them.

## Usage

```
# first deploy, in an empty directory
docker run --rm -v "$PWD:/deploy" izdock/izpbx-asterisk:X.Y.Z izpbx-deploy init

# upgrade: dry-run by default, prints the diff and changes nothing
docker run --rm -v "$PWD:/deploy" izdock/izpbx-asterisk:X.Y.Z izpbx-deploy upgrade
# apply the changes (with automatic backup)
docker run --rm -v "$PWD:/deploy" izdock/izpbx-asterisk:X.Y.Z izpbx-deploy upgrade --apply

# stdout only, no mount
docker run --rm izdock/izpbx-asterisk:X.Y.Z izpbx-deploy compose > compose.yml
docker run --rm izdock/izpbx-asterisk:X.Y.Z izpbx-deploy env > .env
```

`X.Y.Z` is the version to move to: the image used for the upgrade is the target version.

### Subcommands

| Subcommand | What it does |
|---|---|
| `init` | writes `compose.yml` and `.env` in `/deploy`; refuses if one of them already exists |
| `upgrade` | brings the existing `compose.yml` and `.env` to the version of the image (dry-run unless `--apply`) |
| `compose` | prints the `compose.yml` of the image on stdout |
| `env` | prints a new `.env` on stdout (as `init`, random passwords included) |

### Options

| Option | Subcommands | Effect |
|---|---|---|
| `--apply` | `upgrade` | write the changes (default: dry-run) |
| `--env-file FILE` | `init`, `upgrade` | the env file to use, relative to `/deploy` (default: `.env`), for multi-tenant deploys (`izpbx1.env`, ...) |
| `--only env\|compose` | `init`, `upgrade` | handle one file only |
| `--keep-version` | `upgrade` | do not move `IZPBX_VERSION` and `MARIADB_VERSION` to the versions of the image |
| `--major` | `upgrade` | allow a change of version series of `IZPBX_VERSION`, e.g. 20.16 → 22.17 (see [Version change](#version-change)); a `compose.yml` of an unknown version (20.16) is replaced |
| `--prune` | `upgrade` | delete the removed variables, customized ones included, instead of commenting them |
| `--no-backup` | `upgrade` | no backup copy before writing |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | nothing to do (`upgrade` dry-run), or changes written |
| `1` | error (missing file, unreadable `.env`, refused `init`) |
| `2` | dry-run with pending changes |
| `3` | refused: compose merge conflict, or version series change without `--major` |

## Without izpbx-deploy

`compose.yml` and `default.env` are in [`izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy`](../izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy) of the repository, at the tag of every release. For a new deploy download them, `default.env` as `.env` (then change its passwords):

```
curl -fsSL -o compose.yml https://raw.githubusercontent.com/ugoviti/izpbx/22.17.0/izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy/compose.yml
curl -fsSL -o .env https://raw.githubusercontent.com/ugoviti/izpbx/22.17.0/izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy/default.env
```

To upgrade by hand: set `IZPBX_VERSION` of `.env` to the new version, compare your `.env` with the `default.env` of the new release (new, changed and removed variables) and replace `compose.yml` with the new one (your changes belong in `compose.override.yml`).

## Entrypoint

`/init` (s6-overlay) would start every service before a command given to `docker run`. The entrypoint of the image is `/usr/local/sbin/izpbx-entrypoint`: when the first argument is `izpbx-deploy` it runs `/usr/local/sbin/izpbx-deploy` directly, without s6, with its exit code; anything else is exec'd to `/init` as before (PID 1 is still s6-svscan).

## Files in the image

| Path | Content |
|---|---|
| `/usr/local/sbin/izpbx-deploy` | the command (bash, awk) |
| `/usr/local/sbin/izpbx-entrypoint` | the entrypoint of the image |
| `/usr/local/share/izpbx/deploy/compose.yml` | the `compose.yml` of a deploy |
| `/usr/local/share/izpbx/deploy/default.env` | the `.env` of a new deploy, with every variable |
| `/usr/local/share/izpbx/deploy/history/` | the `default.env` and `compose.yml` of every release X.Y.Z with `IZPBX_VERSION` in `default.env` (22.17.0 and later) but the current one: `VERSION.env`, `VERSION.compose.yml`, the base of the 3-way merge |
| `/usr/local/share/izpbx/deploy/keys.txt` | every variable `default.env` ever had (all the tags): a variable of the `.env` in this list and not in the new `default.env` is a removed one, not a custom one |
| `/usr/local/share/izpbx/deploy/renames.tsv` | renamed variables, written by hand: `OLD_NAME NEW_NAME VERSION` |

In the repository they are in `izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy`: `compose.yml` and `default.env` are edited there (they are no longer at the root of the repository); `history/` and `keys.txt` are written from the git tags by `izpbx-asterisk/tools/deploy-sync.sh`, that `tools/make-release.sh` runs in the release commit; `tests/lint.sh` (pre-commit) fails when they are out of date (`deploy-sync.sh --check`).

`IZPBX_DEPLOY_DIR` (default `/deploy`) and `IZPBX_DEPLOY_SHARE` (default `/usr/local/share/izpbx/deploy`) move the two directories, to run it outside the image (tests).

## init

- Refuses if `compose.yml` or the env file already exists in `/deploy` (use `upgrade`).
- Writes `default.env` with `IZPBX_VERSION` and `MARIADB_VERSION` of the image.
- `MYSQL_PASSWORD` and `MYSQL_ROOT_PASSWORD` get random values (never `PleaseCHANGEM3`).
- The files get the owner of the `/deploy` directory (the container runs as root, the directory belongs to the user).

## upgrade of .env

### Variable states

Every variable of a `.env` is in one of three states:
- **active**: `VAR=value`
- **commented**: `#VAR=value` (an example of the template, or a variable disabled by the user)
- **absent**

### The three versions

- **base**: the `default.env` of the version the `.env` comes from, found from `IZPBX_VERSION` of the `.env` in `history/`
- **user**: the `.env` of the deploy
- **new**: the `default.env` of the image

A variable is **customized** when its state or its value in user differs from base.

### Rules

| Case | Result |
|---|---|
| Not customized | follows new: new default, new state, or removal |
| Customized, still in new | keeps the user state and value, at the position of new |
| Active in base, commented by the user (e.g. `MYSQL_ROOT_PASSWORD`, see NOTE1 of `default.env`) | stays commented |
| New in new | added at its position, with its comments |
| Removed from new, customized | commented with a marker: `# REMOVED in X.Y.Z: VAR=value`; deleted with `--prune` |
| Renamed (`renames.tsv`) | the user value moves to the new name; the old name disappears |
| In no template (variable of the user) | kept, active, in a `### Custom` section at the end of the file |
| Defined twice in user | the last one wins (as docker compose), the dry-run reports it |
| `IZPBX_VERSION`, `MARIADB_VERSION` | set to the versions of the image, unless `--keep-version` |

The result has the structure, order and comments of new, with the values of the user. Comments written by the user next to a variable of the template are not kept (the comments come from new): put them in the `### Custom` section.

### .env without a known base (20.16)

A `.env` without `IZPBX_VERSION`, or with a version not in `history/`, is merged in 2 ways (user and new):
- the user value always wins, for every variable present in user
- the dry-run lists the variables whose user value differs from the default of new, so the user can check the defaults that changed
- the other rules (new variables, renames, custom section, commented variables) are the same

### Version change

When `IZPBX_VERSION` of the `.env` and of the image differ in version series X.Y (e.g. 20.16 → 22.17), or the `.env` has no `IZPBX_VERSION` (izPBX 20.16 or older), `upgrade` refuses (exit code `3`) and points to [Upgrade from 20.16 to 22.17](upgrade-20.16-to-22.17.md): the migration of FreePBX is not a plain image update. `--major` lets it go on (also for a 22.17 deploy whose `.env` never got `IZPBX_VERSION`); `--keep-version` does not change the version, so it is not refused.

When `MARIADB_VERSION` changes, the output reminds to run `mariadb-upgrade` after the restart (see `compose.yml`).

## upgrade of compose.yml

`compose.yml` is not meant to be edited (changes go in `compose.override.yml`), but many deploys edit it (`network_mode`, ports, macvlan).

- **base**: the `compose.yml` of the version of the `.env` in `history/`
- **identical to base**: replaced with the new one
- **different from base**: 3-way merge with `diff3 -m` (base, user, new)
  - no conflicts: the merged file is the result
  - conflicts: nothing is written (neither `compose.yml` nor `.env`), exit code `3`, the output shows the conflicts and suggests moving the local changes to `compose.override.yml`
- **no base** (20.16, unknown version): no merge; with `--major` (20.16 → 22.17) or `--only compose` it is replaced by the new one (the old one in the backup: its local changes go in `compose.override.yml`), otherwise it is not changed and the dry-run shows the diff

## Dry-run output

- a colored unified diff for every file that changes (no colors when stdout is not a terminal, or with `NO_COLOR`); the values of the variables with `PASSWORD`, `PASS`, `SECRET`, `TOKEN` or `_KEY` in their name are shown as `*****`
- a summary: variables added, removed, commented as removed, renamed, defaults changed, customized values kept, custom variables, version change
- the command to apply: `... izpbx-deploy upgrade --apply`

## Writes and backups

- Before writing, every file that changes is copied to `FILE.YYYYmmdd-HHMMSS.bak` in the same directory (`.env.20261030-143012.bak`), unless `--no-backup`.
- Atomic write: temporary file in the same directory, then rename.
- The new file keeps owner and mode of the old one (`.env` usually `0600`).
- `compose.yml` and `.env` are written together only when both are ready: a failure of one leaves both untouched.
- An `upgrade` without changes writes nothing (no backup, no mtime change).

## Multi-tenant

One env file per run with `--env-file`:

```
for f in izpbx*.env; do
  docker run --rm -v "$PWD:/deploy" izdock/izpbx-asterisk:X.Y.Z izpbx-deploy upgrade --only env --env-file "$f"
done
```

## Tests

`izpbx-asterisk/tests/run.sh P7-11`: fast, without containers, with awk in POSIX mode (the image has mawk), on synthetic files and on the real `default.env`:
- `.env` of a 22.x release untouched, customized, with disabled variables, with custom variables, with duplicates
- old `.env` without the variables added in 22.17 (`IZPBX_VERSION`, `MARIADB_VERSION`, `IZPBX_LOG_*`, `IZPBX_MIGRATE_*`, ...)
- 20.16 `.env` (2-way merge, refused without `--major`; with `--major` the 20.16 `compose.yml` replaced)
- renamed and removed variables
- `compose.yml` untouched, edited without conflicts, edited with conflicts
- idempotence: a second `upgrade --apply` changes nothing
- `history/` and `keys.txt` in step with `default.env` and the tags (`deploy-sync.sh --check`)

The whole flow in the image: P2-01 (entrypoint, `izpbx-deploy` without s6), P7-01 (the migration guide, `izpbx-deploy upgrade --major` on a 20.16 deploy), P7-09 (release: versions moved, history written).
