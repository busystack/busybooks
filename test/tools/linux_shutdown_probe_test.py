"""Exercise the guarded-close driver's CLI with owned process/input fixtures."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
PROBE = REPO / 'tools/probe_linux_shutdown.py'


class LinuxShutdownProbeTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='busybooks-shutdown-driver-test-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.commands = self.root / 'commands.jsonl'
        self.closed = self.root / 'closed'
        self.app = self.script('application', '''import os,time
from pathlib import Path
deadline=time.monotonic()+15
while not Path(os.environ['SHUTDOWN_FIXTURE_CLOSED']).exists() and time.monotonic()<deadline:
 time.sleep(.01)
''')
        self.xdotool = self.script('xdotool', '''import os,sys,json
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['SHUTDOWN_FIXTURE_COMMANDS'],'a') as log: log.write(json.dumps(args)+'\\n')
if args[0]=='search':
 if '--class' in args: raise SystemExit(1)
 print('123')
if 'alt+F4' in args: Path(os.environ['SHUTDOWN_FIXTURE_CLOSED']).touch()
''')
        self.script('gdb', '''import os,sys,subprocess,time
from pathlib import Path
args=sys.argv[sys.argv.index('--args')+1:]
child=subprocess.Popen(args)
presented=False
while child.poll() is None:
 p=Path(os.environ['SHUTDOWN_FIXTURE_COMMANDS'])
 if p.exists() and 'ctrl+g' in p.read_text() and not presented:
  print('reader-popup stage=presented kind=goto',flush=True);presented=True
 time.sleep(.01)
if os.environ.get('SHUTDOWN_FIXTURE_ABORT'):
 print('received signal SIGABRT')
else:
 print('exited normally')
''')
        self.environment = {
            **os.environ, 'PATH': str(self.root) + os.pathsep + os.environ['PATH'],
            'SHUTDOWN_FIXTURE_COMMANDS': str(self.commands),
            'SHUTDOWN_FIXTURE_CLOSED': str(self.closed),
        }

    def script(self, name, source):
        path = self.root / name
        path.write_text(f'#!{sys.executable}\n' + source)
        path.chmod(0o755)
        return path

    def run_probe(self, *extra, abort=False):
        evidence = self.root / 'evidence'
        environment = dict(self.environment)
        if abort:
            environment['SHUTDOWN_FIXTURE_ABORT'] = '1'
        result = subprocess.run([
            sys.executable, str(PROBE), str(self.app), str(evidence),
            '--display', ':fixture', '--window-class', 'fixture',
            '--xdotool', str(self.xdotool), '--cycles', '1', *extra,
        ], env=environment, capture_output=True, text=True, timeout=20)
        return result, json.loads((evidence / 'outcomes.json').read_text())

    def keys(self):
        return [args for args in map(json.loads, self.commands.read_text().splitlines())
                if args[0] == 'key']

    def test_busybooks_default_does_not_open_a_welcome_file_chooser(self):
        result, outcome = self.run_probe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(outcome['cleanShutdownPassed'])
        self.assertEqual(self.keys(), [['key', '--clearmodifiers', 'alt+F4']])

    def test_template_button_activation_is_explicit(self):
        result, outcome = self.run_probe('--exercise-template-button')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(outcome['cleanShutdownPassed'])
        self.assertIn(['key', '--clearmodifiers', 'Tab', 'Return'], self.keys())

    def test_reader_surface_requires_its_presentation_acknowledgment(self):
        book = self.root / 'fixture.pdf'
        book.write_bytes(b'owned fixture')
        result, outcome = self.run_probe('--book', str(book), '--reader-popover')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(outcome['cleanShutdownPassed'])
        self.assertEqual(self.keys(), [
            ['key', '--clearmodifiers', 'ctrl+g'],
            ['key', '--clearmodifiers', 'Escape'],
            ['key', '--clearmodifiers', 'alt+F4'],
        ])

    def test_aborted_close_remains_a_failure(self):
        result, outcome = self.run_probe(abort=True)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(outcome['cleanShutdownPassed'])
        self.assertTrue(outcome['outcomes'][0]['abort'])
        self.assertFalse(outcome['outcomes'][0]['normal'])


if __name__ == '__main__':
    unittest.main()
