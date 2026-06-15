# TODO — NO DOWNLOADS REFUSED

Shared work tracking for all agents. Update status inline as work progresses.

---

## Rebrand — NO DOWNLOADS REFUSED

The internal codename is `slsk-auto`. The product name is **NO DOWNLOADS REFUSED** — it's
already in the README, it's already the title of this file, it should be on the screen.

Direction: **light emo techno-brutalist.** Reference: brutalistwebsites.com.
White/near-white ground. Electric blue as the single weapon. Massive black type. Hard edges.
Raw structure. No softness, no rounding, no shadow — but not dark mode. The emotion lives
in the typography and the one accent color, not in darkness.

The current cream (#e8e4da) is close but too warm and too editorial. The card, the rounded
corners, the box-shadow — all of that has to go. The score watermark stays if it reads on
light, gets cut if it doesn't.

### [product] Surface the real name: slsk-auto → NO DOWNLOADS REFUSED

- [x] Update `<title>` in `templates/index.html`: `slsk-auto` → `NO DOWNLOADS REFUSED`
- [x] Update `.logo` wordmark text in topbar: `slsk-auto` → `NO DOWNLOADS REFUSED`
      (abbreviated as `NDR` in tight layouts — decide in ux execution)
- [x] Update `CLAUDE.md` title line to lead with `NO DOWNLOADS REFUSED` — already done
- [ ] Add `<link rel="icon" href="/static/favicon.svg" type="image/svg+xml">` to `<head>`

### [ux] Light emo techno-brutalist redesign — Phase 1: Foundation

Full visual direction change. Felix executes. This is the brief.

**Color system — cool the ground, add one electric:**
- [ ] `--bg: #f2f2f2` — neutral light grey, cooler than the current warm cream
- [ ] `--card: #f2f2f2` — card and bg are the same. No floating card. One surface.
- [ ] `--border: #000000` — black borders. Hard lines, full contrast.
- [ ] `--text: #0a0a0a` — near black
- [ ] `--muted: #888888`
- [ ] `--blue: #0000ff` — raw electric blue. This is the accent. The only color.
      Current `--blue: #1c3d8a` is a navy, a corporate color. Kill it. Go full signal.
- [ ] `--green`, `--amber`, `--red` stay for status signals but are subordinate to blue
- [ ] Footer: `background: #0a0a0a`, `color: #f2f2f2` — the one dark surface, inverted,
      acts as a base plate. Contrast against the light body above.

**Shape language — zero softness:**
- [ ] `.card` `border-radius: 16px → 0`. The card disappears — bg and card are the same color.
- [ ] `.hdr-btn` `border-radius: 4px → 0`. Rectangular buttons with hard black borders.
- [ ] `.footer-btn` `border-radius: 3px → 0`
- [ ] `.alb-art` `border-radius: 3px → 0`. Rectangles.
- [ ] Kill `box-shadow` on `.card`. Structure is black lines, not shadows.
- [ ] Add `border: 1px solid var(--border)` to buttons — the outline IS the button.

**Typography — this is where the brutalism lives:**
- [ ] `.logo` / wordmark: `font-weight: 900`, `font-size: 11px`, `letter-spacing: 0.12em`,
      `text-transform: uppercase` — `NO DOWNLOADS REFUSED` or `NDR` if it won't fit one line
- [ ] `.hero-title`: `font-size: 52px`, `font-weight: 900`, `letter-spacing: -0.04em`,
      `line-height: 0.95` — this is the moment. When something's downloading it's all caps
      huge black type. Think concert poster.
- [ ] `.lib-count`: `font-weight: 900`, `font-size: 36px`, `letter-spacing: -0.04em`
- [ ] Group separator labels: `font-size: 8px`, `font-weight: 700`, `letter-spacing: 0.25em`
      — pure stencil. They label sections like a manifest.
- [ ] Tab labels: `font-weight: 700`, `letter-spacing: 0.1em`
- [ ] Active tab indicator: `border-bottom: 2px solid var(--blue)` — the only blue on the tab bar

**Texture — reassess on light:**
- [ ] The score watermark (`bg-score`) was designed for cream with `mix-blend-mode: multiply`.
      Test it on `#f2f2f2` — if it still reads, keep it at `opacity: 0.05`. If not, cut it.

**Explicit structure via black borders:**
- [ ] `border-top: 1px solid var(--border)` on the tab row — divide the topbar from the tabs
- [ ] `border-bottom: 1px solid #e0e0e0` between `.q-item` rows (light separator, not full black)
- [ ] `border-top: 1px solid #333` on footer — explicit transition to dark base plate

### [ux] Light emo techno-brutalist — Phase 2: Hero and Active State

The hero is where the brutalism needs to land hardest.

- [ ] Hero when **live**: `background: var(--blue)` — entire hero block goes electric blue,
      text goes white. `color: #fff`. No subtlety. This is the concert screen moment.
- [ ] Drop `hero-glow` keyframe entirely.
- [ ] Replace with: when live, a `2px solid var(--blue)` border around the hero block.
      Blue fill + blue border = the thing that's running owns the screen.
- [ ] `hero-live-dot`: `8px × 8px`, `background: #fff` when inside the blue hero
- [ ] Hero label "Now downloading": `font-weight: 900`, `font-size: 9px`, `letter-spacing: 0.2em`
- [ ] Hero idle state: `background: transparent`, `border: 1px solid var(--border)` — quiet grid line
- [ ] When live: `.logo` wordmark color also snaps to `var(--blue)` — the whole topbar knows

### [ux] Light emo techno-brutalist — Phase 3: Activity log

The log doesn't need to be a dark terminal anymore. It can be a light-on-light manifest.

- [ ] `#log` background: `#e8e8e8` — slightly darker than body, defines the zone
- [ ] Log text: `#0a0a0a`, `font-size: 11.5px`, `line-height: 1.8`
- [ ] Add a left `border-left: 3px solid var(--blue)` to the log container — editorial margin
- [ ] Classified lines: `ok` → blue, `err` → red, `warn` → amber, `done` → blue bold
- [ ] While running: blinking `▋` cursor appended to last log line, color `var(--blue)`
- [ ] Idle empty state: `$` prompt style in `--muted` instead of italic copy

### [ux] Light emo techno-brutalist — Phase 4: Library

- [ ] Library blur: reduce max `10px → 5px`. On light this smears less but still needs tuning.
- [ ] `.alb-art-ph` placeholder: solid `var(--border)` rectangle + centered `◼` in `#888`
- [ ] `.alb-artist` label: `letter-spacing: 0.15em` — stencil caps, all the way
- [ ] Hover on album row: `background: var(--blue)`, text inverts to white. Aggressive. Fast.
      Not a gentle bg tint — full blue takeover on hover. `transition: 0.08s`.

### [ux] Favicon / identity mark

- [x] Create `static/favicon.svg`: black square, white `N` glyph
- [x] Wire it up in `<head>` of `index.html`

---

## In Progress

### [backend] In Rainbows — bad partial download marked verified

`In Rainbows (2007) — Radiohead` was `completed/verified` in the CSV but was a corrupt
2-track partial download with a .NET crash trace in `fail_reason`. CSV has been reset to
`not_started`. Bad staging folder still needs manual deletion:
```
rm -rf ~/Music/slsk-staging/tmp/"In Rainbows (2007) [mp3]"
```
- [x] Reset CSV to `not_started`, cleared `tmp_path` and `fail_reason`
- [ ] Delete bad staging folder (manual — see above)
- [ ] Re-download will happen on next run

### [backend] Reconciler must not verify entries with non-empty fail_reason

When the reconciler recovers a crashed entry and promotes it to `completed`, it should check
whether `fail_reason` is set. A non-empty `fail_reason` means the download did not succeed
cleanly — it must not be marked `verified` regardless of whether a folder was found.

- [ ] In `download.sh` Phase 0 reconciler: after setting `status=completed`, if `fail_reason`
      is non-empty, set `verified=unverified` (not `verified`) and log a warning
- [ ] Add a test case: entry with fail_reason + matching folder → should land as
      `completed/unverified`, not `completed/verified`

### [backend] prep.sh — strip format bracket tags from folder names

sldl frequently appends `[mp3]`, `[FLAC]`, `[320]`, `[V0]` etc. to downloaded folder names.
These pollute the library and break the `Artist - Album` naming convention.

- [ ] In `prep.sh`, after reading the folder name and before renaming: strip any trailing
      `[...]` bracket group that matches a known format token (mp3, flac, 320, 256, 128,
      V0, V2, CBR, etc.) — case-insensitive
- [ ] Add test cases to `test_prep.sh` covering `[mp3]`, `[FLAC 320]`, `[V0]` variants
- [ ] Confirm that legitimate brackets in real album names (e.g. `(2007) [Remaster]`) are
      not stripped — only format-codec tokens should be targeted

### [backend] verify.sh — silent pass when MusicBrainz lookup fails

In Rainbows passed verify with only 2 tracks against a known 10-track album. The MusicBrainz
lookup either returned 0 or failed silently and the track count check defaulted to pass.

- [ ] In `verify.sh` / `lib.sh`: if the MusicBrainz API returns 0 tracks or an error,
      log a warning and mark the entry `unverified` — do NOT count it as a pass
- [ ] `track_variance()` tolerance check: 2 vs 10 is well outside `max(2, n/5)` — confirm
      this is actually being evaluated and not short-circuiting on a bad API response

### [backend] "Folder not found — skipping" for completed entries

Several albums marked `completed` in the CSV are being skipped during the Phase 0 reconciler
with "Folder not found — skipping". Observed for:

- Floor Filler II — Fierce Ruling Diva
- Yr Body is Nothing (2015) — Boy Harsher
- Lesser Man EP — Boy Harsher
- channel ORANGE — Frank Ocean

These show as DOWNLOADED in the UI, so the CSV status is `completed`, but `find_folder`
can't locate their staging folders. Likely causes:

1. The folders were moved, renamed, or deleted from staging since they were downloaded
2. `tmp_path` in the CSV is stale/wrong and `find_folder` fallback is also failing
3. Folder name on disk doesn't tokenize-match to the entry string (e.g. "channel ORANGE"
   vs "Frank Ocean - channel ORANGE" or similar casing/punctuation mismatch)

