#!/usr/bin/env bash
set -euo pipefail
# Verify downloaded albums against MusicBrainz track counts.
# Checks all completed entries where verified is empty or 'unverified'.
# Safe to run standalone or called by sync.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config

# Collect completed entries where verified is empty or 'unverified'
TARGETS=$(python3 - "$WATCHLIST" <<'PYEOF'
import csv, sys
with open(sys.argv[1], newline='') as f:
    for row in csv.DictReader(f):
        if row['status'] == 'completed' and row.get('verified', '') in ('', 'unverified'):
            print(row['entry'])
PYEOF
)

if [[ -z "$TARGETS" ]]; then
  echo "==> Nothing to verify."; exit 0
fi

total=$(echo "$TARGETS" | wc -l | tr -d ' ')
echo "==> Verifying $total album(s)"
ok=0; mismatch=0; skipped=0

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  parse_entry "$entry"
  echo ""
  echo "--- $entry"

  folder=$(csv_get "$entry" tmp_path)
  [[ -z "$folder" || ! -d "$folder" ]] && folder=$(find_folder "$artist" "$(strip_year "$album")" || true)

  if [[ -z "$folder" || ! -d "$folder" ]]; then
    echo "    Folder not found — skipping"
    (( skipped++ )) || true
    continue
  fi

  actual=$(count_audio "$folder")
  echo "    Folder: $folder ($actual tracks)"

  if [[ -z "$artist" ]]; then
    echo "    No artist in entry — marking unverified (no MB lookup possible)"
    csv_set "$entry" "status=completed" "verified=unverified" "tmp_path=$folder"
    (( skipped++ )) || true
    continue
  fi

  expected=$(mb_track_count "$artist" "$album" 2>/dev/null || true)
  sleep 1

  if [[ -z "$expected" ]]; then
    echo "    MusicBrainz: not found — leaving as unverified"
    csv_set "$entry" "verified=unverified" "tmp_path=$folder"
    (( skipped++ )) || true
    continue
  fi

  result=$(verify_tracks "$folder" "$expected")
  if [[ "$result" == "ok" ]]; then
    echo "    OK — $actual tracks vs $expected expected"
    csv_set "$entry" "status=completed" "verified=verified" "tmp_path=$folder"
    (( ok++ )) || true
  else
    actual_count="${result#mismatch:}"
    echo "    MISMATCH — $actual_count, expected ~$expected — queuing re-download"
    csv_set "$entry" "status=failed" "verified=mismatch" "tmp_path="
    (( mismatch++ )) || true
  fi

done <<< "$TARGETS"

echo ""
echo "==> Verify complete. OK: $ok  Mismatch: $mismatch  Skipped: $skipped"
