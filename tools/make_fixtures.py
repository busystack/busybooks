#!/usr/bin/env python3
"""Deterministic, nonpersonal EPUB 3/PDF acceptance fixtures (CC0)."""
import zipfile, pathlib, struct, zlib, json, re
ROOT=pathlib.Path(__file__).resolve().parents[1]/'test/fixtures'
ROOT.mkdir(parents=True,exist_ok=True)
def png():
 def chunk(tag,data):return struct.pack('!I',len(data))+tag+data+struct.pack('!I',zlib.crc32(tag+data)&0xffffffff)
 return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',96,128,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\0'+bytes([53,132,228])*96 for _ in range(128))))+chunk(b'IEND',b'')
def epub(name,fixed=False,long=False,version='3.0',protected=False):
 count=40 if long else 3
 files={'mimetype':b'application/epub+zip','META-INF/container.xml':b'<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>','EPUB/cover.png':png()}
 chapters=[]
 font=pathlib.Path('/usr/share/fonts/truetype/noto/NotoSerif-Regular.ttf')
 if not font.exists():raise RuntimeError('Install fonts-noto-core to regenerate the embedded-font fixtures')
 files['EPUB/book.ttf']=font.read_bytes()
 files['EPUB/FONT-LICENSE.txt']=(ROOT/'FONT-LICENSE').read_bytes()

 for i in range(count):
  direction=' dir="rtl" lang="ar"' if i==1 else ''
  writing=' style="writing-mode:vertical-rl"' if i==2 and not long and not fixed else ''
  para=''.join(f'<p id="p{j}">A quiet library holds a dependable passage. Chapter {i+1}, paragraph {j+1}. Every bookmark belongs to this edition. Read, select, search and return to the same words.</p>' for j in range(400 if long else 20))
  files[f'EPUB/ch{i}.xhtml']=f'''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"{direction}><head><title>Chapter {i+1}</title>{'<meta name="viewport" content="width=600,height=800"/>' if fixed else ''}<style>@font-face{{font-family:FixtureBook;src:url('book.ttf')}}body{{font-family:FixtureBook,serif;{'width:560px;height:760px;background:#f4ecd8;' if fixed else ''}}}table,td{{border:1px solid}}figure img{{width:96px}}</style></head><body{writing}><h1 id="chapter">Chapter {i+1}</h1><p>Find this exact passage after a font change. A word: library. <a epub:type="noteref" href="#note">Footnote 1</a>.</p><figure><img src="cover.png" alt="Blue book cover"/><figcaption>A deterministic illustration</figcaption></figure><table><caption>A simple table</caption><tr><td>First</td><td>Second</td></tr></table><p lang="ar" dir="rtl">مكتبة هادئة وكتاب مفتوح.</p><ul><li>One item</li><li>Another item</li></ul>{para if not fixed else ''.join(re.findall(r'<p[^>]*>.*?</p>',para)[:3])}<aside epub:type="footnote" id="note"><p>A footnote with a return link <a href="#chapter">Return</a>.</p></aside></body></html>'''.encode()
  chapters.append(f'<item id="ch{i}" href="ch{i}.xhtml" media-type="application/xhtml+xml"/>')
 nav=''.join(f'<li><a href="ch{i}.xhtml#chapter">Chapter {i+1}</a></li>' for i in range(count))
 files['EPUB/nav.xhtml']=f'<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol>{nav}</ol></nav><nav epub:type="page-list"><ol><li><a href="ch0.xhtml#p0">17</a></li></ol></nav></body></html>'.encode()
 files['EPUB/package.opf']=f'''<package xmlns="http://www.idpf.org/2007/opf" version="{version}" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:busybooks:fixture:{name}</dc:identifier><dc:title>{'Fixed Composition' if fixed else 'A Quiet Library'}</dc:title><dc:creator>BusyBooks Fixtures</dc:creator><dc:language>en</dc:language><meta property="dcterms:modified">2026-01-01T00:00:00Z</meta><meta property="belongs-to-collection" id="series">Fixture Books</meta><meta refines="#series" property="collection-type">series</meta><meta property="group-position" refines="#series">1</meta>{'<meta property="rendition:layout">pre-paginated</meta><meta property="rendition:spread">both</meta>' if fixed else ''}</metadata><manifest>{''.join(chapters)}<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="font" href="book.ttf" media-type="font/ttf"/><item id="font-license" href="FONT-LICENSE.txt" media-type="text/plain"/><item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/></manifest><spine>{''.join(f'<itemref idref="ch{i}"/>' for i in range(count))}</spine></package>'''.encode()
 if protected:files['META-INF/encryption.xml']=b'<encryption><EncryptedData><EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/></EncryptedData></encryption>'
 with zipfile.ZipFile(ROOT/f'{name}.epub','w') as z:
  for path,data in files.items():
   info=zipfile.ZipInfo(path,(2000,1,1,0,0,0));info.compress_type=zipfile.ZIP_STORED if path=='mimetype' else zipfile.ZIP_DEFLATED;z.writestr(info,data)
