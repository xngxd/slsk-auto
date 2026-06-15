#!/usr/bin/env bash
set -euo pipefail
# Delete FLACs from staging, move orphaned folders, print summary.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config

flac_count=0
pruned=0

# ── Delete FLACs ──────────────────────────────────────────────────────────────

echo "==> Deleting FLACs from staging"
while IFS= read -r f; do
  echo "  DEL FLAC: $(basename "$(dirname "$f")")/$(basename "$f")"
  rm -f "$f"
  (( flac_count++ )) || true
done < <(find "$STAGING" -maxdepth 3 -iname "*.flac" 2>/dev/null || true)
echo "    $flac_count FLAC(s) deleted"

# ── Move orphaned staging folders ─────────────────────────────────────────────

echo ""
echo "==> Scanning for orphaned folders (not in watchlist)"
ORPHAN_DIR="$STAGING/orphaned"
while IFS= read -r orphan; do
  [[ -z "$orphan" ]] && continue
  mkdir -p "$ORPHAN_DIR"
  name=$(basename "$orphan")
  dest="$ORPHAN_DIR/$name"
  if [[ -e "$dest" ]]; then
    dest="$ORPHAN_DIR/${name}_$(date +%s)"
  fi
  mv "$orphan" "$dest"
  echo "  ORPHAN: $name → orphaned/"
  (( pruned++ )) || true
done < <(python3 - "$WATCHLIST" "$STAGING" <<'PYEOF'
import csv, sys
from pathlib import Path

AUDIO_EXTS = {'.mp3', '.flac', '.opus', '.ogg', '.m4a'}
watchlist_path, staging_path = sys.argv[1], sys.argv[2]
staging = Path(staging_path)

known = set()
with open(watchlist_path, newline='') as f:
    for row in csv.DictReader(f):
        if row.get('tmp_path'):
            known.add(str(Path(row['tmp_path']).resolve()))

SKIP = {'failed', 'orphaned', 'tmp'}
for search in [staging, staging / 'tmp']:
    if not search.is_dir():
        continue
    for d in sorted(search.iterdir()):
        if not d.is_dir() or d.name.startswith('.') or d.name in SKIP:
            continue
        has_audio = any(
            f.suffix.lower() in AUDIO_EXTS
            for f in d.iterdir() if f.is_file()
        )
        if has_audio and str(d.resolve()) not in known:
            print(d)
PYEOF
)
echo "    $pruned orphaned folder(s) moved to orphaned/"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "==> CLEANUP DONE  flacs_deleted=${flac_count}  orphans_moved=${pruned}"
