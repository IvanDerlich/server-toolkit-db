#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Stop, then start the service without cleaning up data
bash "$SCRIPT_DIR/scripts/cleanup.sh" --preserve-data --preserve-certs
bash "$SCRIPT_DIR/scripts/start.sh" "$@"
