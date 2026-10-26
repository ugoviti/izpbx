# syntax=docker/dockerfile:1
# P2-03 test image: the izPBX image plus FOP2 in /usr/local/fop2, as P3-13
# will install it at start. izpbx-asterisk/tests/checks/P2-03.sh downloads the pinned
# tarball of versions.env on the host (x86_64) and puts it in the build
# context: the build itself needs no network.
ARG BASE=izpbx-asterisk:p2-03
FROM ${BASE}
ARG FOP2_SHA256
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY fop2.tgz /tmp/fop2.tgz
RUN echo "${FOP2_SHA256}  /tmp/fop2.tgz" | sha256sum -c - \
 && tar -xzf /tmp/fop2.tgz -C /tmp \
 && mkdir -p /usr/local/fop2 && cp -a /tmp/fop2/server/. /usr/local/fop2/ \
 && rm -rf /tmp/fop2 /tmp/fop2.tgz
