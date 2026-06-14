#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.toml"
WATCHLIST="$SCRIPT_DIR/watchlist.txt"

# --- parse config.toml (no external deps) ---
parse_toml_val() {
  grep -E "^$1\s*=" "$CONFIG" | sed 's/.*=\s*"\(.*\)"/\1/'
}
USERNAME=$(parse_toml_val username)
PASSWORD=$(parse_toml_val password)
STAGING=$(parse_toml_val staging | sed "s|~|$HOME|")
DEVICE=$(parse_toml_val device | sed "s|~|$HOME|")

# --- guards ---
[[ -z "$USERNAME" || -z "$PASSWORD" ]] && { echo "config.toml: missing credentials"; exit 1; }
[[ ! -f "$WATCHLIST" ]] && { echo "watchlist.txt not found"; exit 1; }

# filter to non-empty, non-comment lines
PENDING=$(grep -v '^\s*#' "$WATCHLIST" | grep -v '^\s*$' || true)
[[ -z "$PENDING" ]] && { echo "Watchlist empty — nothing to do."; exit 0; }

mkdir -p "$STAGING"

# write a temp file of just pending entries for sldl
TMPLIST=$(mktemp)
echo "$PENDING" > "$TMPLIST"

echo "==> Downloading $(echo "$PENDING" | wc -l | tr -d ' ') album(s) to $STAGING"

sldl \
  --username "$USERNAME" \
  --password "$PASSWORD" \
  --path "$STAGING" \
  --type album \
  --pref-format mp3 \
  --pref-bitrate 320 \
  --min-bitrate 128 \
  --input "$TMPLIST"

rm "$TMPLIST"

echo "==> Running prep.sh"
bash "$SCRIPT_DIR/prep.sh" "$STAGING"

if [[ -d "$DEVICE" ]]; then
  echo "==> Syncing to $DEVICE"
  rsync -av --ignore-existing "$STAGING"/ "$DEVICE"/
else
  echo "WARNING: Device not mounted at $DEVICE — skipping copy"
fi

# mark completed entries as done in watchlist
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  escaped=$(printf '%s\n' "$line" | sed 's/[[\.*^$()+?{|]/\\&/g')
  sed -i '' "s|^${escaped}$|# done: ${line}|" "$WATCHLIST"
done <<< "$PENDING"

echo "==> Done."
