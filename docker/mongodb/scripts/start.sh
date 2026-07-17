#!/usr/bin/env bash
set -euo pipefail

# Start/recreate flow for hardened MongoDB:
# - validate env and non-root IDs
# - generate/reuse TLS materials
# - ensure data volume ownership for runtime UID/GID
# - recreate container via docker compose
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATED_DIR="$BASE_DIR/.generated"
GENERATED_TLS_DIR="$GENERATED_DIR/tls"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/env-file-load-and-validate.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/print-setup-guide.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/tls-assets.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/volume-assets.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/container-readiness.sh"

load_mongodb_runtime_env_or_exit "$BASE_DIR"

validate_static_env_vars_or_exit
ensure_no_running_mongodb_instances_or_exit

ensure_mongodb_tls_assets_or_exit "$GENERATED_TLS_DIR" "$MONGODB_UID" "$MONGODB_GID"

cd "$BASE_DIR"

sudo docker compose down --remove-orphans >/dev/null 2>&1 || true

ensure_container_name_available_or_exit "$MONGODB_CONTAINER_NAME"

validate_free_local_port_or_exit "$MONGODB_HOST_PORT" "MONGODB_HOST_PORT"
ensure_mongodb_volume_permissions_or_exit "$MONGODB_VOLUME_NAME" "$MONGODB_UID" "$MONGODB_GID"

sudo docker compose up -d --build

wait_for_container_ready_or_exit "$MONGODB_CONTAINER_NAME"

# Wait for MongoDB to accept TLS connections (not just for container to be running)

echo "Wait a few seconds for MongoDB to be fully ready before running integration tests..."
echo "TODO: Reseach why is this necessary. Is there a better way to check for readyness?"

sleep 5


set +u  # Allow sourcing scripts that reference unset variables
source "${SCRIPT_DIR}/integration-test.sh"
set -u

if run_integration_tests; then
  echo "Integration tests passed."
else
  echo "Integration tests failed."
  exit 1
fi




print_mongodb_setup_guide