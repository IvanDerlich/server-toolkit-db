#!/bin/bash
# Script to check that all required environment variables are set in .env

set -e

REQUIRED_VARS=(
    MARIADB_ROOT_PASSWORD
    MARIADB_PORT
    MARIADB_DATABASE
    MARIADB_USER
    MARIADB_PASSWORD
    MARIADB_CONTAINER_NAME
    MARIADB_VOLUME_NAME
)


PROJECT_ROOT="$(pwd)"
ENV_FILE="$PROJECT_ROOT/.env"


if [ ! -f "$ENV_FILE" ]; then
  echo ".env file not found in project root ($PROJECT_ROOT)!" >&2
  exit 1
fi

# Load environment variables from .env
set -a
source "$ENV_FILE"
set +a

missing=0
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Missing required variable: $var" >&2
    missing=1
  fi
done

if [ $missing -eq 1 ]; then
  echo "Sanity check failed: missing required environment variables." >&2
  exit 1
else
  echo "Sanity check passed: all required environment variables are present."
fi
