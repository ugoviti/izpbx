# syntax=docker/dockerfile:1
# sipp for the tests (P3-09): the Debian package on the same pinned base as
# the izPBX image (versions.env DEBIAN_IMAGE), so the version is fixed by the
# image digest and the Debian archive; never installed on the host.
ARG BASE=docker.io/library/debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
FROM ${BASE}
RUN apt-get update && apt-get install -y --no-install-recommends sip-tester \
 && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["sipp"]
