# TODO — NO DOWNLOADS REFUSED

Shared work tracking for all agents. Update status inline as work progresses.

---

## Rebrand — NO DOWNLOADS REFUSED

The internal codename is `slsk-auto`. The product name is **NO DOWNLOADS REFUSED** — it's
already in the README, it's already the title of this file, it should be on the screen.

The current aesthetic (warm cream, rounded card, soft blur, score watermark) is lovely but
wrong for what this is. This app should feel like a loading dock. Brutalist. Dark. High
contrast. The kind of UI that makes you feel like you are doing something slightly illegal,
efficiently, with zero apology.

### [product] Surface the real name: slsk-auto → NO DOWNLOADS REFUSED

- [x] Update `<title>` in `templates/index.html`: `slsk-auto` → `NO DOWNLOADS REFUSED`
- [x] Update `.logo` wordmark text in topbar: `slsk-auto` → `NO DOWNLOADS REFUSED`
      (it can be small-capped, abbreviated as `NDR` in tight layouts if needed — decide in ux)
- [x] Update `CLAUDE.md` title line to lead with `NO DOWNLOADS REFUSED` — already done
- [ ] Add `<link rel="icon" href="/static/favicon.svg" type="image/svg+xml">` to `<head>`

### [ux] Brutalist dark redesign — Phase 1: Foundation

Full visual direction change. Felix executes. This is the brief.

**Color system — kill the cream:**
- [ ] `--bg: #080808` — near black, not pure black
- [ ] `--card: #101010` — one step up, barely perceptible
- [ ] `--border: #222222`
- [ ] `--text: #f0f0f0` — off-white, not blinding
- [ ] `--muted: #555555`
- [ ] `--red: #ff2020` — electric. The only accent with permission to scream.
- [ ] `--green: #00e060`, `--amber: #ffaa00` — signal colors stay, electric versions
- [ ] Footer and body are one dark register — no separate footer bg color

**Shape language — no softness:**
- [ ] `.card` `border-radius: 16px → 0`. No floating card. Full bleed.
- [ ] `.hdr-btn` `border-radius: 4px → 0`
- [ ] `.footer-btn` `border-radius: 3px → 0`
- [ ] `.alb-art` `border-radius: 3px → 0`. Album art is a rectangle. Honor it.
- [ ] Kill `box-shadow` on `.card`. Structure via color + border, not shadow.

**Typography — weight contrast:**
- [ ] `.logo`: `font-size: 11px`, `font-weight: 900`, `letter-spacing: 0.15em`,
      `text-transform: uppercase` — the full name or `NDR` if space is tight
- [ ] `.hero-title`: `font-size: 52px`, `font-weight: 900`, `letter-spacing: -0.05em`
      — when something is downloading, you feel it
- [ ] `.lib-count`: `font-weight: 900`, `font-size: 32px`
- [ ] Group separator labels: `letter-spacing: 0.22em`, `font-size: 8px` — stencil energy
- [ ] Tab labels: `letter-spacing: 0.12em`

**Texture — commit or cut:**
- [ ] Remove `.bg-score` / `score.jpg` — ghost staff-lines on black = invisible = pointless.
      If texture is wanted later, do it properly: CSS `noise` or SVG grain on `body::before`.

**Explicit structure via borders:**
- [ ] `border-top: 1px solid var(--border)` on tab row
- [ ] `border-bottom: 1px solid #1a1a1a` between `.q-item` rows
- [ ] Footer `border-top: 1px solid var(--border)` — explicit, not implied

### [ux] Brutalist dark redesign — Phase 2: Hero and Active State

The hero is where the most potential is. A download in progress should look like a concert
screen.

- [ ] Hero when **live**: `background: var(--red)` — entire hero block goes red, text
      inverts to white. Unmissable. No subtlety.
- [ ] Drop `hero-glow` keyframe animation entirely — replace with red border opacity pulse
- [ ] `hero-live-dot`: `8px × 8px` — it reads on dark, it disappears at 6px on cream
- [ ] Hero when idle: `background: transparent`, `border: 1px solid var(--border)`
- [ ] When live: `.logo` wordmark also pulses to red — full brand moment

### [ux] Brutalist dark redesign — Phase 3: Activity log

The Activity tab is a terminal. Make it look like one.

- [ ] `#log` background: `#000000` — true black. The one place for pure black.
- [ ] Log default text: `#cccccc`, `font-size: 12px`, `line-height: 1.7`
- [ ] While running: blinking `▋` cursor appended to last log line
- [ ] Idle empty state: `$` prompt style instead of italic "Run download…" copy

### [ux] Brutalist dark redesign — Phase 4: Library

- [ ] Reduce max blur `10px → 4px` — dark bg + high blur = smear artifacts
- [ ] `.alb-art-ph` placeholder: add centered `◼` glyph in `--muted` — explicit, not broken
- [ ] `.alb-artist` label: `letter-spacing: 0.15em` — it's a stencil, commit to it

### [ux] Favicon / identity mark

- [ ] Create `static/favicon.svg`: white `H` on `#080808` 16×16 square
- [ ] Wire it up in `<head>` of `index.html`

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

## Queued — UX Polish

