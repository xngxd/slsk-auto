#!/usr/bin/env bash
set -euo pipefail

STAGING="${1:?Usage: prep.sh <staging-dir>}"

# Strip FAT32-illegal chars and collapse extra spaces
sanitize() {
  echo "$1" | tr -d '\\:*?"<>|' | sed 's/  */ /g' | sed 's/^ //;s/ $//'
}

# Read ID3v2 tags from the first MP3 in a folder.
# Prints "Artist|Album" to stdout, or nothing on failure.
read_id3() {
  local dir="$1"
  local mp3
  mp3=$(find "$dir" -maxdepth 1 -iname "*.mp3" | sort | head -1)
  [[ -z "$mp3" ]] && return
  python3 - "$mp3" <<'PYEOF'
import sys, struct

def read_id3v2(path):
    tags = {}
    try:
        with open(path, 'rb') as f:
            header = f.read(10)
            if header[:3] != b'ID3':
                return tags
            size_bytes = header[6:10]
            size = (size_bytes[0]<<21)|(size_bytes[1]<<14)|(size_bytes[2]<<7)|size_bytes[3]
            data = f.read(size)
        pos = 0
        while pos < len(data) - 10:
            frame_id = data[pos:pos+4].decode('ascii', errors='ignore')
            if not frame_id.strip('\x00'):
                break
            frame_size = struct.unpack('>I', data[pos+4:pos+8])[0]
            frame_data = data[pos+10:pos+10+frame_size]
            if frame_id in ('TPE1', 'TPE2', 'TALB'):
                enc = frame_data[0]
                text = frame_data[1:]
                if enc == 0:
                    tags[frame_id] = text.decode('latin-1', errors='replace').strip('\x00').strip()
                elif enc == 1:
                    tags[frame_id] = text.decode('utf-16', errors='replace').strip('\x00').strip()
                elif enc == 3:
                    tags[frame_id] = text.decode('utf-8', errors='replace').strip('\x00').strip()
            pos += 10 + frame_size
    except Exception:
        pass
    return tags

tags = read_id3v2(sys.argv[1])
artist = tags.get('TPE2') or tags.get('TPE1', '')
album  = tags.get('TALB', '')
if artist and album:
    print(f"{artist}|{album}")
PYEOF
}

shopt -s nullglob
for dir in "$STAGING"/*/; do
  [[ -d "$dir" ]] || continue
  dir="${dir%/}"
  folder=$(basename "$dir")

  if find "$dir" -maxdepth 1 -name "*.incomplete" -print -quit | grep -q .; then
    echo "SKIP (.incomplete): $folder"
    continue
  fi

  find "$dir" -iname "*.lrc" -delete

  tag_info=$(read_id3 "$dir")
  if [[ -z "$tag_info" ]]; then
    echo "SKIP (no ID3): $folder"
    continue
  fi

  raw_artist="${tag_info%%|*}"
  raw_album="${tag_info##*|}"

  artist=$(sanitize "$raw_artist")
  album=$(sanitize "$raw_album")

  if [[ -z "$artist" || -z "$album" ]]; then
    echo "SKIP (empty tags after sanitize): $folder"
    continue
  fi

  new_name="$artist - $album"
  new_path="$(dirname "$dir")/$new_name"

  if [[ "$dir" == "$new_path" ]]; then
    echo "OK (already named): $new_name"
    continue
  fi

  if [[ -e "$new_path" ]]; then
    echo "SKIP (target exists): $new_name"
    continue
  fi

  mv "$dir" "$new_path"
  echo "RENAMED: $folder → $new_name"
done
