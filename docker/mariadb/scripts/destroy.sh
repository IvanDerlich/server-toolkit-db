#!/bin/bash
# Script to start the MongoDB container with fresh data 
# Removes existing data volume

set -e

echo "Stopping and removing MariaDB container and data volume..."
docker compose down -v

"./scripts/shared/init.sh"