#!/usr/bin/env python3
"""Drive the actual bundled GTK application on an isolated X11 display.

Prepare a disposable seed with prepare_workspace_probe.dart first. Run this
under dbus-run-session, with DISPLAY pointing at a private X server. Send JSON
commands on stdin; screenshots contain the real native WebKit/popover/menu
windows. No application test channel or mocked renderer is used.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

import gi

gi.require_version('Gdk', '3.0')
gi.require_version('GdkX11', '3.0')
gi.require_version('Gtk', '3.0')
from gi.repository import Gdk, Gtk  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('seed', type=Path)
parser.add_argument('evidence', type=Path)
parser.add_argument('--binary', type=Path, default=Path('build/linux/x64/release/bundle/busybooks'))
parser.add_argument('--xdotool', default=shutil.which('xdotool'))
args = parser.parse_args()
if not args.xdotool or not (args.seed / 'input.json').is_file():
    raise SystemExit('Supply xdotool and a prepared, disposable seed directory')
args.evidence.mkdir(parents=True, exist_ok=True)
# The desktop portal must read the same disposable settings as the application.
# Per-process GSettings alone does not control Flutter's portal text scaling.
desktop_config = Path(tempfile.mkdtemp(prefix='busybooks-native-desktop-'))
os.environ.update({'XDG_CONFIG_HOME': str(desktop_config), 'GSETTINGS_BACKEND': 'keyfile', 'GIO_USE_VFS': 'local'})
subprocess.run(['dbus-update-activation-environment', 'XDG_CONFIG_HOME', 'GSETTINGS_BACKEND', 'GIO_USE_VFS'], check=True)

process = None
runtime = None
application_env = None
window = None
scale = 1
log = None


def pause(seconds=.4):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        while Gtk.events_pending():
            Gtk.main_iteration_do(False)
        time.sleep(.01)


def x(*values):
    return subprocess.check_output([args.xdotool, *map(str, values)], text=True).strip()


def geometry(identity):
    return {key: int(value) for key, value in
            (line.split('=') for line in x('getwindowgeometry', '--shell', identity).splitlines())}


def locate():
    candidates = x('search', '--onlyvisible', '--pid', process.pid).splitlines()
    windows = [(identity, geometry(identity)) for identity in candidates]
    return max(windows, key=lambda pair: pair[1]['WIDTH'] * pair[1]['HEIGHT'])[0]


def snapshot(name, full_display=False):
    rect = geometry(window)
    if full_display:
        root = Gdk.get_default_root_window()
        rect = {'X': 0, 'Y': 0, 'WIDTH': root.get_width(), 'HEIGHT': root.get_height()}
    image = Gdk.pixbuf_get_from_window(Gdk.get_default_root_window(), rect['X'], rect['Y'], rect['WIDTH'], rect['HEIGHT'])
    target = args.evidence / name
    image.savev(str(target), 'png', [], [])
    return {'screenshot': str(target), 'width': rect['WIDTH'], 'height': rect['HEIGHT']}


def data(book_id=None):
    with sqlite3.connect(f'file:{runtime / "profile/reading-data.sqlite"}?mode=ro', uri=True) as database:
        records = [json.loads(row[0]) for row in database.execute("SELECT json FROM records WHERE kind='annotation'")]
        books = [json.loads(row[0]) for row in database.execute("SELECT json FROM records WHERE kind='book'")]
    if book_id:
        records = [record for record in records if record['bookId'] == book_id]
        books = [book for book in books if book['id'] == book_id]
    return {'books': [{key: book.get(key) for key in ['id', 'title', 'read', 'anchor']} for book in books],
            'notes': [{'id': record['id'], 'length': len(record.get('note', '')),
                       'sha256': hashlib.sha256(record.get('note', '').encode()).hexdigest(),
                       'tail': record.get('note', '')[-70:]} for record in records]}


def run(command):
    global process, runtime, application_env, window, scale, log
    action = command['action']
    if action == 'launch':
        if process is not None and process.poll() is None:
            raise RuntimeError('Close the previous application first')
        scale = command.get('scale', 1)
        reuse = command.get('runtime')
        runtime = Path(reuse).resolve() if reuse else Path(tempfile.mkdtemp(prefix='busybooks-native-workspace-'))
        if runtime.parent != Path('/tmp') or not runtime.name.startswith('busybooks-native-workspace-'):
            raise ValueError('Only disposable probe profiles under /tmp may be reused')
        if reuse:
            if not (runtime / 'profile/reading-data.sqlite').is_file():
                raise ValueError('The reused probe profile is missing')
        else:
            shutil.copytree(args.seed / 'profile', runtime / 'profile')
        (runtime / 'config').mkdir(exist_ok=True)
        preferences = {'theme': command.get('theme', 'light'), 'locale': 'en',
                       'readerSidebar': True, 'grid': True,
                       'reading': {'color': command.get('theme', 'light')}}
        if not reuse:
            (runtime / 'profile/settings.json').write_text(json.dumps(preferences))
        application_env = {**os.environ, 'BUSYBOOKS_PROFILE': str(runtime / 'profile'),
                           'GDK_BACKEND': 'x11', 'GDK_SCALE': str(scale),
                           'GTK_THEME': command.get('gtkTheme', 'Yaru'),
                           'GSETTINGS_BACKEND': 'keyfile', 'XDG_CONFIG_HOME': str(desktop_config), 'GIO_USE_VFS': 'local'}
        subprocess.run(['gsettings', 'set', 'org.gnome.desktop.interface', 'text-scaling-factor',
                        str(command.get('textScale', 1.0))], env=application_env, check=True)
        log = (args.evidence / (command['tag'] + '.log')).open('w')
        invocation = [str(args.binary.resolve())]
        if command.get('file'):
            invocation.append(str((args.seed / command['file']).resolve()))
        process = subprocess.Popen(invocation, env=application_env, stdout=log, stderr=log)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError('The application exited before mapping a window')
            try:
                window = locate()
                break
            except (subprocess.CalledProcessError, ValueError):
                pause(.1)
        else:
            raise RuntimeError('No application window')
        x('windowactivate', '--sync', window)
        pause(min(5, max(0, float(command.get('settle', 1)))))
        return {'pid': process.pid, 'runtime': str(runtime), 'window': window, 'scale': scale,
                'textScale': command.get('textScale', 1.0), 'theme': command.get('theme', 'light'),
                'portalTextScale': subprocess.check_output(['gdbus', 'call', '--session', '--dest', 'org.freedesktop.portal.Desktop', '--object-path', '/org/freedesktop/portal/desktop', '--method', 'org.freedesktop.portal.Settings.Read', 'org.gnome.desktop.interface', 'text-scaling-factor'], text=True).strip()}
    if action == 'open':
        started = int(time.time() * 1000)
        result = subprocess.run([str(args.binary.resolve()), str((args.seed / command['file']).resolve())],
                                env=application_env, capture_output=True, text=True, timeout=20)
        if result.returncode:
            raise RuntimeError(result.stderr)
        pause(command.get('settle', 1))
        return {'opened': command['file'], 'startedMs': started}
    if action == 'key':
        x('key', '--clearmodifiers', command['keys'])
    elif action == 'click':
        rect = geometry(window)
        x('mousemove', rect['X'] + command['x'], rect['Y'] + command['y'], 'click', command.get('button', 1))
    elif action == 'hover':
        rect = geometry(window)
        x('mousemove', rect['X'] + command['x'], rect['Y'] + command['y'])
    elif action == 'resize':
        x('windowsize', window, command['width'], command['height'])
    elif action == 'paste':
        text = Path(command['path']).read_text() if 'path' in command else command['text']
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
        x('key', '--clearmodifiers', 'ctrl+v')
    elif action == 'screenshot':
        pause(command.get('settle', .4))
        return snapshot(command['name'], command.get('fullDisplay', False))
    elif action == 'data':
        return data(command.get('bookId'))
    elif action == 'close':
        rect = geometry(window)
        x('mousemove', rect['X'] + rect['WIDTH'] - 27 * scale, rect['Y'] + 28 * scale, 'click', 1)
        deadline = time.monotonic() + 15
        while process.poll() is None and time.monotonic() < deadline:
            pause(.1)
        if process.poll() is None:
            raise RuntimeError('The application did not finish its guarded close')
        log.close()
        return {'exitCode': process.returncode, 'runtime': str(runtime)}
    elif action == 'wait':
        pause(min(float(command.get('seconds', 1)), 30))
    elif action == 'quit':
        if process is not None and process.poll() is None:
            raise RuntimeError('Close the application before retiring the probe')
        return {'quit': True}
    else:
        raise ValueError(action)
    pause(command.get('settle', .5))
    return {'action': action, 'geometry': geometry(window)}


transcript = (args.evidence / 'native-actions.jsonl').open('a')
print(json.dumps({'ready': True, 'display': os.environ.get('DISPLAY')}), flush=True)
while True:
    if not select.select([sys.stdin], [], [], .05)[0]:
        pause(.01)
        continue
    line = sys.stdin.readline()
    if not line:
        break
    try:
        command = json.loads(line)
        result = run(command)
        transcript.write(json.dumps({'time': time.time(), 'command': command, 'result': result}) + '\n')
        transcript.flush()
        print(json.dumps(result), flush=True)
        if result.get('quit'):
            break
    except Exception as error:
        print(json.dumps({'error': str(error)}), flush=True)