def pdf(name,image=False,pages=4,mixed=False):
 objects=[]
 def add(s):objects.append(s if isinstance(s,bytes) else s.encode());return len(objects)
 catalog=add('');tree=add('');info=add('<< /Title (A Quiet PDF Library) /Author (BusyBooks Fixtures) >>');font=add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');outline=add('');destoutline=add('');pageids=[];linkids=[]
 image_id=None
 if image:
  pixels=zlib.compress(bytes([53,132,228])*64*96)
  image_id=add(b'<< /Type /XObject /Subtype /Image /Width 64 /Height 96 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length '+str(len(pixels)).encode()+b' >>\nstream\n'+pixels+b'\nendstream')
 for i in range(pages):
  width,height=[(600,800),(800,600),(420,600),(800,400)][i%4] if mixed else (600,800)
  rotation=' /Rotate 90' if mixed and i%4==2 else ''
  stream=(f'BT /F1 20 Tf 60 {height-80} Td (A quiet library - page {i+1}) Tj 0 -40 Td (Find this exact passage and library word.) Tj ET' if not image else 'q 450 0 0 600 60 100 cm /Im1 Do Q').encode()
  content=add(b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'\nendstream')
  linkrect=f'60 {height-180} 300 {height-140}'
  link=add(f'<< /Type /Annot /Subtype /Link /Rect [{linkrect}] /Border [0 0 1] /Dest [{tree+5} 0 R /Fit] >>')
  linkids.append((link,linkrect))
  pageids.append(add(f'<< /Type /Page /Parent {tree} 0 R /MediaBox [0 0 {width} {height}]{rotation} /Resources << /Font << /F1 {font} 0 R >> {'/XObject << /Im1 '+str(image_id)+' 0 R >>' if image else ''} >> /Contents {content} 0 R /Annots [{link} 0 R] >>'))
 for link,linkrect in linkids:objects[link-1]=f'<< /Type /Annot /Subtype /Link /Rect [{linkrect}] /Border [0 0 1] /Dest [{pageids[-1]} 0 R /Fit] >>'.encode()
 objects[catalog-1]=f'<< /Type /Catalog /Pages {tree} 0 R /Outlines {outline} 0 R /PageLabels << /Nums [0 << /S /r >> 2 << /S /D /St 17 >>] >> >>'.encode()
 objects[tree-1]=f'<< /Type /Pages /Kids [{" ".join(f"{i} 0 R" for i in pageids)}] /Count {pages} >>'.encode()
 objects[outline-1]=f'<< /Type /Outlines /First {destoutline} 0 R /Last {destoutline} 0 R /Count 1 >>'.encode()
 objects[destoutline-1]=f'<< /Title (Contents) /Parent {outline} 0 R /Dest [{pageids[-1]} 0 R /Fit] >>'.encode()
 out=bytearray(b'%PDF-1.7\n');offsets=[0]
 for i,obj in enumerate(objects,1):offsets.append(len(out));out+=f'{i} 0 obj\n'.encode()+obj+b'\nendobj\n'
 xref=len(out);out+=f'xref\n0 {len(objects)+1}\n0000000000 65535 f \n'.encode()
 for off in offsets[1:]:out+=f'{off:010d} 00000 n \n'.encode()
 out+=f'trailer\n<< /Size {len(objects)+1} /Root {catalog} 0 R /Info {info} 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode();(ROOT/f'{name}.pdf').write_bytes(out)
epub('reflowable');epub('fixed-layout',fixed=True);epub('long',long=True);epub('protected',protected=True);pdf('text');pdf('image-only',image=True);pdf('long',pages=400);pdf('mixed-pages',pages=8,mixed=True)
(ROOT/'damaged.epub').write_bytes(b'PK\x03\x04broken');(ROOT/'damaged.pdf').write_bytes(b'%PDF-1.7\nbroken');(ROOT/'unsupported.txt').write_text('Not a supported book.\n')
with zipfile.ZipFile(ROOT/'unsafe.epub','w') as z:z.writestr('../escape','unsafe')
print(json.dumps({p.name:p.stat().st_size for p in sorted(ROOT.iterdir()) if p.is_file()},indent=2))
