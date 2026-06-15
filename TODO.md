# TODO — NO DOWNLOADS REFUSED

Shared work tracking for backend and UX agents. Update status inline as work progresses.

---

## In Progress

### [backend] Kill / restart / reload
Kill hanging processes, restart Flask, reload the UI.
- [x] `GET /api/processes` — list running script + sldl PIDs
- [x] `POST /api/kill` — kill all hanging processes (managed _proc + pkill scripts + sldl), clear queue
- [x] `POST /api/restart` — kill all, then `os.execv` to restart Flask; sends `{t:'restart'}` SSE event first so client knows to reconnect
- [x] SSE `generate()` handles dict items in queue — structured events (`{t:'restart'}`) pass through as-is instead of being wrapped in `{t:'log'}`

### [ux] Restart button + client-side reconnect
- [ ] "Restart" button in footer (or settings panel) — calls `POST /api/restart`
- [ ] On `{t:'restart'}` SSE event OR after the POST responds: show "restarting…" state, poll `GET /api/status` every 500ms for up to 15s
- [ ] When poll succeeds (server back up), `window.location.reload()`
- [ ] `GET /api/processes` can power a "hanging processes" indicator before the kill button



### [backend] fail_reason capture
Capture the last meaningful sldl output line on failure → `fail_reason` column in CSV.
- [x] Add `fail_reason` to `CSV_FIELDS` in `web.py`
- [x] Expose `fail_reason` in `/api/watchlist` response per item
- [x] Tee sldl output in `download.sh`, extract last non-empty line on failure
- [x] Clear `fail_reason` when setting `in_progress` (retry clears stale reason)

### [ux] fail_reason tooltip on failed items
Display `fail_reason` from API on failed queue items.
- [x] Show `fail_reason` as a tooltip or sub-line under the album name in the failed state
- [x] If `fail_reason` is empty, show nothing (don't render an empty tooltip)

---

## Queued — Small Features

### [backend] Track name linter / .incomplete guard
- [x] Define canonical folder name format: `Artist - Album` (enforced by prep.sh)
- [ ] Define canonical track name format: `NN Title.ext` — pick one and enforce (deferred: risky/complex)
- [x] In `copy.sh` / rsync: exclude `*.incomplete` files so they never land on the device
- [x] In `download.sh`: detect `.incomplete` files after sldl exits, mark `status=failed`, `fail_reason=.incomplete files remain`
- [x] In `prep.sh`: skip (don't rename) folders with `.incomplete` files

### [ux] Track name linter feedback
- [ ] Surface any `.incomplete` or format-mismatch items in the UI (probably Queue tab, failed bucket)

### [backend] Cleanup endpoint
New `/api/cleanup` (POST) that runs `cleanup.sh`:
- [x] Delete all FLAC files from staging (we prefer MP3; FLACs are dead weight on FAT32)
- [x] Move orphaned staging folders (no CSV match) to `staging/orphaned/` — not auto-deleted
- [x] Print summary line `CLEANUP DONE flacs_deleted=N orphans_moved=N` for UI to parse
- [ ] Run verify as part of cleanup (deferred — verify is already a separate button)

### [ux] Cleanup button
- [ ] Add "Cleanup" button to the footer action bar
- [ ] Show a summary modal/toast after cleanup completes (parse the SSE stream for the summary line)
- [ ] Confirm dialog before running (this is destructive)

### [backend] Sync selector — per-album device flag
Lightweight iTunes: decide which albums actually get copied to the Surfans F20.
- [x] Add `sync` column to `CSV_FIELDS` (values: `yes` / `no` / `''` defaulting to yes)
- [x] `PATCH /api/watchlist/sync` to toggle the flag per entry
- [x] `copy.sh` builds rsync exclude list from entries with `sync=no`

### [ux] Sync selector UI
- [ ] Per-album toggle in Library tab (on/off → synced/excluded)
- [ ] Visual distinction for excluded albums (greyed out, strike-through, or lock icon)
- [ ] Batch controls: "sync all" / "sync none" in Library tab header

### [backend] Device reconciliation script
Clean up the Surfans F20 to match what's currently in staging.
- [x] `GET /api/reconcile-device` — dry-run diff, returns `{to_remove: [{name, path, tracks}], count}`
- [x] `POST /api/reconcile-device` — runs `reconcile_device.sh`, removes orphaned device folders
- [x] `reconcile_device.sh` skips entries with `sync=no` and any untracked staging folders

### [ux] Device reconciliation UI
- [ ] "Reconcile device" button in Library tab (only active when device is mounted)
- [ ] Show diff preview before confirming

---

## Spikes / Research (no owner yet — needs discussion)

- **Hosting**: Find a free/ethical/non-big-tech place to host the Flask app so it's accessible remotely. Must also expose device mount status (Mac online? Surfans connected?). Options: Tailscale + home server, Fly.io free tier, self-hosted VPS.
- **HUMAN: iPhone ↔ Surfans F20**: How can the mp3 player connect to iPhone for on-the-go transfers? Research USB OTG / Lightning to USB-A adapter + FAT32 compatibility.
- **Parallel downloads**: sldl may support concurrent jobs — investigate `--concurrent-processes` or running multiple sldl instances. Needs queue coordination so CSV stays consistent.
- **DAP abstraction**: Decouple the "copy to device" step from the Surfans F20 specifically. Config-driven mount point + format constraints so any DAP can be targeted.
- **Bandcamp / SoundCloud ingestion**: Integrate a youtube-dl/yt-dlp wrapper or the existing youtubetomp3 desktop app to pull from Bandcamp and SoundCloud into the same pipeline.

---

## Future

- **Physical discography management**: Track records + CDs in the watchlist (different type column). Auto-rip when registered (connect to a ripper daemon).
- **Last.fm integration**: Push play counts from Surfans F20 (if it supports scrobbling via a log file or USB sync) to Last.fm.
- **Label maker integration**: Print physical labels for records/CDs from the discography data.
- **DJ USB organization**: Inventory and present music on the DJ USB alongside the main library. Maybe a separate Library tab source.
