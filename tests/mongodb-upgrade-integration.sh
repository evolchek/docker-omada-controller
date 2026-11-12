#!/usr/bin/env bash
# Synthetic data only. Uses unique named volumes and removes them on exit.
set -euo pipefail

FIXTURE=omada-review-mongo36-fixture
HELPER=evolchek/omada-controller:review-mongodb-upgrade
PREFIX=omada-review-integration-$$

cleanup() {
  docker volume rm \
    "${PREFIX}-success" \
    "${PREFIX}-rollback" \
    >/dev/null 2>&1 || true
}

trap cleanup EXIT

seed() {
  docker run --rm --init \
    --platform linux/amd64 \
    --network none \
    --entrypoint bash \
    -e FCV="$2" \
    -v "$1:/data" \
    "${FIXTURE}" -ec '
      mkdir -p /data/db
      mongod --fork \
        --bind_ip 127.0.0.1 \
        --dbpath /data/db \
        --logpath /tmp/mongo.log

      mongo --quiet --eval "
        db.getSiblingDB(\"omada\").sentinel.insert({test:\"preserve-me\"});
        db.adminCommand({setFeatureCompatibilityVersion:\"${FCV}\"})
      "

      mongod --dbpath /data/db --shutdown
    '
}

# Upgrade a supported fixture, then verify its data and compatibility version.
seed "${PREFIX}-success" 3.6

docker run --rm --init \
  --platform linux/amd64 \
  --network none \
  -e ACK_DISPOSABLE_CLONE=yes \
  -v "${PREFIX}-success:/opt/tplink/EAPController/data" \
  "${HELPER}"

docker run --rm --init \
  --platform linux/amd64 \
  --network none \
  --entrypoint bash \
  -v "${PREFIX}-success:/data" \
  "${HELPER}" -ec '
    /tmp/mongod-8.0.12 --fork \
      --dbpath /data/db \
      --bind_ip 127.0.0.1 \
      --logpath /tmp/check.log

    /tmp/mongosh --quiet --eval '\''
      if (db.getSiblingDB("omada").sentinel.findOne({test:"preserve-me"}) === null) quit(1);
      if (db.adminCommand({getParameter:1,featureCompatibilityVersion:1}).featureCompatibilityVersion.version !== "8.0") quit(1);
      print("Upgrade sentinel and FCV verified");
    '\''

    /tmp/mongosh --quiet --eval '\''db.adminCommand({shutdown:1})'\'' || true
  '

# An unsupported fixture must fail and remain readable after rollback.
seed "${PREFIX}-rollback" 3.4

if docker run --rm --init \
  --platform linux/amd64 \
  --network none \
  -e ACK_DISPOSABLE_CLONE=yes \
  -v "${PREFIX}-rollback:/opt/tplink/EAPController/data" \
  "${HELPER}"; then
  echo 'ERROR: unsupported FCV unexpectedly upgraded'
  exit 1
fi

docker run --rm --init \
  --platform linux/amd64 \
  --network none \
  --entrypoint bash \
  -v "${PREFIX}-rollback:/data" \
  "${FIXTURE}" -ec '
    mongod --fork \
      --bind_ip 127.0.0.1 \
      --dbpath /data/db \
      --logpath /tmp/check.log

    mongo --quiet --eval '\''
      if (db.getSiblingDB("omada").sentinel.findOne({test:"preserve-me"}) === null) quit(1);
      if (db.adminCommand({getParameter:1,featureCompatibilityVersion:1}).featureCompatibilityVersion.version !== "3.4") quit(1);
      print("Rollback sentinel and FCV verified");
    '\''

    mongod --dbpath /data/db --shutdown
  '

echo 'MongoDB upgrade and rollback integration tests passed'
