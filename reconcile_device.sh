#!/usr/bin/env bash
set -euo pipefail
# Remove albums from device that are no longer in staging or are marked sync=no.
# Prints a summary of what will be / was removed.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config

if [[ ! -d "$DEVICE" ]]; then
  echo "ERROR: Device not mounted at $DEVICE"; exit 1
fi

removed=0

echo "==> Reconciling device against staging"
while IFS= read -r folder; do
  [[ -z "$folder" ]] && continue
  name=$(basename "$folder")
  echo "  REMOVE from device: $name"
  rm -rf "$folder"
  (( removed++ )) || true
done < <(python3 - "$WATCHLIST" "$STAGING" "$DEVICE" <<'PYEOF'
import csv, sys
from pathlib import Path

AUDIO_EXTS = {'.mp3', '.flac', '.opus', '.ogg', '.m4a'}

def has_audio(d):
    try:
        return any(f.suffix.lower() in AUDIO_EXTS for f in d.iterdir() if f.is_file())
    except PermissionError:
        return False

watchlist_path, staging_path, device_path = sys.argv[1], sys.argv[2], sys.argv[3]
staging = Path(staging_path)
device  = Path(device_path)

# Collect staging folder names that should remain on device (sync != 'no')
staged_names = set()
with open(watchlist_path, newline='') as f:
    for row in csv.DictReader(f):
        if row.get('sync', '') == 'no':
            continue
        if row.get('tmp_path') and Path(row['tmp_path']).is_dir():
            staged_names.add(Path(row['tmp_path']).name.lower())

# Also add any staging folder not tied to a CSV entry (new/untracked)
for search in [staging, staging / 'tmp']:
    if not search.is_dir():
        continue
    for d in search.iterdir():
        if d.is_dir() and not d.name.startswith('.') and has_audio(d):
            staged_names.add(d.name.lower())

# Find device folders not present in staging
for d in sorted(device.iterdir()):
    if not d.is_dir() or d.name.startswith('.'):
        continue
    if not has_audio(d):
        continue
    if d.name.lower() not in staged_names:
        print(d)
PYEOF
)

echo ""
echo "==> RECONCILE DONE  removed_from_device=${removed}"
