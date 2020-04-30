#!/bin/bash
# initzero docker entrypoint init script
# written by Ugo Viti <ugo.viti@initzero.it>
# 20200315

#set -x

appHooks() {
  : ${APP_RUNAS:="false"}
  : ${ENTRYPOINT_TINI:="false"}
  : ${MULTISERVICE:="false"}
  : ${APP_NAME:=CHANGEME}
  : ${APP_DESCRIPTION:=CHANGEME}
  : ${APP_VER:="latest"}
  : ${APP_VER_BUILD:="unknown"}
  : ${APP_BUILD_COMMIT:="unknown"}
  : ${APP_BUILD_DATE:="unknown"}

  [ "${APP_BUILD_DATE}" != "unknown" ] && APP_BUILD_DATE=$(date -d @${APP_BUILD_DATE} +"%Y-%m-%d")
  
  echo "=> Starting container $APP_DESCRIPTION -> $APP_NAME:$APP_VER (build:${APP_VER_BUILD} commit:${APP_BUILD_COMMIT} date:${APP_BUILD_DATE})"
  echo "==============================================================================="
  echo "=> Executing $APP_NAME hooks:"
  . /entrypoint-hooks.sh
  echo "-------------------------------------------------------------------------------"
}

# exec app hooks
appHooks

# set default system umask before starting the container
[ ! -z "$UMASK" ] && umask $UMASK

# use tini init manager if defined in Dockerfile
[ "$ENTRYPOINT_TINI" = "true" ] && ENTRYPOINT="tini -g --" || ENTRYPOINT=""

# if this container will run multiple commands, override the entry point cmd
echo "=> Executing $APP_NAME entrypoint command: $@"
echo "==============================================================================="
if [ "$MULTISERVICE" = "true" ]; then
  set -x
  exec $ENTRYPOINT runsvdir -P /etc/service
 else
  # run the process as user if specified
  if [ "$APP_RUNAS" = "true" ]; then
      set -x
      exec $ENTRYPOINT runuser -p -u $APP_USR -- $@
    else
      set -x
      exec $ENTRYPOINT $@
  fi
fi
exit $?
