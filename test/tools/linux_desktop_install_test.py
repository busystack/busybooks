"""Desktop registration must preserve user launchers and file arguments."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    'linux_desktop_installer', REPO / 'tools/install_linux_desktop.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class LinuxDesktopInstallTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='busybooks-desktop-test-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bundle = self.root / 'bundle with spaces $dollar `tick` "quote"'
        self.bundle.mkdir()
        self.executable = self.bundle / 'busybooks'
        self.executable.write_text('#!/bin/sh\nexit 0\n')
        self.executable.chmod(0o755)
        for relative, data in {
            f'share/applications/{installer.APP_ID}.desktop':
                (REPO / 'linux/io.busystack.busybooks.desktop').read_bytes(),
            f'share/icons/hicolor/scalable/apps/{installer.APP_ID}.svg':
                (REPO / 'assets/branding/busybooks_logo.svg').read_bytes(),
        }.items():
            target = self.bundle / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        self.data_home = self.root / 'xdg'
        self.entry = self.data_home / f'applications/{installer.APP_ID}.desktop'
        self.icon = self.data_home / f'icons/hicolor/scalable/apps/{installer.APP_ID}.svg'

    def test_custom_launcher_blocks_all_writes(self):
        self.entry.parent.mkdir(parents=True)
        self.entry.write_text('custom original launcher\n')
        with self.assertRaises(FileExistsError):
            installer.install(self.bundle, self.data_home)
        self.assertEqual(self.entry.read_text(), 'custom original launcher\n')
        self.assertFalse(self.icon.exists())

    def test_custom_icon_is_preserved_and_explicit_replace_works(self):
        self.icon.parent.mkdir(parents=True)
        self.icon.write_bytes(b'original icon')
        with self.assertRaises(FileExistsError):
            installer.install(self.bundle, self.data_home)
        self.assertEqual(self.icon.read_bytes(), b'original icon')
        self.assertFalse(self.entry.exists())
        installer.install(self.bundle, self.data_home, replace=True)
        self.assertEqual(self.icon.read_bytes(),
                         (REPO / 'assets/branding/busybooks_logo.svg').read_bytes())
        self.assertIn('Icon=io.busystack.busybooks\n', self.entry.read_text())
        self.assertIn('StartupWMClass=io.busystack.busybooks\n', self.entry.read_text())

    def test_unusable_executable_is_rejected_without_registration(self):
        self.executable.unlink()
        with self.assertRaises(ValueError):
            installer.install(self.bundle, self.data_home)
        self.assertFalse(self.data_home.exists())

    @unittest.skipUnless(sys.platform == 'linux' and shutil.which('gtk-update-icon-cache'),
                         'GTK icon cache checks require the Linux desktop tools')
    def test_existing_hicolor_cache_is_refreshed_for_new_icon(self):
        # Reproduce a shared user hicolor directory with a cache made before
        # BusyBooks was installed, and no private index.theme.
        previous = self.icon.parent / 'previous-application.svg'
        previous.parent.mkdir(parents=True)
        previous.write_bytes((REPO / 'assets/branding/busybooks_logo.svg').read_bytes())
        subprocess.run(['gtk-update-icon-cache', '--force', '--ignore-theme-index',
                        str(self.data_home / 'icons/hicolor')], check=True,
                       capture_output=True)
        cache = self.data_home / 'icons/hicolor/icon-theme.cache'
        self.assertNotIn(installer.APP_ID.encode(), cache.read_bytes())
        installer.install(self.bundle, self.data_home)
        self.assertIn(installer.APP_ID.encode(), cache.read_bytes())
        self.assertIn(b'previous-application', cache.read_bytes())
        self.assertFalse((self.data_home / 'icons/hicolor/index.theme').exists())

    @unittest.skipUnless(sys.platform == 'linux' and shutil.which('gio'),
                         'Actual GIO launching requires the Linux desktop tools')
    def test_gio_preserves_quoted_executable_and_file_arguments(self):
        output = self.root / 'arguments.json'
        self.executable.write_text(
            f'#!{sys.executable}\nimport json,sys\n'
            f'open({str(output)!r}, "w").write(json.dumps(sys.argv))\n')
        installer.install(self.bundle, self.data_home)
        books = [self.root / 'one book $with %characters.pdf',
                 self.root / 'second book.pdf']
        for book in books:
            book.write_bytes(b'fixture')
        subprocess.run(['gio', 'launch', str(self.entry), *map(str, books)],
                       check=True, capture_output=True, text=True)
        deadline = time.monotonic() + 5
        while not output.exists() and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertEqual(json.loads(output.read_text()),
                         [str(self.executable), *map(str, books)])


if __name__ == '__main__':
    unittest.main()
