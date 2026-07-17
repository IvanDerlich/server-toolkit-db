#!/usr/bin/env bash

ensure_no_running_mongodb_instances_or_exit() {
	local running_mongodb_containers
	running_mongodb_containers="$(sudo docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | awk 'tolower($2) ~ /mongo/ { print }')"

	if [[ -z "$running_mongodb_containers" ]]; then
		return 0
	fi

	echo "Detected running MongoDB container(s)."
	echo "Startup is stopped to avoid accidental data loss or resetting an instance you want to keep."
	echo
	echo "docker ps (MongoDB-related):"
	sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | awk 'NR == 1 || tolower($2) ~ /mongo/'
	echo
	echo "To continue with this stack:"
	echo "1) Run cleanup:"
	echo "   sudo bash ./scripts/cleanup.sh"
	echo "2) Run startup again:"
	echo "   sudo bash ./start-or-restart.sh"

	exit 1
}

ensure_container_name_available_or_exit() {
	local container_name="$1"

	if sudo docker ps -a --format '{{.Names}}' | grep -Fxq "$container_name"; then
		echo "A container named '${container_name}' already exists."
		echo "Please remove it first if it does not belong to this MongoDB setup:"
		echo "sudo docker rm -f ${container_name}"
		exit 1
	fi
}

wait_for_container_ready_or_exit() {
	local container_name="$1"
	local inspect_cmd="sudo docker inspect -f {{.State.Status}} $container_name"
	echo "Checking if container '$container_name' is up..."

	for attempt in $(seq 1 30); do
		echo "  $inspect_cmd"

		local status
		status="$($inspect_cmd 2>/dev/null || true)"
		if [[ "$status" == "running" ]]; then
			echo "Container '$container_name' is up."
			return 0
		elif [[ "$status" == "exited" ]]; then
			echo "ERROR: Container '$container_name' has exited unexpectedly."
			echo "Inspect logs with:"
			echo "  sudo docker logs --tail 100 ${container_name}"
			exit 1
		fi
		echo "Attempt $attempt: Container status is '$status'. Retrying..."
		sleep 2
	done

	echo "ERROR: Container '$container_name' did not become ready in time. Last status: $status."
	echo "Make sure the container is started with 'docker compose up -d' or similar."
	echo "You can inspect the container with:"
	echo "  sudo docker ps -a | grep $container_name"
	echo "  sudo docker logs $container_name"
	exit 1
}