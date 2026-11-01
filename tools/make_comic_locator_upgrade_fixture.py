#!/usr/bin/env python3
"""Record a real current-data profile made by the pre-review implementation.

Uses the existing pinned package configuration, local Git objects and CC0 books.
No network, installed profile or original publication is changed. The resulting
SQL snapshot is a test fixture, never an application import format.
"""
import io
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LEGACY_REVISION = '852bd74'
PRE_REPAIR_REVISION = 'b36f6fb'
OUTPUT = ROOT / 'test/fixtures/reading-data'

HARNESS = r'''
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:busybooks/src/library/data/library_store.dart';

Future<void> main(List<String> args) async {
  final store = await ReadingDataStore.open(args[0]);
  try {
    if (args[1] == 'seed') {
      final records = <Map<String, dynamic>>[];
      for (final (format, filename) in [
        ('cbz', 'formats/comic-stored.cbz'),
        ('cbr', 'formats/comic-rar5-solid.cbr'),
        ('pdf', 'text.pdf'),
      ]) {
        final id = sha256.convert(await File('${args[2]}/$filename').readAsBytes()).toString();
        final anchor = format == 'pdf'
            ? {'page': 0, 'point': [22, 44]}
            : {'kind': 'comic', 'version': 1, 'format': format, 'page': 0,
                'pageId': sha256.convert(utf8.encode('pages/Page1.jpg')).toString(),
                'position': [.25, .5], 'point': []};
        records.add({'kind': 'book', 'id': id, 'format': format,
          'title': 'Legacy $format fixture', 'author': 'BusyBooks Fixtures',
          'state': 'reading', 'paths': ['/busybooks-fixture-originals/$filename'],
          'added': 1700000000000, 'anchor': anchor,
          'outline': [{'id': 'outline:0', 'label': 'First page', 'anchor': anchor}]});
        records.add({'kind': 'location', 'book_id': id,
          'path': '/busybooks-fixture-originals/$filename', 'status': 'unverified',
          'preferred': 1, 'verified': null});
        if (format == 'pdf') {
          records.add({'kind': 'annotation', 'id': 'annotation-legacy-pdf',
            'bookId': id, 'annotationKind': 'highlight', 'anchor': anchor,
            'text': 'Original quoted text — unchanged.', 'note': 'PDF point stays intact.',
            'color': 'yellow', 'reference': 'Page 1', 'created': 1700000000001});
        } else {
          for (var i = 0; i < 3; i++) {
            final location = {...anchor};
            if (i == 1) location.remove('point');
            if (i < 2) location['region'] = [.1, .2, .3, .4];
            records.add({'kind': 'annotation', 'id': 'annotation-legacy-$format-$i',
              'bookId': id, 'annotationKind': i < 2 ? 'region' : 'bookmark',
              'anchor': location, 'text': '', 'note': 'Private $format note $i — <&> original.',
              'color': 'blue', 'reference': 'Page 1', 'created': 1700000000001 + i});
          }
        }
      }
      final manifest = utf8.encode(jsonEncode({'type': 'busybooks-reading-data',
        'schema': 3, 'records': records, 'preferences': {}}));
      final incoming = '${args[0]}/incoming.busybooks';
      await File(incoming).writeAsBytes(ZipEncoder().encode(Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))));
      await store.call('restore', incoming);
      for (final format in ['cbz', 'cbr']) {
        final note = records.singleWhere((r) => r['id'] == 'annotation-legacy-$format-0');
        await store.call('updateAnnotation', {'id': note['id'], 'bookId': note['bookId'],
          'changes': {'note': 'Edited in previous implementation — $format.', 'color': 'pink'}});
      }
      final backup = '${args[0]}/previous.busybooks';
      await store.call('backup', {'path': backup, 'preferences': {}});
      final archive = ZipDecoder().decodeBytes(await File(backup).readAsBytes());
      await File(args[3]).writeAsString('${const JsonEncoder.withIndent('  ').convert(
        jsonDecode(utf8.decode(archive.single.content)))}\n');
      print(jsonEncode({'stage': 'previous implementation', 'restore': true,
        'edits': 2, 'backup': true, 'records': records.length}));
    } else {
      final failures = <String, String>{};
      final state = jsonDecode(await File(args[2]).readAsString()) as Map;
      final note = (state['records'] as List).singleWhere(
        (r) => r['id'] == 'annotation-legacy-cbz-0') as Map;
      for (final action in ['updateAnnotation', 'backup']) {
        try {
          await store.call(action, action == 'backup'
              ? {'path': '${args[0]}/blocked.busybooks', 'preferences': {}}
              : {'id': note['id'], 'bookId': note['bookId'], 'changes': {'note': 'Blocked edit'}});
          throw StateError('$action unexpectedly succeeded before the repair');
        } catch (error) {
          if (!error.toString().contains('comic locator fields')) rethrow;
          failures[action] = error.toString();
        }
      }
      print(jsonEncode({'stage': 'strict validator before repair', 'failures': failures}));
    }
  } finally {
    await store.close();
  }
}
'''


def checkout(revision, owned):
    source = owned / revision
    source.mkdir()
    archive = subprocess.check_output(
        ['git', 'archive', revision, 'lib', 'pubspec.yaml', 'pubspec.lock'], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(source, filter='data')
    config = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
    for package in config['packages']:
        if package['name'] == 'busybooks':
            package['rootUri'] = source.as_uri() + '/'
        elif not package['rootUri'].startswith('file:'):
            raise RuntimeError('Use the persistent pinned package configuration')
    (source / '.dart_tool').mkdir()
    (source / '.dart_tool/package_config.json').write_text(json.dumps(config))
    (source / 'upgrade_fixture.dart').write_text(HARNESS)
    # Pub's dependency graph is required for sqlite3's native asset hook.
    subprocess.run(['flutter', 'pub', 'get', '--offline', '--enforce-lockfile'],
                   cwd=source, check=True)
    return source


if __name__ == '__main__':
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='busybooks-previous-comic-store-') as directory:
        owned = Path(directory)
        previous = checkout(LEGACY_REVISION, owned)
        profile = owned / 'previous-profile'
        backup_json = OUTPUT / 'comic-locator-previous-backup.json'
        subprocess.run(['dart', 'run', 'upgrade_fixture.dart', str(profile), 'seed',
                        str(ROOT / 'test/fixtures'), str(backup_json)], cwd=previous, check=True)
        with sqlite3.connect(profile / 'reading-data.sqlite') as database:
            version = database.execute('PRAGMA user_version').fetchone()[0]
            snapshot = f'PRAGMA user_version={version};\n' + '\n'.join(database.iterdump()) + '\n'
        (OUTPUT / 'comic-locator-previous-profile.sql').write_text(snapshot)
        before_repair = checkout(PRE_REPAIR_REVISION, owned)
        unchanged = owned / 'strict-profile'
        shutil.copytree(profile, unchanged)
        subprocess.run(['dart', 'run', 'upgrade_fixture.dart', str(unchanged), 'check',
                        str(backup_json)], cwd=before_repair, check=True)
        names = ['comic-locator-previous-backup.json', 'comic-locator-previous-profile.sql']
        (OUTPUT / 'SHA256SUMS').write_text(''.join(
            f'{hashlib.sha256((OUTPUT / name).read_bytes()).hexdigest()}  {name}\n'
            for name in names))
