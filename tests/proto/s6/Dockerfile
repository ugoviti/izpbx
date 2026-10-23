# syntax=docker/dockerfile:1
# P0-15 prototype: Asterisk under s6-overlay, two variants selected at build:
#   VARIANT=fwconsole   the service runs "fwconsole start" and watches Asterisk
#   VARIANT=direct      s6 supervises "asterisk -f" itself; safe_asterisk is a
#                       shim that asks s6 to start the service
FROM izpbx-proto/fpbx17:17.0.33
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG S6_OVERLAY_VER=3.2.3.2
ARG S6_NOARCH_SHA256=5379750ed30a84bbd2e2dd74847ba6b5bd29cd0b2e3ea2ec58049b57eb2eda12
ARG S6_X86_64_SHA256=e6befcc96a437a3831386ecfc51808c5d3e939dc5fe3c02ae9284599e8aa2408
ARG VARIANT=fwconsole
WORKDIR /tmp
RUN curl -fsSLO "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VER}/s6-overlay-noarch.tar.xz" \
 && curl -fsSLO "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VER}/s6-overlay-x86_64.tar.xz" \
 && printf '%s  %s\n' "$S6_NOARCH_SHA256" s6-overlay-noarch.tar.xz "$S6_X86_64_SHA256" s6-overlay-x86_64.tar.xz | sha256sum -c - \
 && tar -C / -Jxpf s6-overlay-noarch.tar.xz && tar -C / -Jxpf s6-overlay-x86_64.tar.xz \
 && rm -f s6-overlay-*.tar.xz
COPY rootfs/ /
COPY variants/${VARIANT}/s6/ /etc/s6-overlay/s6-rc.d/asterisk/
# variant direct also replaces /usr/sbin/safe_asterisk with a shim to s6
COPY variants/ /tmp/variants/
RUN if [ -d "/tmp/variants/${VARIANT}/rootfs" ]; then cp -a "/tmp/variants/${VARIANT}/rootfs/." /; fi && rm -rf /tmp/variants
RUN chmod 0755 /etc/s6-overlay/s6-rc.d/*/run /etc/s6-overlay/s6-rc.d/*/finish /usr/local/bin/proto-init.sh \
 && echo "$VARIANT" > /etc/izpbx-proto-variant
# first install can take minutes: no start timeout; shutdown: let fwconsole stop finish
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 S6_SERVICES_GRACETIME=25000 S6_KILL_GRACETIME=3000 S6_BEHAVIOUR_IF_STAGE2_FAILS=2
ENTRYPOINT ["/init"]
CMD []
