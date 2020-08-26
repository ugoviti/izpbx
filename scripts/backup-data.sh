#!/bin/bash

BACKUP_DIR="${HOME}/projects/izdock-izpbx-backup/$(date +%Y-%m-%d-%H-%M-%S)"

echo "run:"
echo "docker-compose down"
echo "when down press <ENTER>"
read r

mkdir -p ${BACKUP_DIR}/

pushd ..
cp live-default.env ${BACKUP_DIR}/
sudo rsync -avp data ${BACKUP_DIR}/
popd
