#!/usr/bin/env python3
import csv, json, os, queue, re, struct, subprocess, sys, threading, time, urllib.parse, urllib.request
from datetime import datetime
from pathlib import Path
from flask import Flask, Response, jsonify, render_template, request, stream_with_context

SCRIPT_DIR = Path(__file__).parent
CONFIG_PATH = SCRIPT_DIR / "config.toml"
WATCHLIST_PATH = SCRIPT_DIR / "watchlist.csv"
LOGS_DIR = SCRIPT_DIR / "logs"
ARTWORK_DIR = SCRIPT_DIR / "artwork"
AUDIO_EXTS = {'.mp3', '.flac', '.opus', '.ogg', '.m4a'}
CSV_FIELDS = ['entry', 'tmp_path', 'status', 'verified', 'fail_reason', 'sync', 'attempts', 'tried_users']
LOGS_DIR.mkdir(exist_ok=True)
ARTWORK_DIR.mkdir(exist_ok=True)

app = Flask(__name__)
app.config['TEMPLATES_AUTO_RELOAD'] = True
_proc = None
_proc_name = None
_output_queue: queue.Queue = queue.Queue()
_proc_lock = threading.Lock()


# ── Config ────────────────────────────────────────────────────────────────────

def load_config():
    cfg = {}
    if not CONFIG_PATH.exists():
        return cfg
    section = None
    for raw in CONFIG_PATH.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('[') and line.endswith(']'):
            section = line[1:-1]; cfg.setdefault(section, {})
        elif '=' in line and section is not None:
            k, _, v = line.partition('=')
            cfg[section][k.strip()] = v.strip().strip('"')
    return cfg

def get_paths():
    p = load_config().get("paths", {})
    staging = Path(p.get("staging", "~/Music/slsk-staging")).expanduser()
    device  = Path(p.get("device",  "/Volumes/surfans F20"))
    return staging, device


# ── CSV helpers ───────────────────────────────────────────────────────────────

def read_csv():
    if not WATCHLIST_PATH.exists():
        return []
    with open(WATCHLIST_PATH, newline='') as f:
        return list(csv.DictReader(f))

def write_csv(rows):
    tmp = str(WATCHLIST_PATH) + '.tmp'
    with open(tmp, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS, extrasaction='ignore')
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, WATCHLIST_PATH)

def add_entry(entry):
    rows = read_csv()
    if any(r['entry'] == entry for r in rows):
        return False  # already exists
    rows.append({'entry': entry, 'tmp_path': '', 'status': 'not_started', 'verified': ''})
    write_csv(rows)
    return True

def delete_entry(entry):
    rows = [r for r in read_csv() if r['entry'] != entry]
    write_csv(rows)

def count_audio(folder):
    try:
        return sum(1 for f in Path(folder).iterdir()
                   if f.suffix.lower() in AUDIO_EXTS)
    except (PermissionError, FileNotFoundError):
        return 0

def folder_state(folder_path):
    """Returns 'in_progress', 'completed', or None."""
    p = Path(folder_path)
    if not p.is_dir():
        return None
    try:
        files = list(p.iterdir())
    except PermissionError:
        return None
    if any(f.suffix == '.incomplete' for f in files):
        return 'in_progress'
    if any(f.suffix.lower() in AUDIO_EXTS for f in files):
        return 'completed'
    return None

def reconcile_rows(rows, staging):
    """Refresh in_progress/completed status from the filesystem state of tmp_path.
    Fuzzy folder discovery is download.sh's job; this only updates rows that
    already have a tmp_path pointing to a real directory."""
    updated = []
    for row in rows:
        if row['status'] in ('completed', 'verified'):
            updated.append(row)
            continue
        tp = row.get('tmp_path', '')
        if tp and Path(tp).is_dir():
            state = folder_state(tp)
            if state and row['status'] in ('not_started', 'in_progress', 'failed', ''):
                row = dict(row)
                row['status'] = state
        updated.append(row)
    return updated


# ── Artwork ───────────────────────────────────────────────────────────────────

