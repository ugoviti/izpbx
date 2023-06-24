#!/bin/bash
# initzero docker entrypoint init script
# written by Ugo Viti <ugo.viti@initzero.it>
# 20230423

#set -x

## entrypoint env management failback if not defined upstream into Dockerfile
: ${APP_NAME:=unknown}}
: ${APP_DESCRIPTION:=unknown}}
: ${APP_VER:=latest}
: ${APP_VER_BUILD:=unknown}
: ${APP_BUILD_COMMIT:=unknown}
: ${APP_BUILD_DATE:=unknown}
## entrypoints default variables
: ${APP_RUNAS:=false}
: ${ENTRYPOINT_TINI:=false}
: ${MULTISERVICE:=false}

appHooks() {
  [ "${APP_BUILD_DATE}" != "unknown" ] && APP_BUILD_DATE=$(date -d @${APP_BUILD_DATE} +"%Y-%m-%d")

  echo "=> Starting container $APP_DESCRIPTION -> $APP_NAME:$APP_VER (build:${APP_VER_BUILD} commit:${APP_BUILD_COMMIT} date:${APP_BUILD_DATE})"
  echo "==============================================================================="
  if [ -e "/entrypoint-hooks.sh" ]; then
    echo "=> Executing $APP_NAME hooks:"
    . /entrypoint-hooks.sh
  fi
  echo "-------------------------------------------------------------------------------"
}

# exec app hooks
appHooks

# define pre command hooks
if [ "$MULTISERVICE" = "true" ]; then
    # if this container will run multiple commands, override the entry point cmd
    CMD="runsvdir -P /etc/service"
elif [ "$APP_RUNAS" = "true" ]; then
    # run the process as user if specified
    CMD="runuser -p -u $APP_USR -- $@"
  else
    # run the specified command without modifications
    CMD="$@"
fi

# at last if CMD_OVERRIDE is defined use it
[ ! -z "$CMD_OVERRIDE" ] && CMD="${CMD_OVERRIDE}"

# use tini init manager if defined in Dockerfile
[ "$ENTRYPOINT_TINI" = "true" ] && CMD="tini -g -- $CMD"

echo "=> Executing $APP_NAME entrypoint command: $CMD"
echo "==============================================================================="
# set default system umask before starting the container
[ ! -z "$UMASK" ] && umask $UMASK
set -x

exec $CMD
exit $?
