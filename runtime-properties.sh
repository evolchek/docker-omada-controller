#!/usr/bin/env bash
# Shared literal property updates for root and rootless entrypoints.

update_general_properties() {
  # Literal property replacement: never evaluate a URI or interpolate it into sed.
  local ELEM KEY VALUE FILE TMP LINE

  FILE="/opt/tplink/EAPController/properties/omada.properties"

  for ELEM in MONGO_EXTERNAL EAP_MONGOD_URI; do
    KEY="$(printf '%s' "${ELEM}" | tr '[:upper:]_' '[:lower:].')"
    VALUE="${!ELEM}"

    case "${VALUE}" in
      *$'\n'*|*$'\r'*|*\\*)
        echo "ERROR: ${ELEM} must be one literal properties line (percent-encode URI special characters)"
        exit 1
        ;;
    esac

    TMP="$(mktemp "${FILE}.XXXXXX")"

    while IFS= read -r LINE || [ -n "${LINE}" ]; do
      case "${LINE}" in
        "${KEY}="*)
          printf '%s=%s\n' "${KEY}" "${VALUE}"
          ;;
        *)
          printf '%s\n' "${LINE}"
          ;;
      esac
    done < "${FILE}" > "${TMP}"

    cat "${TMP}" > "${FILE}"
    rm -f "${TMP}"
  done
}
