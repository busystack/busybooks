#!/usr/bin/env python3
"""Independent EPUB 2 fixture validation. Supply the pinned EPUBCheck 5.4.0 JAR.

EPUBCheck's UTF-8-only HTML lint and its rejection of stylesheet-only XML
fallback are recorded for the two normative EPUB 2 cases. OPS 2.0.1 permits
UTF-16; OPF 2.0.1 section 2.3.1.2 permits fallback-style without fallback.
Their actual XML trees must independently pass EPUB 2 Relax NG/DTD schemas.
No errors outside these explicit fixture-specific sets are allowed.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

jar = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parents[1]
books = ['epub2.epub', 'epub2-cover-page.epub', 'epub2-dtbook.epub', 'epub2-mime-aliases.epub', 'epub2-xml-island.epub', 'epub2-raster-fallback.epub',
         'representative.kepub.epub', 'epub2-utf16.epub']
with tempfile.TemporaryDirectory(prefix='busybooks-epub-conformance-') as directory:
    owned = Path(directory)
    with zipfile.ZipFile(jar) as source:
        for name in source.namelist():
            if name.startswith('com/adobe/epubcheck/schema/') and not name.endswith('/'):
                target = owned / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read(name))
    schemas = owned / 'com/adobe/epubcheck/schema/20'
    for name in books:
        book = root / 'test/fixtures/formats' / name
        report = owned / f'{name}.json'
        subprocess.run(['java', '-jar', jar, book, '--json', report], capture_output=True, timeout=45)
        messages = json.loads(report.read_text())['messages']
        errors = [m for m in messages if m['severity'] in ['ERROR', 'FATAL']]
        exceptions={'epub2-utf16.epub':{'HTM-058'}, 'epub2-xml-island.epub':{'OPF-032','OPF-043'}}
        if name in exceptions:
            assert {m['ID'].replace('_', '-') for m in errors} == exceptions[name], errors
        else:
            assert not errors, errors
        publication = owned / name
        with zipfile.ZipFile(book) as source:
            source.extractall(publication)
        checks = [(['--relaxng', schemas / 'rng/opf.rng'], publication / 'OPS/book.opf'),
                  (['--dtdvalid', schemas / 'dtd/ncx-2005-1.dtd'], publication / 'OPS/toc.ncx')]
        opf = ET.parse(publication / 'OPS/book.opf').getroot()
        for item in opf.findall('{http://www.idpf.org/2007/opf}manifest/{http://www.idpf.org/2007/opf}item'):
            path = publication / 'OPS' / item.get('href')
            mime = item.get('media-type')
            if mime in ['application/xhtml+xml', 'text/x-oeb1-document']:
                checks.append((['--relaxng', schemas / 'rng/content-xhtml.rng'], path))
            elif mime == 'application/x-dtbook+xml':
                checks.append((['--dtdvalid', schemas / 'dtd/dtbook-2005-2.dtd'], path))
            elif mime == 'application/x-fixture' or item.get('required-namespace'):
                checks.append((['--valid'], path))
        for options, document in checks:
            result = subprocess.run(['xmllint', '--nonet', '--noout', *options, document], capture_output=True, timeout=15)
            assert result.returncode == 0, (document, result.stderr.decode(errors='replace'))
        print(json.dumps({'status': 'passed', 'fixture': name, 'schemaChecks': len(checks),
                          'epubCheckErrors': [m['ID'] for m in errors],
                          'warnings': [m['ID'] for m in messages if m['severity'] == 'WARNING'],
                          'normativeProfileException': name in exceptions}), flush=True)
