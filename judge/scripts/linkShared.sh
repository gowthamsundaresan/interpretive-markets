#!/usr/bin/env bash
set -euo pipefail

# Symlinks @interpretive/shared from the sibling interpretive-markets-backend repo
# into this package's node_modules. The user maintains a plain symlink for local
# dev until @interpretive/shared is published to npm.

SHARED_REL_PATH="../../../../interpretive-markets-backend/packages/shared"
TARGET_DIR="node_modules/@interpretive"

mkdir -p "${TARGET_DIR}"
ln -sfn "${SHARED_REL_PATH}" "${TARGET_DIR}/shared"

echo "linked @interpretive/shared -> ${SHARED_REL_PATH}"
