#!/bin/bash
# Asterisk automatic discovery and check script
# author: Ugo Viti <ugo.viti@initzero.it>
# version: 20200330

# comment to disable sudo
sudo=sudo

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

discovery.sip.registry() {
echo "{
  \"data\":
  ["
$sudo asterisk -r -x "sip show registry" | grep -v -e "^Host" -e "SIP registrations" | while read registry; do
HOST="$(echo $registry | awk '{print $1}')"
USERNAME="$(echo $registry | awk '{print $3}')"
STATE="$(echo $registry | awk '{print $5}')"
echo "    { \"{#HOST}\":\"$HOST\", \"{#USERNAME}\":\"$USERNAME\", \"{#STATE}\":\"$STATE\"},"
done | sed '$ s/,$//'
echo "  ]
}"
}

sip.registry() {
  $sudo asterisk -rx "sip show registry" | grep $1 | awk '{print $5}'
}

version() {
  $sudo asterisk -rx "core show version"
}

# execute the passed command
#set -x
$cmd $@
