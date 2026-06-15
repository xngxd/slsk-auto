#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_PASS=0; TOTAL_FAIL=0

run_suite() {
  local name="$1"; shift
  printf "\n════ %s ════\n" "$name"
  if "$@"; then
    TOTAL_PASS=$(( TOTAL_PASS + 1 ))
  else
    TOTAL_FAIL=$(( TOTAL_FAIL + 1 ))
  fi
}

run_suite "lib.sh unit tests"   bash   "$SCRIPT_DIR/test_lib.sh"
run_suite "CSV helpers"         bash   "$SCRIPT_DIR/test_csv.sh"
run_suite "prep.sh behavior"    bash   "$SCRIPT_DIR/test_prep.sh"
run_suite "reconciler logic"    python3 "$SCRIPT_DIR/test_reconciler.py"

printf "\n════════════════════════════════\n"
if [[ $TOTAL_FAIL -eq 0 ]]; then
  printf "All %d suites passed.\n" "$TOTAL_PASS"
else
  printf "%d passed, %d FAILED.\n" "$TOTAL_PASS" "$TOTAL_FAIL"
fi
[[ $TOTAL_FAIL -eq 0 ]]