### [ux] Hero / currently-downloading redesign
The big title in the Queue hero is just the raw entry name of the first in-progress album — not informative enough and looks awkward when there are multiple.
- [ ] Show a count badge ("3 downloading") prominently instead of or alongside the first title
- [ ] List all in-progress entries as a compact stack, not just item[0] in the giant title slot
- [ ] When only one item: show title large but also surface `tmp_path` folder or track count as a subtitle so you know it's actually progressing
- [ ] Live pulse indicator should be more prominent — currently easy to miss

### [ux] Library blur — reduce intensity + scroll behavior
- [ ] Reduce max blur from 10px to ~5–6px — current level is too heavy
- [ ] Tracklists (`.alb-tracks`) intentionally do not blur — this is correct, leave it
- [ ] Confirm the scroll-tracking focal point feels natural on real content before locking in

### [ux] UI cache — document and harden
- [x] `TEMPLATES_AUTO_RELOAD = True` added to Flask config
- [x] `Cache-Control: no-store` on the `/` route — browser never serves stale HTML

### [ux] Library — tracklist expand on album click
- [x] Click album row → fetches `/api/tracklist?folder=<path>`, renders inline below the row
- [x] Click again to collapse; only one open at a time
- [x] Track number, title, duration (mm:ss from TLEN); graceful fallback if no audio files

### [ux] Activity log persistence
- [x] On page load: reads most recent log file from `/api/logs` and populates Activity tab
- [x] On tab switch to Activity (no active stream): reloads from file
- [x] On page reload mid-download: `pollStatus` reconnects SSE stream if `running=true`

### [ux] Score image background texture
- [x] `Zn9Vr.jpg` (extended-technique score) served from `/static/score.jpg`
- [x] `position: fixed`, `mix-blend-mode: multiply`, `opacity: 0.07` — ghost staff lines on cream bg

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
- [x] Per-album toggle in Library tab (● = synced, ○ = excluded) — only shown for watchlist-tracked albums
- [x] Excluded albums: strikethrough name, reduced opacity on art + info
- [x] Batch controls: "All on" / "All off" in Library toolbar
- [x] Folder→entry join via basename(tmp_path) to handle prep.sh renames

### [backend] Device reconciliation script
Clean up the Surfans F20 to match what's currently in staging.
- [x] `GET /api/reconcile-device` — dry-run diff, returns `{to_remove: [{name, path, tracks}], count}`
- [x] `POST /api/reconcile-device` — runs `reconcile_device.sh`, removes orphaned device folders
- [x] `reconcile_device.sh` skips entries with `sync=no` and any untracked staging folders

### [ux] Device reconciliation UI
- [ ] "Reconcile device" button in Library tab (only active when device is mounted)
- [ ] Show diff preview before confirming

---

## Queued — Backend Bugs (from QA handoff)

### [backend] Wrong staging path assigned to entries — download.sh:191–204
Several watchlist entries marked `completed` but `tmp_path` points to the wrong album's folder (e.g. Kala → AIM folder).
- [x] Root cause: `--path "$STAGING"` sent new downloads to staging root, but before/after diff only scanned `staging/tmp/`. Changed to `--path "$STAGING/tmp"` so sldl output and diff scan are consistent.
- [x] Phase 0 now uses token matching (not substring) so cross-album false matches are gone.
- [x] Manually corrected 17 wrong/stuck entries directly in `watchlist.csv`.

### [backend] Loose `find_folder` matching — lib.sh:130–141
Substring matching lets short artist tokens like "mia" match unrelated folders like "miami". 
- [x] `find_folder` now normalizes both query and folder name: remove dots (M.I.A.→mia), lowercase, collapse non-alnum to spaces, then require each token (len≥2) to appear as a whole word. Phase 0 Python uses the same `tokenize()` + `tokens_match()` helpers.

### [backend] 7 entries stuck `in_progress` — reset automatically
Last run crashed mid-batch. In Rainbows, channel ORANGE, Nymph, Alias, Stretch 2, 1991 EP, Queen were stuck.
- [x] Added **Phase 0.5** to `download.sh`: after Phase 0 reconcile, resets any `in_progress` entry whose `tmp_path` has no audio to `not_started` automatically on every future run.
- [x] Manually reset all 7 stuck entries in `watchlist.csv` now.

### [backend] Reconciler lives in two places — keep in sync
The Phase 0 Python reconciler is an inline heredoc in `download.sh`. `test_reconciler.py` mirrors it manually.
- [x] `test_reconciler.py` updated to mirror `tokenize()`/`tokens_match()` — also added dedicated `tokenize` and `tokens_match` test suites including false-positive regression
- [ ] Consider extracting to a standalone `reconcile.py` so there's one source of truth

### [backend] `mb_track_count` fails when album name includes year — lib.sh
`mb_track_count "Janet Jackson" "janet. (1993)"` returned no results because MB titles never include the year disambiguation we append. Same bug hits every year-suffixed entry.
- [x] Strip `(YYYY)` from album before building the MB query (`re.sub` in the Python inline). Verified: janet. → 28 tracks, Damita Jo → 23 tracks.

### [backend] `find_folder` can't distinguish albums whose title is a subset of the artist name
`janet.` tokenises to `["janet"]`, which also appears in `"Janet Jackson"` — so any Janet Jackson folder matches regardless of album. `find_folder "Janet Jackson" "janet."` incorrectly returns the Damita Jo folder.
- [ ] Require at least one album token that is NOT already covered by the artist tokens. If no discriminating album token exists, skip `find_folder` and fall back to before/after diff only.

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
