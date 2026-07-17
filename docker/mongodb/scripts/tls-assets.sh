#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tls-assets-validity-check.sh"

# Ensures Let's Encrypt TLS assets are present, valid, and sets up MongoDB server.pem and ca.crt.
ensure_mongodb_tls_assets_or_exit() {
	local generated_tls_dir="$1"
	local mongodb_uid="$2"
	local mongodb_gid="$3"

	local remote_host="${MONGODB_DOMAIN:-}"
	local letsencrypt_live_dir letsencrypt_fullchain letsencrypt_privkey letsencrypt_chain
	local tls_ca_cert tls_server_pem

	tls_ca_cert="$generated_tls_dir/ca.crt"
	tls_server_pem="$generated_tls_dir/server.pem"

	letsencrypt_live_dir="/etc/letsencrypt/live/${remote_host}"
	letsencrypt_fullchain="$letsencrypt_live_dir/fullchain.pem"
	letsencrypt_privkey="$letsencrypt_live_dir/privkey.pem"
	letsencrypt_chain="$letsencrypt_live_dir/chain.pem"

	mkdir -p "$generated_tls_dir"

	if [[ -z "$remote_host" || "$remote_host" == "localhost" ]]; then
		echo "[FATAL] MONGODB_DOMAIN must be set to a real domain for Let's Encrypt TLS."
		exit 1
	fi

	echo "Checking Let's Encrypt certificates for ${remote_host}"
	if mongodb_tls_letsencrypt_assets_are_valid_or_report "$letsencrypt_fullchain" "$letsencrypt_privkey" "$remote_host"; then
		echo "Using Let's Encrypt certificate for MongoDB TLS"
		cat "$letsencrypt_fullchain" "$letsencrypt_privkey" > "$tls_server_pem"
		cp "$letsencrypt_chain" "$tls_ca_cert"
		echo "MongoDB TLS certificates are ready (Let's Encrypt mode)"
	else
		echo "[FATAL] Let's Encrypt certificates are required for domain (${remote_host}) but are missing or invalid."
		echo "        Issue a valid certificate with certbot, then rerun this script."
		exit 1
	fi

	# TLS key/cert files must be readable by the non-root container UID/GID.
	chown "${mongodb_uid}:${mongodb_gid}" "$tls_ca_cert" "$tls_server_pem"
	chmod 0644 "$tls_ca_cert"
	chmod 0600 "$tls_server_pem"
}