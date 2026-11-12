#!/usr/bin/env bash
# Pinned amd64 6.3 build.
set -euo pipefail
. /build-inputs.env
[ "${INSTALL_VER:-}" = "${OMADA_VERSION}" ] || { echo 'ERROR: INSTALL_VER must match build-inputs.env'; exit 1; }
[ "${ARCH:-}" = amd64 ] && [ "$(dpkg --print-architecture)" = amd64 ] || { echo 'ERROR: only linux/amd64 is supported by this pinned vendor archive'; exit 1; }
case "${NO_MONGODB:-false}" in true|false) ;; *) echo 'ERROR: invalid NO_MONGODB'; exit 1 ;; esac
OMADA_DIR=/opt/tplink/EAPController
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install --no-install-recommends -y ca-certificates wget gnupg
if [ "${NO_MONGODB:-false}" = false ]; then
  mkdir -p /etc/apt/keyrings
  wget --https-only --timeout=60 --tries=3 -O /tmp/mongodb.asc https://www.mongodb.org/static/pgp/server-8.0.asc
  printf '%s  %s\n' "${MONGODB_KEY_SHA256}" /tmp/mongodb.asc | sha256sum -c -
  gpg --batch --dearmor -o /etc/apt/keyrings/mongodb-server-8.0.gpg /tmp/mongodb.asc
  printf '%s\n' 'deb [arch=amd64 signed-by=/etc/apt/keyrings/mongodb-server-8.0.gpg] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse' > /etc/apt/sources.list.d/mongodb-org-8.0.list
  apt-get update
  apt-get install --no-install-recommends -y mongodb-org-server
fi
apt-get install --no-install-recommends -y gosu libharfbuzz0b libfontconfig1 net-tools tzdata openjdk-17-jre-headless
wget --https-only --timeout=60 --tries=3 -O /tmp/omada.tar.gz "${OMADA_URL}"
printf '%s  %s\n' "${OMADA_SHA256}" /tmp/omada.tar.gz | sha256sum -c -
mkdir -p /tmp/omada "${OMADA_DIR}"
tar xzf /tmp/omada.tar.gz -C /tmp/omada --no-same-owner
cd "/tmp/omada/Omada_Network_Application_v${OMADA_VERSION}_linux_x64"
for name in bin data lib properties install.sh uninstall.sh; do
  cp -r "${name}" "${OMADA_DIR}/"
done
cat >> "${OMADA_DIR}/properties/omada.properties" <<'PROPERTIES'

# Container overrides
web.config.override=false
mongo.external=false
eap.mongod.uri=mongodb://127.0.0.1:27217/omada
PROPERTIES
cp -r "${OMADA_DIR}/properties" "${OMADA_DIR}/properties.defaults"
# Default rootless UID/GID; arbitrary rootless UIDs must have writable properties mounted.
chown -R 508:508 "${OMADA_DIR}/properties"
find "${OMADA_DIR}/properties" -type d -exec chmod 750 {} +
find "${OMADA_DIR}/properties" -type f -exec chmod 640 {} +
if [ "${NO_MONGODB:-false}" = false ]; then
  ln -sf /usr/bin/mongod "${OMADA_DIR}/bin/mongod"
fi
chmod 755 "${OMADA_DIR}"/bin/*
mkdir -p "${OMADA_DIR}/logs"
chown -R 508:508 "${OMADA_DIR}/data" "${OMADA_DIR}/logs"
if [ -d "${OMADA_DIR}/data/html" ]; then
  tar zcf "${OMADA_DIR}/data-html.tar.gz" -C "${OMADA_DIR}/data" html
fi
printf '%s\n' "${OMADA_VERSION}" > "${OMADA_DIR}/IMAGE_OMADA_VER.txt"
cp /build-inputs.env "${OMADA_DIR}/BUILD_INPUTS.env"
dpkg-query -W -f='${Package}\t${Version}\n' > "${OMADA_DIR}/PACKAGES.tsv"
rm -rf /tmp/* /var/lib/apt/lists/* /var/lib/mongodb /var/log/mongodb
