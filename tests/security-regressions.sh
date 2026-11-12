#!/usr/bin/env bash
# Run inside the test image with --network none and --entrypoint bash.
set -euo pipefail

# shellcheck source=runtime-properties.sh
source /runtime-properties.sh

export MONGO_EXTERNAL=false

# Command-substitution text must remain literal, including URI punctuation.
EAP_MONGOD_URI='mongodb://user:$(touch /tmp/uri-executed)@localhost/omada?a=1&b=~x'
update_general_properties

[ ! -e /tmp/uri-executed ]
grep -Fx \
  "eap.mongod.uri=${EAP_MONGOD_URI}" \
  /opt/tplink/EAPController/properties/omada.properties

# Repeated updates must preserve the exact property value.
EAP_MONGOD_URI='mongodb://localhost/omada?x=a&b=c'
update_general_properties
update_general_properties

grep -Fx \
  "eap.mongod.uri=${EAP_MONGOD_URI}" \
  /opt/tplink/EAPController/properties/omada.properties

# Each rejection runs in a subshell because the helper exits on invalid input.
if (
  EAP_MONGOD_URI=$'mongodb://localhost/\nother=value'
  update_general_properties
); then
  echo 'ERROR: newline injection accepted'
  exit 1
fi

if (
  EAP_MONGOD_URI='mongodb://localhost/\bad'
  update_general_properties
); then
  echo 'ERROR: properties escape accepted'
  exit 1
fi

echo 'Security regressions passed'
