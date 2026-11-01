// Real current-schema round trips at both resource boundaries, disposable data.
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/core/reading_preferences.dart';

Future<Map<String, dynamic>> runBackupContractScenario() async {
  const recordLimit = 100000, byteLimit = 128 * 1024 * 1024;
  // Capacity fixtures can exceed a small system temp volume. Keep the same
  // real storage/round-trip checks while allowing an explicit spacious parent.
  final parent = Platform.environment['BUSYBOOKS_BACKUP_FIXTURE_PARENT'];
  final owned =
      await (parent == null ? Directory.systemTemp : Directory(parent))
          .createTemp('busybooks-backup-contract-');
  var checks = 0;
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
    checks++;
  }

  Database connect(String root) {
    final db = sqlite3.open(p.join(root, 'reading-data.sqlite'));
    db.execute('PRAGMA foreign_keys=ON');
    check(
      db.select('PRAGMA foreign_keys').single.values.single == 1,
      'foreign keys',
    );
    return db;
  }

  Future<Map<String, dynamic>> manifest(String path) async =>
      (jsonDecode(
                utf8.decode(
                  ZipDecoder()
                      .decodeBytes(await File(path).readAsBytes())
                      .files
                      .single
                      .content,
                ),
              )
              as Map)
          .cast<String, dynamic>();
  Future<int> encodedSize(String path) async {
    final input = InputFileStream(path);
    try {
      return (ZipDirectory()..read(input)).fileHeaders.single.uncompressedSize;
    } finally {
      await input.close();
    }
  }

  Future<void> rejected(ReadingDataStore store, String path) async {
    final before = await sha256.bind(File(path).openRead()).first;
    final sourceBefore = logicalReadingDigest(store.root);
    final pending = await store.call('pendingPreferences');
    var failed = false;
    try {
      await store.call('backup', {
        'path': path,
        'preferences': {'theme': 'dark'},
        'overwrite': true,
      });
    } on StateError catch (error) {
      if (!error.message.toString().contains('Reading-data backup exceeds')) {
        rethrow;
      }
      failed = true;
    }
    check(failed, 'unsupported backup must fail');
    check(
      logicalReadingDigest(store.root) == sourceBefore,
      'rejected export preserves every source record',
    );
    check(
      await sha256.bind(File(path).openRead()).first == before,
      'previous backup preserved',
    );
    check(
      jsonEncode(await store.call('pendingPreferences')) == jsonEncode(pending),
      'settings replay unchanged',
    );
  }

  Future<(ReadingDataStore, String)> initial(String root) async {
    final file = await File(
      'test/fixtures/text.pdf',
    ).copy(p.join(owned.path, '${p.basename(root)}.pdf'));
    final store = await ReadingDataStore.open(root);
    final id =
        (((await store.call('openPath', {'path': file.path})) as Map)['books']
                    as List)
                .single['id']
            as String;
    final collection =
        await store.call('createCollection', {'name': 'Contract collection'})
            as Map;
    await store.call('addBooks', {
      'collectionId': collection['id'],
      'paths': [file.path],
    });
    await store.call('updateBook', {
      'id': id,
      'changes': {
        'read': 123,
        'progress': .25,
        'state': 'reading',
        'anchor': {'page': 0},
      },
    });
    await file.delete();
    return (store, id);
  }

  Future<void> restoreAndCheck(
    String archive,
    String root,
    String id,
    int expectedRecords,
    String sourceRoot,
  ) async {
    final restored = await ReadingDataStore.open(root);
    try {
      final prefs = await restored.call('restore', archive) as Map;
      check(
        jsonEncode(prefs) ==
            jsonEncode(normalizeAppPreferences({'theme': 'dark'})),
        'all preferences round trip',
      );
      check(
        (await restored.call('pendingPreferences') as Map)['theme'] == 'dark',
        'replay awaits acknowledgement',
      );
      final book = await restored.call('book', id) as Map;
      check(
        book['read'] == 123 &&
            book['progress'] == .25 &&
            book['anchor']['page'] == 0,
        'reading state round trip',
      );
      final collections = await restored.call('collections') as List;
      final collection = collections.singleWhere(
        (c) => c['name'] == 'Contract collection',
      );
      final members =
          (await restored.call('openCollection', {
                    'id': collection['id'],
                    'recordRecent': false,
                  })
                  as Map)['books']
              as List;
      check(
        members.single['id'] == id && members.single['path'] == book['path'],
        'membership and missing location references',
      );
      await restored.call('acknowledgePreferences');
      check(
        await restored.call('pendingPreferences') == null,
        'acknowledgement',
      );
    } finally {
      await restored.close();
    }
    check(
      logicalReadingDigest(root) == logicalReadingDigest(sourceRoot),
      'every logical record round trips, with restored paths unverified',
    );
    final db = connect(root);
    try {
      final total = db
          .select(
            "SELECT (SELECT count(*) FROM records WHERE kind IN ('book','annotation'))+(SELECT count(*) FROM collections)+(SELECT count(*) FROM memberships)+(SELECT count(*) FROM locations)+(SELECT count(*) FROM recent_resources) AS n",
          )
          .single['n'];
      check(total == expectedRecords, 'all record categories round trip');
      check(
        db
            .select('SELECT status,verified FROM locations')
            .every((r) => r['status'] == 'unverified' && r['verified'] == null),
        'restored locations stay references',
      );
    } finally {
      db.close();
    }
  }

  ReadingDataStore? active;
  try {
    final root = p.join(owned.path, 'count-source');
    final initialValue = await initial(root);
    active = initialValue.$1;
    final id = initialValue.$2;
    await active.call('putAnnotation', {
      'id': 'annotation-contract',
      'bookId': id,
      'annotationKind': 'bookmark',
      'anchor': {'page': 0},
      'text': '',
      'note': 'Private note',
      'color': 'yellow',
      'created': 1,
    });
    final target = p.join(owned.path, 'counts.busybooks');
    await active.call('backup', {
      'path': target,
      'preferences': {'theme': 'dark'},
    });
    final base = (await manifest(target))['records'] as List;
    await active.close();
    active = null;
    final db = connect(root);
    try {
      db.execute('BEGIN');
      final insert = db.prepare(
        'INSERT INTO collections(id,name,created) VALUES(?,?,?)',
      );
      try {
        for (var i = base.length; i < recordLimit - 1; i++) {
          insert.execute([
            'collection:${i.toRadixString(16).padLeft(32, '0')}',
            'Boundary $i',
            1,
          ]);
        }
      } finally {
        insert.close();
      }
      db.execute('COMMIT');
    } finally {
      db.close();
    }
    for (final size in [recordLimit - 1, recordLimit, recordLimit + 1]) {
      if (size > recordLimit - 1) {
        final more = connect(root);
        try {
          more.execute(
            'INSERT INTO collections(id,name,created) VALUES(?,?,?)',
            [
              'collection:${size.toRadixString(16).padLeft(32, '0')}',
              'Boundary $size',
              1,
            ],
          );
        } finally {
          more.close();
        }
      }
      active = await ReadingDataStore.open(root);
      if (size <= recordLimit) {
        await active.call('backup', {
          'path': target,
          'preferences': {'theme': 'dark'},
          'overwrite': true,
        });
        check(
          ((await manifest(target))['records'] as List).length == size,
          'combined record boundary $size',
        );
        await restoreAndCheck(
          target,
          p.join(owned.path, 'count-restored-$size'),
          id,
          size,
          root,
        );
      } else {
        await rejected(active, target);
        check(
          (await active.call('collections') as List).length ==
              size - (base.length - 1),
          'rejected export keeps source collections',
        );
      }
      await active.close();
      active = null;
    }
    final byteRoot = p.join(owned.path, 'byte-source');
    final byteInitial = await initial(byteRoot);
    active = byteInitial.$1;
    final byteId = byteInitial.$2;
    final byteTarget = p.join(owned.path, 'bytes.busybooks');
    await active.call('backup', {
      'path': byteTarget,
      'preferences': {'theme': 'dark'},
    });
    final byteManifest = await manifest(byteTarget);
    final rows = List<Map<String, dynamic>>.generate(
      135,
      (i) => {
        'id': 'annotation-byte-$i',
        'bookId': byteId,
        'annotationKind': 'highlight',
        'anchor': {'page': 0},
        'text': '',
        'note': '',
        'color': 'yellow',
        'created': i,
        'kind': 'annotation',
      },
    );
    final records = (byteManifest['records'] as List);
    // Backup serializes annotations immediately after books.
    records.insertAll(1, rows);
    var remaining =
        byteLimit - 1 - utf8.encode(jsonEncode(byteManifest)).length;
    for (final row in rows) {
      final count = remaining.clamp(0, 1000000);
      row['note'] = 'X' * count;
      remaining -= count;
    }
    check(remaining == 0, 'bounded note fixture reaches encoded limit');
    await active.close();
    active = null;
    final byteDb = connect(byteRoot);
    try {
      byteDb.execute('BEGIN');
      final insert = byteDb.prepare(
        'INSERT INTO records(id,kind,book_id,json) VALUES(?,?,?,?)',
      );
      try {
        for (final row in rows) {
          insert.execute([row['id'], 'annotation', byteId, jsonEncode(row)]);
        }
      } finally {
        insert.close();
      }
      byteDb.execute('COMMIT');
    } finally {
      byteDb.close();
    }
    for (final size in [byteLimit - 1, byteLimit, byteLimit + 1]) {
      active = await ReadingDataStore.open(byteRoot);
      if (size > byteLimit - 1) {
        final last = rows.last;
        last['note'] = '${last['note']}X';
        await active.call('updateAnnotation', {
          'id': last['id'],
          'bookId': byteId,
          'changes': {'note': last['note']},
        });
      }
      final sourceBefore = logicalReadingDigest(byteRoot);
      if (size <= byteLimit) {
        await active.call('backup', {
          'path': byteTarget,
          'preferences': {'theme': 'dark'},
          'overwrite': true,
        });
        check(await encodedSize(byteTarget) == size, 'encoded boundary $size');
        final restoredRoot = p.join(owned.path, 'byte-restored-$size');
        await restoreAndCheck(
          byteTarget,
          restoredRoot,
          byteId,
          records.length,
          byteRoot,
        );
        final restoredDb = connect(restoredRoot);
        try {
          final notes = restoredDb.select(
            "SELECT id,length(json_extract(json,'\$.note')) AS n,replace(json_extract(json,'\$.note'),'X','') AS other FROM records WHERE kind='annotation'",
          );
          check(notes.length == rows.length, 'all annotations restored');
          final expected = {
            for (final row in rows) row['id']: (row['note'] as String).length,
          };
          check(
            notes.every((r) => r['n'] == expected[r['id']] && r['other'] == ''),
            'all private notes equivalent',
          );
        } finally {
          restoredDb.close();
        }
        await Directory(restoredRoot).delete(recursive: true);
      } else {
        await rejected(active, byteTarget);
      }
      check(
        logicalReadingDigest(byteRoot) == sourceBefore,
        'export leaves all source reading data intact',
      );
      await active.close();
      active = null;
    }
    return {
      'status': 'passed',
      'checks': checks,
      'scope':
          'real SQLite and data-only archive round trips below/at/above combined 100000 records and encoded 128 MiB; rejected publication preserves source and previous backup',
    };
  } finally {
    await active?.close();
    await owned.delete(recursive: true);
  }
}

