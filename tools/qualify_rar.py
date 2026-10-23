#!/usr/bin/env python3
"""Exercise the *bundled* decoder against CC0 fixtures, including CRC failure."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile
import struct
import zlib

root=Path(__file__).resolve().parents[1]
decoder=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else root/'build/linux/x64/release/bundle/busybooks_comic_archive'
fixtures=root/'test/fixtures/formats'
checks=0
with zipfile.ZipFile(fixtures/'comic-stored.cbz') as source:
    expected={name:source.read(name) for name in source.namelist()}
with tempfile.TemporaryDirectory(prefix='busybooks-rar-qualification-') as directory:
    owned=Path(directory)
    for generation in [4,5]:
        for profile in ['stored','compressed','solid']:
            stage=owned/f'{generation}-{profile}';stage.mkdir()
            source=fixtures/f'comic-rar{generation}-{profile}.cbr'
            result=subprocess.run([decoder,source,stage],capture_output=True,text=True,encoding="utf-8",timeout=30)
            assert result.returncode==0,result.stderr
            actual={entry['name']:(stage/entry['file']).read_bytes() for entry in map(json.loads,result.stdout.splitlines())}
            assert actual==expected,(generation,profile,actual.keys(),expected.keys())
            checks+=1
        for name in ['encrypted','encrypted-headers']:
            source=fixtures/(f'comic-rar4-{name}.cbr' if generation==4 else f'comic-{name}.cbr')
            stage=owned/f'{generation}-{name}';stage.mkdir()
            result=subprocess.run([decoder,source,stage],capture_output=True,text=True,encoding="utf-8",timeout=10)
            assert result.returncode!=0 and 'ncrypted' in result.stderr,result
            checks+=1
        original=fixtures/f'comic-rar{generation}-stored.cbr'
        data=bytearray(original.read_bytes());at=data.index(b'\xff\xd8\xff');data[at+20]^=1
        corrupt=owned/f'corrupt-{generation}.cbr';corrupt.write_bytes(data)
        stage=owned/f'corrupt-{generation}';stage.mkdir()
        result=subprocess.run([decoder,corrupt,stage],capture_output=True,text=True,encoding="utf-8",timeout=10)
        assert result.returncode!=0 and 'Damaged' in result.stderr,result
        checks+=1
    # Stored RAR4 fixtures allow header-only mutations without implementing
    # or invoking a compressor. Recalculate the header checksum, then require
    # our path/duplicate and ambiguous-codepage guards to reject the inputs.
    base=(fixtures/'comic-rar4-stored.cbr').read_bytes()
    headers=[];at=7
    while at+7<=len(base):
        kind=base[at+2];flags,size=struct.unpack_from('<HH',base,at+3)
        packed=struct.unpack_from('<I',base,at+7)[0] if flags&0x8000 else 0
        if kind==0x74:
            name_size=struct.unpack_from('<H',base,at+26)[0];name_at=at+(40 if flags&0x100 else 32)
            if not flags&0x200 and name_size>12:headers.append((at,size,name_at,name_size))
        at+=size+packed
        if kind==0x7b:break
    assert len(headers)>=2
    for mode in ['unsafe','duplicate','legacy-codepage']:
        selected=next(h for h in headers if any(other[3]==h[3] and other[0]!=h[0] for other in headers)) if mode=='duplicate' else headers[0]
        data=bytearray(base);at,size,name_at,name_size=selected
        if mode=='unsafe':data[name_at:name_at+3]=b'../'
        elif mode=='legacy-codepage':data[name_at]=0xe4
        else:
            target=next(h for h in headers if h[3]==name_size and h[0]!=at)
            data[name_at:name_at+name_size]=data[target[2]:target[2]+name_size]
        struct.pack_into('<H',data,at,zlib.crc32(data[at+2:at+size])&0xffff)
        source=owned/(mode+'.cbr');source.write_bytes(data)
        stage=owned/mode;stage.mkdir()
        result=subprocess.run([decoder,source,stage],capture_output=True,text=True,encoding="utf-8",timeout=10)
        assert result.returncode!=0 and ('Unsafe' in result.stderr or 'filename encoding' in result.stderr),result
        checks+=1
    stage=owned/'multipart';stage.mkdir()
    result=subprocess.run([decoder,fixtures/'comic-multipart.part1.cbr',stage],capture_output=True,text=True,encoding="utf-8",timeout=10)
    assert result.returncode!=0 and 'Multipart' in result.stderr,result
    checks+=1
print(json.dumps({'status':'passed','checks':checks,'decoderSha256':hashlib.sha256(decoder.read_bytes()).hexdigest(),'scope':'RAR4/RAR5 stored, compressed and solid exact decoded bytes; encrypted headers/data, multipart and CRC rejection'}))
