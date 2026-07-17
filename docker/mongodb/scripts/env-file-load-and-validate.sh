#!/usr/bin/env bash

# Shared .env loading + validation helpers for MongoDB operational scripts.
# These functions intentionally exit on validation errors to keep callers simple.

load_and_validate_env() {
	local script_dir="$1"
	local env_file="$script_dir/.env"
	shift
	local required_vars=("$@")

	# Source .env in the current shell so all helpers can read exported values.
	if [[ ! -f "$env_file" ]]; then
		echo "Missing .env file: $env_file"
		echo "Copy .env.example to .env and fill in the required values."
		exit 1
	fi

	if [[ ! -s "$env_file" ]]; then
		echo "Empty .env file: $env_file"
		echo "Fill in the required values before running this script."
		exit 1
	fi

	set -a
	# shellcheck disable=SC1090
	source "$env_file"
	set +a

	local missing_vars=()
	local var_name
	for var_name in "${required_vars[@]}"; do
		if [[ -z "${!var_name:-}" ]]; then
			missing_vars+=("$var_name")
		fi
	done

	if (( ${#missing_vars[@]} > 0 )); then
		echo "Missing required values in $env_file:"
		for var_name in "${missing_vars[@]}"; do
			echo "- $var_name"
		done
		exit 1
	fi
}

load_mongodb_runtime_env_or_exit() {
	local base_dir="$1"

	       load_and_validate_env "$base_dir" \
		       "MONGODB_CONTAINER_NAME" \
		       "MONGODB_IMAGE_TAG" \
		       "MONGODB_HOST_PORT" \
		       "MONGODB_VOLUME_NAME" \
		       "MONGODB_ROOT_USERNAME" \
		       "MONGODB_ROOT_PASSWORD" \
		       "MONGODB_APP_DATABASE" \
		       "MONGODB_APP_USERNAME" \
		       "MONGODB_APP_PASSWORD" \
		       "MONGODB_DOMAIN"
}

validate_port_value_or_exit() {
	local port="$1"
	local env_var_name="$2"

	if [[ ! "$port" =~ ^[0-9]+$ ]]; then
		echo "Invalid ${env_var_name} value: ${port}."
		echo "Please edit .env and set ${env_var_name} to a number between 1 and 65535."
		exit 1
	fi

	if (( port < 1 || port > 65535 )); then
		echo "Invalid ${env_var_name} value: ${port}."
		echo "Please edit .env and set ${env_var_name} to a number between 1 and 65535."
		exit 1
	fi
}

validate_port_env_var_or_exit() {
	local env_var_name="$1"
	local port_value="${!env_var_name}"

	validate_port_value_or_exit "$port_value" "$env_var_name"
}

validate_unix_id_value_or_exit() {
	local id_value="$1"
	local env_var_name="$2"

	# UID/GID must be numeric so Docker can apply user/group mapping reliably.
	if [[ ! "$id_value" =~ ^[0-9]+$ ]]; then
		echo "Invalid ${env_var_name} value: ${id_value}."
		echo "Please edit .env and set ${env_var_name} to a positive integer (for example 999)."
		exit 1
	fi

	# Reject 0 to prevent running the MongoDB container as root.
	if (( id_value <= 0 )); then
		echo "Invalid ${env_var_name} value: ${id_value}."
		echo "${env_var_name} must be greater than 0 so the container does not run as root."
		exit 1
	fi
}

validate_free_local_port_or_exit() {
	local port="$1"
	local env_var_name="$2"

	if ss -ltnH "( sport = :${port} )" 2>/dev/null | grep -q .; then
		echo "Local port ${port} is already occupied."
		echo "Please edit .env and choose another ${env_var_name} value."
		echo "Or free it:"
		echo "sudo ss -ltnp \"( sport = :${port} )\""
		echo "sudo fuser -k ${port}/tcp"
		exit 1
	fi
}

validate_simple_name_or_exit() {
	local value="$1"
	local env_var_name="$2"

	if [[ ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
		echo "Invalid ${env_var_name} value: ${value}."
		echo "Use only letters, numbers, dot, underscore, and dash."
		exit 1
	fi
}

validate_static_env_vars_or_exit() {
	# Use sane non-root defaults when UID/GID are not set in .env.
	: "${MONGODB_UID:=999}"
	: "${MONGODB_GID:=999}"

	validate_port_env_var_or_exit "MONGODB_HOST_PORT"
	validate_simple_name_or_exit "$MONGODB_CONTAINER_NAME" "MONGODB_CONTAINER_NAME"
	validate_simple_name_or_exit "$MONGODB_VOLUME_NAME" "MONGODB_VOLUME_NAME"
	validate_simple_name_or_exit "$MONGODB_APP_DATABASE" "MONGODB_APP_DATABASE"
	validate_simple_name_or_exit "$MONGODB_APP_USERNAME" "MONGODB_APP_USERNAME"
	validate_unix_id_value_or_exit "$MONGODB_UID" "MONGODB_UID"
	validate_unix_id_value_or_exit "$MONGODB_GID" "MONGODB_GID"
}

validate_all_env_vars_or_exit() {
	validate_static_env_vars_or_exit
	validate_free_local_port_or_exit "$MONGODB_HOST_PORT" "MONGODB_HOST_PORT"
}