#!/usr/bin/env bash
set -euo pipefail
# Import albums already on the Surfans F20 into watchlist.csv as verified entries.
# Run once (or any time) after the device is connected — safe to re-run, skips duplicates.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config

[[ ! -f "$WATCHLIST" ]] && { echo "watchlist.csv not found"; exit 1; }

if [[ ! -d "$DEVICE" ]]; then
  echo "Device not mounted at $DEVICE — connect Surfans F20 first"
  exit 1
fi

echo "==> Scanning $DEVICE for untracked albums..."

python3 - "$WATCHLIST" "$DEVICE" <<'PYEOF'
import csv, os, sys
from pathlib import Path

AUDIO_EXTS = {'.mp3', '.flac', '.opus', '.ogg', '.m4a'}

def count_audio(d):
    try:
        return sum(1 for f in Path(d).iterdir() if f.suffix.lower() in AUDIO_EXTS)
    except (PermissionError, FileNotFoundError):
        return 0

watchlist_path, device_path = sys.argv[1], sys.argv[2]
device = Path(device_path)

rows = []
with open(watchlist_path, newline='') as f:
    reader = csv.DictReader(f)
    fieldnames = list(reader.fieldnames)
    rows = list(reader)

# Ensure all known fields exist
for field in ['fail_reason', 'sync', 'attempts', 'tried_users']:
    if field not in fieldnames:
        fieldnames.append(field)

# Build sets of already-tracked names (case-insensitive)
tracked_basenames = set()
tracked_entries = set()
for row in rows:
    tp = row.get('tmp_path', '')
    if tp:
        tracked_basenames.add(Path(tp).name.lower())
    tracked_entries.add(row['entry'].strip().lower())

added = 0
skipped_tracked = 0
skipped_empty = 0

for d in sorted(device.iterdir()):
    if not d.is_dir() or d.name.startswith('.') or d.name.startswith('_'):
        continue
    n = count_audio(d)
    if n == 0:
        skipped_empty += 1
        continue
    name_lower = d.name.lower()
    if name_lower in tracked_basenames or name_lower in tracked_entries:
        skipped_tracked += 1
        continue

    row = {f: '' for f in fieldnames}
    row['entry'] = d.name
    row['tmp_path'] = ''
    row['status'] = 'verified'
    row['verified'] = 'verified'
    row['sync'] = 'yes'
    row['attempts'] = '0'
    rows.append(row)
    added += 1
    print(f"  + {d.name} ({n} tracks)")

if added:
    tmp = watchlist_path + '.tmp'
    with open(tmp, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction='ignore')
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, watchlist_path)
    print(f"\n==> Imported {added} album(s) — skipped {skipped_tracked} already tracked")
else:
    print(f"==> Nothing new to import — {skipped_tracked} already tracked")
PYEOF
