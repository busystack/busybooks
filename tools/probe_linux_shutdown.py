#!/usr/bin/env python3
"""Record real guarded GTK closes under GDB on an explicitly private X display.

Works with BusyBooks or an untouched `flutter create --platforms=linux` template.
No engine changes, shutdown delays, forced exits or crash suppression are used.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('binary', type=Path)
parser.add_argument('evidence', type=Path)
parser.add_argument('--display', required=True)
parser.add_argument('--window-class', required=True)
parser.add_argument('--xdotool', required=True)
parser.add_argument('--cycles', type=int, default=5)
parser.add_argument('--book', type=Path)
parser.add_argument('--seed-profile', type=Path)
parser.add_argument('--switch-book-views', action='store_true')
args = parser.parse_args()
args.evidence.mkdir(parents=True, exist_ok=True)
runtime = Path(tempfile.mkdtemp(prefix='busybooks-shutdown-proof-'))
environment = {**os.environ, 'DISPLAY': args.display, 'GDK_BACKEND': 'x11',
               'BUSYBOOKS_PROFILE': str(runtime / 'profile'), 'GIO_USE_VFS': 'local'}
if args.seed_profile:
    shutil.copytree(args.seed_profile, runtime / 'profile')


def x(*values):
    return subprocess.check_output([args.xdotool, *map(str, values)], env=environment, text=True).strip()


def windows(pid=None):
    match = ['--pid', str(pid)] if pid else ['--class', args.window_class]
    result = subprocess.run([args.xdotool, 'search', '--onlyvisible', *match],
                            env=environment, text=True, capture_output=True)
    return result.stdout.splitlines() if result.returncode == 0 else []


if windows():
    raise SystemExit('A matching application already exists; use an isolated display')

outcomes = []
for cycle in range(args.cycles):
    target = args.evidence / f'close-{cycle}-gdb.log'
    invocation = [str(args.binary.resolve())]
    if args.book:
        invocation.append(str(args.book.resolve()))
    with target.open('w') as log:
        debugger = subprocess.Popen([
            'gdb', '-q', '--batch', '-ex', 'set pagination off',
            '-ex', 'set print thread-events off', '-ex', 'run',
            '-ex', 'info sharedlibrary', '-ex', 'info proc mappings',
            '-ex', 'thread apply all bt 30', '--args', *invocation,
        ], env=environment, stdout=log, stderr=log)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            # A plain GtkWindow may not retain a requested WM_CLASS. Match only
            # this debugger's inferior PID, which also avoids another instance.
            children = Path(f'/proc/{debugger.pid}/task/{debugger.pid}/children')
            mapped = [window for child in children.read_text().split() for window in windows(child)] if children.exists() else []
            if mapped:
                identity = mapped[-1]
                break
            if debugger.poll() is not None:
                raise RuntimeError(f'Exited before mapping; inspect {target}')
            time.sleep(.1)
        else:
            raise RuntimeError(f'Window did not map; inspect {target}')
        x('windowactivate', '--sync', identity)
        # Let the first usable frame arrive, then exercise real view switching
        # or the stock template's button before requesting ordinary WM close.
        time.sleep(3)
        if args.switch_book_views:
            x('key', '--clearmodifiers', 'ctrl+alt+2')
            time.sleep(.4)
            x('key', '--clearmodifiers', 'ctrl+alt+1')
            time.sleep(.4)
        else:
            x('key', '--clearmodifiers', 'Tab', 'Return')
        x('key', '--clearmodifiers', 'alt+F4')
        debugger.wait(timeout=45)
    contents = target.read_text()
    outcome = {'cycle': cycle, 'normal': 'exited normally' in contents,
               'abort': 'SIGABRT' in contents, 'log': str(target)}
    outcomes.append(outcome)
    print(json.dumps(outcome), flush=True)
    if not outcome['normal']:
        break

result = {'binary': str(args.binary.resolve()), 'profile': str(runtime / 'profile'),
          'outcomes': outcomes, 'cleanShutdownPassed': all(r['normal'] for r in outcomes)}
(args.evidence / 'outcomes.json').write_text(json.dumps(result, indent=2) + '\n')
raise SystemExit(0 if result['cleanShutdownPassed'] else 1)
