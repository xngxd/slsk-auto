#!/usr/bin/env python3
from flask import Flask, Response, jsonify, render_template, request, stream_with_context
import json, queue, re, subprocess, threading
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
CONFIG_PATH = SCRIPT_DIR / "config.toml"
WATCHLIST_PATH = SCRIPT_DIR / "watchlist.txt"

app = Flask(__name__)

_sync_proc = None
_output_queue: queue.Queue = queue.Queue()
_sync_lock = threading.Lock()


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
            section = line[1:-1]
            cfg.setdefault(section, {})
        elif '=' in line and section is not None:
            k, _, v = line.partition('=')
            cfg[section][k.strip()] = v.strip().strip('"')
    return cfg


def get_paths():
    cfg = load_config()
    paths = cfg.get("paths", {})
    staging = Path(paths.get("staging", "~/Music/slsk-staging")).expanduser()
    device = Path(paths.get("device", "/Volumes/surfans F20"))
    return staging, device


def strip_ansi(s):
    return re.sub(r'(\x1b\[[0-9;]*[a-zA-Z]|\r)', '', s)


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/status")
def api_status():
    _, dev = get_paths()
    return jsonify({
        "sync_running": _sync_proc is not None and _sync_proc.poll() is None,
        "device_mounted": dev.is_dir(),
        "device_name": dev.name,
    })


@app.route("/api/watchlist")
def api_watchlist_get():
    if not WATCHLIST_PATH.exists():
        return jsonify({"pending": [], "done": []})
    lines = WATCHLIST_PATH.read_text().splitlines()
    pending = [l.strip() for l in lines if l.strip() and not l.strip().startswith('#')]
    done = [re.sub(r'^#\s*done:\s*', '', l).strip()
            for l in lines if l.strip().startswith('# done:')]
    return jsonify({"pending": pending, "done": list(reversed(done[-30:]))})


@app.route("/api/watchlist", methods=["POST"])
def api_watchlist_add():
    entry = (request.json or {}).get("entry", "").strip()
    if not entry:
        return jsonify({"error": "empty"}), 400
    with open(WATCHLIST_PATH, "a") as f:
        f.write(f"{entry}\n")
    return jsonify({"ok": True})


@app.route("/api/watchlist/delete", methods=["POST"])
def api_watchlist_delete():
    entry = (request.json or {}).get("entry", "").strip()
    if not entry or not WATCHLIST_PATH.exists():
        return jsonify({"error": "not found"}), 400
    lines = WATCHLIST_PATH.read_text().splitlines()
    lines = [l for l in lines if l.strip() != entry]
    WATCHLIST_PATH.write_text('\n'.join(lines) + '\n')
    return jsonify({"ok": True})


@app.route("/api/library")
def api_library():
    staging, dev = get_paths()
    src = dev if dev.is_dir() else staging
    src_label = "device" if dev.is_dir() else "staging"
    audio_exts = {'.mp3', '.flac', '.opus', '.ogg', '.m4a'}
    albums = []
    if src.is_dir():
        for d in sorted(src.iterdir()):
            if not d.is_dir() or d.name.startswith('.'):
                continue
            try:
                tracks = sum(1 for f in d.iterdir() if f.suffix.lower() in audio_exts)
            except PermissionError:
                continue
            if tracks == 0:
                continue
            parts = d.name.split(' - ', 1)
            albums.append({
                "name": d.name,
                "artist": parts[0] if len(parts) == 2 else "",
                "album": parts[1] if len(parts) == 2 else d.name,
                "tracks": tracks,
            })
    return jsonify({"albums": albums, "source": src_label, "path": str(src)})


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
                _output_queue.put(strip_ansi(line.rstrip()))
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
                    yield f"data: {json.dumps({'t': 'done'})}\n\n"
                    break
                yield f"data: {json.dumps({'t': 'log', 'text': msg})}\n\n"
            except queue.Empty:
                yield f"data: {json.dumps({'t': 'ping'})}\n\n"
    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, threaded=True)
