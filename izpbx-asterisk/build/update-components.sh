# download the FreePBX modules list used by the Dockerfile for offline builds (optional: the Dockerfile downloads it if missing)
# NOTE: query the mirror like FreePBX Module Admin does (POST to all-X.0.xml): the static modules-X.0.xml file lists older releases
curl -fSL --connect-timeout 30 -X POST -d "phpver=7.4" https://mirror.freepbx.org/all-16.0.xml -o modules-16.0.xml
