# amd64 MongoDB conversion helper

Use only a disposable clone of a cold MongoDB 3.6 database.

Build with `docker build --platform linux/amd64 -f Dockerfile.upgrade-amd64 -t evolchek/omada-controller:review-mongodb-upgrade .` from this directory.

The helper requires ACK_DISPOSABLE_CLONE=yes, linux/amd64 with AVX, a clean lock and MongoDB 3.6 WiredTiger files. Mount the cloned data directory at /opt/tplink/EAPController/data. Use `--network none --init`. Never mount live controller data or the only backup. Never run a controller and helper against the same database concurrently.

Archive checksums pin the downloaded bytes; independent vendor signatures have not been verified. All seven intermediate server versions and mongosh must pass SHA256SUMS before extraction. Legacy binaries and Ubuntu 20.04 are confined to offline conversion. The main controller uses official Ubuntu 24.04 and installs the latest available MongoDB patch from the 8.0 repository when rebuilt; PACKAGES.tsv records the installed version. The helper’s intermediate MongoDB versions remain fixed.

The helper checks each featureCompatibilityVersion transition. It bounds waits and attempts verified recovery on failure. Its internal backup is on the same filesystem: keep a separate, checked cold backup and sufficient space. A power loss or SIGKILL can interrupt recovery; preserve archives and recover manually if needed. Do not rerun blindly or downgrade converted files.

See [Running tests](../README.md#running-tests) for build commands and synthetic success/rollback tests. Before production use, rehearse on the target hardware using a disposable copy of a verified backup.
