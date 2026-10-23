#!/bin/bash
# Install an apt package list: build/apt.sh build/packages-build.txt
set -Eeuo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"
apt-get update
apt_install "${1:?package list}"
