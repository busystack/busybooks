import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/data/record_validation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const fixtureRoot = 'test/fixtures/reading-data';

Future<void> previousProfile(String root) async {
  await Directory(root).create(recursive: true);
  final database = sqlite3.open(p.join(root, 'reading-data.sqlite'));
  try {
    // This is the actual closed schema-2 profile produced by commit 852bd74,
    // after restoring the affected notes, editing them and creating a backup.
    database.execute(
      await File(
        '$fixtureRoot/comic-locator-previous-profile.sql',
      ).readAsString(),
    );
  } finally {
    database.close();
  }
}

Map<String, String> storedJson(String root) {
  final database = sqlite3.open(p.join(root, 'reading-data.sqlite'));
  try {
    expect(database.select('PRAGMA user_version').single.values.single, 2);
    return {
      for (final row in database.select('SELECT id,json FROM records'))
        row['id'] as String: row['json'] as String,
    };
  } finally {
    database.close();
  }
}

dynamic withoutComicPoint(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key != 'point' ||
            value['kind'] != 'comic' ||
            value['version'] != 1)
          entry.key: withoutComicPoint(entry.value),
    };
  }
  if (value is List) return value.map(withoutComicPoint).toList();
  return value;
}

Future<File> backupFile(String path, Map manifest) => File(path).writeAsBytes(
  ZipEncoder().encode(
    Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest))),
  ),
);

