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
import sys, re, urllib.request, urllib.parse, json
UA = 'slsk-auto/1.0 (github.com/xngxd/slsk-auto)'

artist, album = sys.argv[1], sys.argv[2]
album = re.sub(r'\s*\(\d{4}\)\s*', '', album).strip()  # strip year

def mb_fetch(q, limit=5):
    url = 'https://musicbrainz.org/ws/2/release/?' + urllib.parse.urlencode(
        {'query': q, 'fmt': 'json', 'limit': str(limit)})
    try:
        with urllib.request.urlopen(
                urllib.request.Request(url, headers={'User-Agent': UA}), timeout=10) as r:
            return json.load(r).get('releases', [])
    except Exception:
        return []

def track_total(releases):
    if not releases:
        return 0
    return sum(m.get('track-count', 0) for m in releases[0].get('media', []))

def slug(s):
    """Strip everything except alphanumeric for fuzzy title comparison."""
    return re.sub(r'[^\w]', '', s, flags=re.ASCII).lower()

# Pass 1: direct query — artistname is accent-folded, handles Beyoncé → Beyonce
releases = mb_fetch(f'artistname:"{artist}" AND release:"{album}"')
total = track_total(releases)

# Pass 2: fetch artist's top releases and fuzzy-match by stripping punctuation.
# Handles cases like watchlist "B-day" matching MB title "B'Day" (both → "bday").
if not total and artist:
    album_slug = slug(album)
    if album_slug:
        for r in mb_fetch(f'artistname:"{artist}"', limit=20):
            if slug(r.get('title', '')) == album_slug:
                t = sum(m.get('track-count', 0) for m in r.get('media', []))
                if t > 0:
                    total = t
                    break

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
  # Normalize: remove dots (M.I.A. → mia), lowercase, collapse non-alnum to spaces.
  # Then require each resulting token (len≥2) to appear as a whole word in the folder name.
  # This prevents "mia" from matching "miami" while still matching "M.I.A. - AIM".
  local a_norm al_norm name_norm word match has_terms
  a_norm=$(echo "$1"  | tr '[:upper:]' '[:lower:]' | tr -d '.' | tr -cs 'a-z0-9 ' ' ' | tr -s ' ')
  al_norm=$(echo "$2" | tr '[:upper:]' '[:lower:]' | tr -d '.' | tr -cs 'a-z0-9 ' ' ' | tr -s ' ')
  has_terms=false
  for word in $a_norm $al_norm; do
    [[ ${#word} -ge 2 ]] && { has_terms=true; break; }
  done
  $has_terms || return
  for search_dir in "$STAGING" "$STAGING/tmp"; do
    [[ -d "$search_dir" ]] || continue
    while IFS= read -r dir; do
      name_norm=" $(basename "$dir" | tr '[:upper:]' '[:lower:]' | tr -d '.' | tr -cs 'a-z0-9 ' ' ' | tr -s ' ') "
      match=true
      for word in $a_norm $al_norm; do
        [[ ${#word} -lt 2 ]] && continue
        [[ "$name_norm" == *" $word "* ]] || { match=false; break; }
      done
      $match && { echo "$dir"; return; }
    done < <(find "$search_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  done
}

verify_tracks() {
  local actual variance
  actual=$(count_audio "$1")
  variance=$(track_variance "$2")
  # Only fail if too few — more tracks (deluxe edition) is acceptable.
  (( actual >= $2 - variance )) && echo "ok" || echo "mismatch:${actual}vs${2}"
}
