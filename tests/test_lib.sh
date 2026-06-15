#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/helpers.sh"

_TMP=$(mktemp -d)
trap 'rm -rf "$_TMP"' EXIT

# lib.sh sets CONFIG/WATCHLIST/SCRIPT_DIR at source time — override after
source "$REPO/lib.sh"
CONFIG="$_TMP/config.toml"
WATCHLIST="$_TMP/watchlist.csv"  # not exercised in these tests

cat > "$CONFIG" <<EOF
[soulseek]
username = "testuser"
password = "testpass"
[paths]
staging = "$_TMP/staging"
device  = "$_TMP/device"
EOF

# ── parse_entry ───────────────────────────────────────────────────────────────
begin_suite "parse_entry"

it "em-dash separates album — artist"
parse_entry "Charli — Charli XCX"
assert_eq "$album" "Charli"
assert_eq "$artist" "Charli XCX"

it "hyphen separates album - artist"
parse_entry "Maya - MIA"
assert_eq "$album" "Maya"
assert_eq "$artist" "MIA"

it "year stays in album name"
parse_entry "In Rainbows (2007) — Radiohead"
assert_eq "$album" "In Rainbows (2007)"
assert_eq "$artist" "Radiohead"

it "hyphen in album name — last - is the separator"
parse_entry "Cut 4 Me - Kelela"
assert_eq "$album" "Cut 4 Me"
assert_eq "$artist" "Kelela"

it "no separator → artist empty, whole string is album"
parse_entry "NoSeparatorEntry"
assert_eq "$artist" ""
assert_eq "$album" "NoSeparatorEntry"

it "artist with trailing dots"
parse_entry "AIM (2016) — M.I.A."
assert_eq "$artist" "M.I.A."
assert_eq "$album" "AIM (2016)"

it "em-dash in watchlist format: album comes first"
parse_entry "MAGDALENE — FKA twigs"
assert_eq "$album" "MAGDALENE"
assert_eq "$artist" "FKA twigs"

# ── strip_year ────────────────────────────────────────────────────────────────
begin_suite "strip_year"

it "strips trailing (YYYY)"
assert_eq "$(strip_year 'In Rainbows (2007)')" "In Rainbows"

it "strips year with surrounding spaces"
assert_eq "$(strip_year 'Safe in the Hands of Love (2018)')" "Safe in the Hands of Love"

it "passes through album with no year"
assert_eq "$(strip_year 'Arular')" "Arular"

it "strips year mid-name"
assert_eq "$(strip_year 'janet. (1993)')" "janet."

it "strips year from Careful"
assert_eq "$(strip_year 'Careful (2019)')" "Careful"

# ── track_variance ────────────────────────────────────────────────────────────
begin_suite "track_variance"

it "floors at 2 for small counts (3)"
assert_eq "$(track_variance 3)" "2"

it "floors at 2 when n/5 < 2 (count 9)"
assert_eq "$(track_variance 9)" "2"

it "2 at count 10 (10/5=2, at the floor)"
assert_eq "$(track_variance 10)" "2"

it "4 at count 20"
assert_eq "$(track_variance 20)" "4"

it "10 at count 50"
assert_eq "$(track_variance 50)" "10"

# ── verify_tracks ─────────────────────────────────────────────────────────────
begin_suite "verify_tracks"

_stg="$_TMP/staging"; mkdir -p "$_stg"

mk() {  # mk <n-tracks> <dir-name> → prints path
  local d="$_stg/$2"; mkdir -p "$d"
  for i in $(seq 1 "$1"); do touch "$d/t${i}.mp3"; done
  echo "$d"
}

it "exact match → ok"
assert_eq "$(verify_tracks "$(mk 10 exact)" 10)" "ok"

it "one under within variance → ok"
assert_eq "$(verify_tracks "$(mk 9 one-under)" 10)" "ok"

it "one over within variance → ok"
assert_eq "$(verify_tracks "$(mk 11 one-over)" 10)" "ok"

it "outside variance → mismatch"
assert_eq "$(verify_tracks "$(mk 7 outside)" 10)" "mismatch:7vs10"

it "empty folder → mismatch"
d="$_stg/empty-dir"; mkdir -p "$d"
assert_eq "$(verify_tracks "$d" 10)" "mismatch:0vs10"

# ── find_folder ───────────────────────────────────────────────────────────────
begin_suite "find_folder"

_stg2="$_TMP/staging2"; STAGING="$_stg2"
mkdir -p \
  "$_stg2/tmp/Charli XCX - Charli" \
  "$_stg2/tmp/Radiohead - In Rainbows" \
  "$_stg2/tmp/M.I.A. - AIM" \
  "$_stg2/tmp/M.I.A. - Arular"

it "finds folder by artist+album (case-insensitive)"
assert_eq "$(find_folder 'charli xcx' 'charli')" "$_stg2/tmp/Charli XCX - Charli"

it "finds folder in tmp subdir"
assert_eq "$(find_folder 'radiohead' 'in rainbows')" "$_stg2/tmp/Radiohead - In Rainbows"

it "no match → empty"
assert_empty "$(find_folder 'nobody' 'nothing')"

it "distinguishes M.I.A. AIM from M.I.A. Arular"
assert_eq "$(find_folder 'm.i.a.' 'aim')"    "$_stg2/tmp/M.I.A. - AIM"
assert_eq "$(find_folder 'm.i.a.' 'arular')" "$_stg2/tmp/M.I.A. - Arular"

it "artist-only match is not enough — album must also appear"
# 'radiohead' is in the In Rainbows folder but 'aim' is not
assert_empty "$(find_folder 'radiohead' 'aim')"

it "short artist token does not substring-match longer folder word"
# 'mia' must NOT match 'miami bass' — regression for the false-positive fix.
# Needs its own staging that has no M.I.A. folder (which would legitimately match).
_stg3="$_TMP/staging3"; STAGING="$_stg3"
mkdir -p "$_stg3/tmp/Miami Bass - Aim High"
assert_empty "$(find_folder 'mia' 'aim')"
STAGING="$_stg2"

it "M.I.A. (dotted) correctly matches its own folder after dot removal"
# 'M.I.A.' normalises to 'mia', which must still match 'M.I.A. - AIM' folder
assert_eq "$(find_folder 'm.i.a.' 'aim')" "$_stg2/tmp/M.I.A. - AIM"

finish
