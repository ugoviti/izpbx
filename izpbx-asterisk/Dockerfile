# syntax=docker/dockerfile:1
# izPBX 22.17: FreePBX 17 + Asterisk 22 on Debian 12.
# Versions and checksums: versions.env. Build logic: build/*.sh (one script per RUN).
#   docker build izpbx-asterisk
# The build scripts are removed by the last one (runtime.sh): the container keeps
# /usr/src/izpbx/versions.env only (read at runtime).

## base: Debian + runtime packages + asterisk user
# DEBIAN_IMAGE must match versions.env (checked by izpbx-asterisk/tests/checks/P1-04.sh)
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
RUN --mount=type=cache,target=/usr/src/download-cache \
    /usr/src/izpbx/build/node-modules.sh
# PHP settings and the php-fpm pool, enabled by runtime.sh
COPY rootfs/etc/php/ /etc/php/
RUN /usr/src/izpbx/build/runtime.sh
# izPBX init and services (s6-rc): only the parts already ported to 22.17
COPY rootfs/etc/s6-overlay/ /etc/s6-overlay/
COPY rootfs/usr/local/lib/izpbx/ /usr/local/lib/izpbx/
COPY rootfs/usr/local/sbin/izpbx-init /usr/local/sbin/izpbx-init
COPY rootfs/usr/sbin/safe_asterisk /usr/sbin/safe_asterisk
COPY rootfs/usr/local/sbin/izpbx-service /usr/local/sbin/izpbx-service
# izpbx-healthcheck and the izpbx-* tools (P3-32)
COPY rootfs/usr/local/bin/ /usr/local/bin/
COPY rootfs/usr/local/sbin/izpbx-inventory /usr/local/sbin/izpbx-inventory
COPY rootfs/usr/local/sbin/izpbx-preflight /usr/local/sbin/izpbx-preflight
COPY rootfs/usr/local/sbin/izpbx-migrate /usr/local/sbin/izpbx-migrate
COPY rootfs/usr/local/sbin/izpbx-rollback /usr/local/sbin/izpbx-rollback
COPY rootfs/etc/fail2ban/ /etc/fail2ban/
COPY rootfs/etc/dnsmasq.d/ /etc/dnsmasq.d/
COPY rootfs/usr/local/share/phonebook/ /usr/local/share/phonebook/
COPY rootfs/usr/local/share/izpbx/ /usr/local/share/izpbx/
COPY --chmod=0440 rootfs/etc/sudoers.d/zabbix /etc/sudoers.d/zabbix
# log rotation: Apache, Asterisk (full, messages, security, freepbx logs), fail2ban, FOP2
COPY rootfs/etc/logrotate.d/ /etc/logrotate.d/
COPY rootfs/etc/cron.daily/freepbx-le-renew /etc/cron.daily/freepbx-le-renew
# key of the Sangoma Debian repository (deb.freepbx.org/gpg/aptly-pubkey.asc,
# dearmored, expires 2028-02-11): no apt source uses it, but every install or
# upgrade of framework checks it and, missing or expiring within 30 days,
# raises the notice "Sangoma Debian Repository GPG Key Expiring Soon"
# (fwconsole runs as asterisk and cannot write it in /etc/apt/trusted.gpg.d)
COPY --chmod=0644 rootfs/etc/apt/trusted.gpg.d/freepbx.gpg /etc/apt/trusted.gpg.d/freepbx.gpg

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
# health (design H5): the first start installs FreePBX and a migration can
# take tens of minutes, so failures count only after 30 minutes
HEALTHCHECK --interval=30s --timeout=20s --start-period=30m --retries=3 CMD ["/usr/local/bin/izpbx-healthcheck"]
# s6-overlay is PID 1 (s6-svscan); without a CMD it runs the services only
ENTRYPOINT ["/init"]
CMD []
