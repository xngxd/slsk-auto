#!/usr/bin/env bash
# Minimal test helpers — no external dependencies.

PASS=0; FAIL=0; _test_name=""

begin_suite() { printf "\n  ── %s\n" "$1"; }

it() { _test_name="$1"; }

assert_eq() {
  if [[ "$1" == "$2" ]]; then
    PASS=$(( PASS + 1 )); printf "    ✓ %s\n" "$_test_name"
  else
    FAIL=$(( FAIL + 1 )); printf "    ✗ %s\n" "$_test_name"
    printf "        got:  %s\n" "$(printf '%q' "$1")"
    printf "        want: %s\n" "$(printf '%q' "$2")"
  fi
}

assert_not_empty() {
  if [[ -n "$1" ]]; then
    PASS=$(( PASS + 1 )); printf "    ✓ %s\n" "$_test_name"
  else
    FAIL=$(( FAIL + 1 )); printf "    ✗ %s (was empty)\n" "$_test_name"
  fi
}

assert_empty() {
  if [[ -z "$1" ]]; then
    PASS=$(( PASS + 1 )); printf "    ✓ %s\n" "$_test_name"
  else
    FAIL=$(( FAIL + 1 )); printf "    ✗ %s\n" "$_test_name"
    printf "        expected empty, got: %s\n" "$(printf '%q' "$1")"
  fi
}

finish() {
  printf "\n  %d passed, %d failed\n" "$PASS" "$FAIL"
  [[ $FAIL -eq 0 ]]
}
