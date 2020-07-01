# izpbx-asterisk

izPBX is a TurnKey Cloud Native Telephony System powered by Asterisk Engine and FreePBX Management GUI

for more info: https://github.com/ugoviti/izdock-izpbx

# Docker Development

## Build

Asterisk 16:  
`docker build --pull --rm --build-arg APP_DEBUG=1 --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=fffffff --build-arg APP_BUILD_DATE=$(date +%s) --build-arg APP_VER=16.11.1 -t izpbx-asterisk:dev-16 .`

Asterisk 17:  
`docker build --pull --rm --build-arg APP_DEBUG=1 --build-arg APP_VER_BUILD=1 --build-arg APP_BUILD_COMMIT=fffffff --build-arg APP_BUILD_DATE=$(date +%s) --build-arg APP_VER=17.5.1 -t izpbx-asterisk:dev-17 .`


## Run

Docker Run:  
`docker run --rm -ti --name izpbx-asterisk izpbx-asterisk`

Docker Compose:  
`docker-compose down ; docker-compose -f docker-compose.yml -f docker-compose-dev-16.yml up`