def _extract_apic(mp3_path):
    """Return (mime, bytes) of cover art from an ID3v2 APIC frame, or None."""
    try:
        with open(mp3_path, 'rb') as f:
            hdr = f.read(10)
            if hdr[:3] != b'ID3':
                return None
            tag_size = (hdr[6]<<21)|(hdr[7]<<14)|(hdr[8]<<7)|hdr[9]
            body = f.read(tag_size)
        i = 0
        while i + 10 <= len(body):
            fid = body[i:i+4]
            if fid == b'\x00\x00\x00\x00':
                break
            fsz = struct.unpack('>I', body[i+4:i+8])[0]
            if fsz <= 0 or fsz > len(body):
                break
            fdata = body[i+10:i+10+fsz]
            if fid == b'APIC' and fdata:
                enc = fdata[0]
                nul = fdata.find(b'\x00', 1)
                if nul < 0:
                    i += 10 + fsz; continue
                mime = fdata[1:nul].decode('latin-1') or 'image/jpeg'
                j = nul + 2  # skip pic_type byte
                if enc in (1, 2):  # UTF-16: find double-null
                    while j + 1 < len(fdata) and not (fdata[j] == 0 and fdata[j+1] == 0):
                        j += 2
                    j += 2
                else:
                    nul2 = fdata.find(b'\x00', j)
                    j = (nul2 + 1) if nul2 >= 0 else len(fdata)
                if j < len(fdata):
                    return mime, fdata[j:]
            i += 10 + fsz
    except Exception:
        pass
    return None

def _fetch_caa(artist, album):
    """Return (mime, bytes) from MusicBrainz Cover Art Archive, or None."""
    MB_UA = 'slsk-auto/1.0 (github.com/xngxd/slsk-auto)'
    try:
        url = 'https://musicbrainz.org/ws/2/release/?' + urllib.parse.urlencode(
            {'query': f'artist:"{artist}" AND release:"{album}"', 'fmt': 'json', 'limit': '1'})
        with urllib.request.urlopen(
                urllib.request.Request(url, headers={'User-Agent': MB_UA}), timeout=10) as r:
            data = json.load(r)
        releases = data.get('releases', [])
        if not releases:
            return None
        mbid = releases[0].get('id', '')
        if not mbid:
            return None
        caa_url = f'https://coverartarchive.org/release/{mbid}/front-250'
        with urllib.request.urlopen(
                urllib.request.Request(caa_url, headers={'User-Agent': MB_UA}), timeout=10) as r:
            mime = r.headers.get('Content-Type', 'image/jpeg').split(';')[0]
            return mime, r.read()
    except Exception:
        pass
    return None

def _art_cache_key(folder, artist, album):
    raw = folder or f"{artist}__{album}"
    return re.sub(r'[^\w-]', '_', Path(raw).name if folder else raw)[:80]

def get_artwork(folder='', artist='', album=''):
    """Return (mime, bytes) for album art via cache → embedded ID3 → Cover Art Archive."""
    key = _art_cache_key(folder, artist, album)
    for ext in ('jpg', 'jpeg', 'png', 'webp'):
        cached = ARTWORK_DIR / f"{key}.{ext}"
        if cached.exists():
            return f'image/{ext}', cached.read_bytes()

    result = None
    # Try embedded art from any MP3 in the folder
    if folder:
        p = Path(folder)
        for mp3 in sorted(p.glob('*.mp3')):
            result = _extract_apic(mp3)
            if result:
                break

    # Fall back to Cover Art Archive
    if not result and artist and album:
        result = _fetch_caa(artist, album)

    if result:
        mime, data = result
        ext = 'jpg' if 'jpeg' in mime else mime.split('/')[-1]
        try:
            (ARTWORK_DIR / f"{key}.{ext}").write_bytes(data)
        except Exception:
            pass
        return mime, data

    return None


# ── Tracklist ─────────────────────────────────────────────────────────────────

def _read_id3_text(path, want):
    """Read ID3v2 text frames listed in `want` set. Returns {frame_id: str}."""
    out = {}
    try:
        with open(path, 'rb') as f:
            hdr = f.read(10)
            if hdr[:3] != b'ID3':
                return out
            tag_size = (hdr[6]<<21)|(hdr[7]<<14)|(hdr[8]<<7)|hdr[9]
            body = f.read(tag_size)
        i = 0
        while i + 10 <= len(body):
            fid = body[i:i+4]
            if fid == b'\x00\x00\x00\x00':
                break
            fsz = struct.unpack('>I', body[i+4:i+8])[0]
            if fsz <= 0 or fsz > len(body):
                break
            fid_s = fid.decode('latin-1', errors='replace')
            if fid_s in want and fid_s not in out:
                enc = body[i+10]
                raw = body[i+11:i+10+fsz]
                if   enc == 0: text = raw.decode('latin-1',   errors='replace')
                elif enc == 1: text = raw.decode('utf-16',    errors='replace')
                elif enc == 2: text = raw.decode('utf-16-be', errors='replace')
                else:          text = raw.decode('utf-8',     errors='replace')
                out[fid_s] = text.rstrip('\x00').strip()
                if out.keys() >= want:
                    break
            i += 10 + fsz
    except Exception:
        pass
    return out

