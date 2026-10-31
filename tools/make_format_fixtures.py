#!/usr/bin/env python3
"""BusyBooks CC0 format fixtures. RAR fixture creation is opt-in, never shipped.

Set BUSYBOOKS_FIXTURE_RAR to an official RAR 6.x executable for RAR4 and RAR5.
The resulting archives contain only the CC0 text/artwork generated below.
"""
import base64
import io
import os
import re
from pathlib import Path
import subprocess
import struct
import zlib
import warnings
import tempfile
import zipfile
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / 'test/fixtures/formats'
ROOT.mkdir(parents=True, exist_ok=True)

def image(width, height, codec='PNG', orientation=None):
    art = Image.new('RGB', (width, height), '#fff4c8')
    draw = ImageDraw.Draw(art)
    draw.rectangle((width*.15, height*.2, width*.8, height*.7), fill='#3584e4', outline='black', width=5)
    draw.line((0, 0, width, height), fill='#e01b24', width=12)
    draw.text((width*.2, height*.4), 'BusyBooks fixture', fill='black')
    out = io.BytesIO()
    exif = Image.Exif()
    if orientation: exif[274] = orientation
    art.save(out, format=codec, exif=exif)
    return out.getvalue()

def zipbook(path, files, stored=False):
    with zipfile.ZipFile(path, 'w') as archive:
        for name, data in files.items():
            entry = zipfile.ZipInfo(name, (2000, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_STORED if stored or name == 'mimetype' else zipfile.ZIP_DEFLATED
            archive.writestr(entry, data.encode('utf-8') if isinstance(data, str) else data)

container = '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'
ncx = '''<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="urn:busybooks:epub2"/><meta name="dtb:depth" content="2"/><meta name="dtb:totalPageCount" content="2"/><meta name="dtb:maxPageNumber" content="18"/></head><docTitle><text>EPUB Two</text></docTitle><navMap><navPoint id="n1" playOrder="1"><navLabel><text>First chapter</text></navLabel><content src="{first}#chapter"/><navPoint id="n2" playOrder="2"><navLabel><text>Nested passage</text></navLabel><content src="{first}#passage"/></navPoint></navPoint><navPoint id="n3" playOrder="3"><navLabel><text>Second chapter</text></navLabel><content src="second.xhtml#second"/></navPoint></navMap><pageList><navLabel><text>Print pages</text></navLabel><pageTarget id="p17" type="normal" value="17" playOrder="2"><navLabel><text>17</text></navLabel><content src="{first}#passage"/></pageTarget><pageTarget id="p18" type="normal" value="18" playOrder="3"><navLabel><text>18</text></navLabel><content src="second.xhtml#second"/></pageTarget></pageList></ncx>'''
metadata = '<dc:identifier id="uid">urn:busybooks:epub2</dc:identifier><dc:title>EPUB Two</dc:title><dc:creator>BusyBooks Fixtures</dc:creator><dc:language>en</dc:language><meta name="cover" content="cover-image"/><meta name="calibre:series" content="Fixture Books"/><meta name="calibre:series_index" content="2"/>'
chapter = '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>First</title><link rel="stylesheet" href="style.css"/></head><body><h1 id="chapter">First chapter</h1><p id="passage">A library passage stays attached after typography changes. <a href="#note">Note</a></p><div><img src="art/cover.png" alt="Fixture art"/></div><p id="note">A note and <a href="#passage">backlink</a>.</p></body></html>'
dtbook = '''<?xml version="1.0" encoding="UTF-16"?><?xml-stylesheet type="text/css" href="style.css"?><dtbook xmlns="http://www.daisy.org/z3986/2005/dtbook/" version="2005-2" xml:lang="en"><head><meta name="dtb:uid" content="urn:busybooks:epub2"/></head><book><frontmatter><doctitle>EPUB DTBook</doctitle></frontmatter><bodymatter><level1 id="chapter"><h1>DTBook chapter</h1><p id="passage">A library passage in a DTBook fallback. <noteref idref="#note">1</noteref></p><pagenum id="page17" page="normal">17</pagenum><imggroup><img src="art/cover.png" alt="Illustration"/><caption>CC0 art</caption></imggroup><level2><h2>Nested section</h2><p><em>Emphasis</em> and structure stay attached.</p></level2><note id="note"><p>Note with <a href="#passage">backlink</a> and <img src="art/cover.png" alt="Note art"/>.</p></note></level1></bodymatter><rearmatter><level1><h1>End matter</h1><p>Offline resources.</p></level1></rearmatter></book></dtbook>'''
for name, dt in [('epub2', False), ('epub2-dtbook', True)]:
    first = 'content.xml' if dt else 'first.xhtml'
    content_items = '<item id="foreign" href="foreign.xml" media-type="application/x-fixture" fallback="middle"/><item id="middle" href="middle.xml" media-type="application/x-fixture" fallback="first"/>' if dt else ''
    manifest = f'{content_items}<item id="first" href="{first}" media-type="{"application/x-dtbook+xml" if dt else "application/xhtml+xml"}"/><item id="second" href="second.xhtml" media-type="application/xhtml+xml"/><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="cover-image" href="art/cover.png" media-type="image/png"/><item id="cover-page" href="cover.xhtml" media-type="application/xhtml+xml"/><item id="css" href="style.css" media-type="text/css"/>'
    files = {'mimetype': 'application/epub+zip', 'META-INF/container.xml': container,
        'OPS/book.opf': f'<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">{metadata}</metadata><manifest>{manifest}</manifest><spine toc="ncx"><itemref idref="cover-page" linear="no"/><itemref idref="{"foreign" if dt else "first"}"/><itemref idref="second"/></spine><guide><reference type="cover" title="Cover page" href="cover.xhtml"/><reference type="text" title="Text" href="{first}#chapter"/></guide></package>',
        'OPS/toc.ncx': ncx.format(first=first), 'OPS/'+first: dtbook.encode('utf-16') if dt else chapter,
        'OPS/second.xhtml': ('<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>Second</title></head><body><h1 id="second">Second chapter</h1><p>A second library passage. Русский текст.</p></body></html>').encode('utf-8'),
        'OPS/cover.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Cover</title></head><body><div><img src="art/cover.png" alt="Cover"/></div></body></html>',
        'OPS/art/cover.png': image(240,320), 'OPS/style.css': 'body {line-height:1.5} p {margin:1em 0}'}
    if dt:
        files['OPS/book.opf']=files['OPS/book.opf'].replace('<item id="foreign"','<item id="foreign" required-namespace="urn:busybooks:foreign"').replace('<item id="middle"','<item id="middle" required-namespace="urn:busybooks:foreign"').replace('<item id="first"','<item id="first" fallback="dtbook-xhtml"').replace('</manifest>','<item id="dtbook-xhtml" href="dtbook-fallback.xhtml" media-type="application/xhtml+xml"/><item id="foreign-dtd" href="foreign.dtd" media-type="application/xml-dtd"/></manifest>')
        files['OPS/toc.ncx']=ncx.format(first='foreign.xml')
        files['OPS/dtbook-fallback.xhtml']=chapter.replace('<a href="#note">Note</a>','Note').replace('<a href="#passage">backlink</a>','backlink')
        files['OPS/foreign.dtd']='<!ELEMENT foreign (passage)><!ATTLIST foreign xmlns CDATA #FIXED "urn:busybooks:foreign" id ID #REQUIRED><!ELEMENT passage (#PCDATA)><!ATTLIST passage id ID #REQUIRED>'
    font=Path('/usr/share/fonts/truetype/noto/NotoSerif-Regular.ttf')
    if font.exists():
        files['OPS/fonts/book.ttf']=font.read_bytes();files['META-INF/FONT-LICENSE.txt']=(ROOT.parent/'FONT-LICENSE').read_bytes()
        files['OPS/style.css']+=' @font-face {font-family:FixtureFont;src:url("fonts/book.ttf")} body {font-family:FixtureFont,serif}'
        files['OPS/book.opf']=files['OPS/book.opf'].replace('</manifest>','<item id="font" href="fonts/book.ttf" media-type="application/vnd.ms-opentype"/></manifest>')
    if dt:
        foreign='<?xml version="1.0"?><!DOCTYPE foreign SYSTEM "foreign.dtd"><foreign xmlns="urn:busybooks:foreign" id="chapter"><passage id="passage">Foreign vocabulary with an equivalent preferred-vocabulary fallback.</passage></foreign>'
        files.update({'OPS/foreign.xml':foreign,'OPS/middle.xml':foreign})
    zipbook(ROOT/(name+'.epub'),files)
    if not dt:
        utf16=dict(files)
        for path in ['OPS/book.opf','META-INF/container.xml','OPS/first.xhtml','OPS/second.xhtml','OPS/toc.ncx']:
            value=files[path]
            if isinstance(value,bytes): value=value.decode('utf-8')
            if not value.startswith('<?xml'): value='<?xml version="1.0" encoding="UTF-16"?>'+value
            else: value=value.replace('encoding="UTF-8"','encoding="UTF-16"')
            utf16[path]=(b'\xfe\xff'+value.encode('utf-16be')) if path.endswith('second.xhtml') else value.encode('utf-16')
        zipbook(ROOT/'epub2-utf16.epub',utf16)
        zipbook(ROOT/'representative.kepub.epub',{**files,'OPS/first.xhtml':chapter.replace('A library passage','<span class="koboSpan" id="kobo.1.1">A library passage</span>')})
        zipbook(ROOT/'epub2-cover-page.epub',{**files,'OPS/book.opf':files['OPS/book.opf'].replace('content="cover-image"','content="cover-page"')})
        raster={**files,'OPS/book.opf':files['OPS/book.opf'].replace('</manifest>','<item id="pdf-start" href="start.pdf" media-type="application/pdf" fallback="raster"/><item id="raster" href="raster.png" media-type="image/png" fallback="first"/></manifest>').replace('idref="first"','idref="pdf-start"'),
            'OPS/start.pdf':(ROOT.parent/'text.pdf').read_bytes(),'OPS/raster.png':files['OPS/art/cover.png'],
            'OPS/first.xhtml':chapter.replace('src="art/cover.png"','src="raster.png"').replace('href="#','href="start.pdf#'),
            'OPS/toc.ncx':ncx.format(first='start.pdf')}
        # Guide references must name an OPS Content Document directly. NCX
        # destinations exercise the original non-OPS spine identity instead.
        raster['OPS/book.opf']=raster['OPS/book.opf'].replace('href="first.xhtml#chapter"','href="second.xhtml#second"')
        zipbook(ROOT/'epub2-raster-fallback.epub',raster)
        aliases={**files,'OPS/book.opf':files['OPS/book.opf'].replace('id="first" href="first.xhtml" media-type="application/xhtml+xml"','id="first" href="first.xhtml" media-type="text/x-oeb1-document" fallback="alias-xhtml"').replace('media-type="text/css"','media-type="text/x-oeb1-css"').replace('</manifest>','<item id="alias-xhtml" href="alias-fallback.xhtml" media-type="application/xhtml+xml"/></manifest>'),
            'OPS/alias-fallback.xhtml':chapter.replace('<a href="#note">Note</a>','Note').replace('<a href="#passage">backlink</a>','backlink'),
            'OPS/first.xhtml':chapter.replace('rel="stylesheet"','rel="stylesheet" type="text/x-oeb1-css"').replace('</head>','<style type="text/x-oeb1-css">p {padding-top:1px}</style></head>')}
        zipbook(ROOT/'epub2-mime-aliases.epub',aliases)
        island={**files,'OPS/book.opf':files['OPS/book.opf'].replace('href="first.xhtml" media-type="application/xhtml+xml"','href="first.xml" media-type="application/xml" required-namespace="urn:busybooks:island" fallback-style="css"').replace('first.xhtml#','first.xml#').replace('</manifest>','<item id="island-dtd" href="island.dtd" media-type="application/xml-dtd"/></manifest>'),
            'OPS/toc.ncx':ncx.format(first='first.xml'),
            'OPS/first.xml':'<?xml version="1.0"?><!DOCTYPE island SYSTEM "island.dtd"><island xmlns="urn:busybooks:island" xmlns:h="http://www.w3.org/1999/xhtml" id="chapter"><heading>Styled XML chapter</heading><passage id="passage">A library passage in a styled XML island. <h:a role="doc-noteref" href="#note">1</h:a></passage><art><h:img src="art/cover.png" alt="CC0 art"/></art><note id="note" role="doc-footnote"><h:p>A library footnote with <h:a href="#passage">backlink</h:a> and <h:img src="art/cover.png" alt="Note art"/>.</h:p></note></island>',
            'OPS/island.dtd':'<!ELEMENT island (heading,passage,art,note)><!ATTLIST island xmlns CDATA #FIXED "urn:busybooks:island" xmlns:h CDATA #FIXED "http://www.w3.org/1999/xhtml" id ID #REQUIRED><!ELEMENT heading (#PCDATA)><!ELEMENT passage (#PCDATA|h:a)*><!ATTLIST passage id ID #REQUIRED><!ELEMENT art (h:img)><!ELEMENT note (h:p)><!ELEMENT h:p (#PCDATA|h:a|h:img)*><!ATTLIST note id ID #REQUIRED role CDATA #IMPLIED><!ELEMENT h:a (#PCDATA)><!ATTLIST h:a href CDATA #REQUIRED role CDATA #IMPLIED><!ELEMENT h:img EMPTY><!ATTLIST h:img src CDATA #REQUIRED alt CDATA #REQUIRED>',
            'OPS/style.css':'@namespace f url("urn:busybooks:island"); f|island,f|heading,f|passage,f|art,f|note {display:block} f|heading {font-size:1.5em} f|passage {margin:1em 0} img {max-width:100%}'}
        island.pop('OPS/first.xhtml')
        zipbook(ROOT/'epub2-xml-island.epub',island)
    else:
        for variant, target in [('cycle','foreign'),('missing','absent')]:
            zipbook(ROOT/f'epub2-fallback-{variant}.epub',{**files,'OPS/book.opf':files['OPS/book.opf'].replace('fallback="first"',f'fallback="{target}"')})

# A second DRM-free Kobo-style EPUB exercises EPUB 3 independently of OPF 2.
with zipfile.ZipFile(ROOT.parent/'reflowable.epub') as source:
    kepub3={name:source.read(name) for name in source.namelist()}
for name,data in kepub3.items():
    if not name.endswith('.xhtml'): continue
    text=data.decode('utf-8')
    marked,count=re.subn(r'(<p id="p0">)([^<]+)(</p>)',lambda m:'<div id="passage">'+m[1]+'<span class="koboSpan" id="kobo.1.1">'+m[2]+'</span>'+m[3]+'</div>',text,count=1)
    if count:
        kepub3[name]=marked.encode('utf-8')
        break
else: raise RuntimeError('The EPUB 3 control has no paragraph to mark')
zipbook(ROOT/'reflowable.kepub.epub',kepub3)

art = base64.b64encode(image(240,320)).decode()
fiction = '''<?xml version="1.0" encoding="{encoding}"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink"><description><title-info><genre>prose</genre><author><first-name>First</first-name><last-name>Author</last-name></author><author><nickname>Second Author</nickname></author><book-title>FB2 Library — Библиотека</book-title><lang>en</lang><sequence name="Fixture Books" number="3"/><coverpage><image l:href="#cover"/></coverpage></title-info></description><body><title><p>FB2 Library</p></title><section id="first"><title><p>First chapter</p></title><p id="passage">A library passage stays attached. Русский текст. <strong>Strong</strong> and <emphasis>emphasis</emphasis>. <a type="note" l:href="#note1">1</a></p><section id="nested"><title><p>Nested section</p></title><poem><title><p>A poem</p></title><stanza><v>A quiet library</v><v>A dependable passage</v></stanza><text-author>Fixture Poet</text-author></poem><cite><p>A citation.</p></cite><table><tr><th>One</th><th>Two</th></tr><tr><td>Three</td><td>Four</td></tr></table><image l:href="#cover" alt="CC0 art"/></section></section><section id="second"><title><p>Second chapter</p></title><p>Another library passage.</p></section></body><body name="notes"><title><p>Notes</p></title><section id="note1"><title><p>1</p></title><p>A library footnote <a l:href="#passage">Back</a>.</p><image l:href="#cover" alt="Embedded note art"/></section></body><binary id="cover" content-type="image/png">{art}</binary></FictionBook>'''
for encoding, name in [('UTF-8','utf8'),('UTF-16','utf16'),('windows-1251','cp1251')]:
    data=fiction.format(encoding=encoding,art=art).encode(encoding)
    (ROOT/f'fiction-{name}.fb2').write_bytes(data)
    if name=='utf8':
        for suffix in ['fb2.zip','fbz']:
            zipbook(ROOT/f'fiction.{suffix}',{'book.FB2':data})
        zipbook(ROOT/'ambiguous.fbz',{'one.fb2':data,'two.fb2':data})
        zipbook(ROOT/'empty.fb2.zip',{'readme.txt':'No publication'})
(ROOT/'bad-encoding.fb2').write_text(fiction.format(encoding='KOI8-R',art=art))
(ROOT/'bad-root.fb2').write_text('<FictionBook xmlns="urn:wrong"><body/></FictionBook>')
(ROOT/'malformed.fb2').write_text('<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"><body>')
(ROOT/'fiction-idless.fb2').write_text('''<?xml version="1.0" encoding="UTF-8"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"><description><title-info><genre>prose</genre><author><nickname>BusyBooks Fixtures</nickname></author><book-title>FB2 Unnamed Chapters</book-title><lang>en</lang></title-info></description><body><section><title><p>Outer chapter</p></title><p id="passage">A library passage remains attached inside unnamed sections.</p><p id="busybooks-section-0-0">An authored ID deliberately collides with a generated candidate.</p><section><title><p>Nested one</p></title><p>A library passage in nested chapter one.</p></section><section><title><p>Nested two</p></title><p>A library passage in nested chapter two.</p></section></section></body></FictionBook>''')

pages={'pages/Page1.jpg':image(600,900,'JPEG'),'pages/Page2.png':image(900,600),'pages/Page10.webp':image(600,800,'WEBP'),'pages/page02.png':image(500,850),'pages/Ä3.png':image(640,800),'pages/ä3.png':image(640,800),'pages/rotated4.jpg':image(640,480,'JPEG',6)}
info='<ComicInfo><Title>Comic Library</Title><Writer>Fixture Writer</Writer><Penciller>Fixture Artist</Penciller><Series>Fixture Books</Series><Number>4</Number><LanguageISO>en</LanguageISO><Manga>YesAndRightToLeft</Manga><PageCount>999</PageCount><Pages><Page Image="0" Type="FrontCover" Bookmark="Cover"/><Page Image="1" DoublePage="true" Bookmark="Wide page"/></Pages></ComicInfo>'
pages['ComicInfo.xml']=info.encode()
zipbook(ROOT/'comic-deflated.cbz',pages)
zipbook(ROOT/'comic-stored.cbz',pages,stored=True)
codecs = {}
for codec, options in [('JPEG',{}),('JPEG',{'progressive':True}),('PNG',{}),('PNG',{'mode':'RGBA'}),('PNG',{'mode':'L'}),('WEBP',{}),('WEBP',{'lossless':True})]:
    art=Image.new(options.get('mode','RGB'),(600,900),'white');out=io.BytesIO()
    art.save(out,format=codec,**{k:v for k,v in options.items() if k!='mode'})
    codecs[f'Page{len(codecs)+1}.{dict(JPEG="jpg",PNG="png",WEBP="webp")[codec]}']=out.getvalue()
zipbook(ROOT/'comic-codecs.cbz',codecs)

zipbook(ROOT/'comic-corrupt.cbz',{**pages,'pages/Page3.png':b'not an image'})
zipbook(ROOT/'comic-unsupported.cbz',{**pages,'pages/Page3.tiff':image(10,10,'TIFF')})
animated=io.BytesIO()
Image.new('RGB',(10,10),'red').save(animated,format='PNG',save_all=True,append_images=[Image.new('RGB',(10,10),'blue')],duration=100,loop=0)
zipbook(ROOT/'comic-animated.cbz',{'Page1.png':animated.getvalue()})
zipbook(ROOT/'comic-unsafe.cbz',{'../escape.png':image(10,10)})
large=bytearray(image(10,10));large[16:24]=struct.pack('!II',20000,20000);large[29:33]=struct.pack('!I',zlib.crc32(large[12:29]))
zipbook(ROOT/'comic-dimensions.cbz',{'Page1.png':bytes(large)})
with warnings.catch_warnings():
    warnings.simplefilter('ignore')
    with zipfile.ZipFile(ROOT/'comic-duplicate.cbz','w') as duplicate:
        duplicate.writestr('Page1.png',image(10,10));duplicate.writestr('Page1.png',image(20,20))
corrupt=bytearray((ROOT/'comic-stored.cbz').read_bytes());at=corrupt.index(b'\xff\xd8');corrupt[at+20]^=1
(ROOT/'comic-crc.cbz').write_bytes(corrupt)

zipbook(ROOT/'comic-long.cbz',{**{f'Page{i:04}.png':image(1200,1600) for i in range(1,121)},'ComicInfo.xml':info})
rar=os.environ.get('BUSYBOOKS_FIXTURE_RAR')
if rar:
    with tempfile.TemporaryDirectory(prefix='busybooks-fixture-art-') as directory:
        source=Path(directory)
        for name,data in pages.items():
            path=source/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data);os.utime(path,(946684800,946684800))
        for generation in [4,5]:
            for profile,options in [('stored',['-m0','-s-']),('compressed',['-m5','-s-']),('solid',['-m5','-s'])]:
                destination=ROOT/f'comic-rar{generation}-{profile}.rar'
                if destination.exists(): destination.unlink()
                subprocess.run([rar,'a','-idq','-r',f'-ma{generation}',*options,str(destination),'.'],cwd=directory,check=True)
                destination.replace(destination.with_suffix('.cbr'))
        for name,options in [('encrypted',['-pfixture']),('encrypted-headers',['-hpfixture'])]:
            destination=ROOT/f'comic-rar4-{name}.rar'
            if destination.exists(): destination.unlink()
            subprocess.run([rar,'a','-idq','-r','-ma4',*options,str(destination),'.'],cwd=directory,check=True)
            destination.replace(destination.with_suffix('.cbr'))
        for volume in [*ROOT.glob('comic-multipart.part*.rar'),*ROOT.glob('comic-multipart.part*.cbr')]: volume.unlink()
        for name,options in [('encrypted',['-pfixture']),('encrypted-headers',['-hpfixture']),('multipart',['-v16k','-m0'])]:
            destination=ROOT/f'comic-{name}.rar'
            if destination.exists(): destination.unlink()
            subprocess.run([rar,'a','-idq','-r','-ma5',*options,str(destination),'.'],cwd=directory,check=True)
            if destination.exists(): destination.replace(destination.with_suffix('.cbr'))
            if name=='multipart':
                for volume in ROOT.glob('comic-multipart.part*.rar'): volume.rename(volume.with_suffix('.cbr'))
print(ROOT)
