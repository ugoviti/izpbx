#!/bin/bash
podname=pbx
version=18.15

### check configuration file
if [ ! -f ../.env ]; then
    echo '.env file is missing !'
    exit 1
fi

mkdir -p /$podname/data
mkdir -p /$podname/db
mkdir -p /$podname/backup

echo 'Creating pod: ' $podname
### create pod
podman pod create -n $podname --hostname odo.pir.lt \
    --runtime=/usr/lib/cri-o-runc/sbin/runc \
    --network static \
    -p 80:80 -p 443:443 \
    -p 5550:5550 -p 5550:5550/udp -p 5551:5551 -p 5551:5551/udp \
    -p 8089:8089 \
    -p 18000-18200:18000-18200/udp

echo 'Starting pod: ' $podname
podman pod start $podname

# echo 'Backing up data folder...'
# rsync -a /$podname/data /$podname/backup/$podname-dir.bkp.$(date +%Y%m%d-%H.%M.%S)

echo 'Running DB container: ' $podname-db
### create db container
podman run -d --name $podname-db --pod $podname \
    --runtime=/usr/lib/cri-o-runc/sbin/runc \
    --env-file=pir.env \
    -v /$podname/db:/var/lib/mysql \
        docker.io/library/mariadb:10.5

echo 'Running APP container: ' $podname-app
### create app container - run attached to 
podman run -d --name $podname-app --pod $podname \
    --runtime=/usr/lib/cri-o-runc/sbin/runc \
    --env-file=pir.env \
    -v /$podname/data:/data \
    --cap-add=NET_ADMIN \
        docker.io/izdock/izpbx-asterisk:$version
