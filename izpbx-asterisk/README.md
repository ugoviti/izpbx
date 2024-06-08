# izpbx-asterisk

izPBX is a Turnkey Cloud Native VoIP Telephony System powered by Asterisk Engine and FreePBX Management GUI

for more info: https://github.com/ugoviti/izdock-izpbx

# izPBX Development

## BUILD

Asterisk 20 + FreePBX 16: (using Dockerfile variables)
```
docker build --pull --rm --build-arg APP_DEBUG=1 --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=0000000 --build-arg APP_BUILD_DATE=$(date +%s) --build-arg APP_VER=dev-20.16 -t izpbx-asterisk:dev-20.16 .
```

Asterisk 18 + FreePBX 15: (overriding Dockerfile variables)
```
docker build --pull --rm --build-arg APP_DEBUG=1 --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=0000000 --build-arg APP_BUILD_DATE=$(date +%s) --build-arg APP_VER=dev-18.15 --build-arg ASTERISK_VER=18.15.0 --build-arg FREEPBX_VER=15 -t izpbx-asterisk:dev-18.15 .
```

### Multi Arch Build
```
docker buildx build --platform linux/amd64,linux/arm64 --pull --rm --build-arg APP_DEBUG=1 --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=0000000 --build-arg APP_BUILD_DATE=$(date +%s) --build-arg APP_VER=dev-20.16 -t izpbx-asterisk:dev-20.16 .
```

## RUN

### Docker Run:
Start MySQL:  
```
docker run --rm -ti -p 3306:3306 -v ${PWD}/data/db:/var/lib/mysql -e MYSQL_DATABASE=asterisk -e MYSQL_USER=asterisk -e MYSQL_ROOT_PASSWORD=CHANGEM3 -e MYSQL_PASSWORD=CHANGEM3 --name izpbx-db mariadb:10.6
```

Start izPBX:  
```
docker run --rm -ti --network=host --privileged --cap-add=NET_ADMIN -v ${PWD}/data/izpbx:/data -e MYSQL_SERVER=127.0.0.1 -e MYSQL_DATABASE=asterisk -e MYSQL_USER=asterisk -e MYSQL_ROOT_PASSWORD=CHANGEM3 -e MYSQL_PASSWORD=CHANGEM3 -e APP_DATA=/data --name izpbx izpbx-asterisk:dev-20.16
```


### docker compose:

Asterisk 20 + FreePBX 16:  
```
docker compose down ; docker compose -f compose.yml -f compose-dev-20.16.yml up
```

Asterisk 18 + FreePBX 16:  
```
docker compose down ; docker compose -f compose.yml -f compose-dev-18.16.yml up
```

Asterisk 18 + FreePBX 15:  
```
docker compose down ; docker compose -f compose.yml -f compose-dev-18.15.yml up
```

### entering into container:
```
docker exec -it izpbx bash
```
