#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.toml"
WATCHLIST="$SCRIPT_DIR/watchlist.txt"

parse_toml_val() {
  grep -E "^$1[[:space:]]*=" "$CONFIG" | sed 's/.*=[[:space:]]*"\(.*\)"/\1/'
}
USERNAME=$(parse_toml_val username)
PASSWORD=$(parse_toml_val password)
STAGING=$(parse_toml_val staging | sed "s|~|$HOME|")
DEVICE=$(parse_toml_val device | sed "s|~|$HOME|")

[[ -z "$USERNAME" || -z "$PASSWORD" ]] && { echo "config.toml: missing credentials"; exit 1; }
[[ ! -f "$WATCHLIST" ]] && { echo "watchlist.txt not found"; exit 1; }

PENDING=$(grep -v '^\s*#' "$WATCHLIST" | grep -v '^\s*$' || true)
[[ -z "$PENDING" ]] && { echo "Watchlist empty — nothing to do."; exit 0; }

mkdir -p "$STAGING"

# Query MusicBrainz for official track count. Returns empty if not found.
mb_track_count() {
  python3 - "$1" "$2" <<'PYEOF'
import sys, urllib.request, urllib.parse, json

artist, album = sys.argv[1], sys.argv[2]
query = f'artist:"{artist}" AND release:"{album}"'
url = 'https://musicbrainz.org/ws/2/release/?' + urllib.parse.urlencode(
    {'query': query, 'fmt': 'json', 'limit': '5'})
req = urllib.request.Request(url, headers={
    'User-Agent': 'slsk-auto/1.0 (github.com/xngxd/slsk-auto)'})
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

# Count audio files in a directory (top-level only)
count_audio() {
  find "$1" -maxdepth 1 \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.opus" \
    -o -iname "*.ogg" -o -iname "*.m4a" \) | wc -l | tr -d ' '
}

# Variance: ±20% of expected, minimum ±2
track_variance() {
  local v=$(( $1 / 5 ))
  echo $(( v < 2 ? 2 : v ))
}

# Find an existing staging folder for this artist/album (case-insensitive)
find_staging_folder() {
  local artist album name a b
  artist=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  album=$(echo "$2"  | tr '[:upper:]' '[:lower:]')
  while IFS= read -r dir; do
    name=$(basename "$dir" | tr '[:upper:]' '[:lower:]')
    [[ "$name" == *"$artist"* && "$name" == *"$album"* ]] && { echo "$dir"; return; }
  done < <(find "$STAGING" -maxdepth 1 -mindepth 1 -type d)
}

# Mark a watchlist entry as done in-place
mark_done() {
  local escaped
  escaped=$(printf '%s\n' "$1" | sed 's/[[\.*^$()+?{|]/\\&/g')
  sed -i '' "s|^${escaped}$|# done: ${1}|" "$WATCHLIST"
}

echo "==> Processing $(echo "$PENDING" | wc -l | tr -d ' ') album(s)"

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue

  # Parse "Artist - Album"
  if [[ "$entry" =~ ^(.+)[[:space:]]+-[[:space:]]+(.+)$ ]]; then
    artist="${BASH_REMATCH[1]}"
    album="${BASH_REMATCH[2]}"
  else
    artist=""
    album="$entry"
  fi

  echo ""
  echo "--- $entry"

  # MusicBrainz lookup (rate-limit: 1 req/sec for unauthenticated)
  expected=""
  if [[ -n "$artist" ]]; then
    expected=$(mb_track_count "$artist" "$album" 2>/dev/null || true)
    sleep 1
    if [[ -n "$expected" ]]; then
      variance=$(track_variance "$expected")
      min_tracks=$(( expected - variance ))
      (( min_tracks < 1 )) && min_tracks=1
      echo "    MusicBrainz: $expected tracks (accepting ${min_tracks}+)"
    else
      echo "    MusicBrainz: not found — no track count constraint"
    fi
  fi

  # Check existing staging folder
  existing=""
  if [[ -n "$artist" ]]; then
    existing=$(find_staging_folder "$artist" "$album" || true)
  fi

  if [[ -n "$existing" ]]; then
    actual=$(count_audio "$existing")
    echo "    Staging: $actual tracks in $(basename "$existing")"

    if [[ -n "$expected" ]]; then
      variance=$(track_variance "$expected")
      diff=$(( actual > expected ? actual - expected : expected - actual ))
      if (( diff <= variance )); then
        echo "    OK — close enough ($actual vs $expected expected)"
        mark_done "$entry"
        continue
      else
        echo "    INCOMPLETE — $actual tracks vs $expected expected, re-downloading"
        rm -rf "$existing"
      fi
    else
      echo "    No MB data to verify — keeping existing folder"
      mark_done "$entry"
      continue
    fi
  fi

  # Download
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
  if [[ -n "$expected" ]]; then
    sldl_args+=(--album-track-count "${min_tracks}+")
  fi

  if sldl "${sldl_args[@]}"; then
    mark_done "$entry"
  else
    echo "    WARNING: download failed for: $entry"
  fi

done <<< "$PENDING"

echo ""
echo "==> Running prep.sh"
bash "$SCRIPT_DIR/prep.sh" "$STAGING"

if [[ -d "$DEVICE" ]]; then
  echo "==> Syncing to $DEVICE"
  rsync -av --ignore-existing "$STAGING"/ "$DEVICE"/
else
  echo "WARNING: Device not mounted at $DEVICE — skipping copy"
fi

echo "==> Done."
