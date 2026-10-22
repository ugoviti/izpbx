# izpbx-asterisk

izPBX is a Turnkey Cloud Native VoIP Telephony System powered by Asterisk Engine and FreePBX Management GUI

for more info: https://github.com/ugoviti/izdock-izpbx

# izPBX Development

## BUILD

run docker build from inside `izpbx-asterisk` directory


Asterisk 20 + FreePBX 16: (using Dockerfile variables)
```
docker build --pull --rm --build-arg APP_DEBUG=1 --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=0000000 --build-arg APP_BUILD_DATE=$(date +%s) --build-arg APP_VER=dev-20.16 -t izpbx-asterisk:dev-20.16 .
```

### Multi Arch Build
```
docker buildx build --platform linux/amd64,linux/arm64 --pull --rm --build-arg APP_DEBUG=1 --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=0000000 --build-arg APP_BUILD_DATE=$(date +%s) --build-arg APP_VER=dev-20.16 -t izpbx-asterisk:dev-20.16 .
```

## RUN

### Docker Run:
Start MySQL:  
```
docker run --rm -ti -p 3306:3306 -v ${PWD}/data/db:/var/lib/mysql -e MYSQL_DATABASE=asterisk -e MYSQL_USER=asterisk -e MYSQL_ROOT_PASSWORD=CHANGEM3 -e MYSQL_PASSWORD=CHANGEM3 --name izpbx-db mariadb:10.11
```

Start izPBX:  
```
docker run --rm -ti --network=host --privileged --cap-add=NET_ADMIN -v ${PWD}/data/izpbx:/data -e MYSQL_SERVER=127.0.0.1 -e MYSQL_DATABASE=asterisk -e MYSQL_USER=asterisk -e MYSQL_ROOT_PASSWORD=CHANGEM3 -e MYSQL_PASSWORD=CHANGEM3 -e APP_DATA=/data --name izpbx izpbx-asterisk:dev-20.16
```


### docker compose:

from izpbx directory root, exec:

Asterisk 20 + FreePBX 16:  
```
docker compose down ; docker compose -f compose.yml -f izpbx-asterisk/compose/compose-dev-20.16.yml up
```

### entering into container:
```
docker exec -it izpbx bash
```