void main() {
  test(
    'previous implementation → reopen → edit → backup → restore preserves notes',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-comic-upgrade-',
      );
      final root = p.join(owned.path, 'previous-profile');
      ReadingDataStore? store, restored;
      try {
        await previousProfile(root);
        final before = storedJson(root);
        final expected = {
          for (final entry in before.entries)
            entry.key: withoutComicPoint(jsonDecode(entry.value)) as Map,
        };
        store = await ReadingDataStore.open(root);
        final repaired = storedJson(root);
        expect(repaired.keys.toSet(), before.keys.toSet());
        for (final entry in repaired.entries) {
          expect(jsonDecode(entry.value), expected[entry.key]);
          if (before[entry.key] == jsonEncode(expected[entry.key])) {
            // Unaffected rows, including actual PDF points, are byte-identical.
            expect(entry.value, before[entry.key]);
          }
        }
        // Backup must work immediately, without first editing the affected note
        // and without an original publication being available.
        await store.call('backup', {
          'path': p.join(owned.path, 'before-edit.busybooks'),
          'preferences': {},
        });
        for (final (format, index) in [
          ('cbz', 0),
          ('cbz', 2),
          ('cbr', 0),
          ('cbr', 2),
        ]) {
          final id = 'annotation-legacy-$format-$index', note = expected[id]!;
          final anchor = jsonDecode(jsonEncode(note['anchor']));
          final edited =
              await store.call('updateAnnotation', {
                    'id': id,
                    'bookId': note['bookId'],
                    'changes': {'note': 'Edited after upgrade — $format <&>.'},
                  })
                  as Map;
          expect(edited['anchor'], anchor);
          expect(edited['text'], note['text']);
          expect(edited['id'], id);
          expect(edited['created'], note['created']);
          final colored =
              await store.call('updateAnnotation', {
                    'id': id,
                    'bookId': note['bookId'],
                    'changes': {'color': 'green'},
                  })
                  as Map;
          note['note'] = edited['note'];
          note['color'] = 'green';
          expect(colored, note);
        }
        final backup = p.join(owned.path, 'upgraded.busybooks');
        await store.call('backup', {'path': backup, 'preferences': {}});
        final archive = ZipDecoder().decodeBytes(
          await File(backup).readAsBytes(),
        );
        expect(archive.map((entry) => entry.name), ['manifest.json']);
        final manifest = jsonDecode(utf8.decode(archive.single.content)) as Map;
        final books = {
          for (final record in manifest['records'] as List)
            if (record['kind'] == 'book') record['id']: record,
        };
        for (final record in manifest['records'] as List) {
          if (record['kind'] == 'book') validateBook(record);
          if (record['kind'] == 'annotation') {
            validateAnnotation(record, books[record['bookId']]);
          }
        }
        restored = await ReadingDataStore.open(p.join(owned.path, 'restored'));
        await restored.call('restore', backup);
        final restoredRows = storedJson(restored.root);
        expect(restoredRows.keys.toSet(), expected.keys.toSet());
        for (final entry in restoredRows.entries) {
          expect(jsonDecode(entry.value), expected[entry.key]);
        }
        final after = storedJson(root);
        await store.close();
        store = await ReadingDataStore.open(root);
        expect(
          storedJson(root),
          after,
          reason: 'Repair is persisted/idempotent',
        );
      } finally {
        await store?.close();
        await restored?.close();
        await owned.delete(recursive: true);
      }
    },
  );

  test(
    'stored repair never sanitizes an incoming previous-version backup',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-comic-upgrade-restore-',
      );
      ReadingDataStore? store;
      try {
        await previousProfile(owned.path);
        store = await ReadingDataStore.open(owned.path);
        final before = storedJson(owned.path);
        final previous =
            jsonDecode(
                  await File(
                    '$fixtureRoot/comic-locator-previous-backup.json',
                  ).readAsString(),
                )
                as Map;
        for (final cleanBooks in [false, true]) {
          final incoming = jsonDecode(jsonEncode(previous)) as Map;
          if (cleanBooks) {
            // Also reach strict annotation validation after valid book records.
            incoming['records'] = [
              for (final record in incoming['records'] as List)
                record['kind'] == 'book' ? withoutComicPoint(record) : record,
            ];
          }
          final backup = await backupFile(
            p.join(owned.path, 'incoming-$cleanBooks.busybooks'),
            incoming,
          );
          await expectLater(
            store.call('restore', backup.path),
            throwsA(
              predicate(
                (error) => error.toString().contains('comic locator fields'),
              ),
            ),
          );
          expect(storedJson(owned.path), before);
        }
      } finally {
        await store?.close();
        await owned.delete(recursive: true);
      }
    },
  );

  test(
    'stored repair preserves invalid geometry and unknown locator versions',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-comic-upgrade-invalid-',
      );
      ReadingDataStore? store;
      try {
        await previousProfile(owned.path);
        final database = sqlite3.open(
          p.join(owned.path, 'reading-data.sqlite'),
        );
        final unchanged = <String, String>{};
        try {
          for (final (format, field, value) in [
            ('cbz', 'region', [-.1, .2, .3, .4]),
            ('cbr', 'version', 2),
          ]) {
            final id = 'annotation-legacy-$format-0';
            final record =
                jsonDecode(
                      database.select('SELECT json FROM records WHERE id=?', [
                            id,
                          ]).single['json']
                          as String,
                    )
                    as Map;
            record['anchor'][field] = value;
            unchanged[id] = jsonEncode(record);
            database.execute('UPDATE records SET json=? WHERE id=?', [
              unchanged[id],
              id,
            ]);
          }
        } finally {
          database.close();
        }
        store = await ReadingDataStore.open(owned.path);
        final after = storedJson(owned.path);
        for (final entry in unchanged.entries) {
          expect(after[entry.key], entry.value);
        }
      } finally {
        await store?.close();
        await owned.delete(recursive: true);
      }
    },
  );

  test(
    'interrupted batched repair rolls back all records and retries on reopen',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-comic-upgrade-atomic-',
      );
      ReadingDataStore? store;
      try {
        await previousProfile(owned.path);
        final database = sqlite3.open(
          p.join(owned.path, 'reading-data.sqlite'),
        );
        try {
          final template =
              jsonDecode(
                    database
                            .select(
                              "SELECT json FROM records WHERE id='annotation-legacy-cbz-0'",
                            )
                            .single['json']
                        as String,
                  )
                  as Map;
          for (var i = 0; i < 40; i++) {
            final record = {...template, 'id': 'annotation-legacy-batch-$i'};
            database.execute(
              'INSERT INTO records(id,kind,book_id,json) VALUES(?,?,?,?)',
              [
                record['id'],
                'annotation',
                record['bookId'],
                jsonEncode(record),
              ],
            );
          }
          database.execute(
            '''CREATE TRIGGER fail_repair BEFORE UPDATE OF json ON records
          WHEN old.id='annotation-legacy-batch-39'
          BEGIN SELECT RAISE(ABORT,'injected repair failure'); END''',
          );
        } finally {
          database.close();
        }
        final before = storedJson(owned.path);
        await expectLater(
          ReadingDataStore.open(owned.path),
          throwsA(
            predicate(
              (error) => error.toString().contains('injected repair failure'),
            ),
          ),
        );
        expect(storedJson(owned.path), before);
        final retry = sqlite3.open(p.join(owned.path, 'reading-data.sqlite'));
        retry.execute('DROP TRIGGER fail_repair');
        retry.close();
        store = await ReadingDataStore.open(owned.path);
        final after = storedJson(owned.path);
        expect(after.keys.toSet(), before.keys.toSet());
        for (final entry in after.entries) {
          expect(
            jsonDecode(entry.value),
            withoutComicPoint(jsonDecode(before[entry.key]!)),
          );
        }
      } finally {
        await store?.close();
        await owned.delete(recursive: true);
      }
    },
  );
}
