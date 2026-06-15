#!/usr/bin/env bash
set -euo pipefail
# Rename staged folders via ID3 tags and rsync to the device.
# Respects sync=no entries and never copies .incomplete files.
# Safe to run standalone or called by sync.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config

echo "==> Renaming folders via ID3 tags"
bash "$SCRIPT_DIR/prep.sh" "$STAGING"
[[ -d "$STAGING/tmp" ]] && bash "$SCRIPT_DIR/prep.sh" "$STAGING/tmp"

if [[ ! -d "$DEVICE" ]]; then
  echo "WARNING: Device not mounted at $DEVICE — nothing copied."
  exit 1
fi

# Build rsync exclude list from entries marked sync=no
EXCLUDE_ARGS=(--exclude='*.incomplete')
while IFS= read -r folder_path; do
  [[ -n "$folder_path" ]] && EXCLUDE_ARGS+=(--exclude="$(basename "$folder_path")/")
done < <(python3 - "$WATCHLIST" <<'PYEOF'
import csv, sys
with open(sys.argv[1], newline='') as f:
    for row in csv.DictReader(f):
        if row.get('sync', '') == 'no' and row.get('tmp_path', ''):
            print(row['tmp_path'])
PYEOF
)

excluded=${#EXCLUDE_ARGS[@]}
excluded=$(( excluded - 1 ))  # subtract the .incomplete entry
[[ "$excluded" -gt 0 ]] && echo "==> Excluding $excluded sync=no album(s)"

echo "==> Syncing to $DEVICE"
rsync -av --ignore-existing "${EXCLUDE_ARGS[@]}" "$STAGING"/ "$DEVICE"/
[[ -d "$STAGING/tmp" ]] && rsync -av --ignore-existing "${EXCLUDE_ARGS[@]}" "$STAGING/tmp"/ "$DEVICE"/
echo "==> Copy complete."