- [x] Investigated all four. Root causes vary:
      - **Floor Filler II**, **channel ORANGE**: not in staging under any name. Folders
        genuinely gone (deleted or never succeeded). Reset to `not_started`.
      - **Yr Body is Nothing**: not in staging under any variant. Reset to `not_started`.
      - **Lesser Man EP**: stale `tmp_path` (old folder deleted). Actual download landed as
        `Boy Harsher - Lesser Man (extended version)` (9 tracks). `find_folder` correctly
        rejected the match — "ep" is not a token in "extended version". Fixed `tmp_path` in
        CSV to point to the extended version folder; set `verified=unverified` so verify.sh
        will pick it up. Not a `find_folder` bug — the release on disk is a different edition.
- [x] CSV patched directly. Floor Filler II / Yr Body is Nothing / channel ORANGE queued
      for re-download. Lesser Man EP wired to the correct staging path.

### [backend] sldl crash — Console.KeyAvailable in non-TTY context

sldl throws an unhandled exception mid-download when it tries to check for a keypress in a
context where stdin is not a real TTY (i.e. when called from download.sh via Flask):

```
System.InvalidOperationException: Cannot see if a key has been pressed when either
application does not have a console or when console input has been redirected from a file.
  at DownloaderApplication.DownloadAlbum(...) :line 820
  at DownloaderApplication.MainLoop() :line 510
```

