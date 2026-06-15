# NO DOWNLOADS REFUSED (slsk-auto)

A sleazy little app to manage a music library and source albums from Soulseek. Because unlike that ad says — I would download a car.

Automates the full pipeline: watchlist → download via sldl → rename from ID3 tags → copy to Surfans F20 DAP.

Work items and roadmap live in `TODO.md`.

## Pipeline

```
iPhone (Files app)
  → iCloud Drive: slsk-watchlist.txt
    → symlink: ~/src/slsk-auto/watchlist.txt
      → sync.sh
        → sldl (download to ~/Music/slsk-staging/)
          → prep.sh (rename folders via ID3 tags, strip .lrc files)
            → rsync to /Volumes/surfans F20
              → completed entries marked "# done: " in watchlist
```

## Setup (run once on your Mac)

```bash
# install sldl binary
curl -L https://github.com/fiso64/slsk-batchdl/releases/latest/download/sldl-osx-x64 \
  -o /usr/local/bin/sldl
chmod +x /usr/local/bin/sldl

# create config from template
cp config.toml.example config.toml
# edit config.toml and fill in username/password

# symlink iCloud watchlist into repo
ln -s ~/Library/Mobile\ Documents/com~apple~CloudDocs/slsk-watchlist.txt watchlist.txt
```

## Watchlist format

One album per line: `Artist - Album`

```
Björk - Vespertine
Robyn - Body Talk
Charli XCX - BRAT
```

Edit from iPhone via Files app → iCloud Drive → slsk-watchlist.txt.
Completed entries are prefixed with `# done: ` automatically by sync.sh.

## Running

```bash
./sync.sh
```

No scheduling is wired up. Run manually whenever you add albums.

## Surfans F20 (FAT32 constraints)

- Mount point: `/Volumes/surfans F20`
- Folder naming convention: `Artist - Album` (e.g. `Aphex Twin - Syro`)
- FAT32 illegal chars stripped by prep.sh: `\ : * ? " < > |`
- Apostrophes are fine on FAT32

## ID3 tag parsing (prep.sh)

Uses Python's `struct` module — no third-party packages needed. Reads ID3v2 frames directly
from the first MP3 in each folder. Prefers `TPE2` (album artist) over `TPE1` (track artist)
to avoid "feat." variants polluting the folder name. Falls back gracefully if no tags found
(prints SKIP and leaves folder as-is).

Relevant frame IDs:
- `TPE2` — album artist (preferred)
- `TPE1` — track artist (fallback)
- `TALB` — album title

## sldl flags

| Flag | Value | Purpose |
|---|---|---|
| `--type` | `album` | Search for full albums, not individual tracks |
| `--pref-format` | `mp3` | Prefer MP3 over FLAC |
| `--pref-bitrate` | `320` | Prefer 320 kbps |
| `--min-bitrate` | `128` | Reject obviously low-quality rips |

## Files

| File | Purpose |
|---|---|
| `web.py` | Flask backend (port 5001) — API + SSE stream |
| `sync.sh` | Full pipeline: download → prep → copy |
| `download.sh` | Download pending/failed, verify track counts |
| `verify.sh` | Standalone verify against MusicBrainz |
| `copy.sh` | prep.sh → rsync to device |
| `prep.sh` | Rename folders from ID3 tags, strip .lrc files |
| `lib.sh` | Shared bash helpers (config, CSV, MusicBrainz, audio count) |
| `watchlist.csv` | Album queue: entry, tmp_path, status, verified, fail_reason |
| `config.toml` | Credentials + paths (gitignored) |
| `config.toml.example` | Template to copy |
| `templates/index.html` | Frontend SPA |
| `artwork/` | Cached cover art (keyed by sanitized folder name) |
| `logs/` | Per-run logs from all scripts |
