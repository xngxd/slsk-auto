#!/usr/bin/env bash
set -euo pipefail
# Download pending albums and verify track counts against MusicBrainz.
# Safe to run standalone or called by sync.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config
mkdir -p "$STAGING"

[[ ! -f "$WATCHLIST" ]] && { echo "watchlist.csv not found"; exit 1; }

MIN_STAGING_TRACKS=5  # reject staging matches with fewer tracks than this

# ── Phase 0: Reconcile staging against watchlist ──────────────────────────────

echo "==> Scanning staging for already-downloaded albums"
python3 - "$WATCHLIST" "$STAGING" "$MIN_STAGING_TRACKS" <<'PYEOF'
import csv, os, re, sys
from pathlib import Path

AUDIO_EXTS = {'.mp3', '.flac', '.opus', '.ogg', '.m4a'}

def count_audio(d):
    try:
        return sum(1 for f in Path(d).iterdir() if f.suffix.lower() in AUDIO_EXTS)
    except (PermissionError, FileNotFoundError):
        return 0

def parse_entry(entry):
    m = re.match(r'^(.+)\s+[—\-]\s+(.+)$', entry)
    if m:
        return m.group(2).strip(), re.sub(r'\s*\(\d{4}\)\s*', ' ', m.group(1)).strip()
    return '', entry

watchlist_path, staging_path, min_s = sys.argv[1], sys.argv[2], sys.argv[3]
MIN_TRACKS = int(min_s)
staging = Path(staging_path)

staging_folders = []
for search in [staging, staging / 'tmp']:
    if not search.is_dir():
        continue
    for d in sorted(search.iterdir()):
        if not d.is_dir() or d.name.startswith('.') or d.name == 'failed':
            continue
        n = count_audio(d)
        if n >= MIN_TRACKS:
            staging_folders.append((d.name.lower(), str(d), n))

rows = []
with open(watchlist_path, newline='') as f:
    reader = csv.DictReader(f)
    fieldnames = list(reader.fieldnames)
    rows = list(reader)

if 'fail_reason' not in fieldnames:
    fieldnames.append('fail_reason')

changed = 0
for row in rows:
    if row['status'] == 'verified':
        continue
    if row['status'] == 'completed' and row.get('tmp_path') and Path(row['tmp_path']).is_dir():
        continue

    artist, album = parse_entry(row['entry'])
    terms = [t.lower() for t in [artist, album] if t]
    if not terms:
        continue

    for folder_name, folder_path, n in staging_folders:
        if all(t in folder_name for t in terms):
            old = row['status']
            row['status'] = 'completed'
            row['verified'] = 'unverified'
            row['tmp_path'] = folder_path
            row['fail_reason'] = ''
            changed += 1
            print(f"  {row['entry']} → {Path(folder_path).name} ({n} tracks) [was: {old}]")
            break

if changed:
    tmp = watchlist_path + '.tmp'
    with open(tmp, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction='ignore')
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, watchlist_path)

print(f"==> Reconciled {changed} entr{'y' if changed == 1 else 'ies'} from staging")
PYEOF

# ── Phase 1: verify completed-but-unverified ─────────────────────────────────

UNVERIFIED=$(csv_rows_where verified unverified || true)
if [[ -n "$UNVERIFIED" ]]; then
  echo ""; echo "==> Verifying $(echo "$UNVERIFIED" | wc -l | tr -d ' ') downloaded album(s)"
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    parse_entry "$entry"
    echo ""; echo "--- $entry (verify)"
    folder=$(csv_get "$entry" tmp_path)
    [[ -z "$folder" || ! -d "$folder" ]] && folder=$(find_folder "$artist" "$(strip_year "$album")" || true)
    if [[ -z "$folder" ]]; then echo "    Folder not found — skipping"; continue; fi
    expected=$(mb_track_count "$artist" "$album" 2>/dev/null || true)
    sleep 1
    if [[ -z "$expected" ]]; then
      echo "    MusicBrainz: not found — leaving as unverified"
      continue
    fi
    result=$(verify_tracks "$folder" "$expected")
    if [[ "$result" == "ok" ]]; then
      echo "    OK — $(count_audio "$folder") tracks vs $expected expected"
      csv_set "$entry" "verified=verified"
    else
      actual="${result#mismatch:}"
      echo "    MISMATCH — $actual, expected ~$expected — queuing re-download"
      csv_set "$entry" "status=failed" "verified=mismatch" "tmp_path="
    fi
  done <<< "$UNVERIFIED"
fi

# ── Phase 2: download pending + failed ───────────────────────────────────────

PENDING=$(csv_rows_where status not_started failed || true)
if [[ -z "$PENDING" ]]; then
  echo ""; echo "==> Nothing to download."; exit 0
