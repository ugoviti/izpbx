# izPBX Development

Notes to build and run the `izpbx-asterisk` image from the sources. Component updates, tests and releases: [maintainers.md](maintainers.md).

## BUILD

run docker build from inside the `izpbx-asterisk` directory


Asterisk 22 + FreePBX 17 (component versions and checksums from `versions.env`):
```
docker build --pull --rm --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=0000000 --build-arg APP_BUILD_DATE=$(date +%s) --build-arg APP_VER=dev-22.17 -t izpbx-asterisk:dev-22.17 .
```

### Multi Arch Build
```
docker buildx build --platform linux/amd64,linux/arm64 --pull --rm --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=0000000 --build-arg APP_BUILD_DATE=$(date +%s) --build-arg APP_VER=dev-22.17 -t izpbx-asterisk:dev-22.17 .
```

## RUN

### Docker Run:
Start MySQL:  
```
docker run --rm -ti -p 3306:3306 -v ${PWD}/data/db:/var/lib/mysql -e MYSQL_DATABASE=asterisk -e MYSQL_USER=asterisk -e MYSQL_ROOT_PASSWORD=CHANGEM3 -e MYSQL_PASSWORD=CHANGEM3 --name izpbx-db mariadb:10.11
```

Start izPBX:  
```
docker run --rm -ti --network=host --privileged --cap-add=NET_ADMIN -v ${PWD}/data/izpbx:/data -e MYSQL_SERVER=127.0.0.1 -e MYSQL_DATABASE=asterisk -e MYSQL_USER=asterisk -e MYSQL_ROOT_PASSWORD=CHANGEM3 -e MYSQL_PASSWORD=CHANGEM3 -e APP_DATA=/data --name izpbx izpbx-asterisk:dev-22.17
```


### docker compose:

from izpbx directory root, exec:

Asterisk 22 + FreePBX 17:  
```
docker compose down ; docker compose -f compose.yml -f izpbx-asterisk/compose/compose-dev-22.17.yml up
```

### entering into container:
```
docker exec -it izpbx bash
```
