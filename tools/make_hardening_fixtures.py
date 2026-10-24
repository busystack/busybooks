#!/usr/bin/env python3
"""Recreate the CC0 F22 regression and optional high-expansion F18 EPUB.

The review's sandbox attachments are not mounted in the developer checkout.
This fixture independently reproduces the specified geometry/orientation/fill.
"""
import argparse
import hashlib
import io
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--expansion', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
if args.expansion:
    args.expansion.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.expansion, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        archive.writestr('META-INF/container.xml', '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>')
        items = ''.join(f'<item id="r{i}" href="r{i}.bin" media-type="application/octet-stream"/>' for i in range(32))
        archive.writestr('OPS/book.opf', '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Expansion regression</dc:title></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>' + items + '</manifest><spine><itemref idref="chapter"/></spine></package>')
        archive.writestr('OPS/chapter.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Expansion</title></head><body><p>Readable bounded metadata.</p></body></html>')
        for i in range(32):
            with archive.open(f'OPS/r{i}.bin', 'w') as resource:
                for _ in range(128):
                    resource.write(bytes(65536))
else:
    from PIL import Image, ImageDraw
    image = Image.new('RGB', (600, 900), '#fff4c8')
    draw = ImageDraw.Draw(image)
    draw.rectangle((40, 40, 300, 450), fill='#3584e4')
    exif = Image.Exif()
    exif[274] = 6
    encoded = io.BytesIO()
    image.save(encoded, 'JPEG', exif=exif)
    jpeg = encoded.getvalue()
    marker = jpeg.index(b'\xff\xe1')
    # Include both legal fill and a standalone TEM marker before EXIF.
    jpeg = jpeg[:marker] + b'\xff\x01\xff' + jpeg[marker:]
    fixture = root / 'test/fixtures/formats/orientation6-fill.cbz'
    with zipfile.ZipFile(fixture, 'w') as archive:
        archive.writestr(zipfile.ZipInfo('page.jpg', (2000, 1, 1, 0, 0, 0)), jpeg)
    checksums = fixture.parent / 'SHA256SUMS'
    rows = [r for r in checksums.read_text().splitlines() if not r.endswith('  ' + fixture.name)]
    rows.append(hashlib.sha256(fixture.read_bytes()).hexdigest() + '  ' + fixture.name)
    checksums.write_text('\n'.join(sorted(rows, key=lambda r: r.split('  ', 1)[1])) + '\n')