`--interactive false` is already set in `download.sh` but this crash is still occurring,
which means that flag doesn't cover every Console.KeyAvailable call in sldl.

- [x] Version is 2.6.0.0. Crash confirmed in logs — happens after EVERY successful download
      (sldl polls for a "continue?" keypress after finishing, not mid-download). Crash recovery
      in download.sh catches it, marking albums `unverified`. Net effect: all Flask-triggered
      downloads bypass inline verify and land in the unverified queue.
- [x] `--interactive false` IS passed in `sldl_args` with no dropped code path. That flag
      disables interactive *folder selection* but does NOT suppress the post-download keypress
      poll in `MainLoop` — two separate call sites in sldl.
- [x] No `--no-modify-shares` or stdin workaround exists in sldl 2.6.0.0.
- [x] **Fixed in `download.sh`**: added `--no-browse-folder` to `sldl_args`. This disables
      `RetrieveFullFolderCancellableAsync`, the specific call site that invokes
      `Console.KeyAvailable`. Confirmed in live run: sldl now exits 0, `Done — marked
      unverified/verified` appears instead of `sldl crashed but files recovered`.
      PTY stdin approach (tried first) did not work — the crash originates inside a bash
      pipeline subshell, which doesn't propagate PTY characteristics to .NET's console
      detection. `--no-browse-folder` is the correct targeted fix.

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