def _track_sort_key(trck):
    """'3/12' or '03' → 3 for sorting."""
    try:
        return int(trck.split('/')[0])
    except (ValueError, AttributeError):
        return 0

def get_tracklist(folder):
    tracks = []
    p = Path(folder)
    for f in sorted(p.iterdir()):
        if f.suffix.lower() not in AUDIO_EXTS:
            continue
        frames = _read_id3_text(f, {'TIT2', 'TRCK', 'TLEN', 'TPE1'})
        tracks.append({
            'filename': f.name,
            'title':    frames.get('TIT2') or f.stem,
            'track':    frames.get('TRCK', ''),
            'artist':   frames.get('TPE1', ''),
            'duration_ms': int(frames['TLEN']) if frames.get('TLEN','').isdigit() else None,
        })
    tracks.sort(key=lambda t: _track_sort_key(t['track']))
    return tracks


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    resp = app.make_response(render_template("index.html"))
    resp.headers['Cache-Control'] = 'no-store'
    return resp


def _is_running():
    return _proc is not None and _proc.poll() is None

def _external_script():
    for pat in _SCRIPT_PATTERNS:
        if not pat.endswith('.sh'):
            continue
        try:
            subprocess.check_output(["pgrep", "-f", pat], text=True)
            return pat.replace(".sh", "")
        except subprocess.CalledProcessError:
            pass
    return None

@app.route("/api/status")
def api_status():
    import shutil
    _, dev = get_paths()
    running = _is_running()
    script = _proc_name if running else _external_script()
    rows = read_csv()
    mounted = dev.is_dir()
    device_free = device_total = None
    if mounted:
        try:
            usage = shutil.disk_usage(dev)
            device_free  = round(usage.free  / 1e9, 1)
            device_total = round(usage.total / 1e9, 1)
        except Exception:
            pass
    return jsonify({
        "running": bool(running or script),
        "running_script": script,
        "device_mounted": mounted,
        "device_name": dev.name,
        "device_free_gb": device_free,
        "device_total_gb": device_total,
        "in_progress_count": sum(1 for r in rows if r['status'] == 'in_progress'),
    })


@app.route("/api/watchlist")
def api_watchlist_get():
    staging, device = get_paths()
    dev_mounted = device.is_dir()
    rows = reconcile_rows(read_csv(), staging)
    result = {'not_started': [], 'in_progress': [], 'completed': [],
              'failed': [], 'verified': []}
    for r in rows:
        status = r['status']
        verified = r['verified']
        tp = r['tmp_path']
        folder_name = Path(tp).name if tp else ''
        on_device = dev_mounted and bool(folder_name) and (device / folder_name).is_dir()
        item = {
            'entry': r['entry'],
            'tmp_path': tp,
            'status': status,
            'verified': verified,
            'tracks': count_audio(tp) if tp else 0,
            'fail_reason': r.get('fail_reason', ''),
            'sync': r.get('sync', ''),
            'attempts': int(r.get('attempts', 0) or 0),
            'tried_users': r.get('tried_users', ''),
            'on_device': on_device,
        }
        if status == 'completed' and verified == 'verified':
            result['verified'].append(item)
        elif status == 'in_progress':
            result['in_progress'].append(item)
        elif status == 'failed' or (status == 'completed' and verified == 'mismatch'):
            result['failed'].append(item)
        elif status == 'completed':
            result['completed'].append(item)  # downloaded, unverified
        else:
            result['not_started'].append(item)
    return jsonify(result)


@app.route("/api/watchlist", methods=["POST"])
def api_watchlist_add():
    entry = (request.json or {}).get("entry", "").strip()
    if not entry:
        return jsonify({"error": "empty"}), 400
    added = add_entry(entry)
    return jsonify({"ok": True, "duplicate": not added})


@app.route("/api/watchlist/delete", methods=["POST"])
def api_watchlist_delete():
    entry = (request.json or {}).get("entry", "").strip()
    if not entry:
        return jsonify({"error": "missing entry"}), 400
    delete_entry(entry)
    return jsonify({"ok": True})


@app.route("/api/watchlist/sync", methods=["PATCH"])
def api_watchlist_sync():
    body = request.json or {}
    entry = body.get("entry", "").strip()
    sync  = body.get("sync", "").strip()
    if not entry:
        return jsonify({"error": "missing entry"}), 400
    if sync not in ("yes", "no", ""):
        return jsonify({"error": "sync must be 'yes', 'no', or ''"}), 400
    rows = read_csv()
    if not any(r['entry'] == entry for r in rows):
        return jsonify({"error": "not found"}), 404
    # update via write_csv (atomic)
    for r in rows:
        if r['entry'] == entry:
            r['sync'] = sync
    write_csv(rows)
    return jsonify({"ok": True, "entry": entry, "sync": sync})


