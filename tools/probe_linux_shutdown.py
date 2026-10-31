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
import signal
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
parser.add_argument('--exercise-template-button', action='store_true',
                    help='Press Tab/Return for a stock Flutter counter template only')
args = parser.parse_args()
if args.cycles < 1:
    parser.error('--cycles must be positive')
args.evidence.mkdir(parents=True, exist_ok=True)
runtime = Path(tempfile.mkdtemp(prefix='busybooks-shutdown-proof-'))
environment = {**os.environ, 'DISPLAY': args.display, 'GDK_BACKEND': 'x11',
               'BUSYBOOKS_PROFILE': str(runtime / 'profile'), 'GIO_USE_VFS': 'local'}
if args.seed_profile:
    shutil.copytree(args.seed_profile, runtime / 'profile')


def x(*values):
    return subprocess.check_output([args.xdotool, *map(str, values)], env=environment, text=True, timeout=15).strip()


def windows(pid=None):
    match = ['--pid', str(pid)] if pid else ['--class', args.window_class]
    result = subprocess.run([args.xdotool, 'search', '--onlyvisible', *match],
                            env=environment, text=True, capture_output=True, timeout=15)
    return result.stdout.splitlines() if result.returncode == 0 else []


if windows():
    raise SystemExit('A matching application already exists; use an isolated display')

def run_cycle(cycle):
    target = args.evidence / f'close-{cycle}-gdb.log'
    invocation = [str(args.binary.resolve())]
    if args.book:
        invocation.append(str(args.book.resolve()))
    debugger = None
    failure = None
    try:
        with target.open('w') as log:
            debugger = subprocess.Popen([
                'gdb', '-q', '--batch', '-ex', 'set pagination off',
                '-ex', 'set print thread-events off', '-ex', 'run',
                '-ex', 'info sharedlibrary', '-ex', 'info proc mappings',
                '-ex', 'thread apply all bt 80', '--args', *invocation,
            ], env=environment, stdout=log, stderr=log, start_new_session=True)
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
            # Let the first usable frame arrive before requesting ordinary WM close.
            # Tab/Return is opt-in for the stock counter: on BusyBooks Welcome it
            # opens a file chooser, so Alt+F4 would close the chooser, not the app.
            time.sleep(3)
            if args.switch_book_views:
                x('key', '--clearmodifiers', 'ctrl+alt+2')
                time.sleep(.4)
                x('key', '--clearmodifiers', 'ctrl+alt+1')
                time.sleep(.4)
            elif args.exercise_template_button:
                x('key', '--clearmodifiers', 'Tab', 'Return')
            x('key', '--clearmodifiers', 'alt+F4')
            debugger.wait(timeout=45)
    except (RuntimeError, subprocess.SubprocessError, OSError) as error:
        failure = str(error)
    finally:
        if debugger is not None and debugger.poll() is None:
            # Stop a failed diagnostic for its backtrace; this can never count
            # as clean shutdown. Product shutdown uses only ordinary WM close.
            failure = failure or 'Debugger did not finish'
            debugger.send_signal(signal.SIGINT)
            try:
                debugger.wait(timeout=15)
            except subprocess.TimeoutExpired:
                debugger.terminate()
                try:
                    debugger.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    # A debugger stopped inside graphics code may not respond
                    # to termination. Retire only its disposable process group;
                    # forced diagnostic cleanup never counts as product close.
                    os.killpg(debugger.pid, signal.SIGKILL)
                    debugger.wait(timeout=5)
    contents = target.read_text()
    return {'cycle': cycle, 'normal': failure is None and 'exited normally' in contents,
            'abort': 'received signal SIGABRT' in contents,
            'segmentationFault': 'received signal SIGSEGV' in contents,
            'error': failure, 'log': str(target)}

outcomes = []
for cycle in range(args.cycles):
    outcome = run_cycle(cycle)
    outcomes.append(outcome)
    print(json.dumps(outcome), flush=True)
    if not outcome['normal']:
        break

result = {'binary': str(args.binary.resolve()), 'profile': str(runtime / 'profile'),
          'outcomes': outcomes, 'cleanShutdownPassed': all(r['normal'] for r in outcomes)}
(args.evidence / 'outcomes.json').write_text(json.dumps(result, indent=2) + '\n')
raise SystemExit(0 if result['cleanShutdownPassed'] else 1)