### [backend] Import device albums into watchlist — import_device.sh
Albums on the Surfans F20 before this project started are invisible to the app (not in watchlist.csv).
- [x] `import_device.sh` — scans device mount, adds untracked folders as `status=verified, verified=verified, sync=yes`
- [ ] **TEST**: plug in Surfans, run `./import_device.sh`, confirm pre-existing albums appear in Queue tab as verified
- [ ] After import, check for any `entry` values that don't match `Artist - Album` format (e.g. bare album names, various-artists folders) and clean up manually

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

### [ux] Eject device button
- [x] `POST /api/eject` — runs `diskutil eject` on device mount point, returns 404 if not mounted
- [x] ⏏ button next to device label in topbar — hidden when no device, dims during eject, hides on success, shows error alert on failure

### [ux] Library storage display
- [x] `/api/status` now returns `device_free_gb` + `device_total_gb` via `shutil.disk_usage`
- [x] Library toolbar shows "X.X GB free of Y.Y GB" next to the source tag

### [ux] Topbar UX polish
- [x] Logo scroll-collapse: `.topbar-identity` fades + collapses to zero height when any panel scrolls past 20px; restores on scroll back
- [x] Device label wording: "laptop connected to \<device name\>" when mounted, "no device" otherwise
- [x] Removed topbar DL/Copy/Stop buttons (footer-only now)
- [x] Activity log: `touch-action: pan-y; overflow-x: hidden; word-break: break-all` — no horizontal scroll on mobile

### [ux] Tracklist double-render fix
- [x] Per-row `_loading` flag prevents concurrent fetches on rapid taps
- [x] Post-await guard (`expandedAlbumRow !== row`) discards stale responses
- [x] Stale panel cleanup before insertion covers any remaining edge cases

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
- [ ] Consider extracting to a standalone `reconcile.py` so there's one source of truth (low priority — heredoc + test coverage is working fine)

### [backend] `mb_track_count` fails when album name includes year — lib.sh
`mb_track_count "Janet Jackson" "janet. (1993)"` returned no results because MB titles never include the year disambiguation we append. Same bug hits every year-suffixed entry.
- [x] Strip `(YYYY)` from album before building the MB query (`re.sub` in the Python inline). Verified: janet. → 28 tracks, Damita Jo → 23 tracks.

### [backend] `verify_tracks` rejects deluxe editions — lib.sh
Symmetric variance check failed BUBBA (17 tracks) vs expected 13 — got queued for re-download.
- [x] `verify_tracks` now only fails if `actual < expected - variance`. More tracks (deluxe editions) always accepted.

### [backend] Nested/variant subdirs not flattened before verify — prep.sh
Renaissance has `clean/` and `m4a/` subdirs (variants). In Rainbows has `CD1/`+`CD2/` (disc split, no root tracks). prep.sh skipped these because `read_id3` only looks at root-level MP3s.
- [x] `prep.sh` runs a Python flatten pass before the ID3 rename loop: CD/disc subdirs with no root audio → merged to root; variant subdirs when root has audio → deleted.

### [backend] Verify skips MB-not-found albums instead of accepting them — verify.sh
Many albums (especially non-English or obscure) don't appear in MusicBrainz. `verify.sh` was leaving them as `unverified` indefinitely.
- [x] `verify.sh` now accepts MB-not-found albums with ≥5 tracks as `verified`. Also runs `prep.sh` on staging at start so folder renames happen before lookup.

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
