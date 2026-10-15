#!/usr/bin/env python3
"""Isolated native QML preview, bound to loopback."""
import functools
import importlib.util
import json
import os
from pathlib import Path
import signal
import shutil
import socket
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

BASE = Path(__file__).resolve().parent
ROOT = BASE.parent
RUNTIME = ROOT / 'runtime'
PORT, VNC_PORT, WS_PORT, DISPLAY = 8771, 5971, 6071, ':171'
# Compatibility with the existing local preview tool cache.
CACHED_VNC = Path.home() / '.cache/handunit-preview/root/usr'
CACHED_PYTHON = Path.home() / '.cache/handunit-preview/venv/bin/python'
PREVIEW_PYTHON = Path.home() / '.local/share/rezero-sddm/venv/bin/python'
X11VNC = os.environ.get('REZERO_X11VNC') or shutil.which('x11vnc') or str(CACHED_VNC / 'bin/x11vnc')
PYTHON = os.environ.get('REZERO_WEBSOCKIFY_PYTHON') or (
    sys.executable if importlib.util.find_spec('websockify') else
    next((str(path) for path in (PREVIEW_PYTHON, CACHED_PYTHON) if path.exists()), sys.executable))
WALLPAPERS = {
    'subaru-promise': {'label': 'A Promise at Dawn · Subaru + Emilia', 'path': 'assets/subaru-promise.png'},
    'subaru-rewind': {'label': 'Return by Death · Subaru', 'path': 'assets/subaru-rewind.png'},
    'sanctuary': {'label': 'Sanctuary · Emilia', 'path': 'assets/sanctuary.png'},
    'original': {'label': 'Original artwork', 'path': 'assets/background.png'},
    'royal-capital': {'label': 'Royal Capital', 'path': 'assets/royal-capital.png'},
    'moonlit-forest': {'label': 'Moonlit Forest', 'path': 'assets/moonlit-forest.png'},
}
selected_wallpaper = 'royal-capital'
selected_motion = 'full'
MOTION_LEVELS = ('full', 'gentle', 'still')
children, logs = {}, []
lock = threading.RLock()
shutdown_event = threading.Event()
ready_event = threading.Event()


def spawn(name, command, env=None, pipe=False):
    log = (RUNTIME / (name + '.log')).open('w')
    logs.append(log)
    process = subprocess.Popen([str(c) for c in command], env=env, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE if pipe else log, stderr=log)
    children[name] = process
    return process


def stop(name):
    process = children.pop(name, None)
    if process and process.poll() is None:
        process.terminate()
        try: process.wait(timeout=3)
        except subprocess.TimeoutExpired: process.kill(); process.wait()


def wait_port(port, process):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if process.poll() is not None: raise RuntimeError(f'Process exited before port {port} was ready')
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=.2): return
        except OSError: time.sleep(.1)
    raise RuntimeError(f'Port {port} did not become ready')


def start_login(wallpaper=None, motion=None):
    global selected_wallpaper, selected_motion
    with lock:
        choice = wallpaper or selected_wallpaper
        motion_choice = motion or selected_motion
        background = WALLPAPERS[choice]['path']
        if not (ROOT / 'theme' / background).is_file():
            raise RuntimeError('Wallpaper is unavailable')
        stop('login')
        env = dict(os.environ, DISPLAY=DISPLAY, QT_QPA_PLATFORM='xcb', QSG_RHI_BACKEND='opengl',
                   QSG_RENDER_LOOP='basic', LP_NUM_THREADS='2', QT_QUICK_CONTROLS_STYLE='Basic',
                   QT_FORCE_STDERR_LOGGING='1', REZERO_PREVIEW_BACKGROUND=background, REZERO_PREVIEW_MOTION=motion_choice)
        env.pop('QT_QUICK_BACKEND', None)
        env.pop('WAYLAND_DISPLAY', None)
        process = spawn('login', [BASE / 'qt-preview', ROOT / 'theme/Main.qml'], env)
        time.sleep(.4)
        if process.poll() is not None: raise RuntimeError('Qt preview failed; inspect runtime/login.log')
        selected_wallpaper = choice
        selected_motion = motion_choice


