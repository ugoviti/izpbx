#!/bin/bash
# initzero docker entrypoint init script
# written by Ugo Viti <ugo.viti@initzero.it>
# 20200315

#set -x

appHooks() {
  : ${APP_RUNAS:="false"}
  : ${APP_ENTRYPOINT:=""}
  : ${APP_ENTRYPOINT_TINI:="false"}
  : ${APP_MULTISERVICE:="false"}
  : ${APP_NAME:="unknown"}
  : ${APP_DESCRIPTION:="unknown"}
  : ${APP_VER:="unknown"}
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

echo "=> Executing $APP_NAME entrypoint command: $@"
echo "==============================================================================="

# set default system umask before starting the container
[ ! -z "$UMASK" ] && umask $UMASK

# use tini init manager if defined in Dockerfile
[ "$APP_ENTRYPOINT_TINI" = "true" ] && APP_ENTRYPOINT="tini -g --"

# if this container will run multiple commands, override the entry point cmd
if [ "$APP_MULTISERVICE" = "true" ]; then
  set -x
  exec $APP_ENTRYPOINT runsvdir -P /etc/service
 else
  # run the process as user if specified
  if [ "$APP_RUNAS" = "true" ]; then
      set -x
      exec $APP_ENTRYPOINT runuser -p -u $APP_USR -- $@
    else
      set -x
      exec $APP_ENTRYPOINT $@
  fi
fi
exit $?
