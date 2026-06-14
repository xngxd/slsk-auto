#!/usr/bin/env bash
set -euo pipefail
# Download pending albums and verify track counts against MusicBrainz.
# Safe to run standalone or called by sync.sh.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_config
mkdir -p "$STAGING"

[[ ! -f "$WATCHLIST" ]] && { echo "watchlist.csv not found"; exit 1; }

parse_entry() {
  if [[ "$1" =~ ^(.+)[[:space:]]+-[[:space:]]+(.+)$ ]]; then
    artist="${BASH_REMATCH[1]}"; album="${BASH_REMATCH[2]}"
  else
    artist=""; album="$1"
  fi
}

# ── Phase 1: verify completed-but-unverified ─────────────────────────────────

UNVERIFIED=$(csv_rows_where verified unverified || true)
if [[ -n "$UNVERIFIED" ]]; then
  echo "==> Verifying $(echo "$UNVERIFIED" | wc -l | tr -d ' ') downloaded album(s)"
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    parse_entry "$entry"
    echo ""; echo "--- $entry (verify)"
    folder=$(csv_get "$entry" tmp_path)
    [[ -z "$folder" || ! -d "$folder" ]] && folder=$(find_folder "$artist" "$album" || true)
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
  echo "==> Nothing to download."; exit 0
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

  csv_set "$entry" "status=in_progress" "verified="

  sldl_args=(
    "$entry"
    --user "$USERNAME" --pass "$PASSWORD"
    --path "$STAGING" --album
    --pref-format mp3 --pref-min-bitrate 320 --min-bitrate 128
  )
  [[ -n "$min_tracks" ]] && sldl_args+=(--album-track-count "${min_tracks}+")

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

echo ""; echo "==> Download phase complete."
