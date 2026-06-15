# TODO — NO DOWNLOADS REFUSED

Shared work tracking for backend and UX agents. Update status inline as work progresses.

---

## In Progress

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
- [ ] Define canonical folder name format: `Artist - Album` (already enforced by prep.sh)
- [ ] Define canonical track name format: `NN Title.ext` or `Artist - Album - NN Title.ext` — pick one and enforce
- [ ] In `copy.sh` / rsync: exclude `*.incomplete` files so they never land on the device
- [ ] In `download.sh`: detect folders containing `.incomplete` files after sldl exits, mark those entries `status=failed`, `fail_reason=incomplete files present`
- [ ] In `prep.sh`: warn and skip (don't rename) folders with `.incomplete` files

### [ux] Track name linter feedback
- [ ] Surface any `.incomplete` or format-mismatch items in the UI (probably Queue tab, failed bucket)

### [backend] Cleanup endpoint
New `/api/cleanup` (POST) that runs a cleanup script:
- [ ] Delete all FLAC files from staging (we prefer MP3; FLACs are dead weight on FAT32)
- [ ] Run verify logic (same as `verify.sh`) as part of cleanup
- [ ] Prune staging folders with no match in `watchlist.csv` (orphaned downloads)
- [ ] Return a summary: `{flacs_deleted, folders_pruned, verified, mismatched}`

### [ux] Cleanup button
- [ ] Add "Cleanup" button to the footer action bar
- [ ] Show a summary modal/toast after cleanup completes (parse the SSE stream for the summary line)
- [ ] Confirm dialog before running (this is destructive)

### [backend] Sync selector — per-album device flag
Lightweight iTunes: decide which albums actually get copied to the Surfans F20.
- [ ] Add `sync` column to `CSV_FIELDS` (values: `yes` / `no` / `''` defaulting to yes)
- [ ] New `/api/watchlist/<entry>/sync` (PATCH) to toggle the flag
- [ ] Update `copy.sh` to only rsync folders whose CSV entry has `sync != 'no'`

### [ux] Sync selector UI
- [ ] Per-album toggle in Library tab (on/off → synced/excluded)
- [ ] Visual distinction for excluded albums (greyed out, strike-through, or lock icon)
- [ ] Batch controls: "sync all" / "sync none" in Library tab header

### [backend] Device reconciliation script
Clean up the Surfans F20 to match what's currently in staging.
- [ ] Script (or `/api/reconcile-device`) that diffs device contents against staging
- [ ] Remove albums from device that are no longer in staging or are marked `sync=no`
- [ ] Dry-run mode first, confirm before delete

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
