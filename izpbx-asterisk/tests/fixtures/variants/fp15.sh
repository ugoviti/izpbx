# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # sourced by make-fixture.sh: shares its variables
# fp15 (P0-08b): an install born on 18.15.x (FreePBX 15), upgraded by the
# izPBX automatic upgrade to 18.16.14 (FreePBX 16), then started on the target
# 20.16.x and populated there.
CHAIN=(18.15.24 18.16.14)
# FOP2 off on the old images (their FOP2 installer is not the 20.16 one)
CHAIN_ENV=(-e FREEPBX_AUTOUPGRADE_CORE=true -e FOP2_ENABLED=false)
variant_manifest() { echo "anomaly=born on FreePBX 15 (18.15.24), upgraded via 18.16.14"; }
