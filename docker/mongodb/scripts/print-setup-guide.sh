#!/usr/bin/env bash

# Prints post-start operator commands (connectivity, logs, security checks).

run_print_mongodb_setup_guide_or_exit() {
	local script_dir base_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	base_dir="$(cd "$script_dir/.." && pwd)"

	# Standalone use should self-load env values before printing the guide.
	# shellcheck disable=SC1091
	source "$script_dir/env-file-load-and-validate.sh"

	load_mongodb_runtime_env_or_exit "$base_dir"
	validate_static_env_vars_or_exit
	print_mongodb_setup_guide
}

print_mongodb_setup_guide() {
	local script_dir base_dir ca_file
	local local_host="localhost"
	local remote_host="${MONGODB_DOMAIN:-}"
	local local_root_uri="mongodb://${MONGODB_ROOT_USERNAME}:${MONGODB_ROOT_PASSWORD}@${local_host}:${MONGODB_HOST_PORT}/admin?authSource=admin"
	local local_app_uri="mongodb://${MONGODB_APP_USERNAME}:${MONGODB_APP_PASSWORD}@${local_host}:${MONGODB_HOST_PORT}/${MONGODB_APP_DATABASE}?authSource=${MONGODB_APP_DATABASE}"
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	base_dir="$(cd "$script_dir/.." && pwd)"
	ca_file="$base_dir/.generated/tls/ca.crt"

	echo
	echo "--- Container Status ---"
	sudo docker ps --filter "name=${MONGODB_CONTAINER_NAME}"

	echo
	echo "============================================================"
	echo "                 MongoDB Setup Guide"
	echo "============================================================"
	echo
	echo "[Endpoints]"
	echo "Local (Not Recommended):  mongodb://${local_host}:${MONGODB_HOST_PORT}"
	if [[ -n "$remote_host" && "$remote_host" != "localhost" ]]; then
		echo "Domain: mongodb://${remote_host}:${MONGODB_HOST_PORT}"
	fi
	echo
	echo "[Connection Instructions]"
	# Domain-based connection URIs
	local domain_uri_root="mongodb://${MONGODB_ROOT_USERNAME}:${MONGODB_ROOT_PASSWORD}@${MONGODB_DOMAIN}:${MONGODB_HOST_PORT}/admin?authSource=admin"
	local domain_uri_app="mongodb://${MONGODB_APP_USERNAME}:${MONGODB_APP_PASSWORD}@${MONGODB_DOMAIN}:${MONGODB_HOST_PORT}/${MONGODB_APP_DATABASE}?authSource=${MONGODB_APP_DATABASE}"
	echo "(1) Connect as root (TLS, recommended)]"
	echo "mongosh --tls \"$domain_uri_root\" "
	echo

	echo "(2) Connect as app user (TLS, recommended)]"
	echo "mongosh --tls \"$domain_uri_app\" "
	echo

	echo "[If you must skip TLS (not recommended, unencrypted connection):]"
	echo "mongosh \"$domain_uri_root\""
	echo "mongosh \"$domain_uri_app\""
	echo
	echo "[Diagnostics]"
	echo "Check logs:"
	echo "sudo docker logs --tail 100 ${MONGODB_CONTAINER_NAME}"
	echo
	echo "Check least-privilege runtime settings:"
	echo "sudo docker inspect ${MONGODB_CONTAINER_NAME} --format 'user={{.Config.User}} cap_drop={{.HostConfig.CapDrop}} security_opt={{.HostConfig.SecurityOpt}}'"
	echo
	echo "[Integration Tests]"
	echo "Verify app user and root user operations end-to-end:"
	echo "  sudo bash ./scripts/integration-test.sh"
	echo
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	set -euo pipefail
	run_print_mongodb_setup_guide_or_exit "$@"
fi
