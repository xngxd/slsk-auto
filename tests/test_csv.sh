#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/helpers.sh"

_TMP=$(mktemp -d)
trap 'rm -rf "$_TMP"' EXIT

source "$REPO/lib.sh"
CONFIG="$_TMP/config.toml"
cat > "$CONFIG" <<EOF
[soulseek]
username = "u"
password = "p"
[paths]
staging = "$_TMP/staging"
device  = "$_TMP/device"
EOF

_csv="$_TMP/watchlist.csv"
WATCHLIST="$_csv"

reset_csv() {
  cat > "$_csv" <<'CSV'
entry,tmp_path,status,verified,fail_reason
Charli — Charli XCX,,not_started,,
In Rainbows (2007) — Radiohead,/tmp/in-rainbows,completed,verified,
Maya - MIA,,failed,,sldl exited 1
CSV
}

# ── csv_get ───────────────────────────────────────────────────────────────────
begin_suite "csv_get"

reset_csv

it "reads a string field"
assert_eq "$(csv_get 'In Rainbows (2007) — Radiohead' status)" "completed"

it "reads verified field"
assert_eq "$(csv_get 'In Rainbows (2007) — Radiohead' verified)" "verified"

it "reads empty field as empty string"
assert_eq "$(csv_get 'Charli — Charli XCX' tmp_path)" ""

it "reads fail_reason"
assert_eq "$(csv_get 'Maya - MIA' fail_reason)" "sldl exited 1"

# ── csv_set ───────────────────────────────────────────────────────────────────
begin_suite "csv_set"

reset_csv

it "sets a single field"
csv_set 'Charli — Charli XCX' 'status=in_progress'
assert_eq "$(csv_get 'Charli — Charli XCX' status)" "in_progress"

it "sets multiple fields in one call"
csv_set 'Maya - MIA' 'status=completed' 'verified=unverified' 'tmp_path=/tmp/maya'
assert_eq "$(csv_get 'Maya - MIA' status)" "completed"
assert_eq "$(csv_get 'Maya - MIA' verified)" "unverified"
assert_eq "$(csv_get 'Maya - MIA' tmp_path)" "/tmp/maya"

it "sets field to empty string"
csv_set 'In Rainbows (2007) — Radiohead' 'verified='
assert_eq "$(csv_get 'In Rainbows (2007) — Radiohead' verified)" ""

it "does not modify unrelated rows"
assert_eq "$(csv_get 'Charli — Charli XCX' status)" "in_progress"  # unchanged from above

it "writes atomically — file is valid CSV after set"
python3 -c "
import csv, sys
with open('$_csv', newline='') as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 3, f'expected 3 rows, got {len(rows)}'
sys.exit(0)
"
assert_eq "$?" "0"

# ── csv_rows_where ────────────────────────────────────────────────────────────
begin_suite "csv_rows_where"

reset_csv

it "returns entries matching a single status"
result=$(csv_rows_where status not_started)
assert_eq "$result" "Charli — Charli XCX"

it "returns entries matching completed"
result=$(csv_rows_where status completed)
assert_eq "$result" "In Rainbows (2007) — Radiohead"

it "accepts multiple values (OR semantics)"
result=$(csv_rows_where status not_started failed)
assert_eq "$(echo "$result" | wc -l | tr -d ' ')" "2"

it "returns empty string when no rows match"
result=$(csv_rows_where status in_progress || true)
assert_empty "$result"

it "returns empty string for unknown status"
result=$(csv_rows_where status bananas || true)
assert_empty "$result"

finish
