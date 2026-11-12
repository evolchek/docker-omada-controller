#!/usr/bin/env bash
# Staged physical upgrade for a disposable cold MongoDB 3.6 clone only.
set -Eeuo pipefail

DATA=/opt/tplink/EAPController/data
WAIT_SECONDS=${WAIT_SECONDS:-120}

[[ "${WAIT_SECONDS}" =~ ^[1-9][0-9]*$ ]] || {
  echo 'ERROR: invalid WAIT_SECONDS'
  exit 1
}
[ "${ACK_DISPOSABLE_CLONE:-}" = yes ] || {
  echo 'ERROR: set ACK_DISPOSABLE_CLONE=yes only for a disposable cold clone'
  exit 1
}
[ "$(uname -m)" = x86_64 ] && grep -qE '^flags.* avx( .*|$)' /proc/cpuinfo || {
  echo 'ERROR: native amd64 AVX required'
  exit 1
}
[ -f "${DATA}/db/WiredTiger" ] && [ -f "${DATA}/db/storage.bson" ] || {
  echo 'ERROR: missing database'
  exit 1
}
[ ! -s "${DATA}/db/mongod.lock" ] || {
  echo 'ERROR: database was not shut down cleanly'
  exit 1
}
WT=$(grep -o 'WiredTiger [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' "${DATA}/db/WiredTiger.turtle" | cut -d' ' -f2)
case "${WT}" in
  3.1.0|3.1.1)
    ;;
  *)
    echo 'ERROR: expected MongoDB 3.6 WiredTiger'
    exit 1
    ;;
esac

ORIGINAL_OWNER=$(stat -c '%u:%g' "${DATA}/db")
cd "${DATA}"

# Never overwrite a previous recovery archive.
BACKUP=$(mktemp "${DATA}/mongodb-preupgrade.XXXXXXXX.tar")
tar cf "${BACKUP}" db
tar tf "${BACKUP}" >/dev/null
sha256sum "${BACKUP}" > "${BACKUP}.sha256"

rollback() {
  trap - ERR INT TERM
  echo 'ERROR: upgrade failed; stopping helper MongoDB before restoring clone'
  if [ -s "${DATA}/mongo.pid" ]; then
    PID=$(cat "${DATA}/mongo.pid")
    if kill -0 "${PID}" 2>/dev/null; then
      kill -TERM "${PID}" || true

      for ((i = 0; i < WAIT_SECONDS; i++)); do
        kill -0 "${PID}" 2>/dev/null || break
        sleep 1
      done

      if kill -0 "${PID}" 2>/dev/null; then
        echo 'ERROR: MongoDB did not stop. No restore attempted; preserve backup for manual recovery.'
        exit 1
      fi
    fi
  fi

  if ! sha256sum -c "${BACKUP}.sha256" || ! tar tf "${BACKUP}" >/dev/null; then
    echo 'ERROR: backup verification failed; no restore attempted'
    exit 1
  fi

  FAILED=$(mktemp -d "${DATA}/mongodb-failed.XXXXXXXX")
  if mv db "${FAILED}/db" && tar xf "${BACKUP}"; then
    rm -f "${DATA}/mongo.pid"
    echo "Restored pre-upgrade clone; failed database retained in ${FAILED}"
  else
    echo 'ERROR: restore failed. Recover from independent cold backup.'
  fi

  exit 1
}

trap rollback ERR INT TERM

mongo_eval() {
  timeout "${WAIT_SECONDS}" "/tmp/${CLIENT}" --quiet --eval "$1"
}

for SPEC in \
  '4.0.28:3.6' \
  '4.2.23:4.0' \
  '4.4.18:4.2' \
  '5.0.31:4.4' \
  '6.0.25:5.0' \
  '7.0.22:6.0' \
  '8.0.12:7.0'; do
  VER=${SPEC%:*}
  EXPECTED=${SPEC#*:}
  TARGET=${VER%.*}

  CLIENT=mongo-${VER}
  case "${TARGET}" in
    6.0|7.0|8.0)
      CLIENT=mongosh
      ;;
  esac

  JOURNAL=(--journal)
  case "${TARGET}" in
    7.0|8.0)
      JOURNAL=()
      ;;
  esac

  rm -f "${DATA}/mongo.pid"
  echo "Upgrading to ${VER}; expecting FCV ${EXPECTED}"
  timeout "${WAIT_SECONDS}" "/tmp/mongod-${VER}" \
    --fork \
    --dbpath "${DATA}/db" \
    --pidfilepath "${DATA}/mongo.pid" \
    --bind_ip 127.0.0.1 \
    --logpath "${DATA}/mongodb_upgrade.log" \
    --logappend \
    "${JOURNAL[@]}"

  READY=false
  for ((i = 0; i < WAIT_SECONDS; i++)); do
    if timeout 2 "/tmp/${CLIENT}" --quiet \
      --eval 'quit(db.adminCommand({ping:1}).ok === 1 ? 0 : 1)' \
      >/dev/null 2>&1; then
      READY=true
      break
    fi
    sleep 1
  done

  [ "${READY}" = true ]

  mongo_eval \
    "if (db.adminCommand({getParameter:1,featureCompatibilityVersion:1}).featureCompatibilityVersion.version !== '${EXPECTED}') quit(1)"
  CONFIRM=''
  case "${TARGET}" in
    7.0|8.0)
      CONFIRM=',confirm:true'
      ;;
  esac

  mongo_eval \
    "if (db.adminCommand({setFeatureCompatibilityVersion:'${TARGET}'${CONFIRM}}).ok !== 1) quit(1)"
  mongo_eval \
    "if (db.adminCommand({getParameter:1,featureCompatibilityVersion:1}).featureCompatibilityVersion.version !== '${TARGET}') quit(1)"

  # Shutdown intentionally closes the shell connection, so verify process exit separately.
  PID=$(cat "${DATA}/mongo.pid")
  mongo_eval 'db.adminCommand({shutdown:1})' >/dev/null 2>&1 || true
  for ((i = 0; i < WAIT_SECONDS; i++)); do
    kill -0 "${PID}" 2>/dev/null || break
    sleep 1
  done
  ! kill -0 "${PID}" 2>/dev/null
  rm -f "${DATA}/mongo.pid"
done

trap - ERR INT TERM

# Keep original database ownership; helper runs as root only during the conversion.
chown -R "${ORIGINAL_OWNER}" "${DATA}/db"

echo "Upgrade complete. Preserve ${BACKUP} and the independent cold backup. Validate a controller on this clone before any cutover."
