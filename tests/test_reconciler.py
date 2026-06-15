#!/usr/bin/env python3
"""Tests for Phase 0 reconciler logic — mirrored from download.sh.

If these tests break, cross-check against the Phase 0 Python heredoc in
download.sh to see whether the production code diverged.
"""
import csv, sys, tempfile, re
from pathlib import Path

# ── Logic mirrored from download.sh Phase 0 ──────────────────────────────────

AUDIO_EXTS = {'.mp3', '.flac', '.opus', '.ogg', '.m4a'}


def count_audio(d):
    try:
        return sum(1 for f in Path(d).iterdir() if f.suffix.lower() in AUDIO_EXTS)
    except (PermissionError, FileNotFoundError):
        return 0


def parse_entry(entry):
    """Returns (artist, album). Album has year stripped; artist is the right-hand side."""
    m = re.match(r'^(.+)\s+[—\-]\s+(.+)$', entry)
    if m:
        return m.group(2).strip(), re.sub(r'\s*\(\d{4}\)\s*', ' ', m.group(1)).strip()
    return '', entry


def tokenize(s):
    """Normalize and split into whole tokens. M.I.A. → ['mia'], not ['m','i','a']."""
    s = s.lower().replace('.', '')
    return [w for w in re.split(r'[^a-z0-9]+', s) if len(w) >= 2]


def tokens_match(query_tokens, folder_name):
    folder_set = set(tokenize(folder_name))
    return bool(query_tokens) and all(w in folder_set for w in query_tokens)


def reconcile(rows, staging_folders):
    """Core matching loop. Mutates rows in place; returns changed count."""
    changed = 0
    for row in rows:
        if row['status'] == 'verified':
            continue
        if row['status'] == 'completed' and row.get('tmp_path') and Path(row['tmp_path']).is_dir():
            continue
        artist, album = parse_entry(row['entry'])
        query_tokens = tokenize(artist) + tokenize(album)
        if not query_tokens:
            continue
        for folder_name, folder_path, n in staging_folders:
            if tokens_match(query_tokens, folder_name):
                row['status'] = 'completed'
                row['verified'] = 'unverified'
                row['tmp_path'] = folder_path
                row.setdefault('fail_reason', '')
                changed += 1
                break
    return changed


# ── Helpers ───────────────────────────────────────────────────────────────────

PASS = 0
FAIL = 0


def ok(name):
    global PASS
    PASS += 1
    print(f"  ✓ {name}")


def fail(name, msg=""):
    global FAIL
    FAIL += 1
    print(f"  ✗ {name}")
    if msg:
        print(f"      {msg}")


def assert_eq(got, want, name):
    if got == want:
        ok(name)
    else:
        fail(name, f"got={got!r}, want={want!r}")


def suite(name):
    print(f"\n  ── {name}")


def populate_staging(tmp, folders_with_tracks):
    """Create temp staging/tmp dirs populated with fake audio files."""
    staging_tmp = Path(tmp) / "staging" / "tmp"
    staging_tmp.mkdir(parents=True)
    for folder_name, n_tracks in folders_with_tracks:
        d = staging_tmp / folder_name
        d.mkdir()
        for i in range(n_tracks):
            (d / f"track{i}.mp3").touch()
    return Path(tmp) / "staging"


def scan_staging(staging_path, min_tracks):
    """Mirror production Phase 0: build qualifying folder list with min_tracks filter."""
    staging = Path(staging_path)
    folders = []
    for search in [staging, staging / 'tmp']:
        if not search.is_dir():
            continue
        for d in sorted(search.iterdir()):
            if not d.is_dir() or d.name.startswith('.') or d.name == 'failed':
                continue
            n = count_audio(d)
            if n >= min_tracks:
                folders.append((d.name, str(d), n))  # original case; tokenize() lowercases
    return folders


# ── parse_entry ───────────────────────────────────────────────────────────────

suite("parse_entry")

artist, album = parse_entry("Charli — Charli XCX")
assert_eq(artist, "Charli XCX", "em-dash: artist is right-hand side")
assert_eq(album,  "Charli",     "em-dash: album is left-hand side")

artist, album = parse_entry("Maya - MIA")
assert_eq(artist, "MIA",  "hyphen: artist")
assert_eq(album,  "Maya", "hyphen: album")

artist, album = parse_entry("In Rainbows (2007) — Radiohead")
assert_eq(artist, "Radiohead",    "year entry: artist")
assert_eq(album,  "In Rainbows",  "year entry: year stripped from album")

artist, album = parse_entry("janet. (1993) — Janet Jackson")
assert_eq(artist, "Janet Jackson", "janet.: artist")
assert_eq(album.strip(), "janet.", "janet.: album with year stripped")

artist, album = parse_entry("NoSeparator")
assert_eq(artist, "",            "no separator: artist is empty")
assert_eq(album,  "NoSeparator", "no separator: whole string is album")

artist, album = parse_entry("AIM (2016) — M.I.A.")
assert_eq(artist, "M.I.A.", "dots in artist name preserved")
assert_eq(album,  "AIM",    "year stripped from AIM")

# ── reconciler: folder matching ───────────────────────────────────────────────

suite("reconciler: folder matching")

CSV = """\
entry,tmp_path,status,verified,fail_reason
Charli — Charli XCX,,not_started,,
In Rainbows (2007) — Radiohead,,failed,,
"""

MIN_TRACKS = 5

