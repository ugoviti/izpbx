#!/bin/bash
# P3-21: samples the command line of every process until /tmp/sampler.stop
# exists. The secrets are only in /secrets/patterns (read by grep -f), never
# in an argument of this script or of its commands. Results:
#   /tmp/sampler.hits  command lines holding a secret
#   /tmp/sampler.seen  one line per sample in which the installer was running
#   /tmp/sampler.count number of samples
n=0
: > /tmp/sampler.hits; : > /tmp/sampler.seen
until [ -e /tmp/sampler.stop ]; do
  for p in /proc/[0-9]*; do tr '\0' ' ' < "$p/cmdline" 2>/dev/null; echo; done > /tmp/sampler.snap
  grep -F -f /secrets/patterns /tmp/sampler.snap >> /tmp/sampler.hits || true
  grep -q 'freepbx-install.php' /tmp/sampler.snap && echo "$n" >> /tmp/sampler.seen
  n=$((n + 1)); echo "$n" > /tmp/sampler.count
  sleep 0.2
done