fi

echo ""; echo "==> Downloading $(echo "$PENDING" | wc -l | tr -d ' ') album(s)"

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  parse_entry "$entry"
  echo ""; echo "--- $entry"

  expected=""; min_tracks=""
  if [[ -n "$artist" ]]; then
    expected=$(mb_track_count "$artist" "$album" 2>/dev/null || true)
    sleep 1
    if [[ -n "$expected" ]]; then
      variance=$(track_variance "$expected")
      min_tracks=$(( expected - variance < 1 ? 1 : expected - variance ))
      echo "    MusicBrainz: $expected tracks (accepting ${min_tracks}+)"
    else
      echo "    MusicBrainz: not found"
    fi
  fi

  existing=$(find_folder "$artist" "$(strip_year "${album:-}")" || true)
  if [[ -n "$existing" ]]; then
    actual=$(count_audio "$existing")
    echo "    Found in staging: $actual tracks"
    if [[ -n "$expected" ]]; then
      result=$(verify_tracks "$existing" "$expected")
      if [[ "$result" == "ok" ]]; then
        echo "    OK — already complete"
        csv_set "$entry" "status=completed" "verified=verified" "tmp_path=$existing"
        continue
      else
        echo "    Track count mismatch — re-downloading"
        rm -rf "$existing"
      fi
    elif [[ "$actual" -ge "$MIN_STAGING_TRACKS" ]]; then
      echo "    No MB data — accepting ($actual tracks)"
      csv_set "$entry" "status=completed" "verified=unverified" "tmp_path=$existing"
      continue
    else
      echo "    Only $actual tracks — too few to trust, re-downloading"
    fi
  fi

  csv_set "$entry" "status=in_progress" "verified=" "fail_reason="

  # Construct canonical "Artist - Album" search string for sldl
  if [[ -n "$artist" ]]; then
    sldl_search="$artist - $album"
  else
    sldl_search="$entry"
  fi

  sldl_args=(
    "$sldl_search"
    --user "$USERNAME" --pass "$PASSWORD"
    --path "$STAGING" --album
    --pref-format mp3 --pref-min-bitrate 320 --min-bitrate 128
    --interactive false
  )
  [[ -n "$min_tracks" ]] && sldl_args+=(--album-track-count "${min_tracks}+")

  before=$(find "$STAGING/tmp" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort || true)

  _sldl_log=$(mktemp)
  if sldl "${sldl_args[@]}" 2>&1 | tee "$_sldl_log"; then
    rm -f "$_sldl_log"
    after=$(find "$STAGING/tmp" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort || true)
    new_folder=$(comm -13 <(echo "$before") <(echo "$after") | head -1 || true)
    [[ -z "$new_folder" ]] && new_folder=$(find_folder "$artist" "$(strip_year "${album:-}")" || true)
    verified_val="unverified"
    if [[ -n "$expected" && -n "$new_folder" ]]; then
      result=$(verify_tracks "$new_folder" "$expected")
      [[ "$result" == "ok" ]] && verified_val="verified"
    fi
    if [[ -n "$new_folder" ]] && find "$new_folder" -maxdepth 1 -name "*.incomplete" -print -quit | grep -q .; then
      echo "    .incomplete files present — marking failed for retry"
      csv_set "$entry" "status=failed" "verified=" "tmp_path=$new_folder" \
        "fail_reason=.incomplete files remain after download"
    else
      csv_set "$entry" "status=completed" "verified=$verified_val" "tmp_path=${new_folder:-}"
      echo "    Done — marked $verified_val"
    fi
  else
    _fail_reason=$(grep -v '^[[:space:]]*$' "$_sldl_log" \
      | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g;s/\r//g' \
      | tail -1)
    # sldl sometimes crashes after successful download — check for recovered files
    after=$(find "$STAGING/tmp" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort || true)
    recovered=$(comm -13 <(echo "$before") <(echo "$after") | head -1 || true)
    [[ -z "$recovered" ]] && recovered=$(find_folder "$artist" "$(strip_year "${album:-}")" || true)
    rm -f "$_sldl_log"
    if [[ -n "$recovered" && $(count_audio "$recovered") -ge "$MIN_STAGING_TRACKS" ]]; then
      echo "    sldl crashed but files recovered in $(basename "$recovered") — marking unverified"
      csv_set "$entry" "status=completed" "verified=unverified" "tmp_path=$recovered" \
        "fail_reason=recovered after crash: ${_fail_reason}"
    else
      csv_set "$entry" "status=failed" "verified=" "tmp_path=" "fail_reason=${_fail_reason}"
      echo "    FAILED: ${_fail_reason:-(no output captured)}"
    fi
  fi

done <<< "$PENDING"

echo ""; echo "==> Download phase complete."
