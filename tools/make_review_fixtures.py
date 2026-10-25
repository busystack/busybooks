"""Create small deterministic format-review regressions in a disposable directory."""
import base64
import json
from pathlib import Path
import struct
import sys
import zlib
import zipfile


def png(width, height):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    pixels = (b'\0' + bytes([53, 132, 228]) * width) * height
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


def archive(path, files):
    with zipfile.ZipFile(path, 'w') as output:
        for name, data in files.items():
            entry = zipfile.ZipInfo(name, (2000, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_STORED if name == 'mimetype' else zipfile.ZIP_DEFLATED
            output.writestr(entry, data.encode() if isinstance(data, str) else data)


def main():
    root = Path(sys.argv[1]).resolve()
    root.mkdir(parents=True, exist_ok=True)
    html = lambda body: '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Review</title></head><body>' + body + '</body></html>'
    paragraphs = ''.join(f'<p>Library passage {i}. Read and return to this exact passage in the chapter.</p>' for i in range(180))
    chapter = html('''<h1 id="chapter:two">Review chapter</h1>
<p id="formatted">quick <em>brown </em>fox</p>
<a id="ref1" epub:type="noteref" href="notes.xhtml#note">Read note</a>
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="80"><image id="ordinary" href="art%232.png" width="100" height="80"/></svg>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100" height="80"><image id="legacy" xlink:href="art%232.png" width="100" height="80"/></svg>
''' + paragraphs + '<p id="later">Cross-reference destination much later in the referring chapter.</p>')
    files = {
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        'OPS/book.opf': '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:busybooks:review-regressions</dc:identifier><dc:title>Reader review regressions</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta></metadata><manifest>
<item id="chapter" href="chapter%232.xhtml" media-type="application/xhtml+xml"/>
<item id="percent" href="%70er%25cent.xhtml" media-type="application/xhtml+xml"/>
<item id="unicode" href="арт.xhtml" media-type="application/xhtml+xml"/>
<item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="art" href="art%232.png" media-type="image/png"/>
</manifest><spine><itemref idref="chapter"/><itemref idref="percent"/><itemref idref="unicode"/><itemref idref="notes" linear="no"/></spine></package>''',
        'OPS/nav.xhtml': html('<nav epub:type="toc"><ol><li><a href="chapter%232.xhtml#chapter%3Atwo">Chapter</a></li><li><a href="per%25cent.xhtml#percent">Percent</a></li><li><a href="%d0%b0%d1%80%d1%82.xhtml#unicode">Unicode</a></li><li><a href="missing%zz.xhtml#%zz">Broken optional</a></li></ol></nav>'),
        'OPS/chapter#2.xhtml': chapter,
        'OPS/per%cent.xhtml': html('<p id="percent">Percent filename works. <a href="chapter%232.xhtml#chapter%3Atwo">Return to chapter</a></p>'),
        'OPS/арт.xhtml': html('<p id="unicode">Unicode resource names preserve equivalent percent escapes.</p>'),
        'OPS/notes.xhtml': html('<aside id="note" epub:type="footnote"><p>A note with <a id="cross" href="chapter%232.xhtml#later">a cross-reference in the referring chapter</a> and <a id="back" role="doc-backlink" href="chapter%232.xhtml#ref1">a backlink</a>.</p></aside>'),
        'OPS/art#2.png': png(10, 8),
    }
    archive(root / 'reader-review.epub', files)
    archive(root / 'reader-review.kepub.epub', files)
    # Preserve the qualified EPUB 2 package/NCX structure while changing only
    # resource names and their URL references.
    epub2 = {}
    with zipfile.ZipFile(Path(__file__).resolve().parents[1] / 'test/fixtures/formats/epub2.epub') as original:
        for entry in original.infolist():
            name = entry.filename.replace('first.xhtml', 'chapter#2.xhtml').replace('second.xhtml', 'per%cent.xhtml')
            data = original.read(entry)
            if name.endswith(('.xml', '.opf', '.ncx', '.xhtml', '.css')):
                data = data.decode().replace('first.xhtml', 'chapter%232.xhtml').replace('second.xhtml', 'per%25cent.xhtml').replace('<dc:title>EPUB Two</dc:title>', '<dc:title>Encoded EPUB 2 review</dc:title>').encode()
            epub2[name] = data
    archive(root / 'reader-review-epub2.epub', epub2)
    missing = dict(files)
    del missing['OPS/chapter#2.xhtml']
    archive(root / 'missing-first.epub', missing)
    archive(root / 'comic-review.cbz', {
        f'{i+1}.png': png(900, 600) if i < 3 else png(600, 900) for i in range(6)
    })
    binary = base64.b64encode(png(2, 3)).decode()
    fb2 = f'''<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink"><description><title-info><book-title>Reader review FB2</book-title></title-info></description><body><section id="chapter"><title><p>Chapter</p></title><p>quick <emphasis>brown </emphasis>fox <a id="ref1" type="note" l:href="#note">Read note</a></p><image l:href="#%D0%B0%D1%80%D1%82"/>{paragraphs}<p id="later">Cross-reference destination much later.</p></section></body><body name="notes"><section id="note"><p>A note with <a l:href="#later">a cross-reference in the referring chapter</a>.</p></section></body><binary id="арт" content-type="image/png">{binary}</binary></FictionBook>'''
    (root / 'reader-review.fb2').write_text(fb2)
    archive(root / 'reader-review.fbz', {'book.fb2': fb2, '__MACOSX/._book.fb2': b'AppleDouble metadata'})
    (root / 'annotations.json').write_text(json.dumps([
        {'id': f'annotation-{i}', 'annotationKind': 'highlight', 'color': 'yellow', 'text': f'Passage {i} ' + 'x' * 2500,
         'anchor': {'page': 0, 'segments': [{'page': 0, 'start': i, 'text': 'saved passage', 'boxes': [[60, 650, 300, 670]]}]}}
        for i in range(400)
    ]))
    print(json.dumps({'directory': str(root), 'fixtures': sorted(path.name for path in root.iterdir())}))


if __name__ == '__main__':
    main()
