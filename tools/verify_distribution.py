#!/usr/bin/env python3
"""Inspect the shipped application, native architecture, assets and provenance."""
import argparse
import json
from pathlib import Path
import struct
import sys

from release_metadata import appstream_version, sha256, versions
from verify_vendor import load_manifest, verify_bundle

ROOT = Path(__file__).resolve().parents[1]


def verify_native(stream, relative, platform):
    header = stream.read(64)
    native = relative.name in {'busybooks', 'busybooks.exe', 'busybooks_comic_archive', 'busybooks_comic_archive.exe', 'unins000.exe'} or relative.suffix.lower() in {'.dll', '.so'} or '.so.' in relative.name
    # Flutter's WindowsAotBundle ships an app-aot-elf snapshot. Windows loads
    # this through Flutter, while application executables and DLLs remain PE.
    aot = platform == 'windows' and relative.as_posix() == 'data/app.so'
    expected_magic = b'\x7fELF' if platform == 'linux' or aot else b'MZ'
    if native and not header.startswith(expected_magic):
        raise ValueError(f'Invalid native binary: {relative}')
    if header[:4] == b'\x7fELF':
        if len(header) < 20 or header[4:6] != b'\x02\x01' or struct.unpack_from('<H', header, 18)[0] != 62:
            raise ValueError(f'Expected x64 ELF: {relative}')
    elif header[:2] == b'MZ':
        if len(header) < 64:
            raise ValueError(f'Truncated Windows PE: {relative}')
        stream.seek(struct.unpack_from('<I', header, 60)[0])
        pe = stream.read(6)
        # Inno 6's uninstaller and Microsoft's runtime launchers can be x86
        # even in an x64 application installation.
        bootstrap = relative.as_posix() in {
            'MicrosoftEdgeWebView2RuntimeInstallerX64.exe',
            'VC_redist.x64.exe', 'unins000.exe',
        }
        allowed = {b'PE\0\0d\x86', b'PE\0\0L\x01'} if bootstrap else {b'PE\0\0d\x86'}
        if pe not in allowed:
            raise ValueError(f'Unexpected Windows PE architecture: {relative}')


def verify(root, platform):
    required = ['data/icudtl.dat', 'data/flutter_assets/AssetManifest.bin']
    if platform == 'windows':
        required += ['busybooks.exe', 'busybooks_comic_archive.exe', 'flutter_windows.dll', 'data/app.so']
        if not list(root.rglob('*sqlite3*.dll')):
            raise ValueError('Missing bundled Windows SQLite native asset')
    else:
        required += ['busybooks', 'busybooks_comic_archive', 'lib/libflutter_linux_gtk.so',
                     'lib/libapp.so', 'lib/libsqlite3.so',
                     'share/applications/io.busystack.busybooks.desktop',
                     'share/icons/hicolor/scalable/apps/io.busystack.busybooks.svg',
                     'share/metainfo/io.busystack.busybooks.metainfo.xml',
                     'share/mime/packages/io.busystack.busybooks.mime.xml',
                     'share/licenses/busybooks/LICENSE', 'share/licenses/busybooks/NOTICE']
    for name in required:
        path = root / name
        if not path.is_file() or not path.stat().st_size:
            raise ValueError(f'Missing or empty distribution file: {path}')
    manifest = load_manifest(ROOT / 'tools/vendor-manifest.json')
    verify_bundle(manifest, root, platform)
    owned_assets = 0
    for source in (ROOT / 'assets').rglob('*'):
        if not source.is_file():
            continue
        relative = source.relative_to(ROOT).as_posix()
        if relative in manifest['sha256']:
            continue  # The upstream verifier already checks these exact bytes.
        shipped = root / 'data/flutter_assets' / relative
        if not shipped.is_file() or sha256(shipped) != sha256(source):
            raise ValueError(f'Missing or changed application asset: {relative}')
        owned_assets += 1
    version, build = versions()
    if platform == 'linux':
        if appstream_version(root / 'share/metainfo/io.busystack.busybooks.metainfo.xml') != version:
            raise ValueError('Bundled Linux AppStream identity/version differs')
        metadata = json.loads((root / 'data/flutter_assets/version.json').read_text(encoding='utf-8'))
        if (metadata.get('version'), metadata.get('build_number'), metadata.get('app_name')) != (version, build, 'busybooks'):
            raise ValueError(f'Bundled Flutter application metadata differs: {metadata}')
    # Windows packaging and installed-package qualification validate the native
    # executable's VERSIONINFO using System.Diagnostics.FileVersionInfo. The
    # pinned Windows build does not generate Linux's version.json asset.
    inventory = []
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if any(p.lower() in {'.git', '.aws', '.env', 'credentials', 'id_rsa', 'id_ed25519'} for p in relative.parts) or path.suffix.lower() in {'.pfx', '.p12', '.key'}:
            raise ValueError(f'Unexpected credential/development file: {relative}')
        if not path.is_file():
            continue
        # Linux runtime trust stores contain public PEM certificates legitimately.
        if path.suffix.lower() == '.pem' and b'PRIVATE KEY' in path.read_bytes():
            raise ValueError(f'Unexpected private key: {relative}')
        with path.open('rb') as stream:
            verify_native(stream, relative, platform)
        inventory.append(dict(path=relative.as_posix(), bytes=path.stat().st_size, sha256=sha256(path)))
    return dict(platform=platform, architecture='x64', applicationAssets=owned_assets,
                files=inventory, status='passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', required=True, choices=['linux', 'windows'])
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        result = verify(args.bundle.resolve(strict=True), args.platform)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        print(f"Verified {len(result['files'])} distribution files ({args.platform} x64)")
    except (ValueError, OSError) as error:
        parser.exit(1, f'Distribution verification failed: {error}\n')


if __name__ == '__main__':
    main()
