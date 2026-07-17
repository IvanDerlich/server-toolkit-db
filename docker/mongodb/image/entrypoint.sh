#!/usr/bin/env bash
set -euo pipefail

DB_PATH="/data/db"
INIT_CONFIG="/etc/mongo/mongod-init.conf"
RUNTIME_CONFIG="/etc/mongo/mongod.conf"

wait_for_local_mongod_or_exit() {
	local attempt
	for attempt in $(seq 1 30); do
		if mongosh --quiet --host 127.0.0.1 --port 27017 --eval 'db.adminCommand({ ping: 1 }).ok' 2>/dev/null | grep -q 1; then
			return 0
		fi
		sleep 1
	done

	echo "Bootstrap mongod did not become ready in time."
	exit 1
}

bootstrap_users_or_exit() {
	mongosh --quiet --host 127.0.0.1 --port 27017 <<EOF
use admin
db.createUser({
  user: "${MONGODB_ROOT_USERNAME}",
  pwd: "${MONGODB_ROOT_PASSWORD}",
  roles: [{ role: "root", db: "admin" }]
})

use ${MONGODB_APP_DATABASE}
db.createUser({
  user: "${MONGODB_APP_USERNAME}",
  pwd: "${MONGODB_APP_PASSWORD}",
  roles: [{ role: "readWrite", db: "${MONGODB_APP_DATABASE}" }]
})
EOF
}

if [[ -z "$(ls -A "$DB_PATH" 2>/dev/null || true)" ]]; then
	echo "Detected empty data directory; bootstrapping MongoDB users."
	mongod --config "$INIT_CONFIG" --fork --logpath /tmp/mongod-bootstrap.log
	wait_for_local_mongod_or_exit
	bootstrap_users_or_exit
	mongosh --quiet --host 127.0.0.1 --port 27017 --eval 'db.getSiblingDB("admin").shutdownServer({ force: true })' >/dev/null 2>&1 || true
	echo "MongoDB bootstrap completed."
fi

exec "$@"