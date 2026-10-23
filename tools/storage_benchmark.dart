import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:busybooks/src/library/data/library_store.dart';

Future<void> main() async {
  final profile = await Directory.systemTemp.createTemp('busybooks-benchmark-');
  ReadingDataStore? store;
  final metrics = <String, Object>{
    'scope':
        'AOT original-file inspection and reading-data component; excludes native rendering and Flutter frame presentation',
  };
  try {
    final timer = Stopwatch()..start();
    store = await ReadingDataStore.open(profile.path);
    metrics['newProfileOpenMs'] = timer.elapsedMicroseconds / 1000;
    final names = [
      'long.epub',
      'long.pdf',
      'reflowable.epub',
      'fixed-layout.epub',
      'text.pdf',
      'image-only.pdf',
    ];
    final fixtures = names
        .map(
          (name) =>
              File(p.join(Directory.current.path, 'test', 'fixtures', name)),
        )
        .toList();
    metrics['fixtures'] = {
      for (final file in fixtures) p.basename(file.path): await file.length(),
    };
    timer.reset();
    for (final file in fixtures) {
      await store.call('openPath', {'path': file.path});
    }
    metrics['batchOpenMetadataMs'] = timer.elapsedMicroseconds / 1000;
    timer.reset();
    final snapshot = await store.call('snapshot') as Map;
    metrics['snapshotMs'] = timer.elapsedMicroseconds / 1000;
    final book =
        await store.call(
              'book',
              (snapshot['recent'] as List).firstWhere(
                (r) =>
                    r['resourceKind'] == 'book' && r['path'].endsWith('.pdf'),
              )['resourceId'],
            )
            as Map;
    final writes = <double>[];
    for (var i = 0; i < 30; i++) {
      book['anchor'] = {
        'page': i,
        'point': [200, 600],
      };
      book['progress'] = i / 400;
      timer.reset();
      await store.call('updateBook', {
        'id': book['id'],
        'changes': {'anchor': book['anchor'], 'progress': book['progress']},
      });
      writes.add(timer.elapsedMicroseconds / 1000);
    }
    writes.sort();
    metrics['positionCommitMedianMs'] = writes[15];
    metrics['positionCommitP95Ms'] = writes[28];
    await store.close();
    timer.reset();
    store = await ReadingDataStore.open(profile.path);
    await store.call('snapshot');
    metrics['resumeStoreAndSnapshotMs'] = timer.elapsedMicroseconds / 1000;
    timer.reset();
    await store.call('backup', {
      'path': p.join(profile.path, 'reading-data.busybooks'),
      'overwrite': false,
      'preferences': {'theme': 'system'},
    });
    metrics['backupMs'] = timer.elapsedMicroseconds / 1000;
    stdout.writeln(jsonEncode({'status': 'passed', 'metrics': metrics}));
  } finally {
    await store?.close();
    await profile.delete(recursive: true);
  }
}
