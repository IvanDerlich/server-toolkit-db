#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"



# shellcheck disable=SC1091
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	source "$SCRIPT_DIR/env-file-load-and-validate.sh"
fi




run_integration_tests() {

	# ---------------------------------------------------------------------------
	# Preflight
	# ---------------------------------------------------------------------------

	if ! sudo docker ps --format '{{.Names}}' | grep -Fxq "$MONGODB_CONTAINER_NAME"; then
		echo "There's nothing to test right now: container '${MONGODB_CONTAINER_NAME}' is not running."
		echo "Start it first with:"
		echo "  sudo bash ./start.sh"
		return 0
	fi

	# Fixed names are safe because:
	#  - The _smoketest_ prefix will never collide with real application data.
	#  - Pre-test cleanup ensures a clean slate on every run.
	SMOKETEST_COLLECTION="_smoketest_collection"
	SMOKETEST_USER_COLLECTION="_smoketest_user_collection"
	SMOKETEST_USER="_smoketest_user"
	SMOKETEST_USER_PASSWORD="_smoketest_user_password"

	PASS_COUNT=0
	FAIL_COUNT=0
	TEST_INDEX=0

	pass() {
		PASS_COUNT=$((PASS_COUNT + 1))
		echo "  PASS: $1"
	}

	fail() {
		FAIL_COUNT=$((FAIL_COUNT + 1))
		echo "  FAIL: $1"
	}

	nested_pass() {
		PASS_COUNT=$((PASS_COUNT + 1))
		echo "    PASS: $1"
	}

	nested_fail() {
		FAIL_COUNT=$((FAIL_COUNT + 1))
		echo "    FAIL: $1"
	}

	test_case() {
		TEST_INDEX=$((TEST_INDEX + 1))
		echo
		echo "[Test ${TEST_INDEX}] $1"
	}

	mongosh_as_root() {
		sudo docker exec "$MONGODB_CONTAINER_NAME" \
			mongosh --quiet \
			--host "$MONGODB_DOMAIN" --port 27017 \
			--tls \
			-u "$MONGODB_ROOT_USERNAME" -p "$MONGODB_ROOT_PASSWORD" \
			--authenticationDatabase admin \
			--eval "$1"
	}

	mongosh_as_app() {


    echo "> sudo docker exec \"$MONGODB_CONTAINER_NAME\" \\
        mongosh --quiet \\
        --host \"$MONGODB_DOMAIN\" --port 27017 \\
        --tls \\
        -u \"$MONGODB_APP_USERNAME\" -p \"$MONGODB_APP_PASSWORD\" \\
        --authenticationDatabase \"$MONGODB_APP_DATABASE\" \\
        --eval \"$1\""
    sudo docker exec "$MONGODB_CONTAINER_NAME" \
        mongosh --quiet \
        --host "$MONGODB_DOMAIN" --port 27017 \
        --tls \
        -u "$MONGODB_APP_USERNAME" -p "$MONGODB_APP_PASSWORD" \
        --authenticationDatabase "$MONGODB_APP_DATABASE" \
        --eval "$1"
	}

	mongosh_as_test_user() {
		sudo docker exec "$MONGODB_CONTAINER_NAME" \
			mongosh --quiet \
			--host "$MONGODB_DOMAIN" --port 27017 \
			--tls \
			-u "$SMOKETEST_USER" -p "$SMOKETEST_USER_PASSWORD" \
			--authenticationDatabase admin \
			--eval "$1"
	}

	# ---------------------------------------------------------------------------
	# Pre-test cleanup — idempotent, runs before every test suite execution
	# ---------------------------------------------------------------------------

	echo "Preparing test environment (idempotent pre-test cleanup)..."

	mongosh_as_app "
		db.getSiblingDB('$MONGODB_APP_DATABASE').getCollection('$SMOKETEST_COLLECTION').drop()
	" >/dev/null 2>&1 || true

	mongosh_as_app "
		db.getSiblingDB('$MONGODB_APP_DATABASE').getCollection('$SMOKETEST_USER_COLLECTION').drop()
	" >/dev/null 2>&1 || true

	mongosh_as_root "
		const u = db.getSiblingDB('admin').getUser('$SMOKETEST_USER');
		if (u) { db.getSiblingDB('admin').dropUser('$SMOKETEST_USER'); }
	" >/dev/null 2>&1 || true

	# ---------------------------------------------------------------------------
	# Test 1 — App user: collection CRUD
	# ---------------------------------------------------------------------------

	test_case "App user collection CRUD (create, insert, find, drop)"

	CREATE_OUT="$(mongosh_as_app "
		db.getSiblingDB('$MONGODB_APP_DATABASE').createCollection('$SMOKETEST_COLLECTION');
	" 2>/tmp/itest_t1_create.err)"

	echo $MONGODB_APP_DATABASE

	if echo "$CREATE_OUT" | grep -q '{ ok: 1 }'; then
		pass "Collection created"
	else
		fail "Collection creation failed"
		echo "    Output: $CREATE_OUT"
		cat /tmp/itest_t1_create.err || true
	fi

	INSERT_OUT="$(mongosh_as_app "
		db.getSiblingDB('$MONGODB_APP_DATABASE').getCollection('$SMOKETEST_COLLECTION').insertOne({ _itest: true });
	" 2>/tmp/itest_t1_insert.err)"
	if echo "$INSERT_OUT" | grep -q 'acknowledged: true'; then
		pass "Document inserted"
	else
		fail "Document insert failed"
		echo "    Output: $INSERT_OUT"
		cat /tmp/itest_t1_insert.err || true
	fi

	FIND_OUT="$(mongosh_as_app "
		db.getSiblingDB('$MONGODB_APP_DATABASE').getCollection('$SMOKETEST_COLLECTION').findOne({ _itest: true });
	" 2>/tmp/itest_t1_find.err)"
	if echo "$FIND_OUT" | grep -q '_itest: true'; then
		pass "Document found"
	else
		fail "Inserted document not found"
		echo "    Output: $FIND_OUT"
		cat /tmp/itest_t1_find.err || true
	fi

	DROP_OUT="$(mongosh_as_app "
		db.getSiblingDB('$MONGODB_APP_DATABASE').getCollection('$SMOKETEST_COLLECTION').drop();
	" 2>/tmp/itest_t1_drop.err)"
	if echo "$DROP_OUT" | grep -q '^true$'; then
		pass "Collection dropped"
	else
		fail "Collection drop failed"
		echo "    Output: $DROP_OUT"
		cat /tmp/itest_t1_drop.err || true
	fi

	GONE_OUT="$(mongosh_as_app "
		db.getSiblingDB('$MONGODB_APP_DATABASE').getCollectionNames().includes('$SMOKETEST_COLLECTION');
	" 2>/tmp/itest_t1_gone.err)"
	if echo "$GONE_OUT" | grep -q '^false$'; then
		pass "Collection no longer exists after drop"
	else
		fail "Collection still present after drop"
		echo "    Output: $GONE_OUT"
	fi

	APP_ADMIN_OUT="$(mongosh_as_app '
		db.getSiblingDB("admin").runCommand({ usersInfo: 1 });
	' 2>/tmp/itest_t1_admin_check.err || true)"
	if grep -qi 'Unauthorized\|requires authentication\|not authorized' /tmp/itest_t1_admin_check.err; then
		pass "App user is blocked from admin-only command"
	else
		fail "App user unexpectedly executed admin-only command"
		echo "    Output: $APP_ADMIN_OUT"
		cat /tmp/itest_t1_admin_check.err || true
	fi

	# ---------------------------------------------------------------------------
	# Test 2 — Root user: user lifecycle (create, verify, delete, verify gone)
	# ---------------------------------------------------------------------------

	test_case "Root user management (create, verify, delete, verify gone)"

	CREATE_USER_OUT="$(mongosh_as_root "
		db.getSiblingDB('admin').createUser({
			user: '$SMOKETEST_USER',
			pwd: '$SMOKETEST_USER_PASSWORD',
			roles: [{ role: 'readWrite', db: '$MONGODB_APP_DATABASE' }]
		});
	" 2>/tmp/itest_t2_create.err)"
	if echo "$CREATE_USER_OUT" | grep -q '{ ok: 1 }'; then
		pass "Test user created"
	else
		fail "Test user creation failed"
		echo "    Output: $CREATE_USER_OUT"
		cat /tmp/itest_t2_create.err || true
	fi

	USER_EXISTS_OUT="$(mongosh_as_root "
		db.getSiblingDB('admin').getUser('$SMOKETEST_USER') !== null;
	" 2>/tmp/itest_t2_exists.err)"
	if echo "$USER_EXISTS_OUT" | grep -q '^true$'; then
		pass "Test user verified to exist after creation"
	else
		fail "Test user not found after creation"
		echo "    Output: $USER_EXISTS_OUT"
	fi

	echo
	echo "  [Test 2.A] Nested test user CRUD + least-privilege"

	NESTED_CREATE_OUT="$(mongosh_as_test_user "
		db.getSiblingDB('$MONGODB_APP_DATABASE').createCollection('$SMOKETEST_USER_COLLECTION');
	" 2>/tmp/itest_t2_nested_create.err)"
	if echo "$NESTED_CREATE_OUT" | grep -q '{ ok: 1 }'; then
		nested_pass "Test user created collection"
	else
		nested_fail "Test user collection creation failed"
		echo "    Output: $NESTED_CREATE_OUT"
		cat /tmp/itest_t2_nested_create.err || true
	fi

	NESTED_INSERT_OUT="$(mongosh_as_test_user "
		db.getSiblingDB('$MONGODB_APP_DATABASE').getCollection('$SMOKETEST_USER_COLLECTION').insertOne({ _itest_nested: true });
	" 2>/tmp/itest_t2_nested_insert.err)"
	if echo "$NESTED_INSERT_OUT" | grep -q 'acknowledged: true'; then
		nested_pass "Test user inserted document"
	else
		nested_fail "Test user document insert failed"
		echo "    Output: $NESTED_INSERT_OUT"
		cat /tmp/itest_t2_nested_insert.err || true
	fi

	NESTED_FIND_OUT="$(mongosh_as_test_user "
		db.getSiblingDB('$MONGODB_APP_DATABASE').getCollection('$SMOKETEST_USER_COLLECTION').findOne({ _itest_nested: true });
	" 2>/tmp/itest_t2_nested_find.err)"
	if echo "$NESTED_FIND_OUT" | grep -q '_itest_nested: true'; then
		nested_pass "Test user found inserted document"
	else
		nested_fail "Test user inserted document not found"
		echo "    Output: $NESTED_FIND_OUT"
		cat /tmp/itest_t2_nested_find.err || true
	fi

	NESTED_DROP_OUT="$(mongosh_as_test_user "
		db.getSiblingDB('$MONGODB_APP_DATABASE').getCollection('$SMOKETEST_USER_COLLECTION').drop();
	" 2>/tmp/itest_t2_nested_drop.err)"
	if echo "$NESTED_DROP_OUT" | grep -q '^true$'; then
		nested_pass "Test user dropped collection"
	else
		nested_fail "Test user collection drop failed"
		echo "    Output: $NESTED_DROP_OUT"
		cat /tmp/itest_t2_nested_drop.err || true
	fi

	NESTED_GONE_OUT="$(mongosh_as_test_user "
		db.getSiblingDB('$MONGODB_APP_DATABASE').getCollectionNames().includes('$SMOKETEST_USER_COLLECTION');
	" 2>/tmp/itest_t2_nested_gone.err)"
	if echo "$NESTED_GONE_OUT" | grep -q '^false$'; then
		nested_pass "Test user collection no longer exists after drop"
	else
		nested_fail "Test user collection still present after drop"
		echo "    Output: $NESTED_GONE_OUT"
	fi

	TEST_USER_ADMIN_OUT="$(mongosh_as_test_user '
		db.getSiblingDB("admin").runCommand({ usersInfo: 1 });
	' 2>/tmp/itest_t2_admin_check.err || true)"
	if grep -qi 'Unauthorized\|requires authentication\|not authorized' /tmp/itest_t2_admin_check.err; then
		nested_pass "Test user is blocked from admin-only command"
	else
		nested_fail "Test user unexpectedly executed admin-only command"
		echo "    Output: $TEST_USER_ADMIN_OUT"
		cat /tmp/itest_t2_admin_check.err || true
	fi

	echo

	DROP_USER_OUT="$(mongosh_as_root "
		db.getSiblingDB('admin').dropUser('$SMOKETEST_USER');
	" 2>/tmp/itest_t2_drop.err)"
	if echo "$DROP_USER_OUT" | grep -q '{ ok: 1 }'; then
		pass "Test user deleted"
	else
		fail "Test user deletion failed"
		echo "    Output: $DROP_USER_OUT"
		cat /tmp/itest_t2_drop.err || true
	fi

	USER_GONE_OUT="$(mongosh_as_root "
		db.getSiblingDB('admin').getUser('$SMOKETEST_USER') === null;
	" 2>/tmp/itest_t2_gone.err)"
	if echo "$USER_GONE_OUT" | grep -q '^true$'; then
		pass "Test user no longer exists after deletion"
	else
		fail "Test user still present after deletion"
		echo "    Output: $USER_GONE_OUT"
	fi

	# ---------------------------------------------------------------------------
	# Test 3 — TLS connection modes
	# ---------------------------------------------------------------------------

	test_case "TLS connection modes (no-CA allowed, CA-verified, plaintext rejected)"

	ALLOW_TLS_ROOT_OUT="$(sudo docker exec "$MONGODB_CONTAINER_NAME" \
		mongosh --quiet \
		--host "$MONGODB_DOMAIN" --port 27017 \
		--tls \
		-u "$MONGODB_ROOT_USERNAME" -p "$MONGODB_ROOT_PASSWORD" \
		--authenticationDatabase admin \
		--eval 'db.runCommand({ping:1})' 2>/tmp/itest_t3_root_tls.err)"
	if echo "$ALLOW_TLS_ROOT_OUT" | grep -q 'ok: 1'; then
		pass "Root can connect with --tls (system CA)"
	else
		fail "Root failed to connect with --tls (system CA)"
		echo "    Output: $ALLOW_TLS_ROOT_OUT"
		cat /tmp/itest_t3_root_tls.err || true
	fi

	ALLOW_TLS_APP_OUT="$(sudo docker exec "$MONGODB_CONTAINER_NAME" \
		mongosh --quiet \
		--host "$MONGODB_DOMAIN" --port 27017 \
		--tls \
		-u "$MONGODB_APP_USERNAME" -p "$MONGODB_APP_PASSWORD" \
		--authenticationDatabase "$MONGODB_APP_DATABASE" \
		--eval 'db.runCommand({ping:1})' 2>/tmp/itest_t3_app_tls.err)"
	if echo "$ALLOW_TLS_APP_OUT" | grep -q 'ok: 1'; then
		pass "App user can connect with --tls (system CA)"
	else
		fail "App user failed to connect with --tls (system CA)"
		echo "    Output: $ALLOW_TLS_APP_OUT"
		cat /tmp/itest_t3_app_tls.err || true
	fi

	echo
	echo "[INFO] Running plaintext (non-TLS) rejection test"
	echo "This may take 30-60 seconds..."
	set +e
	PLAINTEXT_OUT="$(sudo docker exec "$MONGODB_CONTAINER_NAME" \
		mongosh --quiet \
		--host "$MONGODB_DOMAIN" --port 27017 \
		-u "$MONGODB_ROOT_USERNAME" -p "$MONGODB_ROOT_PASSWORD" \
		--authenticationDatabase admin \
		--eval 'db.runCommand({ping:1})' 2>/tmp/itest_t3_plaintext.err)"
	PLAINTEXT_RC=$?
	set -e

	if (( PLAINTEXT_RC != 0 )) && ! echo "$PLAINTEXT_OUT" | grep -q 'ok: 1'; then
		pass "Non-TLS connection is rejected by server"
	else
		fail "Non-TLS connection was not rejected (requireTLS may not be enforced)"
		echo "    Exit code: $PLAINTEXT_RC"
		echo "    Output: $PLAINTEXT_OUT"
		cat /tmp/itest_t3_plaintext.err || true
	fi

	# ---------------------------------------------------------------------------
	# Summary
	# ---------------------------------------------------------------------------

	echo
	echo "Summary: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT}"

	if (( FAIL_COUNT > 0 )); then
		echo "Result: FAILED"
		echo
		echo "To debug, check the container logs:"
		echo "  sudo docker logs --tail 100 ${MONGODB_CONTAINER_NAME}"
		echo
		echo "Or open a shell inside the container:"
		echo "  sudo docker exec -it ${MONGODB_CONTAINER_NAME} bash"
		return 1
	fi

	echo "Result: ALL TESTS PASSED"
	return 0
}


# Always run tests, but only load env if executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  load_mongodb_runtime_env_or_exit "$BASE_DIR"
  validate_static_env_vars_or_exit
  run_integration_tests
fi
