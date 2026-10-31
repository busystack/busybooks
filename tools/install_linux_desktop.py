#!/usr/bin/env python3
"""Explicitly register a stable portable bundle in the user's XDG data home.

Keep the bundle at its selected location; rerun after moving it. This never
changes default file associations or removes another application's launcher.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

APP_ID = 'io.busystack.busybooks'


def desktop_exec(executable):
    value = str(executable)
    if any(character in value for character in ('\n', '\r', '=', '%')):
        # GLib checks the executable exists before expanding %% in an Exec key.
        raise ValueError('Desktop executable paths cannot contain newline, = or %')
    # Exec argument quoting, followed by desktop-entry string escaping. Keep the
    # one %F field code outside the executable's quoted argument.
    value = ''.join('\\' + char if char in '\\"`$' else char for char in value)
    return '"' + value.replace('\\', '\\\\') + '" %F'


def install(bundle, data_home, replace=False):
    bundle = bundle.resolve(strict=True)
    executable = bundle / 'busybooks'
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError(f'Not an executable BusyBooks bundle: {executable}')
    source_entry = bundle / f'share/applications/{APP_ID}.desktop'
    source_icon = bundle / f'share/icons/hicolor/scalable/apps/{APP_ID}.svg'
    entry = source_entry.read_text()
    icon = source_icon.read_bytes()
    lines = entry.splitlines()
    if sum(line.startswith('Exec=') for line in lines) != 1:
        raise ValueError('Expected exactly one Exec key in the bundle desktop entry')
    entry = '\n'.join('Exec=' + desktop_exec(executable)
                      if line.startswith('Exec=') else line for line in lines) + '\n'
    destinations = {
        data_home / f'icons/hicolor/scalable/apps/{APP_ID}.svg': icon,
        data_home / f'applications/{APP_ID}.desktop': entry.encode(),
    }
    # Check every target before writing anything. Preserve a pre-existing custom
    # BusyBooks launcher unless replacement was explicitly requested.
    for target, content in destinations.items():
        if target.exists() and target.read_bytes() != content and not replace:
            raise FileExistsError(f'{target} already exists; inspect it before using --replace')
    for target, content in destinations.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    updater = shutil.which('update-desktop-database')
    if updater:
        subprocess.run([updater, str(data_home / 'applications')], check=True)
    icon_updater = shutil.which('gtk-update-icon-cache')
    if icon_updater:
        # Existing user hicolor caches can hide a newly installed scalable icon.
        # Rebuild that cache explicitly; a user icon directory need not contain
        # index.theme because the system supplies the hicolor theme metadata.
        subprocess.run([icon_updater, '--force', '--ignore-theme-index',
                        str(data_home / 'icons/hicolor')], check=True)
    return data_home / f'applications/{APP_ID}.desktop'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path, help='stable extracted release bundle directory')
    parser.add_argument('--data-home', type=Path,
                        default=Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')))
    parser.add_argument('--replace', action='store_true', help='replace this app ID after inspecting existing files')
    args = parser.parse_args()
    print(install(args.bundle, args.data_home.expanduser().resolve(), args.replace))


if __name__ == '__main__':
    main()
