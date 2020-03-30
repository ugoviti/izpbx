#!/bin/bash
# Asterisk automatic discovery and check script
# author: Ugo Viti <ugo.viti@initzero.it>
# version: 20200330

# comment to disable sudo
sudo="sudo -u asterisk"

# example JSON file for zabbix discovery
# {
#   "data":
#   [
#     { "{#HOST}":"voip.eutelia.it:5060", "{#USERNAME}":"05751234567", "{#STATE}":"Registered"},
#     { "{#HOST}":"sip.messagenet.it:5060", "{#USERNAME}":"34887123456", "{#STATE}":"Registered"}
#   ]
# }

cmd="$1"
shift

[ -z "$cmd" ] && echo "ERROR: missing arguments... exiting" && exit 1

## discovery functions
convert_registrations_to_json() {
  echo "{
  \"data\":
  ["
  echo "$REGISTRY" | while read registry; do
  HOST="$(echo $registry | awk '{print $1}')"
  USERNAME="$(echo $registry | awk '{print $3}')"
  STATE="$(echo $registry | awk '{print $5}')"
  echo "    { \"{#HOST}\":\"$HOST\", \"{#USERNAME}\":\"$USERNAME\", \"{#STATE}\":\"$STATE\"},"
  done | sed '$ s/,$//'
  echo "  ]
}"
}

discovery.sip.registry() {
  REGISTRY="$($sudo asterisk -r -x "sip show registry" | grep -v -e "^Host" -e "SIP registrations")"
  [ ! -z "$REGISTRY" ] && convert_registrations_to_json
}

discovery.iax2.registry() {
  REGISTRY="$($sudo asterisk -r -x "iax2 show registry" | grep -v -e "^Host" -e "IAX2 registrations")"
  [ ! -z "$REGISTRY" ] && convert_registrations_to_json
}

## status functions 

# return int
calls.active() {
  $sudo asterisk -rx "core show channels" | grep "active calls" | awk '{print$1}'
}

# return int
calls.processed() {
  $sudo asterisk -rx "core show channels" | grep "calls processed" | awk '{print$1}'
}

calls.longest() {
  # grab only latest call
  CHANNEL="$($sudo asterisk -rx 'core show channels concise' | cut -d'!' -f12,1 | sed 's/!/ /g' | sort -n -k 2 | tail -1)"
  CHANNEL_NAME=$(echo $CHANNEL | awk '{print $1}')
  CHANNEL_TIME=$(echo $CHANNEL | awk '{print $2}')
  : ${CHANNEL_TIME:="0"}
  [ "$CHANNEL_TIME" -gt 3600 ] && echo "Call $CHANNEL_NAME is stuck $CHANNEL_TIME seconds" || echo 0
}

# return secs
lastreload() {
  $sudo asterisk -rx "core show uptime seconds" | awk -F": " '/Last reload:/{print$2}'
}

# return secs
systemuptime() {
  $sudo asterisk -rx "core show uptime seconds" | awk -F": " '/System uptime:/{print$2}'
}

# return text
version() {
  $sudo asterisk -rx "core show version"
}

## sip/iax2 functions - nb. trunks names must container alphanumeric chars adn peer names only numbers
# return text
sip.registry() {
  $sudo asterisk -rx "sip show registry" | grep $1 | awk '{print $5}'
}

sip.peers.online(){
  $sudo asterisk -rx "sip show peers" | grep OK | awk '{print $1}' | grep -v [A-Za-z] | wc -l
}

sip.peers.offline(){
  $sudo asterisk -rx "sip show peers" | grep -e UNREACHABLE  -e UNKNOWN | awk '{print $1}' | grep -v [A-Za-z] | wc -l
}

sip.trunks.online(){
  $sudo asterisk -rx "sip show peers" | grep OK | awk '{print $1}' | grep [A-Za-z] | wc -l
}

sip.trunks.offline(){
  $sudo asterisk -rx "sip show peers" | grep -e UNREACHABLE  -e UNKNOWN | awk '{print $1}' | grep [A-Za-z] | wc -l
}

iax2.registry() {
  $sudo asterisk -rx "iax2 show registry" | grep $1 | awk '{print $5}'
}

iax2.peers.online(){
  $sudo asterisk -rx "iax2 show peers" | grep OK | awk '{print $1}' | wc -l
}

iax2.peers.offline(){
  $sudo asterisk -rx "iax2 show peers" | grep -e UNREACHABLE  -e UNKNOWN | awk '{print $1}' | wc -l
}

iax2.trunks.online(){
  $sudo asterisk -rx "iax2 show peers" | grep OK | awk '{print $1}' | grep [A-Za-z] | wc -l
}

iax2.trunks.offline(){
  $sudo asterisk -rx "iax2 show peers" | grep -e UNREACHABLE  -e UNKNOWN | awk '{print $1}' | grep [A-Za-z] | wc -l
}


# execute the passed command
#set -x
$cmd $@
