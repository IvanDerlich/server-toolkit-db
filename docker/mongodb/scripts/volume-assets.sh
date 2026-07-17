#!/usr/bin/env bash

volume_mountpoint() {
	local volume_name="$1"
	sudo docker volume inspect "$volume_name" --format '{{.Mountpoint}}'
}

data_dir_for_mountpoint() {
	local mountpoint="$1"
	if [[ "$mountpoint" == */_data ]]; then
		echo "$mountpoint"
	else
		echo "$mountpoint/_data"
	fi
}

ensure_mongodb_volume_permissions_or_exit() {
	local volume_name="$1"
	local mongodb_uid="$2"
	local mongodb_gid="$3"

	local mountpoint data_dir

	# Create/ensure the volume exists before inspecting/chowning its mountpoint.
	sudo docker volume create "$volume_name" >/dev/null
	mountpoint="$(volume_mountpoint "$volume_name")"
	data_dir="$(data_dir_for_mountpoint "$mountpoint")"

	if [[ ! -d "$data_dir" ]]; then
		echo "MongoDB volume data directory not found: $data_dir"
		exit 1
	fi

	echo "Applying least-privilege volume ownership (${mongodb_uid}:${mongodb_gid})"
	# The runtime user (compose user:) must own the data directory.
	sudo chown -R "${mongodb_uid}:${mongodb_gid}" "$data_dir"
	sudo chmod -R 0700 "$data_dir"
}