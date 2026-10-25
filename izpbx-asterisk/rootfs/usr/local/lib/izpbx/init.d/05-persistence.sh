# shellcheck shell=bash
# izpbx-init step: persistent storage under APP_DATA (symlinks to the volume,
# <dir>.dist, seeding of empty directories), before any configuration step
# writes into those directories; then the directories that belong to the
# image (Asterisk documentation, rest-api, static-http) equal to it again.
# shellcheck source=../persistence.sh
. /usr/local/lib/izpbx/persistence.sh
persistence_setup
persistence_sync_dist
