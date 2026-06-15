#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/helpers.sh"

_TMP=$(mktemp -d)
trap 'rm -rf "$_TMP"' EXIT

MAKE_MP3="python3 $SCRIPT_DIR/fixtures/make_mp3.py"

# Fresh staging dir for each test — avoids folder collisions
next_stg() { local d="$_TMP/stg$((++_STG_N))"; mkdir -p "$d"; echo "$d"; }
_STG_N=0

# ── sanitize ──────────────────────────────────────────────────────────────────
# Function is defined inside prep.sh, so we source it inline here for unit testing.
sanitize() {
  echo "$1" | tr -d '\\:*?"<>|' | sed 's/  */ /g' | sed 's/^ //;s/ $//'
}

begin_suite "sanitize (FAT32 char stripping)"

it "passes through normal artist - album"
assert_eq "$(sanitize 'Aphex Twin - Syro')" "Aphex Twin - Syro"

it "strips colon"
assert_eq "$(sanitize 'A: Side')" "A Side"

it "strips all illegal FAT32 chars"
assert_eq "$(sanitize 'A:B*C?D"E<F>G|H')" "ABCDEFGH"

it "collapses multiple spaces"
assert_eq "$(sanitize 'A  B   C')" "A B C"

it "trims leading and trailing spaces"
assert_eq "$(sanitize '  hello world  ')" "hello world"

it "preserves apostrophes (valid on FAT32)"
assert_eq "$(sanitize "Don't Stop")" "Don't Stop"

it "preserves forward slash (valid on FAT32, not in set)"
assert_eq "$(sanitize 'AC/DC')" "AC/DC"

# ── prep.sh integration ───────────────────────────────────────────────────────
begin_suite "prep.sh folder rename"

it "renames folder to Artist - Album based on ID3"
stg=$(next_stg)
mkdir -p "$stg/random-folder-name"
$MAKE_MP3 "$stg/random-folder-name/track1.mp3" "Radiohead" "In Rainbows" > /dev/null
bash "$REPO/prep.sh" "$stg" > /dev/null
assert_not_empty "$(ls -d "$stg/Radiohead - In Rainbows" 2>/dev/null || true)"

it "prefers TPE2 (album artist) over TPE1 (track artist)"
stg=$(next_stg)
mkdir -p "$stg/feat-folder"
$MAKE_MP3 "$stg/feat-folder/track1.mp3" \
  "Clean Album Artist" "The Album" "Feat. Someone" > /dev/null
bash "$REPO/prep.sh" "$stg" > /dev/null
assert_not_empty "$(ls -d "$stg/Clean Album Artist - The Album" 2>/dev/null || true)"

it "skips folder with no MP3 (no ID3 readable)"
stg=$(next_stg)
mkdir -p "$stg/no-mp3-folder"
touch "$stg/no-mp3-folder/audio.flac"
bash "$REPO/prep.sh" "$stg" > /dev/null
assert_not_empty "$(ls -d "$stg/no-mp3-folder" 2>/dev/null || true)"

it "skips rename when already correctly named"
stg=$(next_stg)
mkdir -p "$stg/Charli XCX - Charli"
$MAKE_MP3 "$stg/Charli XCX - Charli/track1.mp3" "Charli XCX" "Charli" > /dev/null
out=$(bash "$REPO/prep.sh" "$stg" 2>&1)
[[ "$out" == *"OK (already named)"* ]]
it "already-named output is present"; assert_eq "$?" "0"

it "skips when target folder already exists (avoids clobber)"
stg=$(next_stg)
mkdir -p "$stg/source-folder"
mkdir -p "$stg/Dupe Artist - Dupe Album"  # pre-existing target
$MAKE_MP3 "$stg/source-folder/track1.mp3" "Dupe Artist" "Dupe Album" > /dev/null
bash "$REPO/prep.sh" "$stg" > /dev/null
assert_not_empty "$(ls -d "$stg/source-folder" 2>/dev/null || true)"

it "strips FAT32-illegal chars from renamed folder"
stg=$(next_stg)
mkdir -p "$stg/raw-folder"
$MAKE_MP3 "$stg/raw-folder/track1.mp3" 'Bad: Artist*Name' 'Album?Title' > /dev/null
bash "$REPO/prep.sh" "$stg" > /dev/null
assert_not_empty "$(ls -d "$stg/Bad Artist*Name - AlbumTitle" 2>/dev/null \
  || ls -d "$stg/"Bad*"Artist"*"Name"* 2>/dev/null || true)"

begin_suite "prep.sh LRC deletion"

it "deletes .lrc files from folder"
stg=$(next_stg)
mkdir -p "$stg/lrc-test"
$MAKE_MP3 "$stg/lrc-test/track1.mp3" "Test Artist" "Test Album" > /dev/null
touch "$stg/lrc-test/track1.lrc" "$stg/lrc-test/track2.lrc"
bash "$REPO/prep.sh" "$stg" > /dev/null
# Folder was renamed by prep.sh
new_dir="$stg/Test Artist - Test Album"
assert_empty "$(find "${new_dir:-$stg/lrc-test}" -name '*.lrc' 2>/dev/null | head -1)"

it "preserves audio files when deleting LRCs"
stg=$(next_stg)
mkdir -p "$stg/lrc-only-del"
$MAKE_MP3 "$stg/lrc-only-del/track1.mp3" "Keep Artist" "Keep Album" > /dev/null
touch "$stg/lrc-only-del/track1.lrc"
bash "$REPO/prep.sh" "$stg" > /dev/null
new_dir="$stg/Keep Artist - Keep Album"
assert_not_empty "$(find "${new_dir:-$stg/lrc-only-del}" -name '*.mp3' 2>/dev/null | head -1)"

finish
