#!/usr/bin/env python3
"""Validate the real shared MIME database in disposable XDG directories."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
cases = [('Book.Fb2', 'fiction-utf8.fb2', 'application/x-fictionbook+xml'),
         ('Book.FB2.ZiP', 'fiction.fb2.zip', 'application/x-zip-compressed-fb2'),
         ('Book.FbZ', 'fiction.fbz', 'application/x-zip-compressed-fb2'),
         ('Book.CbZ', 'comic-deflated.cbz', 'application/vnd.comicbook+zip'),
         ('Book.CbR', 'comic-rar5-solid.cbr', 'application/vnd.comicbook-rar'),
         ('ordinary.zip', 'comic-deflated.cbz', 'application/zip'),
         ('ordinary.rar', 'comic-rar5-solid.cbr', 'application/vnd.rar')]
with tempfile.TemporaryDirectory(prefix='busybooks-mime-') as directory:
    if len(sys.argv) > 1:
        mime = Path(sys.argv[1]).resolve()
        assert (mime / 'mime.cache').is_file(), 'The packaged MIME cache is missing'
        data = mime.parent
    else:
        data = Path(directory) / 'share'
        mime = data / 'mime'
        (mime / 'packages').mkdir(parents=True)
        shutil.copyfile(root / 'linux/io.busystack.busybooks.mime.xml', mime / 'packages/io.busystack.busybooks.xml')
        subprocess.run(['update-mime-database', mime], check=True, capture_output=True)
    actual = {}
    for name, source, expected in cases:
        original = Path(directory) / name
        shutil.copyfile(root / 'test/fixtures/formats' / source, original)
        result = subprocess.run(['gio', 'info', '-a', 'standard::content-type', original],
                                env={**os.environ, 'XDG_DATA_HOME': str(data), 'XDG_DATA_DIRS': str(data)+':/usr/share'},
                                capture_output=True, text=True, check=True)
        value = next(line.split(': ', 1)[1] for line in result.stdout.splitlines() if line.strip().startswith('standard::content-type:'))
        assert value == expected, (name, value, expected)
        actual[name] = value
    print(json.dumps({'status': 'passed', 'mimeTypes': actual}))
