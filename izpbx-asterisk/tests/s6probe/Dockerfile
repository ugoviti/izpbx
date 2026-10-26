# syntax=docker/dockerfile:1
# P2-02 test image: the izPBX image plus a longrun "probe" that depends on
# izpbx-init and an init step that can fail (IZPBX_PROBE_FAIL=1)
ARG BASE=izpbx-asterisk:p2-02
FROM ${BASE}
COPY rootfs/ /
