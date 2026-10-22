# syntax=docker/dockerfile:1
# SIPp for SIP call tests, built from the release tarball with a pinned sha256.
FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8 AS build
ARG SIPP_VER=3.7.3
ARG SIPP_SHA256=f7cf9ced5e2915c6aa8d88b48a32869ce5bc1f23b0b8da0de4df928db4925bf7
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl cmake g++ make \
      libncurses-dev libssl-dev libpcap-dev libsctp-dev libgsl-dev
WORKDIR /src
RUN curl -fsSLo sipp.tar.gz "https://github.com/SIPp/sipp/releases/download/v${SIPP_VER}/sipp-${SIPP_VER}.tar.gz" \
 && echo "${SIPP_SHA256}  sipp.tar.gz" | sha256sum -c - \
 && tar xzf sipp.tar.gz --strip-components=1 \
 && cmake . -DUSE_SSL=1 -DUSE_PCAP=1 -DUSE_SCTP=1 -DUSE_GSL=1 \
 && make -j"$(nproc)" sipp

FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
RUN apt-get update \
 && apt-get install -y --no-install-recommends libncursesw6 libssl3 libpcap0.8 libsctp1 libgsl27 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/sipp /usr/local/bin/sipp
ENTRYPOINT ["sipp"]
