#!/usr/bin/env bash
set -euo pipefail
# Full pipeline: download then copy to device.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Starting download phase"
bash "$SCRIPT_DIR/download.sh"

echo ""
echo "==> Starting copy phase"
bash "$SCRIPT_DIR/copy.sh"
