# syntax=docker/dockerfile:1
# P0-14: the FreePBX 17 prototype without a C/C++ toolchain (gcc, g++, cc,
# make removed after Asterisk is built), like the izPBX runtime image: the
# npm installs of pm2 and ucp must not need node-gyp.
FROM izpbx-proto/fpbx17:17.0.33
RUN apt-get purge -y build-essential gcc g++ cpp make gcc-12 g++-12 cpp-12 >/dev/null \
 && apt-get autoremove -y >/dev/null \
 && ! command -v gcc && ! command -v cc && ! command -v make && ! command -v g++ && ! command -v c++
