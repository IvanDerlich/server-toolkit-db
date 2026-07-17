#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Stop, clean up all data (force, no prompt), then start fresh
bash "$SCRIPT_DIR/scripts/cleanup.sh" -y
bash "$SCRIPT_DIR/scripts/start.sh" "$@"
