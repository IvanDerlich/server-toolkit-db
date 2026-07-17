#!/usr/bin/env bash
set -euo pipefail

# Fast preflight check: validate env values/dependencies without starting containers.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/env-file-load-and-validate.sh"

load_mongodb_runtime_env_or_exit "$BASE_DIR"

validate_all_env_vars_or_exit

if ! command -v openssl >/dev/null 2>&1; then
	echo "OpenSSL is required to generate MongoDB TLS certificates."
	echo "Install openssl and rerun this check."
	exit 1
fi

echo ".env validation: OK"
echo "Local host port ${MONGODB_HOST_PORT}: available"
echo "Container name: ${MONGODB_CONTAINER_NAME}"
echo "Volume name: ${MONGODB_VOLUME_NAME}"
echo "Runtime user: ${MONGODB_UID}:${MONGODB_GID}"