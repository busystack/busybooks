#!/usr/bin/env python3
"""Verify pinned upstream bytes in the repository and release bundles.

Normal verification is offline. --upstream additionally compares supplied
official Git checkouts / release archives with the established manifest.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import zipfile


class VerificationError(Exception):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git_blob(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


def relative(value):
    if not isinstance(value, str) or not value or '\\' in value:
        raise VerificationError(f'Invalid relative path: {value!r}')
    path = PurePosixPath(value)
    if path.is_absolute() or any(p in ('', '.', '..') for p in value.split('/')) or ':' in value:
        raise VerificationError(f'Invalid relative path: {value!r}')
    return value


def load_manifest(path):
    manifest = json.loads(Path(path).read_text(encoding='utf-8'))
    if manifest.get('schemaVersion') != 2 or 'modifiedVendorFiles' in manifest or 'ownedMetadataFiles' in manifest:
        raise VerificationError('A version-2 manifest without vendor modification exceptions is required')
    hashes = manifest['sha256']
    provenance = manifest['provenance']
    if not hashes or set(hashes) != set(provenance):
        raise VerificationError('Every distributed upstream file requires a hash and provenance')
    for name, expected in hashes.items():
        relative(name)
        if len(expected) != 64 or any(c not in '0123456789abcdef' for c in expected):
            raise VerificationError(f'Invalid SHA-256: {name}')
        entry = provenance[name]
        relative(entry['path'])
        source = manifest['sources'].get(entry['source'])
        if source is None or not source.get('url'):
            raise VerificationError(f'Missing official source: {name}')
        if source['kind'] == 'git':
            if len(source.get('revision', '')) != 40 or len(entry.get('gitBlob', '')) != 40:
                raise VerificationError(f'Missing immutable Git provenance: {name}')
        elif source['kind'] in ('zip', 'tar.gz'):
            if not source.get('release') or len(source.get('sha256', '')) != 64:
                raise VerificationError(f'Missing immutable archive provenance: {name}')
        else:
            raise VerificationError(f'Unsupported upstream source: {entry["source"]}')
    roots = [relative(p) for p in manifest['vendorRoots']]
    for name in hashes:
        if not any(name.startswith(root + '/') for root in roots):
            raise VerificationError(f'File is outside declared vendor inventory: {name}')
    for entry in manifest['bundleNotices']:
        relative(entry['path'])
        relative(entry['bundlePath'])
        source = manifest['sources'].get(entry['source']) or manifest.get('buildInputs', {}).get(entry['source'])
        if source is None or not source.get('url') or len(entry['sha256']) != 64 or not entry['platforms'] or not set(entry['platforms']) <= {'linux', 'windows'}:
            raise VerificationError(f'Incomplete bundled notice provenance: {entry["bundlePath"]}')
    return manifest


def inventory(root, directories):
    found = set()
    for directory in directories:
        parent = root
        for component in PurePosixPath(relative(directory)).parts:
            parent = parent / component
            if parent.is_symlink():
                raise VerificationError(f'Linked vendor directory component: {parent}')
        if not parent.is_dir() or parent.is_symlink():
            raise VerificationError(f'Missing or linked vendor directory: {parent}')
        for item in parent.rglob('*'):
            if item.is_symlink():
                raise VerificationError(f'Linked vendor entry: {item}')
            if item.is_file():
                found.add(item.relative_to(root).as_posix())
    return found


def verify_files(root, hashes, directories):
    root = Path(root)
    expected = set(hashes)
    found = inventory(root, directories)
    missing, unexpected = sorted(expected - found), sorted(found - expected)
    if missing or unexpected:
        raise VerificationError(f'Vendor inventory differs: missing={missing}, unexpected={unexpected}')
    for name, expected_hash in hashes.items():
        if digest((root / name).read_bytes()) != expected_hash:
            raise VerificationError(f'Upstream checksum mismatch: {root / name}')


def verify_repository(manifest, root):
    verify_files(root, manifest['sha256'], manifest['vendorRoots'])
    for name, entry in manifest['provenance'].items():
        if 'gitBlob' in entry and git_blob((Path(root) / name).read_bytes()) != entry['gitBlob']:
            raise VerificationError(f'Upstream Git blob mismatch: {Path(root) / name}')


def bundle_hashes(manifest, platform):
    hashes = {}
    for name, expected in manifest['sha256'].items():
        if name.startswith('assets/'):
            hashes['data/flutter_assets/' + name] = expected
    for entry in manifest['bundleNotices']:
        if platform in entry['platforms']:
            hashes[relative(entry['bundlePath'])] = entry['sha256']
    return hashes


def verify_bundle(manifest, root, platform):
    roots = ['data/flutter_assets/assets/reader/vendor', 'share/licenses/unrar']
    if platform == 'windows':
        roots.append('licenses/webview2-sdk')
    verify_files(root, bundle_hashes(manifest, platform), roots)


def archive_files(path, kind):
    if kind == 'zip':
        with zipfile.ZipFile(path) as archive:
            result = {}
            for info in archive.infolist():
                if info.is_dir():
                    continue
                name = relative(info.filename)
                if name in result or (info.external_attr >> 16) & 0o170000 == 0o120000:
                    raise VerificationError(f'Duplicate or linked archive member: {name}')
                result[name] = archive.read(info)
            return result
    with tarfile.open(path, 'r:gz') as archive:
        result = {}
        for info in archive.getmembers():
            if info.isdir():
                continue
            name = relative(info.name)
            if not info.isfile() or name in result:
                raise VerificationError(f'Duplicate or non-file archive member: {name}')
            result[name] = archive.extractfile(info).read()
        return result


def verified_archive(source, path):
    if digest(Path(path).read_bytes()) != source['sha256']:
        raise VerificationError(f'Official archive checksum mismatch: {path}')
    return archive_files(path, source['kind'])


def verify_upstream(manifest, inputs):
    for source_id, path in inputs.items():
        source = manifest['sources'].get(source_id) or manifest.get('buildInputs', {}).get(source_id)
        if source is None:
            raise VerificationError(f'Unknown upstream source: {source_id}')
        entries = [(name, entry) for name, entry in manifest['provenance'].items() if entry['source'] == source_id]
        if source['kind'] == 'git':
            for name, entry in entries:
                try:
                    data = subprocess.check_output(['git', '-C', str(path), 'show', source['revision'] + ':' + entry['path']], stderr=subprocess.PIPE)
                except subprocess.CalledProcessError as error:
                    raise VerificationError(f'Pinned Git source unavailable: {source_id}/{entry["path"]}') from error
                blob = git_blob(data)
                if blob != entry['gitBlob'] or digest(data) != manifest['sha256'][name]:
                    raise VerificationError(f'Official Git file differs: {source_id}/{entry["path"]}')
        else:
            contents = verified_archive(source, path)
            for name, entry in entries:
                data = Path(path).read_bytes() if entry.get('archiveItself') else contents.get(entry['path'])
                if data is None or digest(data) != manifest['sha256'][name]:
                    raise VerificationError(f'Official archive file differs: {source_id}/{entry["path"]}')
            for notice in manifest['bundleNotices']:
                if notice['source'] == source_id:
                    data = contents.get(notice['path'])
                    if data is None or digest(data) != notice['sha256']:
                        raise VerificationError(f'Official notice differs: {source_id}/{notice["path"]}')


def verify_extracted(source, archive, directory, prefix=''):
    contents = verified_archive(source, archive)
    contents = {name[len(prefix):]: data for name, data in contents.items() if name.startswith(prefix)}
    if not contents:
        raise VerificationError(f'No upstream files under prefix: {prefix}')
    expected = {name: digest(data) for name, data in contents.items()}
    directory = Path(directory)
    if not directory.is_dir():
        raise VerificationError(f'Missing extracted dependency: {directory}')
    found = set()
    for item in directory.rglob('*'):
        if item.is_symlink():
            raise VerificationError(f'Linked extracted dependency entry: {item}')
        if item.is_file():
            found.add(item.relative_to(directory).as_posix())
    if found != set(expected):
        raise VerificationError(f'Extracted dependency inventory differs: {directory}')
    for name, expected_hash in expected.items():
        if digest((directory / name).read_bytes()) != expected_hash:
            raise VerificationError(f'Modified extracted dependency: {directory / name}')


def verify_build(manifest, repository, build, platform):
    repository, build = Path(repository), Path(build)
    verify_extracted(manifest['sources']['unrar'], repository / 'native/vendor/unrar/unrarsrc-7.2.6.tar.gz', build / 'comic-decoder/unrar-source/unrar', 'unrar/')
    if platform == 'windows':
        archives = list((build / '_deps/webview2_sdk-subbuild').rglob('webview2.zip'))
        if len(archives) != 1:
            raise VerificationError('The exact downloaded WebView2 SDK archive must remain in the build tree')
        verify_extracted(manifest['buildInputs']['webview2'], archives[0], build / '_deps/webview2_sdk-src')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--bundle', type=Path)
    parser.add_argument('--platform', choices=['linux', 'windows'])
    parser.add_argument('--build-tree', type=Path)
    parser.add_argument('--upstream', action='append', default=[], metavar='SOURCE=PATH')
    args = parser.parse_args(argv)
    if (args.bundle or args.build_tree) and not args.platform:
        parser.error('--bundle/--build-tree requires --platform')
    try:
        manifest = load_manifest(args.manifest or args.repository / 'tools/vendor-manifest.json')
        verify_repository(manifest, args.repository)
        if args.bundle:
            verify_bundle(manifest, args.bundle, args.platform)
        if args.build_tree:
            verify_build(manifest, args.repository, args.build_tree, args.platform)
        inputs = {}
        for value in args.upstream:
            source, separator, filename = value.partition('=')
            if not separator or source in inputs:
                raise VerificationError('Each --upstream must uniquely identify SOURCE=PATH')
            inputs[source] = Path(filename)
        verify_upstream(manifest, inputs)
        print(json.dumps({'status': 'passed', 'upstreamFiles': len(manifest['sha256']), 'bundle': str(args.bundle) if args.bundle else None, 'buildTree': str(args.build_tree) if args.build_tree else None, 'authoritativeSources': sorted(inputs)}))
        return 0
    except (VerificationError, KeyError, TypeError, ValueError, OSError, zipfile.BadZipFile, tarfile.TarError) as error:
        print(f'Vendor verification failed: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
