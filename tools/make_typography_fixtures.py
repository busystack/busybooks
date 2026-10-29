#!/usr/bin/env python3
"""Disposable typography inputs made only from unmodified licensed font bytes.

Noto Serif comes from the committed EPUB; Liberation Sans comes from PDF.js.
Lato's real weight/style faces come from the official fonts-lato package. An
extracted package can be used without installing it via BUSYBOOKS_LATO_ROOT.
Punctuation/Unicode is a publication CSS alias, not native font metadata.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import zipfile
from xml.sax.saxutils import escape

REPO = Path(__file__).resolve().parents[1]
CSS_FAMILY = 'BusyBooks "Ä", \\ Serif'
LATO_STYLES = ('Light', 'Regular', 'Medium', 'Semibold', 'Bold',
               'LightItalic', 'Italic', 'MediumItalic', 'SemiboldItalic', 'BoldItalic')


def publication_files():
    with zipfile.ZipFile(REPO / 'test/fixtures/reflowable.epub') as source:
        files = {name: source.read(name) for name in source.namelist()}
    # CSS aliases exercise literal names and publisher/local precedence without
    # changing the embedded font's names, weights, flags, tables or checksums.
    family = json.dumps(CSS_FAMILY, ensure_ascii=False)
    for name, data in list(files.items()):
        if not name.endswith('.xhtml') or '/ch' not in name:
            continue
        text = data.decode().replace('FixtureBook', 'Liberation Sans')
        text = text.replace('</style>',
                            '@font-face{font-family:' + family + ';src:url("book.ttf")}'
                            'p,span:not(.symbol){font-family:"Liberation Sans"!important}'
                            '.symbol{font-family:' + family + '}'
                            'code{font-family:monospace}h1{font-size:2em}</style>')
        text = text.replace('<p>Find this',
                            '<p><span class="symbol">Specialist symbols: + = 0123.</span></p>'
                            '<p id="typography">Normal prose: <strong>bold emphasis</strong>, '
                            '<em>italic emphasis</em>, <span>inline words</span>, digits '
                            '0123456789. <code>code = 42;</code></p><p>Find this')
        files[name] = text.encode()
    files['EPUB/package.opf'] = files['EPUB/package.opf'].replace(
        b'A Quiet Library', b'Typography Probe')
    return files


def make_fixtures(root, lato_root):
    lato_fonts = lato_root / 'fonts/truetype/lato'
    license_path = lato_root / 'doc/fonts-lato/copyright'
    inputs = [lato_fonts / ('Lato-' + style + '.ttf') for style in LATO_STYLES]
    for path in [*inputs, license_path]:
        if not path.is_file():
            raise FileNotFoundError(
                f'{path}: supply the official fonts-lato package (an extracted '
                'package is sufficient) with BUSYBOOKS_LATO_ROOT=/path/to/usr/share')
    fonts = root / 'fonts'
    # Refuse stale font collections, including outputs of older generators.
    fonts.mkdir(parents=True)
    files = publication_files()
    (fonts / 'NotoSerif-Regular.ttf').write_bytes(files['EPUB/book.ttf'])
    (fonts / 'OFL.txt').write_bytes(files['EPUB/FONT-LICENSE.txt'])
    vendor_fonts = REPO / 'assets/reader/vendor/pdfjs/standard_fonts'
    for path in vendor_fonts.glob('LiberationSans-*.ttf'):
        shutil.copyfile(path, fonts / path.name)
    shutil.copyfile(vendor_fonts / 'LICENSE_LIBERATION', fonts / 'LICENSE_LIBERATION')
    for path in inputs:
        shutil.copyfile(path, fonts / path.name)
    shutil.copyfile(license_path, fonts / 'LICENSE_LATO')
    with zipfile.ZipFile(root / 'typography.epub', 'w') as archive:
        for name, data in files.items():
            info = zipfile.ZipInfo(name, (2000, 1, 1, 0, 0, 0))
            info.compress_type = (zipfile.ZIP_STORED if name == 'mimetype'
                                  else zipfile.ZIP_DEFLATED)
            archive.writestr(info, data)
    # Both Pango and WebKit use only this disposable collection and cache.
    (root / 'fonts.conf').write_text(
        '<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">'
        '<fontconfig><dir>' + escape(str(fonts)) + '</dir><cachedir>'
        + escape(str(root / 'font-cache')) + '</cachedir></fontconfig>')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output_directory', type=Path)
    args = parser.parse_args()
    root = args.output_directory.resolve()
    make_fixtures(root, Path(os.environ.get('BUSYBOOKS_LATO_ROOT', '/usr/share')))
    print(root)


if __name__ == '__main__':
    main()
