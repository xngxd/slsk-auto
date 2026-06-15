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

def tokenize(s):
    """Normalize and split into whole tokens. M.I.A. → ['mia'], not ['m','i','a']."""
    s = s.lower().replace('.', '')
    return [w for w in re.split(r'[^a-z0-9]+', s) if len(w) >= 2]

def tokens_match(query_tokens, folder_name):
    folder_set = set(tokenize(folder_name))
    return bool(query_tokens) and all(w in folder_set for w in query_tokens)

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
            staging_folders.append((d.name, str(d), n))

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
    query_tokens = tokenize(artist) + tokenize(album)
    if not query_tokens:
        continue

    for folder_name, folder_path, n in staging_folders:
        if tokens_match(query_tokens, folder_name):
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

# ── Phase 0.5: reset stuck in_progress entries ───────────────────────────────
# Any entry that is still in_progress with no valid staging folder got stranded
# by a crashed run. Reset to not_started so Phase 2 picks it up again.
python3 - "$WATCHLIST" <<'PYEOF'
import csv, os, sys
from pathlib import Path

AUDIO_EXTS = {'.mp3', '.flac', '.opus', '.ogg', '.m4a'}

watchlist_path = sys.argv[1]
rows = []
with open(watchlist_path, newline='') as f:
    reader = csv.DictReader(f)
    fieldnames = list(reader.fieldnames)
    rows = list(reader)

reset = 0
for row in rows:
    if row.get('status') != 'in_progress':
        continue
    tp = row.get('tmp_path', '')
    if tp and Path(tp).is_dir():
        has_audio = any(f.suffix.lower() in AUDIO_EXTS for f in Path(tp).iterdir() if f.is_file())
        if has_audio:
            continue  # folder is real and has audio, leave it
    row['status'] = 'not_started'
    row['tmp_path'] = ''
    row['fail_reason'] = 'reset: no valid staging folder after crash'
    reset += 1
    print(f"  RESET → not_started: {row['entry']}")

if reset:
    tmp = watchlist_path + '.tmp'
    with open(tmp, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction='ignore')
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, watchlist_path)

print(f"==> Reset {reset} stuck in_progress entr{'y' if reset == 1 else 'ies'} to not_started")
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
      rm -rf "$existing"
    fi
  fi

  # Increment attempt counter
  _cur_attempts=$(csv_get "$entry" attempts 2>/dev/null || echo "0")
  _new_attempts=$(( ${_cur_attempts:-0} + 1 ))
  csv_set "$entry" "status=in_progress" "verified=" "fail_reason=" "attempts=$_new_attempts"

  # Construct canonical "Artist - Album" search string for sldl
  if [[ -n "$artist" ]]; then
    sldl_search="$artist - $album"
  else
    sldl_search="$entry"
  fi

  # Read previously tried users so we don't hit the same source twice
  _tried_users=$(csv_get "$entry" tried_users 2>/dev/null || echo "")
  [[ -n "$_tried_users" ]] && echo "    Banning previously tried: $_tried_users"

  sldl_args=(
    "$sldl_search"
    --user "$USERNAME" --pass "$PASSWORD"
    --path "$STAGING/tmp" --album
    --pref-format mp3 --pref-min-bitrate 320 --min-bitrate 128
    --interactive false
    --no-browse-folder
  )
  [[ -n "$min_tracks" ]] && sldl_args+=(--album-track-count "${min_tracks}+")
  [[ -n "$_tried_users" ]] && sldl_args+=(--banned-users "$_tried_users")

  before=$(find "$STAGING/tmp" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort || true)

  _record_tried_users() {
    local log_file="$1" new_users existing all_tried
    new_users=$(grep '^User  :' "$log_file" | awk '{print $3}' | sort -u | paste -sd, || true)
    if [[ -n "$new_users" ]]; then
      existing=$(csv_get "$entry" tried_users 2>/dev/null || echo "")
      if [[ -z "$existing" ]]; then
        all_tried="$new_users"
      else
        all_tried=$(printf '%s\n' "$existing" "$new_users" | tr ',' '\n' | sort -u | paste -sd,)
      fi
      csv_set "$entry" "tried_users=$all_tried"
      echo "    Source(s) recorded: $new_users"
    fi
  }

  _sldl_log=$(mktemp)
  if sldl "${sldl_args[@]}" 2>&1 | tee "$_sldl_log"; then
    _record_tried_users "$_sldl_log"
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
    _record_tried_users "$_sldl_log"
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
