#!/usr/bin/env python3
import csv, json, os, queue, re, subprocess, threading
from pathlib import Path
from flask import Flask, Response, jsonify, render_template, request, stream_with_context

SCRIPT_DIR = Path(__file__).parent
CONFIG_PATH = SCRIPT_DIR / "config.toml"
WATCHLIST_PATH = SCRIPT_DIR / "watchlist.csv"
AUDIO_EXTS = {'.mp3', '.flac', '.opus', '.ogg', '.m4a'}
CSV_FIELDS = ['entry', 'tmp_path', 'status', 'verified']

app = Flask(__name__)
_sync_proc = None
_output_queue: queue.Queue = queue.Queue()
_sync_lock = threading.Lock()


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
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
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
    """Scan staging/tmp and update in_progress/completed statuses from filesystem."""
    tmp_dir = staging / 'tmp'
    if not tmp_dir.is_dir():
        return rows
    tmp_folders = {d.name.lower(): d for d in tmp_dir.iterdir()
                   if d.is_dir() and not d.name.startswith('.')}
    updated = []
    for row in rows:
        if row['status'] in ('completed', 'verified'):
            updated.append(row)
            continue
        # Try to find a matching tmp folder
        entry_lower = row['entry'].lower()
        words = [w for w in entry_lower.split() if len(w) > 3]
        match = None
        for name, folder in tmp_folders.items():
            if any(w in name for w in words):
                match = folder
                break
        if match:
            state = folder_state(match)
            if state and row['status'] in ('not_started', 'in_progress', 'failed', ''):
                row = dict(row)
                row['status'] = state
                row['tmp_path'] = str(match)
        updated.append(row)
    return updated


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/status")
def api_status():
    _, dev = get_paths()
    managed = _sync_proc is not None and _sync_proc.poll() is None
    try:
        external = bool(subprocess.check_output(["pgrep", "-f", "sync.sh"], text=True).strip())
    except subprocess.CalledProcessError:
        external = False
    rows = read_csv()
    in_progress = sum(1 for r in rows if r['status'] == 'in_progress')
    return jsonify({
        "sync_running": managed or external,
        "device_mounted": dev.is_dir(),
        "device_name": dev.name,
        "in_progress_count": in_progress,
    })


@app.route("/api/watchlist")
def api_watchlist_get():
    staging, _ = get_paths()
    rows = reconcile_rows(read_csv(), staging)
    result = {'not_started': [], 'in_progress': [], 'completed': [],
              'failed': [], 'verified': []}
    for r in rows:
        status = r['status']
        verified = r['verified']
        item = {
            'entry': r['entry'],
            'tmp_path': r['tmp_path'],
            'status': status,
            'verified': verified,
            'tracks': count_audio(r['tmp_path']) if r['tmp_path'] else 0,
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
            })
    # deduplicate by name
    seen = set()
    unique = []
    for a in albums:
        if a['name'] not in seen:
            seen.add(a['name']); unique.append(a)
    return jsonify({"albums": unique, "source": src_label, "path": str(src)})


@app.route("/api/sync", methods=["POST"])
def api_sync_start():
    global _sync_proc
    with _sync_lock:
        if _sync_proc is not None and _sync_proc.poll() is None:
            return jsonify({"error": "already running"}), 400
        while not _output_queue.empty():
            try: _output_queue.get_nowait()
            except queue.Empty: break
        _sync_proc = subprocess.Popen(
            ["bash", str(SCRIPT_DIR / "sync.sh")],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, cwd=str(SCRIPT_DIR),
        )
        def _reader():
            for line in iter(_sync_proc.stdout.readline, ''):
                _output_queue.put(re.sub(r'(\x1b\[[0-9;]*[a-zA-Z]|\r)', '', line.rstrip()))
            _output_queue.put(None)
        threading.Thread(target=_reader, daemon=True).start()
    return jsonify({"ok": True})


@app.route("/api/sync/stop", methods=["POST"])
def api_sync_stop():
    with _sync_lock:
        if _sync_proc is not None and _sync_proc.poll() is None:
            _sync_proc.terminate()
            return jsonify({"ok": True})
    return jsonify({"error": "not running"}), 400


@app.route("/stream")
def stream():
    def generate():
        while True:
            try:
                msg = _output_queue.get(timeout=20)
                if msg is None:
                    yield f"data: {json.dumps({'t': 'done'})}\n\n"; break
                yield f"data: {json.dumps({'t': 'log', 'text': msg})}\n\n"
            except queue.Empty:
                yield f"data: {json.dumps({'t': 'ping'})}\n\n"
    return Response(stream_with_context(generate()), mimetype="text/event-stream",
                    headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, threaded=True)
