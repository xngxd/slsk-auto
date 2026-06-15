#!/usr/bin/env bash
# Shared helpers — source this file, do not run directly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.toml"
WATCHLIST="$SCRIPT_DIR/watchlist.csv"

# ── Config ────────────────────────────────────────────────────────────────────

parse_toml_val() {
  grep -E "^$1[[:space:]]*=" "$CONFIG" | sed 's/.*=[[:space:]]*"\(.*\)"/\1/'
}

load_config() {
  USERNAME=$(parse_toml_val username)
  PASSWORD=$(parse_toml_val password)
  STAGING=$(parse_toml_val staging | sed "s|~|$HOME|")
  DEVICE=$(parse_toml_val device | sed "s|~|$HOME|")
  if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
    echo "config.toml: missing credentials"; exit 1
  fi
}

# ── CSV helpers ───────────────────────────────────────────────────────────────

csv_rows_where() {
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
  python3 - "$WATCHLIST" "$1" "$2" <<'PYEOF'
import csv, sys
path, entry, field = sys.argv[1:4]
with open(path, newline='') as f:
    for row in csv.DictReader(f):
        if row['entry'] == entry:
            print(row.get(field, '')); break
PYEOF
}

csv_set() {
  local entry="$1"; shift
  python3 - "$WATCHLIST" "$entry" "$@" <<'PYEOF'
import csv, os, sys
path, entry, *pairs = sys.argv[1:]
updates = dict(p.split('=', 1) for p in pairs)
rows = []
with open(path, newline='') as f:
    reader = csv.DictReader(f)
    fieldnames = list(reader.fieldnames)
    for row in reader:
        if row['entry'] == entry:
            row.update(updates)
        rows.append(row)
for key in updates:
    if key not in fieldnames:
        fieldnames.append(key)
tmp = path + '.tmp'
with open(tmp, 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction='ignore')
    w.writeheader(); w.writerows(rows)
os.replace(tmp, path)
PYEOF
}

# ── Entry parsing ────────────────────────────────────────────────────────────
#
# Watchlist convention: Album [— or -] Artist
# Both separators, same order — album always comes first.

parse_entry() {
  if [[ "$1" =~ ^(.+)[[:space:]]+—[[:space:]]+(.+)$ ]]; then
    album="${BASH_REMATCH[1]}"; artist="${BASH_REMATCH[2]}"
  elif [[ "$1" =~ ^(.+)[[:space:]]+-[[:space:]]+(.+)$ ]]; then
    album="${BASH_REMATCH[1]}"; artist="${BASH_REMATCH[2]}"
  else
    artist=""; album="$1"
  fi
}

# Strip trailing/embedded (YYYY) from album name — used for folder matching
# where staged folder names don't include the year qualifier.
strip_year() {
  echo "$1" | sed 's/[[:space:]]*([0-9]\{4\})[[:space:]]*//'
}

# ── MusicBrainz ───────────────────────────────────────────────────────────────

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

# ── Folder / audio helpers ────────────────────────────────────────────────────

count_audio() {
  find "$1" -maxdepth 1 \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.opus" \
    -o -iname "*.ogg" -o -iname "*.m4a" \) 2>/dev/null | wc -l | tr -d ' '
}

track_variance() {
  local v=$(( $1 / 5 ))
  echo $(( v < 2 ? 2 : v ))
}

find_folder() {
  local artist album name
  artist=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  album=$(echo "$2"  | tr '[:upper:]' '[:lower:]')
  for search_dir in "$STAGING" "$STAGING/tmp"; do
    [[ -d "$search_dir" ]] || continue
    while IFS= read -r dir; do
      name=$(basename "$dir" | tr '[:upper:]' '[:lower:]')
      [[ "$name" == *"$artist"* && "$name" == *"$album"* ]] && { echo "$dir"; return; }
    done < <(find "$search_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  done
}

verify_tracks() {
  local actual variance diff
  actual=$(count_audio "$1")
  variance=$(track_variance "$2")
  diff=$(( actual > $2 ? actual - $2 : $2 - actual ))
  (( diff <= variance )) && echo "ok" || echo "mismatch:${actual}vs${2}"
}
