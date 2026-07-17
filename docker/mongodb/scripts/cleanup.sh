#!/usr/bin/env bash
set -euo pipefail

# Stops the stack and optionally removes persistent data plus generated local assets.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/env-file-load-and-validate.sh"

load_and_validate_env "$BASE_DIR" \
	"MONGODB_CONTAINER_NAME" \
	"MONGODB_VOLUME_NAME"


yes_mode=""
cleanup_data_mode=""
cleanup_certs_mode=""

print_cleanup_usage() {
	echo "Usage: sudo bash ./scripts/cleanup.sh [--preserve-data|--delete-data] [--preserve-certs|--delete-certs]"
	echo
	echo "Options:"
	echo "  --preserve-data   Remove containers/network only; keep Docker volume data."
	echo "  --delete-data     Remove containers/network and delete Docker volume data."
	echo "  --preserve-certs  Keep generated TLS assets under .generated/."
	echo "  --delete-certs    Delete generated TLS assets under .generated/."
	echo
	echo "If a data/cert option is omitted, cleanup asks interactively."
}

parse_cleanup_modes_or_exit() {
	while (( $# > 0 )); do
		case "$1" in
			--preserve-data)
				if [[ -n "$cleanup_data_mode" && "$cleanup_data_mode" != "preserve" ]]; then
					echo "Conflicting options: --preserve-data and --delete-data"
					print_cleanup_usage
					exit 1
				fi
				cleanup_data_mode="preserve"
				;;
			--delete-data)
				if [[ -n "$cleanup_data_mode" && "$cleanup_data_mode" != "delete" ]]; then
					echo "Conflicting options: --preserve-data and --delete-data"
					print_cleanup_usage
					exit 1
				fi
				cleanup_data_mode="delete"
				;;
			--preserve-certs)
				if [[ -n "$cleanup_certs_mode" && "$cleanup_certs_mode" != "preserve" ]]; then
					echo "Conflicting options: --preserve-certs and --delete-certs"
					print_cleanup_usage
					exit 1
				fi
				cleanup_certs_mode="preserve"
				;;
			--delete-certs)
				if [[ -n "$cleanup_certs_mode" && "$cleanup_certs_mode" != "delete" ]]; then
					echo "Conflicting options: --preserve-certs and --delete-certs"
					print_cleanup_usage
					exit 1
				fi
				cleanup_certs_mode="delete"
				;;
			-y|--yes)
				yes_mode="1"
				;;
			-h|--help)
				print_cleanup_usage
				exit 0
				;;
			*)
				echo "Unknown option: $1"
				print_cleanup_usage
				exit 1
				;;
		esac
		shift
	done
}

prompt_cleanup_modes_if_missing() {
	local delete_data_choice delete_certs_choice

	if [[ -n "$yes_mode" ]]; then
		# Default to delete for both if -y is set
		[[ -z "$cleanup_data_mode" ]] && cleanup_data_mode="delete"
		[[ -z "$cleanup_certs_mode" ]] && cleanup_certs_mode="delete"
		return
	fi

	if [[ -z "$cleanup_data_mode" ]]; then
		read -r -p "Delete MongoDB Docker volume data? [y/N]: " delete_data_choice
		if [[ "${delete_data_choice,,}" == "y" ]]; then
			cleanup_data_mode="delete"
		else
			cleanup_data_mode="preserve"
		fi
	fi

	if [[ -z "$cleanup_certs_mode" ]]; then
		read -r -p "Delete generated TLS assets (.generated)? [y/N]: " delete_certs_choice
		if [[ "${delete_certs_choice,,}" == "y" ]]; then
			cleanup_certs_mode="delete"
		else
			cleanup_certs_mode="preserve"
		fi
	fi
}

parse_cleanup_modes_or_exit "$@"

cd "$BASE_DIR"

prompt_cleanup_modes_if_missing

echo "This will stop the MongoDB service and apply the selected cleanup options."
if [[ "$cleanup_data_mode" == "delete" ]]; then
	echo "Data volume: delete (${MONGODB_VOLUME_NAME})"
else
	echo "Data volume: preserve (${MONGODB_VOLUME_NAME})"
fi

if [[ "$cleanup_certs_mode" == "delete" ]]; then
	echo "TLS assets: delete (${BASE_DIR}/.generated)"
else
	echo "TLS assets: preserve (${BASE_DIR}/.generated)"
fi

echo "Container: ${MONGODB_CONTAINER_NAME}"

if [[ -n "$yes_mode" ]]; then
	echo "Proceeding without confirmation due to -y/--yes flag."
else
	echo "Tip: pass explicit flags to skip prompts:"
	echo "  --preserve-data|--delete-data --preserve-certs|--delete-certs"
	read -r -p "Proceed? [y/N]: " proceed_choice
	if [[ "${proceed_choice,,}" != "y" ]]; then
		echo "Aborted."
		exit 0
	fi
fi

if [[ "$cleanup_data_mode" == "delete" ]]; then
	sudo docker compose down --volumes --remove-orphans
else
	sudo docker compose down --remove-orphans
fi

if [[ "$cleanup_certs_mode" == "delete" ]]; then
	rm -rf "$BASE_DIR/.generated"
fi

echo "MongoDB service removed."
if [[ "$cleanup_data_mode" == "delete" ]]; then
	echo "Data volume removed."
else
	echo "Data volume preserved."
fi

if [[ "$cleanup_certs_mode" == "delete" ]]; then
	echo "TLS assets removed."
else
	echo "TLS assets preserved."
fi

echo
echo "Next step: start MongoDB again with:"
echo "  sudo bash ./start-or-restart.sh"
