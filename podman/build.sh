#!/bin/bash
cd ../izpbx-asterisk
podman build -t al3nas/izpbx:183 \
    --format=docker \
    --runtime=/usr/lib/cri-o-runc/sbin/runc \
    --pull=true \
    --rm \
    --cap-add=NET_ADMIN \
    --squash \
    --build-arg=APP_VER_BUILD=18.15.3 \
    --build-arg=APP_BUILD_COMMIT=123 \
    --build-arg=APP_BUILD_DATE=20210315 \
    -f Dockerfile