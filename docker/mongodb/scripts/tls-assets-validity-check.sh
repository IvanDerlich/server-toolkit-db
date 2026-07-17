#!/usr/bin/env bash

mongodb_tls_is_ipv4_address() {
	local candidate="$1"
	local octet
	local IFS='.'
	local -a octets

	read -r -a octets <<< "$candidate"
	if (( ${#octets[@]} != 4 )); then
		return 1
	fi

	for octet in "${octets[@]}"; do
		if [[ ! "$octet" =~ ^[0-9]+$ ]]; then
			return 1
		fi
		if (( octet < 0 || octet > 255 )); then
			return 1
		fi
	done

	return 0
}

mongodb_tls_letsencrypt_assets_are_valid_or_report() {
	local fullchain_file="$1"
	local privkey_file="$2"
	local remote_host="$3"
	local cert_pubkey_fingerprint key_pubkey_fingerprint san_extension expected_remote_san
	local issuer_line

	echo "[TLS][Let's Encrypt][Stage 1/6] Checking certificate file presence"
	if [[ ! -f "$fullchain_file" ]]; then
		echo "[TLS][Let's Encrypt][ERROR] Missing certificate chain file: ${fullchain_file}"
		echo "[TLS][Let's Encrypt][HINT] Issue the certificate first (certbot), then rerun start-or-restart."
		return 1
	fi
	if [[ ! -s "$fullchain_file" ]]; then
		echo "[TLS][Let's Encrypt][ERROR] Certificate chain file is empty: ${fullchain_file}"
		return 1
	fi

	echo "[TLS][Let's Encrypt][Stage 2/6] Checking private key file presence"
	if [[ ! -f "$privkey_file" ]]; then
		echo "[TLS][Let's Encrypt][ERROR] Missing private key file: ${privkey_file}"
		echo "[TLS][Let's Encrypt][HINT] Issue the certificate first (certbot), then rerun start-or-restart."
		return 1
	fi
	if [[ ! -s "$privkey_file" ]]; then
		echo "[TLS][Let's Encrypt][ERROR] Private key file is empty: ${privkey_file}"
		return 1
	fi

	echo "[TLS][Let's Encrypt][Stage 3/6] Validating certificate issuer and expiry"
	if ! openssl x509 -in "$fullchain_file" -noout >/dev/null 2>&1; then
		echo "[TLS][Let's Encrypt][ERROR] fullchain.pem is not a parseable X.509 certificate."
		return 1
	fi
	issuer_line="$(openssl x509 -in "$fullchain_file" -noout -issuer 2>/dev/null || true)"
	if [[ "$issuer_line" != *"Let's Encrypt"* ]]; then
		echo "[TLS][Let's Encrypt][ERROR] Certificate issuer is not Let's Encrypt: ${issuer_line:-unknown}"
		return 1
	fi
	if ! openssl x509 -checkend 0 -noout -in "$fullchain_file" >/dev/null 2>&1; then
		echo "[TLS][Let's Encrypt][ERROR] Certificate is expired."
		return 1
	fi

	echo "[TLS][Let's Encrypt][Stage 4/6] Validating domain coverage (SAN)"
	san_extension="$(openssl x509 -in "$fullchain_file" -noout -ext subjectAltName 2>/dev/null || true)"
	if [[ -z "$san_extension" ]]; then
		echo "[TLS][Let's Encrypt][ERROR] Certificate has no subjectAltName extension."
		return 1
	fi
	if mongodb_tls_is_ipv4_address "$remote_host"; then
		expected_remote_san="IP Address:${remote_host}"
	else
		expected_remote_san="DNS:${remote_host}"
	fi
	if [[ "$san_extension" != *"$expected_remote_san"* ]]; then
		echo "[TLS][Let's Encrypt][ERROR] Certificate SAN does not include ${expected_remote_san}."
		return 1
	fi

	echo "[TLS][Let's Encrypt][Stage 5/6] Validating private key integrity"
	if ! openssl pkey -in "$privkey_file" -noout >/dev/null 2>&1; then
		echo "[TLS][Let's Encrypt][ERROR] Private key is not parseable."
		return 1
	fi

	echo "[TLS][Let's Encrypt][Stage 6/6] Validating certificate-key match"
	cert_pubkey_fingerprint="$(openssl x509 -in "$fullchain_file" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256 2>/dev/null | awk '{print $2}')"
	key_pubkey_fingerprint="$(openssl pkey -in "$privkey_file" -pubout -outform DER 2>/dev/null | openssl dgst -sha256 2>/dev/null | awk '{print $2}')"
	if [[ -z "$cert_pubkey_fingerprint" || "$cert_pubkey_fingerprint" != "$key_pubkey_fingerprint" ]]; then
		echo "[TLS][Let's Encrypt][ERROR] fullchain.pem and privkey.pem do not belong to the same certificate."
		return 1
	fi

	echo "[TLS][Let's Encrypt][OK] Certificate files are valid and ready for MongoDB TLS."
	return 0
}

# Validates locally generated MongoDB TLS assets before reuse.
mongodb_tls_assets_are_valid() {
	local tls_ca_cert="$1"
	local tls_server_pem="$2"
	local remote_host="${3:-}"
	local cert_pubkey_fingerprint key_pubkey_fingerprint extracted_server_cert
	local san_extension expected_remote_san

	if [[ ! -s "$tls_ca_cert" || ! -s "$tls_server_pem" ]]; then
		return 1
	fi

	# CA cert must be parseable and not expired.
	if ! openssl x509 -in "$tls_ca_cert" -noout >/dev/null 2>&1; then
		return 1
	fi
	if ! openssl x509 -checkend 0 -noout -in "$tls_ca_cert" >/dev/null 2>&1; then
		return 1
	fi

	# server.pem must contain a parseable cert + private key, and cert must not be expired.
	if ! openssl x509 -in "$tls_server_pem" -noout >/dev/null 2>&1; then
		return 1
	fi
	if ! openssl pkey -in "$tls_server_pem" -noout >/dev/null 2>&1; then
		return 1
	fi
	if ! openssl x509 -checkend 0 -noout -in "$tls_server_pem" >/dev/null 2>&1; then
		return 1
	fi

	# Ensure the private key in server.pem matches the embedded server certificate.
	cert_pubkey_fingerprint="$(openssl x509 -in "$tls_server_pem" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256 2>/dev/null | awk '{print $2}')"
	key_pubkey_fingerprint="$(openssl pkey -in "$tls_server_pem" -pubout -outform DER 2>/dev/null | openssl dgst -sha256 2>/dev/null | awk '{print $2}')"
	if [[ -z "$cert_pubkey_fingerprint" || "$cert_pubkey_fingerprint" != "$key_pubkey_fingerprint" ]]; then
		return 1
	fi

	# Ensure SAN always includes localhost/127.0.0.1 and optional remote host.
	san_extension="$(openssl x509 -in "$tls_server_pem" -noout -ext subjectAltName 2>/dev/null || true)"
	if [[ -z "$san_extension" ]]; then
		return 1
	fi
	if [[ "$san_extension" != *"DNS:localhost"* ]]; then
		return 1
	fi
	if [[ "$san_extension" != *"IP Address:127.0.0.1"* ]]; then
		return 1
	fi
	if [[ -n "$remote_host" && "$remote_host" != "localhost" ]]; then
		if mongodb_tls_is_ipv4_address "$remote_host"; then
			expected_remote_san="IP Address:${remote_host}"
		else
			expected_remote_san="DNS:${remote_host}"
		fi
		if [[ "$san_extension" != *"$expected_remote_san"* ]]; then
			return 1
		fi
	fi

	extracted_server_cert="$(mktemp)"
	if ! openssl x509 -in "$tls_server_pem" -out "$extracted_server_cert" >/dev/null 2>&1; then
		rm -f "$extracted_server_cert"
		return 1
	fi

	if ! openssl verify -CAfile "$tls_ca_cert" "$extracted_server_cert" >/dev/null 2>&1; then
		rm -f "$extracted_server_cert"
		return 1
	fi

	rm -f "$extracted_server_cert"
	return 0
}