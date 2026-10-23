#!/usr/bin/env python3
"""Actual bundled application, GTK instance delivery, reader and SQLite boundary.

Requires a Linux display/session bus. Uses only copied fixtures and a disposable
profile. A book must report both a rendered/opened reading timestamp and a saved
typed location, so successful inspection alone cannot pass this probe.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'build/linux/x64/release/bundle/busybooks'
names = [
    'formats/epub2.epub', 'formats/epub2-utf16.epub',
    'formats/epub2-raster-fallback.epub', 'formats/fiction-idless.fb2',
    'formats/epub2-dtbook.epub', 'formats/representative.kepub.epub',
    'formats/epub2-mime-aliases.epub', 'formats/epub2-xml-island.epub',
    'formats/reflowable.kepub.epub',
    'formats/fiction-utf16.fb2', 'formats/fiction.fb2.zip', 'formats/fiction.fbz',
    'formats/comic-deflated.cbz', 'formats/comic-rar4-solid.cbr',
    'formats/comic-rar5-solid.cbr', 'reflowable.epub', 'fixed-layout.epub',
    'text.pdf', 'image-only.pdf',
]
with tempfile.TemporaryDirectory(prefix='busybooks-opening-') as directory:
    owned = Path(directory)
    books = owned / 'books'
    books.mkdir()
    sender = owned / 'different-sender-cwd'
    sender.mkdir()
    profile = owned / 'profile'
    originals = []
    for name in names:
        source = root / 'test/fixtures' / name
        target = books / ('Wrapped.FB2.ZIP' if source.name == 'fiction.fb2.zip' else source.name)
        shutil.copyfile(source, target)
        originals.append(target)
    environment = {**os.environ, 'BUSYBOOKS_PROFILE': str(profile)}
    with (owned / 'application.log').open('w+') as log:
        started_ms = int(time.time() * 1000)
        application = subprocess.Popen([binary, originals[0]], cwd=root, env=environment, stdout=log, stderr=log)
        try:
            for index, original in enumerate(originals):
                watch = time.monotonic()
                if index:
                    started_ms = int(time.time() * 1000)
                    forwarded = subprocess.run([binary, os.path.relpath(original, sender)], cwd=sender, env=environment, capture_output=True, timeout=15)
                    if forwarded.returncode:
                        raise RuntimeError(forwarded.stderr.decode(errors='replace'))
                identity = hashlib.sha256(original.read_bytes()).hexdigest()
                database = profile / 'reading-data.sqlite'
                book = None
                while time.monotonic() - watch < 45:
                    if application.poll() is not None:
                        raise RuntimeError('The primary application exited')
                    if database.exists():
                        try:
                            with sqlite3.connect(f'file:{database}?mode=ro', uri=True, timeout=1) as connection:
                                row = connection.execute("SELECT json FROM records WHERE kind='book' AND id=?", [identity]).fetchone()
                                location = connection.execute('SELECT path FROM locations WHERE book_id=? AND preferred=1', [identity]).fetchone()
                            if row:
                                book = json.loads(row[0])
                                if book.get('read', 0) >= started_ms and book.get('anchor') and location and Path(location[0]) == original:
                                    break
                        except sqlite3.Error:
                            pass
                    time.sleep(.05)
                else:
                    raise RuntimeError(f'No rendered, saved location for {original.name}: {book and {k:book.get(k) for k in ["format","anchor","read"]}}')
                assert original.read_bytes() == (root / 'test/fixtures' / names[index]).read_bytes()
                print(json.dumps({'fixture': original.name, 'format': book['format'], 'openedAndSavedMs': round((time.monotonic()-watch)*1000), 'forwarded': index > 0}), flush=True)
            print(json.dumps({'status': 'passed', 'books': len(originals), 'scope': 'Actual Linux bundle, first and forwarded relative paths, original-byte identity, renderer opened, saved typed locations, same primary process'}))
        except BaseException:
            log.seek(0)
            print(log.read()[-16000:], file=sys.stderr)
            raise
        finally:
            application.terminate()
            try:
                application.wait(timeout=10)
            except subprocess.TimeoutExpired:
                application.kill()
                application.wait(timeout=5)