with tempfile.TemporaryDirectory() as tmp:
    staging = populate_staging(tmp, [
        ("charli xcx - charli", 10),
        ("radiohead - in rainbows", 12),
    ])
    folders = scan_staging(staging, MIN_TRACKS)
    rows = list(csv.DictReader(CSV.splitlines()))
    changed = reconcile(rows, folders)
    r = {row['entry']: row for row in rows}

    assert_eq(r["Charli — Charli XCX"]["status"], "completed", "not_started entry matched → completed")
    assert_eq(r["Charli — Charli XCX"]["verified"], "unverified", "matched entry → unverified")
    assert_eq(r["In Rainbows (2007) — Radiohead"]["status"], "completed", "failed entry matched → completed")
    assert_eq(changed, 2, "changed count is 2")

# ── reconciler: min_tracks threshold ─────────────────────────────────────────

suite("reconciler: min_tracks threshold")

with tempfile.TemporaryDirectory() as tmp:
    staging = populate_staging(tmp, [("charli xcx - charli", 3)])  # below threshold
    folders = scan_staging(staging, MIN_TRACKS)
    rows = list(csv.DictReader(CSV.splitlines()))
    changed = reconcile(rows, folders)
    r = {row['entry']: row for row in rows}
    assert_eq(r["Charli — Charli XCX"]["status"], "not_started", "below min_tracks → not matched")
    assert_eq(changed, 0, "no changes when folder has too few tracks")

with tempfile.TemporaryDirectory() as tmp:
    staging = populate_staging(tmp, [("charli xcx - charli", 5)])  # exactly at threshold
    folders = scan_staging(staging, MIN_TRACKS)
    rows = list(csv.DictReader(CSV.splitlines()))
    changed = reconcile(rows, folders)
    r = {row['entry']: row for row in rows}
    assert_eq(r["Charli — Charli XCX"]["status"], "completed", "exactly at min_tracks → matched")

# ── reconciler: verified rows not overwritten ─────────────────────────────────

suite("reconciler: guard rails")

CSV_VERIFIED = """\
entry,tmp_path,status,verified,fail_reason
Charli — Charli XCX,/old/path,verified,,
"""

with tempfile.TemporaryDirectory() as tmp:
    staging = populate_staging(tmp, [("charli xcx - charli", 10)])
    folders = scan_staging(staging, MIN_TRACKS)
    rows = list(csv.DictReader(CSV_VERIFIED.splitlines()))
    changed = reconcile(rows, folders)
    r = {row['entry']: row for row in rows}
    assert_eq(r["Charli — Charli XCX"]["status"], "verified", "verified rows not overwritten")
    assert_eq(changed, 0, "no changes for verified rows")

# completed rows with a valid existing path are left alone (path existence checked externally)
# here we test that completed+no path DOES get updated
CSV_COMPLETED_NO_PATH = """\
entry,tmp_path,status,verified,fail_reason
Charli — Charli XCX,,completed,,
"""

with tempfile.TemporaryDirectory() as tmp:
    staging = populate_staging(tmp, [("charli xcx - charli", 10)])
    folders = scan_staging(staging, MIN_TRACKS)
    rows = list(csv.DictReader(CSV_COMPLETED_NO_PATH.splitlines()))
    changed = reconcile(rows, folders)
    r = {row['entry']: row for row in rows}
    got_path = r["Charli — Charli XCX"]["tmp_path"]
    assert_eq("charli xcx - charli" in got_path.lower(), True,
              "completed+no path gets updated with staging folder")
    assert_eq(changed, 1, "one change for completed row with missing path")

# ── tokenize ─────────────────────────────────────────────────────────────────

suite("tokenize")

assert_eq(tokenize("Charli XCX"), ["charli", "xcx"], "splits on spaces")
assert_eq(tokenize("M.I.A."),     ["mia"],            "removes dots, joins letters")
assert_eq(tokenize("AIM (2016)"), ["aim", "2016"],    "strips parens, keeps year tokens")
assert_eq(tokenize("janet."),     ["janet"],           "trailing dot stripped")
assert_eq(tokenize(""),           [],                  "empty string → no tokens")
assert_eq(tokenize("AC/DC"),      ["ac", "dc"],        "slash splits into tokens")

suite("tokens_match: false-positive regression")

# 'mia' must not match 'miami' after the tokenize fix
assert_eq(tokens_match(["mia"], "Miami Bass - Aim High"), False,
          "mia token does not match miami (different words)")
assert_eq(tokens_match(["mia", "aim"], "M.I.A. - AIM"), True,
          "mia+aim tokens correctly match M.I.A. - AIM")
assert_eq(tokens_match(["mia", "kala"], "M.I.A. - AIM"), False,
          "kala token not present in M.I.A. - AIM")
assert_eq(tokens_match([], "anything"), False,
          "empty query never matches")

# ── count_audio ───────────────────────────────────────────────────────────────

suite("count_audio")

with tempfile.TemporaryDirectory() as tmp:
    d = Path(tmp)
    for ext in ['.mp3', '.flac', '.opus', '.ogg', '.m4a']:
        (d / f"track{ext}").touch()
    (d / "cover.jpg").touch()
    (d / "info.txt").touch()
    assert_eq(count_audio(tmp), 5, "counts all audio extensions, ignores non-audio")

with tempfile.TemporaryDirectory() as tmp:
    assert_eq(count_audio(tmp), 0, "empty dir → 0")

assert_eq(count_audio("/nonexistent/path/xyz"), 0, "missing dir → 0 (no exception)")

# ── Results ───────────────────────────────────────────────────────────────────

print(f"\n  {PASS} passed, {FAIL} failed")
sys.exit(0 if FAIL == 0 else 1)