class _ReadingDigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) => value = digest;
  @override
  void close() {}
}

String logicalReadingDigest(String root) {
  final db = sqlite3.open(p.join(root, 'reading-data.sqlite'));
  try {
    db.execute('PRAGMA foreign_keys=ON');
    if (db.select('PRAGMA foreign_keys').single.values.single != 1) {
      throw StateError('Foreign keys unavailable');
    }
    db.execute('BEGIN');
    final output = _ReadingDigestSink();
    final sink = sha256.startChunkedConversion(output);
    for (final query in [
      "SELECT id,kind,book_id,json FROM records WHERE kind IN ('book','annotation') ORDER BY id",
      'SELECT id,name,created FROM collections ORDER BY id',
      'SELECT collection_id,book_id,added FROM memberships ORDER BY collection_id,book_id',
      "SELECT book_id,path,'unverified',NULL,preferred FROM locations ORDER BY book_id,path",
      'SELECT kind,resource_id,opened FROM recent_resources ORDER BY kind,resource_id',
    ]) {
      final statement = db.prepare(query);
      try {
        final rows = statement.selectCursor();
        while (rows.moveNext()) {
          sink.add(utf8.encode(jsonEncode(rows.current.values.toList())));
          sink.add([10]);
        }
      } finally {
        statement.close();
      }
    }
    sink.close();
    db.execute('COMMIT');
    return output.value.toString();
  } finally {
    db.close();
  }
}