@app.route("/api/library")
def api_library():
    staging, dev = get_paths()
    src = dev if dev.is_dir() else staging
    src_label = "device" if dev.is_dir() else "staging"
    albums = []
    for search in [src, src / 'tmp'] if src == staging else [src]:
        if not search.is_dir():
            continue
        for d in sorted(search.iterdir()):
            if not d.is_dir() or d.name.startswith('.'):
                continue
            tracks = count_audio(d)
            if tracks == 0:
                continue
            parts = d.name.split(' - ', 1)
            albums.append({
                "name": d.name,
                "artist": parts[0] if len(parts) == 2 else "",
                "album": parts[1] if len(parts) == 2 else d.name,
                "tracks": tracks,
                "path": str(d),
            })
    # deduplicate by name
    seen = set()
    unique = []
    for a in albums:
        if a['name'] not in seen:
            seen.add(a['name']); unique.append(a)
    return jsonify({"albums": unique, "source": src_label, "path": str(src)})


@app.route("/api/tracklist")
def api_tracklist():
    folder = request.args.get('folder', '').strip()
    if not folder:
        return jsonify({"error": "missing folder"}), 400
    p = Path(folder)
    if not p.is_dir():
        return jsonify({"error": "not found"}), 404
    # Guard: only serve paths inside staging or device
    staging, device = get_paths()
    resolved = p.resolve()
    allowed = False
    for root in [staging, device]:
        try:
            resolved.relative_to(root.resolve()); allowed = True; break
        except ValueError:
            pass
    if not allowed:
        return jsonify({"error": "forbidden"}), 403
    return jsonify({"tracks": get_tracklist(folder), "folder": str(p), "name": p.name})


@app.route("/api/artwork")
def api_artwork():
    folder = request.args.get('folder', '').strip()
    artist = request.args.get('artist', '').strip()
    album  = request.args.get('album',  '').strip()
    if not folder and not (artist and album):
        return ('', 404)
    result = get_artwork(folder, artist, album)
    if not result:
        return ('', 404)
    mime, data = result
    return Response(data, mimetype=mime,
                    headers={'Cache-Control': 'public, max-age=86400'})


@app.route("/api/reconcile-device")
def api_reconcile_device_preview():
    staging, device = get_paths()
    if not device.is_dir():
        return jsonify({"error": "device not mounted"}), 404

    rows = read_csv()
    # Staging folders that should stay: all entries with sync != 'no' that have a folder
    staged_names = set()
    for r in rows:
        if r.get('sync', '') == 'no':
            continue
        tp = r.get('tmp_path', '')
        if tp and Path(tp).is_dir():
            staged_names.add(Path(tp).name.lower())
    # Also include any staging folder not in CSV (untracked downloads)
    for search in [staging, staging / 'tmp']:
        if not search.is_dir():
            continue
        for d in search.iterdir():
            if d.is_dir() and not d.name.startswith('.') and count_audio(d) > 0:
                staged_names.add(d.name.lower())

    to_remove = []
    for d in sorted(device.iterdir()):
        if not d.is_dir() or d.name.startswith('.'):
            continue
        if count_audio(d) == 0:
            continue
        if d.name.lower() not in staged_names:
            to_remove.append({"name": d.name, "path": str(d), "tracks": count_audio(d)})

    return jsonify({"to_remove": to_remove, "count": len(to_remove)})


def _start_script(name):
    global _proc, _proc_name
    with _proc_lock:
        if _is_running():
            return False
        while not _output_queue.empty():
            try: _output_queue.get_nowait()
            except queue.Empty: break
        ts = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
        log_path = LOGS_DIR / f"{name}-{ts}.log"
        _proc = subprocess.Popen(
            ["bash", str(SCRIPT_DIR / f"{name}.sh")],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, cwd=str(SCRIPT_DIR),
        )
        _proc_name = name
        def _reader(p=_proc, lp=log_path):
            with open(lp, 'w') as lf:
                lf.write(f"# {name} — {datetime.now().isoformat()}\n")
                for line in iter(p.stdout.readline, ''):
                    clean = re.sub(r'(\x1b\[[0-9;]*[a-zA-Z]|\r)', '', line.rstrip())
                    lf.write(clean + '\n')
                    lf.flush()
                    _output_queue.put(clean)
            _output_queue.put(None)
        threading.Thread(target=_reader, daemon=True).start()
    return True

