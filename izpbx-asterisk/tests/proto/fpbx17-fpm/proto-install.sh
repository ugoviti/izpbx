#!/bin/bash
# start php-fpm, then the usual prototype install (which starts apache)
set -Eeuo pipefail
mkdir -p /run/php
php-fpm8.2 -D
exec /usr/local/bin/proto-install-base.sh "$@"
