#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.toml"
WATCHLIST="$SCRIPT_DIR/watchlist.csv"

parse_toml_val() {
  grep -E "^$1[[:space:]]*=" "$CONFIG" | sed 's/.*=[[:space:]]*"\(.*\)"/\1/'
}
USERNAME=$(parse_toml_val username)
PASSWORD=$(parse_toml_val password)
STAGING=$(parse_toml_val staging | sed "s|~|$HOME|")
DEVICE=$(parse_toml_val device | sed "s|~|$HOME|")

[[ -z "$USERNAME" || -z "$PASSWORD" ]] && { echo "config.toml: missing credentials"; exit 1; }
[[ ! -f "$WATCHLIST" ]] && { echo "watchlist.csv not found"; exit 1; }

mkdir -p "$STAGING"

# ── CSV helpers ──────────────────────────────────────────────────────────────

csv_rows_where() {
  # Print entry lines where field matches value(s): csv_rows_where status not_started failed
  local field="$1"; shift
  python3 - "$WATCHLIST" "$field" "$@" <<'PYEOF'
import csv, sys
path, field, *vals = sys.argv[1:]
with open(path, newline='') as f:
    for row in csv.DictReader(f):
        if row.get(field, '') in vals:
            print(row['entry'])
PYEOF
}

csv_get() {
  local entry="$1" field="$2"
  python3 - "$WATCHLIST" "$entry" "$field" <<'PYEOF'
import csv, sys
path, entry, field = sys.argv[1:4]
with open(path, newline='') as f:
    for row in csv.DictReader(f):
        if row['entry'] == entry:
            print(row.get(field, ''))
            break
PYEOF
}