@app.route("/api/sync", methods=["POST"])
def api_sync():
    return jsonify({"ok": True}) if _start_script("sync") else (jsonify({"error": "already running"}), 400)

@app.route("/api/download", methods=["POST"])
def api_download():
    return jsonify({"ok": True}) if _start_script("download") else (jsonify({"error": "already running"}), 400)

@app.route("/api/copy", methods=["POST"])
def api_copy():
    return jsonify({"ok": True}) if _start_script("copy") else (jsonify({"error": "already running"}), 400)

@app.route("/api/verify", methods=["POST"])
def api_verify():
    return jsonify({"ok": True}) if _start_script("verify") else (jsonify({"error": "already running"}), 400)

@app.route("/api/cleanup", methods=["POST"])
def api_cleanup():
    return jsonify({"ok": True}) if _start_script("cleanup") else (jsonify({"error": "already running"}), 400)

@app.route("/api/reconcile-device", methods=["POST"])
def api_reconcile_device_run():
    return jsonify({"ok": True}) if _start_script("reconcile_device") else (jsonify({"error": "already running"}), 400)

@app.route("/api/eject", methods=["POST"])
def api_eject():
    import subprocess
    _, dev = get_paths()
    if not dev.is_dir():
        return jsonify({"error": "device not mounted"}), 404
    result = subprocess.run(["diskutil", "eject", str(dev)], capture_output=True, text=True)
    if result.returncode == 0:
        return jsonify({"ok": True})
    return jsonify({"error": result.stderr.strip() or "eject failed"}), 500

@app.route("/api/logs")
def api_logs():
    logs = sorted(LOGS_DIR.glob("*.log"), reverse=True)[:20]
    return jsonify([{"name": l.name, "size": l.stat().st_size} for l in logs])

@app.route("/api/logs/<name>")
def api_log_file(name):
    p = LOGS_DIR / name
    if not p.exists() or p.parent != LOGS_DIR:
        return jsonify({"error": "not found"}), 404
    return Response(p.read_text(), mimetype="text/plain")

_SCRIPT_PATTERNS = (
    'sldl', 'download.sh', 'sync.sh', 'copy.sh',
    'verify.sh', 'cleanup.sh', 'reconcile_device.sh',
)

def _kill_all():
    global _proc, _proc_name
    with _proc_lock:
        if _is_running():
            try: _proc.terminate()
            except Exception: pass
        _proc = None
        _proc_name = None
    for pat in _SCRIPT_PATTERNS:
        try: subprocess.run(['pkill', '-f', pat], check=False)
        except Exception: pass


@app.route("/api/processes")
def api_processes():
    procs = []
    for pat in _SCRIPT_PATTERNS:
        try:
            pids = subprocess.check_output(['pgrep', '-f', pat], text=True).split()
            for pid in pids:
                procs.append({"pid": pid, "name": pat})
        except subprocess.CalledProcessError:
            pass
    if _is_running():
        procs.append({"pid": str(_proc.pid), "name": _proc_name or "managed"})
    return jsonify({"processes": procs, "count": len(procs)})


@app.route("/api/stop", methods=["POST"])
def api_stop():
    with _proc_lock:
        if _is_running():
            _proc.terminate()
            return jsonify({"ok": True})
    return jsonify({"error": "not running"}), 400


@app.route("/api/kill", methods=["POST"])
def api_kill():
    _kill_all()
    while not _output_queue.empty():
        try: _output_queue.get_nowait()
        except queue.Empty: break
    return jsonify({"ok": True})


@app.route("/api/restart", methods=["POST"])
def api_restart():
    def _do_restart():
        time.sleep(0.5)
        _kill_all()
        time.sleep(0.2)
        os.execv(sys.executable, [sys.executable] + sys.argv)
    _output_queue.put({'t': 'restart'})
    threading.Thread(target=_do_restart, daemon=False).start()
    return jsonify({"ok": True})


@app.route("/stream")
def stream():
    def generate():
        while True:
            try:
                msg = _output_queue.get(timeout=20)
                if msg is None:
                    yield f"data: {json.dumps({'t': 'done'})}\n\n"; break
                if isinstance(msg, dict):
                    yield f"data: {json.dumps(msg)}\n\n"
                    if msg.get('t') == 'restart':
                        break
                else:
                    yield f"data: {json.dumps({'t': 'log', 'text': msg})}\n\n"
            except queue.Empty:
                yield f"data: {json.dumps({'t': 'ping'})}\n\n"
    return Response(stream_with_context(generate()), mimetype="text/event-stream",
                    headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, threaded=True)
