#!/usr/bin/env python3
"""Generate optional CC0 comic resource fixtures outside the application data.

Pillow is an authoring dependency only. --cancellable requires the official RAR
6.x authoring tool via BUSYBOOKS_FIXTURE_RAR; it is never an app dependency.
The approximately 277 MiB --large fixture is deliberately not checked in.
"""
import argparse
import io
import os
from pathlib import Path
import random
import subprocess
import struct
import zlib
import tempfile
import zipfile
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--large', type=Path, help='write a >256 MiB stored CBZ')
parser.add_argument('--cancellable', type=Path, help='write a RAR5 solid CBR')
args = parser.parse_args()
if not args.large and not args.cancellable:
    parser.error('choose --large and/or --cancellable')
if args.cancellable:
    destination = args.cancellable.resolve()
    rar = os.environ.get('BUSYBOOKS_FIXTURE_RAR')
    if not rar:
        parser.error('--cancellable requires BUSYBOOKS_FIXTURE_RAR')
    with tempfile.TemporaryDirectory(prefix='busybooks-cancellable-author-') as directory:
        source = Path(directory)
        Image.new('RGB', (10, 10), 'red').save(source / 'page.png')
        original=(source/'page.png').read_bytes()
        payload=b'Fixture padding\0'+bytes(range(256))*32768
        chunk=b'tEXt'+payload
        padded=original[:-12]+struct.pack('>I',len(payload))+chunk+struct.pack('>I',zlib.crc32(chunk))+original[-12:]
        for index in range(64):
            (source / f'page-{index:03}.png').write_bytes(padded)
        archive = source.parent / f'{source.name}.rar'
        try:
            subprocess.run([rar, 'a', '-idq', '-r', '-ma5', '-m1', '-s', str(archive), '.'], cwd=source, check=True)
            destination.write_bytes(archive.read_bytes())
        finally:
            archive.unlink(missing_ok=True)
if args.large:
    art = Image.frombytes('RGB', (1280, 1800), random.Random(20261023).randbytes(1280 * 1800 * 3))
    encoded = io.BytesIO()
    art.save(encoded, format='PNG')
    page = encoded.getvalue()
    with zipfile.ZipFile(args.large, 'w', compression=zipfile.ZIP_STORED) as book:
        for index in range(42):
            entry = zipfile.ZipInfo(f'Page{index+1:03}.png', (2000, 1, 1, 0, 0, 0))
            book.writestr(entry, page)
    print({'sourceBytes': args.large.stat().st_size, 'pages': 42})
