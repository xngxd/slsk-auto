# slsk-auto test suite — demo

**Built by:** Claude Sonnet 4.6, gay twink QA engineer.

---

## What this is

A no-dependency test suite for `slsk-auto`, the Soulseek album download pipeline. Four suites, 92 tests, runs in a few seconds.

```
bash tests/run_tests.sh
```

---

## What's covered

| Suite | File | What it tests |
|---|---|---|
| lib.sh unit tests | `test_lib.sh` | `parse_entry`, `strip_year`, `track_variance`, `verify_tracks`, `find_folder` |
| CSV helpers | `test_csv.sh` | `csv_get`, `csv_set`, `csv_rows_where` |
| prep.sh behavior | `test_prep.sh` | folder rename from ID3 tags, FAT32 sanitize, LRC deletion, clobber guard, TPE2-over-TPE1 |
| reconciler logic | `test_reconciler.py` | Phase 0 folder matching, `min_tracks` threshold, guard rails on verified/completed rows |

Tests are self-contained — they create temp dirs, stub configs, and fake MP3s via `tests/fixtures/make_mp3.py`. No credentials or real network needed.

---

## Spike findings

### 1. Wrongly-mapped staging paths in `watchlist.csv`
Several M.I.A. albums (Kala, Maya, Matangi) are marked completed with `tmp_path` pointing to the AIM staging folder. Substring matching in `find_folder` can't explain this (Kala ≠ AIM). Most likely cause: the before/after directory diff in Phase 2 of `download.sh` fires on a folder created by an *earlier album in the same run*, then assigns it to the next entry processed.

**Where to look:** `download.sh` lines 191–204 — the `before`/`after` diff and the `new_folder` assignment.

### 2. `find_folder` loose substring matching
`find_folder "mia" "aim"` would also match `miami bass - aim high` because `"mia"` is a substring of `"miami"`. Short artist names are at risk. Currently no word-boundary checking.

**Where to look:** `lib.sh:130–141`.

### 3. `fail_reason` leaks raw stack traces
The current `watchlist.csv` has entries like:
```
   at Program.<Main>(String[] args)
```
in the `fail_reason` column. The new capture logic (`tail -1` of filtered log) should help, but hasn't been tested against the sldl crash pattern that caused this.

### 4. Reconciler logic is duplicated
The Phase 0 Python runs as a heredoc inside `download.sh`. `test_reconciler.py` mirrors it manually — if they diverge, tests silently miss bugs. Extract to `lib/reconciler.py` when there's appetite for it.

---

## Files

```
tests/
  run_tests.sh          — runner
  helpers.sh            — bash assert helpers
  test_lib.sh           — lib.sh unit tests
  test_csv.sh           — CSV helper tests
  test_prep.sh          — prep.sh integration tests
  test_reconciler.py    — Phase 0 reconciler logic tests
  fixtures/
    make_mp3.py         — generates minimal ID3v2.3-tagged MP3 files
```