csv_set() {
  # csv_set entry field=value [field=value ...]
  local entry="$1"; shift
  python3 - "$WATCHLIST" "$entry" "$@" <<'PYEOF'
import csv, os, sys
path, entry, *pairs = sys.argv[1:]
updates = dict(p.split('=', 1) for p in pairs)
rows = []
with open(path, newline='') as f:
    reader = csv.DictReader(f)
    fieldnames = reader.fieldnames
    for row in reader:
        if row['entry'] == entry:
            row.update(updates)
        rows.append(row)
tmp = path + '.tmp'
with open(tmp, 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    w.writerows(rows)
os.replace(tmp, path)
PYEOF
}

# ── MusicBrainz lookup ───────────────────────────────────────────────────────

mb_track_count() {
  python3 - "$1" "$2" <<'PYEOF'
import sys, urllib.request, urllib.parse, json
artist, album = sys.argv[1], sys.argv[2]
url = 'https://musicbrainz.org/ws/2/release/?' + urllib.parse.urlencode(
    {'query': f'artist:"{artist}" AND release:"{album}"', 'fmt': 'json', 'limit': '5'})
req = urllib.request.Request(url, headers={'User-Agent': 'slsk-auto/1.0 (github.com/xngxd/slsk-auto)'})
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.load(r)
except Exception:
    sys.exit(0)
releases = data.get('releases', [])
if not releases:
    sys.exit(0)
total = sum(m.get('track-count', 0) for m in releases[0].get('media', []))
if total > 0:
    print(total)
PYEOF
}

# ── Audio / folder helpers ───────────────────────────────────────────────────

count_audio() {
  find "$1" -maxdepth 1 \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.opus" \
    -o -iname "*.ogg" -o -iname "*.m4a" \) 2>/dev/null | wc -l | tr -d ' '
}

track_variance() {
  local v=$(( $1 / 5 ))
  echo $(( v < 2 ? 2 : v ))
}

find_folder() {
  # Search staging and staging/tmp for a folder matching artist+album
  local artist album a b
  artist=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  album=$(echo "$2"  | tr '[:upper:]' '[:lower:]')
  for search_dir in "$STAGING" "$STAGING/tmp"; do
    [[ -d "$search_dir" ]] || continue
    while IFS= read -r dir; do
      local name
      name=$(basename "$dir" | tr '[:upper:]' '[:lower:]')
      [[ "$name" == *"$artist"* && "$name" == *"$album"* ]] && { echo "$dir"; return; }
    done < <(find "$search_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  done
}

verify_tracks() {
  local folder="$1" expected="$2"
  local actual variance diff
  actual=$(count_audio "$folder")
  variance=$(track_variance "$expected")
  diff=$(( actual > expected ? actual - expected : expected - actual ))
  (( diff <= variance )) && echo "ok" || echo "mismatch:${actual}vs${expected}"
}

# ── Phase 1: verify completed-but-unverified albums ──────────────────────────

UNVERIFIED=$(csv_rows_where verified unverified || true)
if [[ -n "$UNVERIFIED" ]]; then
  echo "==> Verifying $(echo "$UNVERIFIED" | wc -l | tr -d ' ') downloaded album(s)"
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if [[ "$entry" =~ ^(.+)[[:space:]]+-[[:space:]]+(.+)$ ]]; then
      artist="${BASH_REMATCH[1]}"; album="${BASH_REMATCH[2]}"
    else
      artist=""; album="$entry"
    fi
    echo ""
    echo "--- $entry (verify)"
    folder=$(csv_get "$entry" tmp_path)
    [[ -z "$folder" || ! -d "$folder" ]] && folder=$(find_folder "$artist" "$album")
    if [[ -z "$folder" ]]; then
      echo "    Folder not found — skipping"
      continue
    fi
    expected=$(mb_track_count "$artist" "$album" 2>/dev/null || true)
    sleep 1
    if [[ -z "$expected" ]]; then
      echo "    MusicBrainz: not found — marking unverified"
      csv_set "$entry" "verified=unverified"
      continue
    fi
    result=$(verify_tracks "$folder" "$expected")
    if [[ "$result" == "ok" ]]; then
      echo "    OK — $(count_audio "$folder") tracks vs $expected expected"
      csv_set "$entry" "verified=verified"
    else
      actual="${result#mismatch:}"
      echo "    MISMATCH — $actual, expected ~$expected — flagging for re-download"
      csv_set "$entry" "status=failed" "verified=mismatch" "tmp_path="
    fi
  done <<< "$UNVERIFIED"
fi

# ── Phase 2: download pending + failed albums ─────────────────────────────────

PENDING=$(csv_rows_where status not_started failed || true)
if [[ -z "$PENDING" ]]; then
  echo "==> Nothing to download."
else
  echo ""
  echo "==> Downloading $(echo "$PENDING" | wc -l | tr -d ' ') album(s)"
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if [[ "$entry" =~ ^(.+)[[:space:]]+-[[:space:]]+(.+)$ ]]; then
      artist="${BASH_REMATCH[1]}"; album="${BASH_REMATCH[2]}"
    else
      artist=""; album="$entry"
    fi
    echo ""
    echo "--- $entry"

    expected=""
    min_tracks=""
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

    # Check if already downloaded
    existing=$(find_folder "$artist" "$album" || true)
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
      else
        csv_set "$entry" "status=completed" "verified=unverified" "tmp_path=$existing"
        continue
      fi
    fi

    # Mark in_progress before starting
    csv_set "$entry" "status=in_progress" "verified="

    sldl_args=(
      "$entry"
      --user "$USERNAME"
      --pass "$PASSWORD"
      --path "$STAGING"
      --album
      --pref-format mp3
      --pref-min-bitrate 320
      --min-bitrate 128
    )
    [[ -n "$min_tracks" ]] && sldl_args+=(--album-track-count "${min_tracks}+")

    # Snapshot tmp folders before download to detect new one
    before=$(find "$STAGING/tmp" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort || true)

    if sldl "${sldl_args[@]}"; then
      after=$(find "$STAGING/tmp" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort || true)
      new_folder=$(comm -13 <(echo "$before") <(echo "$after") | head -1 || true)
      [[ -z "$new_folder" ]] && new_folder=$(find_folder "$artist" "$album" || true)
      verified_val="unverified"
      if [[ -n "$expected" && -n "$new_folder" ]]; then
        result=$(verify_tracks "$new_folder" "$expected")
        [[ "$result" == "ok" ]] && verified_val="verified"
      fi
      csv_set "$entry" "status=completed" "verified=$verified_val" "tmp_path=${new_folder:-}"
      echo "    Done — marked $verified_val"
    else
      csv_set "$entry" "status=failed" "verified=" "tmp_path="
      echo "    FAILED"
    fi

  done <<< "$PENDING"
fi

echo ""
echo "==> Running prep.sh on staging"
bash "$SCRIPT_DIR/prep.sh" "$STAGING"
[[ -d "$STAGING/tmp" ]] && bash "$SCRIPT_DIR/prep.sh" "$STAGING/tmp"

if [[ -d "$DEVICE" ]]; then
  echo "==> Syncing to $DEVICE"
  rsync -av --ignore-existing "$STAGING"/ "$DEVICE"/
  [[ -d "$STAGING/tmp" ]] && rsync -av --ignore-existing "$STAGING/tmp"/ "$DEVICE"/
else
  echo "WARNING: Device not mounted at $DEVICE — skipping copy"
fi

echo "==> Done."
