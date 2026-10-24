# syntax=docker/dockerfile:1
# izPBX 22.17: FreePBX 17 + Asterisk 22 on Debian 12.
# Versions and checksums: versions.env. Build logic: build/*.sh (one script per RUN).
#   docker build izpbx-asterisk

## base: Debian + runtime packages + asterisk user
# DEBIAN_IMAGE must match versions.env (checked by tests/checks/P1-04.sh)
FROM docker.io/library/debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8 AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG OS_UPDATE_STAMP=""
# only what base.sh reads: other changes do not invalidate the base layer
COPY versions.env /usr/src/izpbx/versions.env
COPY build/lib.sh build/base.sh build/packages-runtime.txt /usr/src/izpbx/build/
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    /usr/src/izpbx/build/base.sh

## builder: toolchain, Asterisk and addons installed into /staging
FROM base AS builder
COPY build/apt.sh build/packages-build.txt /usr/src/izpbx/build/
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    /usr/src/izpbx/build/apt.sh /usr/src/izpbx/build/packages-build.txt
COPY versions.env /usr/src/izpbx/versions.env
COPY build/asterisk.sh build/asterisk-menuselect.txt /usr/src/izpbx/build/
RUN --mount=type=cache,target=/root/.ccache \
    --mount=type=cache,target=/usr/src/download-cache \
    /usr/src/izpbx/build/asterisk.sh
COPY build/addons.sh /usr/src/izpbx/build/
RUN --mount=type=cache,target=/root/.ccache \
    --mount=type=cache,target=/usr/src/download-cache \
    /usr/src/izpbx/build/addons.sh

## freepbx: FreePBX 17 install tree (independent of builder: built in parallel)
FROM base AS freepbx
COPY versions.env /usr/src/izpbx/versions.env
COPY build/freepbx.sh build/freepbx-modules.txt /usr/src/izpbx/build/
RUN --mount=type=cache,target=/usr/src/download-cache \
    /usr/src/izpbx/build/freepbx.sh

## runtime: base + build results, no toolchain
FROM base AS runtime
COPY --from=builder /staging/ /
COPY --from=freepbx /usr/src/freepbx /usr/src/freepbx
COPY versions.env /usr/src/izpbx/versions.env
COPY build/ /usr/src/izpbx/build/
RUN --mount=type=cache,target=/usr/src/download-cache \
    /usr/src/izpbx/build/extras.sh
RUN --mount=type=cache,target=/usr/src/download-cache \
    /usr/src/izpbx/build/s6.sh
# PHP settings and the php-fpm pool, enabled by runtime.sh
COPY rootfs/etc/php/ /etc/php/
RUN /usr/src/izpbx/build/runtime.sh
# izPBX init and services (s6-rc): only the parts already ported to 22.17
COPY rootfs/etc/s6-overlay/ /etc/s6-overlay/
COPY rootfs/usr/local/lib/izpbx/ /usr/local/lib/izpbx/
COPY rootfs/usr/local/sbin/izpbx-init /usr/local/sbin/izpbx-init
COPY rootfs/usr/sbin/safe_asterisk /usr/sbin/safe_asterisk
COPY rootfs/usr/local/sbin/izpbx-service /usr/local/sbin/izpbx-service
COPY rootfs/etc/fail2ban/ /etc/fail2ban/
COPY rootfs/etc/dnsmasq.d/ /etc/dnsmasq.d/
COPY rootfs/usr/local/share/phonebook/ /usr/local/share/phonebook/
COPY --chmod=0440 rootfs/etc/sudoers.d/zabbix /etc/sudoers.d/zabbix
COPY rootfs/etc/logrotate.d/httpd /etc/logrotate.d/httpd
COPY rootfs/etc/cron.daily/freepbx-le-renew /etc/cron.daily/freepbx-le-renew

ARG APP_VER
ARG APP_VER_BUILD
ARG APP_BUILD_COMMIT
ARG APP_BUILD_DATE
LABEL org.opencontainers.image.title="izpbx-asterisk" \
      org.opencontainers.image.description="izPBX Cloud Native Telephony System" \
      org.opencontainers.image.source="https://github.com/ugoviti/izpbx" \
      org.opencontainers.image.version="${APP_VER:-dev}"
ENV APP_NAME="izpbx-asterisk" \
    APP_VER="${APP_VER:-dev}" \
    APP_VER_BUILD="${APP_VER_BUILD}" \
    APP_BUILD_COMMIT="${APP_BUILD_COMMIT}" \
    APP_BUILD_DATE="${APP_BUILD_DATE}" \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2
# S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0: the first izpbx-init (FreePBX install)
# takes minutes; S6_BEHAVIOUR_IF_STAGE2_FAILS=2: a failed izpbx-init stops
# the container instead of leaving it up without services
# s6-overlay is PID 1 (s6-svscan); without a CMD it runs the services only
ENTRYPOINT ["/init"]
CMD []
