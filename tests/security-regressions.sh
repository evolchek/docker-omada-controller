#!/usr/bin/env bash
# Run inside the review image with --network none and --entrypoint bash.
set -euo pipefail

# Functions are extracted without executing the real entrypoint.
# shellcheck disable=SC1090
source <(sed '/^# initialize global EXEC_ARGS/,$d' /entrypoint.sh)

# Command-substitution text must remain literal, including URI punctuation.
EAP_MONGOD_URI='mongodb://user:$(touch /tmp/uri-executed)@localhost/omada?a=1&b=~x'
setup_environment
update_general_properties

[ ! -e /tmp/uri-executed ]
grep -Fx \
  "eap.mongod.uri=${EAP_MONGOD_URI}" \
  /opt/tplink/EAPController/properties/omada.properties

# Repeated writes must match literally, including old metacharacters.
EAP_MONGOD_URI='mongodb://localhost/omada?x=a&b=c'
update_general_properties
update_general_properties

grep -Fx \
  "eap.mongod.uri=${EAP_MONGOD_URI}" \
  /opt/tplink/EAPController/properties/omada.properties

# Extra MongoDB arguments must not execute shell commands.
export ROOTLESS=false
export MONGO_EXTERNAL=false
export MONGOD_EXTRA_ARGS='--quiet; touch /tmp/args-executed'
setup_mongodb_wrapper
bash -n /opt/tplink/EAPController/bin/mongod

# Replace only the binary with printf to inspect arguments without starting MongoDB.
sed -i \
  's|/usr/bin/mongod|/usr/bin/printf|' \
  /opt/tplink/EAPController/bin/mongod
/opt/tplink/EAPController/bin/mongod '%s\n' > /tmp/literal-args

grep -Fx -- '--quiet;' /tmp/literal-args
[ ! -e /tmp/args-executed ]

# Invalid input runs in a subshell because the helper exits on rejection.
if (
  EAP_MONGOD_URI=$'mongodb://localhost/\nother=value'
  update_general_properties
); then
  echo 'ERROR: newline injection accepted'
  exit 1
fi

# sha256sum must reject tampered payloads.
printf original > /tmp/payload
sha256sum /tmp/payload > /tmp/payload.sha256
printf changed > /tmp/payload

if sha256sum -c /tmp/payload.sha256; then
  exit 1
fi

echo 'Security regressions passed'
