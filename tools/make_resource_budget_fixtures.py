#!/usr/bin/env python3
"""CC0 publication-resource fixtures, authored with bounded writes. RAR is dev-only."""
import argparse
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import zipfile
import zlib

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory',type=Path)
parser.add_argument('--rar',default=os.environ.get('BUSYBOOKS_FIXTURE_RAR'))
args=parser.parse_args()
args.directory.mkdir(parents=True,exist_ok=True)

def png():
    def chunk(kind,data):
        value=kind+data
        return struct.pack('>I',len(data))+value+struct.pack('>I',zlib.crc32(value))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',10,10,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+b'\xff\x80\0'*10)*10))+chunk(b'IEND',b'')

def entry(archive,name):
    header=zipfile.ZipInfo(name,(2000,1,1,0,0,0))
    header.compress_type=zipfile.ZIP_DEFLATED
    return archive.open(header,'w')

with zipfile.ZipFile(args.directory/'epub-spine-256m.epub','w') as archive:
    archive.writestr('mimetype','application/epub+zip',compress_type=zipfile.ZIP_STORED)
    archive.writestr('META-INF/container.xml','<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    archive.writestr('OPS/book.opf','<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="pub-id">urn:busybooks:resource-budget</dc:identifier><dc:title>Oversized spine rejection</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-10-24T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>')
    archive.writestr('OPS/nav.xhtml','<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc" id="toc"><ol><li><a href="chapter.xhtml">Oversized chapter</a></li></ol></nav></body></html>')
    prefix=b'<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Budget</title></head><body><p>Readable</p>'
    suffix=b'</body></html>'
    with entry(archive,'OPS/chapter.xhtml') as output:
        output.write(prefix)
        remaining=256*1024*1024-len(prefix)-len(suffix)
        block=b' '*65536
        while remaining:
            count=min(len(block),remaining);output.write(block[:count]);remaining-=count
        output.write(suffix)
with zipfile.ZipFile(args.directory/'comic-irrelevant-128m.cbz','w') as archive:
    archive.writestr('page.png',png())
    for name in ['one.bin','two.bin']:
        with entry(archive,name) as output:
            for _ in range(1024):output.write(bytes(65536))
if args.rar:
    with tempfile.TemporaryDirectory(prefix='busybooks-budget-author-') as temp:
        source=Path(temp)
        (source/'page.png').write_bytes(png())
        for name in ['one.bin','two.bin']:
            with (source/name).open('wb') as output:
                for _ in range(1024):output.write(bytes(65536))
        target=(args.directory/'comic-irrelevant-128m.cbr').resolve()
        target.unlink(missing_ok=True)
        subprocess.run([args.rar,'a','-idq','-ma5','-m1','-s',str(target),'.'],cwd=source,check=True,capture_output=True)
for path in sorted(args.directory.iterdir()):
    if path.is_file():print(path.name,path.stat().st_size,hashlib.sha256(path.read_bytes()).hexdigest())
