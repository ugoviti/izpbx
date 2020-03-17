#!/bin/bash
# initzero docker entrypoint generic script
# written by Ugo Viti <ugo.viti@initzero.it>
# 20200315

#set -x

app_pre_hooks() {
  : ${APP_RUNAS:="false"}
  : ${ENTRYPOINT_TINI:="false"}
  : ${MULTISERVICE:="false"}
  : ${APP_NAME:=CHANGEME}
  : ${APP_DESCRIPTION:=CHANGEME}
  : ${APP_VER:=$(cat /VERSION)}
  echo "=> Starting container $APP_DESCRIPTION :: $APP_NAME:$APP_VER"
}

app_post_hooks() {
  . /entrypoint-hooks.sh
}

# exec app hooks
app_pre_hooks
app_post_hooks
echo "========================================================================"

# set default system umask before starting the container
umask $UMASK

# use tini init manager if required
[ "$ENTRYPOINT_TINI" = "true" ] && ENTRYPOINT="tini -g --" || ENTRYPOINT=""

# if this container will run multiple commands, override the entry point cmd
if [ "$MULTISERVICE" = "true" ]; then
  set -x
  exec $ENTRYPOINT runsvdir -P /etc/service
 else
  set -x
  # run the process as user if specified
  [ "${APP_RUNAS}" = "true" ] && exec $ENTRYPOINT runuser -p -u ${APP_USR} -- $@ || exec $ENTRYPOINT $@
fi
