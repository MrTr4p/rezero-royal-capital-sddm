#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ ! -f theme/shaders/subaru-wind.vert.qsb ] || [ theme/shaders/subaru-wind.vert -nt theme/shaders/subaru-wind.vert.qsb ]; then ./theme/shaders/build.sh; fi
if [ ! -x preview/qt-preview ] || [ preview/preview.cpp -nt preview/qt-preview ] || [ preview/context.h -nt preview/qt-preview ]; then ./preview/build.sh; fi
if ! systemctl --user is-active --quiet rezero-sanctuary-preview.service; then
    systemd-run --user --collect --unit=rezero-sanctuary-preview --description='Re:Zero Royal Capital localhost preview' \
        --setenv="REZERO_X11VNC=${REZERO_X11VNC:-}" \
        --setenv="REZERO_WEBSOCKIFY_PYTHON=${REZERO_WEBSOCKIFY_PYTHON:-}" "$(command -v python3)" "$PWD/preview/serve.py"
fi
python3 - <<'PYREADY'
import json, time, urllib.request
for attempt in range(75):
    try:
        with urllib.request.urlopen('http://127.0.0.1:8771/api/status', timeout=1) as response:
            if json.load(response).get('ready'):
                break
    except (OSError, ValueError):
        pass
    time.sleep(.2)
else:
    raise SystemExit('Preview startup timed out; check journalctl --user -u rezero-sanctuary-preview.service')
PYREADY
printf '%s\n' 'http://localhost:8771/'
