#!/usr/bin/env bash
set -euo pipefail
# Rename staged folders via ID3 tags and rsync to the device.
# Safe to run standalone or called by sync.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config

echo "==> Renaming folders via ID3 tags"
bash "$SCRIPT_DIR/prep.sh" "$STAGING"
[[ -d "$STAGING/tmp" ]] && bash "$SCRIPT_DIR/prep.sh" "$STAGING/tmp"

if [[ -d "$DEVICE" ]]; then
  echo "==> Syncing to $DEVICE"
  rsync -av --ignore-existing "$STAGING"/ "$DEVICE"/
  [[ -d "$STAGING/tmp" ]] && rsync -av --ignore-existing "$STAGING/tmp"/ "$DEVICE"/
  echo "==> Copy complete."
else
  echo "WARNING: Device not mounted at $DEVICE — nothing copied."
  exit 1
fi
