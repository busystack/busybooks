#!/usr/bin/env python3
"""Disposable deterministic font tests; no fonts enter the application bundle.

Uses the existing OFL Noto fixture and PDF.js's licensed Liberation test source.
The renamed OFL derivative deliberately exercises literal punctuation/Unicode.
"""
import pathlib, struct, sys, zipfile

root = pathlib.Path(sys.argv[1]).resolve()
repo = pathlib.Path(__file__).resolve().parents[1]
fonts = root / 'fonts'
fonts.mkdir(parents=True, exist_ok=True)


def checksum(data):
    data += b'\0' * (-len(data) % 4)
    return sum(struct.unpack('>' + 'I' * (len(data) // 4), data)) & 0xffffffff


def renamed(data, family, postscript, weight=None, italic=False):
    count = struct.unpack_from('>H', data, 4)[0]
    tables = {}
    for i in range(count):
        tag, _, offset, length = struct.unpack_from('>4sIII', data, 12 + i * 16)
        if tag != b'DSIG':
            tables[tag] = data[offset:offset + length]
    # Retain copyright, version and license metadata. Weight fixtures are
    # deliberately distinct glyph sets with explicit, deterministic metadata.
    name = tables[b'name']
    _, count, start = struct.unpack_from('>HHH', name)
    records = {}
    for i in range(count):
        platform, encoding, language, kind, size, offset = struct.unpack_from('>HHHHHH', name, 6 + i * 12)
        if platform == 3 and encoding in (1, 10) and language == 0x409:
            records[kind] = name[start + offset:start + offset + size].decode('utf-16-be')
    style = 'Regular' if weight is None else {300: 'Light', 400: 'Regular', 500: 'Medium', 600: 'Semibold', 700: 'Bold'}[weight]
    if italic: style += ' Italic'
    records.update({1: family, 2: style, 3: postscript + '-1', 4: family if weight is None else family + ' ' + style, 6: postscript, 16: family, 17: style})
    blob = bytearray()
    entries = bytearray()
    for kind, value in sorted(records.items()):
        encoded = value.encode('utf-16-be')
        entries += struct.pack('>HHHHHH', 3, 1, 0x409, kind, len(encoded), len(blob))
        blob += encoded
    tables[b'name'] = struct.pack('>HHH', 0, len(records), 6 + len(entries)) + entries + blob
    head = bytearray(tables[b'head']); head[8:12] = b'\0' * 4; tables[b'head'] = head
    if weight is not None:
        os2 = bytearray(tables[b'OS/2'])
        struct.pack_into('>H', os2, 4, weight)
        selection = struct.unpack_from('>H', os2, 62)[0] & ~0x261
        selection |= (1 if italic else 0) | (32 if weight >= 700 else 0) | (64 if weight == 400 and not italic else 0)
        struct.pack_into('>H', os2, 62, selection)
        tables[b'OS/2'] = os2
        struct.pack_into('>H', head, 44, (1 if weight >= 700 else 0) | (2 if italic else 0))
        post = bytearray(tables[b'post'])
        struct.pack_into('>i', post, 4, -12 * 65536 if italic else 0)
        tables[b'post'] = post
    count = len(tables); power = 2 ** (count.bit_length() - 1)
    out = bytearray(data[:4] + struct.pack('>HHHH', count, power * 16, power.bit_length() - 1, count * 16 - power * 16))
    offset = 12 + count * 16
    payload = bytearray(); head_offset = None
    for tag, body in sorted(tables.items()):
        if tag == b'head': head_offset = offset
        out += struct.pack('>4sIII', tag, checksum(bytes(body)), offset, len(body))
        padded = bytes(body) + b'\0' * (-len(body) % 4)
        payload += padded; offset += len(padded)
    out += payload
    struct.pack_into('>I', out, head_offset + 8, (0xB1B0AFBA - checksum(bytes(out))) & 0xffffffff)
    return out


with zipfile.ZipFile(repo / 'test/fixtures/reflowable.epub') as source:
    serif = source.read('EPUB/book.ttf')
    (fonts / 'NotoSerif-Regular.ttf').write_bytes(serif)
    (fonts / 'Punctuation.ttf').write_bytes(renamed(serif, 'BusyBooks "Ä", \\ Serif', 'BusyBooksPunctuationSerif'))
    (fonts / 'OFL.txt').write_bytes(source.read('EPUB/FONT-LICENSE.txt'))
    files = {name: source.read(name) for name in source.namelist()}
for path in (repo / 'assets/reader/vendor/pdfjs/standard_fonts').glob('LiberationSans-*.ttf'):
    (fonts / path.name).write_bytes(path.read_bytes())
(fonts / 'Specialist.ttf').write_bytes(renamed(serif, 'BusyBooks Specialist', 'BusyBooksSpecialist'))
# Each normal face has different licensed outlines, making a wrong match
# detectable by raster comparison even on machines without Lato installed.
sources = [serif] + [(fonts / ('LiberationSans-' + face + '.ttf')).read_bytes() for face in ['Regular', 'Bold', 'Italic', 'BoldItalic']]
for i, weight in enumerate([300, 400, 500, 600, 700]):
    for italic in [False, True]:
        suffix = str(weight) + ('Italic' if italic else 'Normal')
        (fonts / ('Weight' + suffix + '.ttf')).write_bytes(renamed(sources[(i + int(italic)) % len(sources)], 'BusyBooks Weight Proof', 'BusyBooksWeight' + suffix, weight, italic))
(fonts / 'LICENSE_LIBERATION').write_bytes((repo / 'assets/reader/vendor/pdfjs/standard_fonts/LICENSE_LIBERATION').read_bytes())
# An embedded Noto face deliberately claims the installed sans family's name.
# Body/p/span !important rules also test precedence without flattening emphasis.
for name, data in list(files.items()):
    if not name.endswith('.xhtml') or '/ch' not in name: continue
    text = data.decode().replace('FixtureBook', 'Liberation Sans')
    text = text.replace('</style>', 'p,span:not(.symbol){font-family:"Liberation Sans"!important}.symbol{font-family:"BusyBooks Specialist"}code{font-family:monospace}h1{font-size:2em}</style>')
    text = text.replace('<p>Find this', '<p><span class="symbol">Specialist symbols: + = 0123.</span></p><p>Find this')
    text = text.replace('<p>Find this', '<p id="typography">Normal prose: <strong>bold emphasis</strong>, <em>italic emphasis</em>, <span>inline words</span>, digits 0123456789. <code>code = 42;</code></p><p>Find this')
    files[name] = text.encode()
files['EPUB/package.opf'] = files['EPUB/package.opf'].replace(b'A Quiet Library', b'Typography Verification')
with zipfile.ZipFile(root / 'typography.epub', 'w') as archive:
    for name, data in files.items():
        info = zipfile.ZipInfo(name, (2000, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED if name == 'mimetype' else zipfile.ZIP_DEFLATED
        archive.writestr(info, data)
# Both Pango and WebKit inherit this same *test-only* font environment. It never
# reads a developer's installed collection or changes their font installation.
(root / 'fonts.conf').write_text('<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig><dir>' + str(fonts) + '</dir><cachedir>' + str(root / 'font-cache') + '</cachedir></fontconfig>')
print(root)
