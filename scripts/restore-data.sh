#!/bin/bash

echo "run:"
echo "docker-compose down"
echo "when down press <ENTER>"
read r

echo "which data you want to restore?"
ls -lah ${HOME}/projects/izdock-izpbx-backup/
echo "enter the dir"
read BACKUP_DIR_END

BACKUP_DIR="${HOME}/projects/izdock-izpbx-backup/${BACKUP_DIR_END}"

pushd ..
set -x
if [ -f live-default.env ]; then
  mv live-default.env live-default.env.old
fi
if [ -d data ]; then
mv data data.old
fi

cp ${BACKUP_DIR}/live-default.env .
sudo rsync -avp ${BACKUP_DIR}/data .
set +x
popd
