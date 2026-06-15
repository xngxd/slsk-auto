# NO DOWNLOADS REFUSED

A sleazy little app to manage a music library and source albums from Soulseek.
Because unlike that ad says — I would download a car.

---

## What it does

Maintains a watchlist of albums, downloads them from Soulseek via `sldl`, verifies track counts against MusicBrainz, renames folders from ID3 tags, and syncs to a Surfans F20 DAP (FAT32).

A Flask web UI at `localhost:5001` exposes the whole pipeline with live log streaming.

```
watchlist.csv → download.sh → staging/ → prep.sh → copy.sh → /Volumes/surfans F20
```

## Setup

```bash
# install sldl
curl -L https://github.com/fiso64/slsk-batchdl/releases/latest/download/sldl-osx-x64 \
  -o /usr/local/bin/sldl && chmod +x /usr/local/bin/sldl

# configure credentials
cp config.toml.example config.toml
# fill in username + password

# start the web UI
python3 web.py
```

Open `http://localhost:5001`.

## Watchlist format

`watchlist.csv` is managed by the UI, but you can also edit it directly.
Each entry follows the convention `Album - Artist` or `Album — Artist`.

```
Charli — Charli XCX
Heaven or Las Vegas - Cocteau Twins
In Rainbows (2007) — Radiohead
```

## Pipeline scripts

| Script | What it does |
|---|---|
| `sync.sh` | Full run: download → prep → copy |
| `download.sh` | Reconcile staging, verify unverified, download pending/failed |
| `verify.sh` | Standalone verify against MusicBrainz |
| `copy.sh` | Rename via ID3 tags, rsync to device |
| `prep.sh` | Rename folders from ID3 tags, strip `.lrc` files, sanitize for FAT32 |

## API

```
GET  /api/status          running state, device mount, in-progress count
GET  /api/watchlist       albums grouped by status (includes fail_reason)
POST /api/watchlist       add album
POST /api/watchlist/delete remove album
GET  /api/library         albums on device (or staging if unmounted)
GET  /api/artwork         cover art — embedded ID3 → Cover Art Archive, cached
GET  /api/tracklist       track listing from ID3 tags (path-guarded)
POST /api/download        start download.sh
POST /api/sync            start sync.sh
POST /api/copy            start copy.sh
POST /api/verify          start verify.sh
POST /api/stop            kill running script
GET  /stream              SSE stream of live script output
GET  /api/logs            recent log files
```

## Config

```toml
[soulseek]
username = ""
password = ""

[paths]
staging = "~/Music/slsk-staging"
device  = "/Volumes/surfans F20"
```

## Notes

- All ID3 parsing is pure Python (`struct`) — no third-party dependencies
- `sldl` is called with `--interactive false` to avoid crashes in non-TTY contexts
- Artwork is cached in `artwork/` keyed by sanitized folder name
- Logs land in `logs/` with timestamps; the UI streams them live
- `config.toml` is gitignored — never commit credentials