class Handler(SimpleHTTPRequestHandler):
    def allowed(self):
        return self.headers.get('Host') in (f'localhost:{PORT}', f'127.0.0.1:{PORT}')

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Content-Security-Policy', f"default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self' ws://127.0.0.1:{WS_PORT} ws://localhost:{WS_PORT}; frame-ancestors 'self'")
        super().end_headers()

    def respond(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        if not self.allowed(): return self.respond({'error':'Local preview only'}, 403)
        path = urlsplit(self.path).path
        if path == '/api/status':
            return self.respond({'websocketPort':WS_PORT, 'hostname':socket.gethostname(), 'ready':ready_event.is_set(),
                                 'wallpaper':selected_wallpaper, 'motion':selected_motion,
                                 'wallpapers':[{'id':key, 'label':value['label']} for key,value in WALLPAPERS.items()],
                                 'running':{k:p.poll() is None for k,p in children.copy().items()}})
        return super().do_GET()

    def list_directory(self, path):
        self.send_error(403, 'Directory listing disabled'); return None

    def do_POST(self):
        if not self.allowed() or self.headers.get('X-Preview-Action') != '1' or self.headers.get('Origin') not in (f'http://localhost:{PORT}', f'http://127.0.0.1:{PORT}'):
            return self.respond({'error':'Invalid request'},403)
        if self.path not in ('/api/reset', '/api/wallpaper', '/api/motion'):
            return self.respond({'error':'Not found'},404)
        wallpaper = None
        motion = None
        if self.path in ('/api/wallpaper', '/api/motion'):
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if length < 1 or length > 1024: raise ValueError('Invalid body size')
                body = json.loads(self.rfile.read(length))
                if self.path == '/api/wallpaper':
                    wallpaper = body.get('wallpaper')
                    if not isinstance(wallpaper, str) or wallpaper not in WALLPAPERS:
                        raise ValueError('Unknown wallpaper')
                else:
                    motion = body.get('motion')
                    if not isinstance(motion, str) or motion not in MOTION_LEVELS:
                        raise ValueError('Unknown motion level')
            except (ValueError, AttributeError):
                return self.respond({'error':'Choose one of the available scene or motion options'},400)
        try: start_login(wallpaper, motion); self.respond({'ok':True, 'wallpaper':selected_wallpaper, 'motion':selected_motion})
        except Exception: self.respond({'error':'Could not reset preview'},500)

    def log_message(self, *_): pass


def cleanup():
    shutdown_event.set()
    for name in list(children)[::-1]: stop(name)
    for log in logs: log.close()


def shutdown(*_): raise SystemExit(0)


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)
RUNTIME.mkdir(parents=True, exist_ok=True)
try:
    if not shutil.which('Xvfb'):
        raise RuntimeError('Install Xvfb to run the local preview.')
    if not Path(X11VNC).is_file():
        raise RuntimeError('Install x11vnc, or set REZERO_X11VNC to its executable.')
    check = subprocess.run([PYTHON, '-c', 'import websockify'], capture_output=True)
    if check.returncode:
        raise RuntimeError('Install the Python websockify package, or set REZERO_WEBSOCKIFY_PYTHON to a Python environment containing it.')
    for port in (PORT,VNC_PORT,WS_PORT):
        with socket.socket() as check:
            check.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            check.bind(('127.0.0.1',port))
    server = ThreadingHTTPServer(('127.0.0.1',PORT),functools.partial(Handler,directory=str(BASE)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    x = spawn('xvfb', ['Xvfb', DISPLAY, '-screen','0','1920x1080x24','-nolisten','tcp','-ac','-s','0'])
    time.sleep(.5)
    if x.poll() is not None: raise RuntimeError('Virtual display failed')
    start_login()
    env = dict(os.environ, XDG_SESSION_TYPE='x11', DISPLAY=DISPLAY)
    if Path(X11VNC) == CACHED_VNC / 'bin/x11vnc':
        env['LD_LIBRARY_PATH'] = str(CACHED_VNC / 'lib') + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
    env.pop('WAYLAND_DISPLAY',None)
    vnc = spawn('vnc',[X11VNC,'-display',DISPLAY,'-rfbport',str(VNC_PORT),'-localhost',
                      '-forever','-shared','-nopw','-noxdamage','-noxfixes','-noxrecord','-noscr',
                      '-nowait_bog','-nonap','-snapfb','-nowf','-wait','30','-defer','20','-quiet'],env)
    wait_port(VNC_PORT,vnc)
    bridge = spawn('websocket',[PYTHON, BASE/'websocket.py'])
    wait_port(WS_PORT,bridge)
    ready_event.set()
    print(f'Re:Zero native QML preview ready at http://localhost:{PORT}/',flush=True)
    while not shutdown_event.wait(2):
        with lock:
            if any(children[name].poll() is not None for name in ('login','xvfb','vnc','websocket')):
                raise RuntimeError('A preview process exited. See runtime logs.')
finally:
    cleanup()
