// Real SQLite worker + disposable originals. No native-rendering claims.
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Map<String, dynamic>> runFileWorkspaceScenario() async {
  final owned = await Directory.systemTemp.createTemp('busybooks-db-model-');
  ReadingDataStore? store, restored;
  var checks = 0;
  void check(bool value, String message) {
    if (!value) throw StateError(message);
    checks++;
  }

  Future<void> rejects(
    Future<dynamic> Function() action,
    String message,
  ) async {
    try {
      await action();
    } catch (_) {
      checks++;
      return;
    }
    throw StateError(message);
  }

  Future<File> fixture(String name, String dir) async {
    final file = File(p.join(owned.path, dir, name));
    await file.parent.create(recursive: true);
    return File('test/fixtures/$name').copy(file.path);
  }

  try {
    final epub = await fixture('reflowable.epub', 'originals-a'),
        pdf = await fixture('text.pdf', 'originals-b');
    final epubBytes = await epub.readAsBytes(),
        pdfBytes = await pdf.readAsBytes();
    final oldManifest = File(p.join(epub.parent.path, '.busybooks.json'));
    await oldManifest.writeAsString('preserve user data, never parse');
    store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
    final first = await store.call('openPath', {'path': epub.path}) as Map;
    final id = (first['books'] as List).single['id'] as String;
    final pdfOpen = await store.call('openPath', {'path': pdf.path}) as Map;
    final pdfId = (pdfOpen['books'] as List).single['id'] as String;
    check(id == sha256.convert(epubBytes).toString(), 'SHA-256 identity');
    check(pdfId == sha256.convert(pdfBytes).toString(), 'PDF SHA-256');
    check(
      !await Directory(p.join(owned.path, 'profile', 'books')).exists(),
      'no managed copies',
    );
    await rejects(
      () => store!.call('openPath', {'path': epub.parent.path}),
      'directories unsupported',
    );
    await rejects(
      () => store!.call('openPath', {'path': oldManifest.path}),
      'manifests unsupported',
    );
    check(
      await oldManifest.readAsString() == 'preserve user data, never parse',
      'old manifest untouched',
    );
    final a = await store.call('createCollection', {'name': 'Research'}) as Map;
    final b = await store.call('createCollection', {'name': 'Research'}) as Map;
    final aId = a['id'] as String, bId = b['id'] as String;
    check(aId != bId, 'same names do not merge');
    check(a['path'] == null, 'collections have no filesystem identity');
    check((a['books'] as List).isEmpty, 'empty collection');
    final added =
        await store.call('addBooks', {
              'collectionId': aId,
              'paths': [
                epub.path,
                p.join(owned.path, 'bad.pdf'),
                pdf.path,
                epub.path,
              ],
            })
            as Map;
    check(
      (added['results'] as List).where((r) => r['status'] == 'failed').length ==
          1,
      'per-file failures isolated',
    );
    check(
      ((added['workspace'] as Map)['books'] as List).length == 2,
      'unique content membership',
    );
    await store.call('addBooks', {
      'collectionId': bId,
      'paths': [epub.path],
    });
    final anchor = {'cfi': 'epubcfi(/6/2!/4/2/1:6)', 'index': 0};
    await store.call('updateBook', {
      'id': id,
      'changes': {
        'anchor': anchor,
        'progress': .4,
        'state': 'reading',
        'appearance': {'size': 22},
      },
    });
    final annotation = <String, dynamic>{
      'id': 'annotation-fixture-1',
      'bookId': id,
      'annotationKind': 'highlight',
      'anchor': anchor,
      'text': 'Original quotation',
      'note': 'Private\nmultiline note',
      'reference': 'Chapter 1',
      'color': 'yellow',
      'created': 1,
    };
    await store.call('putAnnotation', annotation);
    final bookmark = {
      ...annotation,
      'id': 'annotation-fixture-2',
      'annotationKind': 'bookmark',
      'text': '',
      'note': 'Bookmark note',
    };
    await store.call('putAnnotation', bookmark);
    check(
      (await store.call('annotations', id) as List).length == 2,
      'shared annotation records',
    );
    check(
      (await store.call('annotations', pdfId) as List).isEmpty,
      'book-scoped query',
    );
    await rejects(
      () => store!.call('putAnnotation', {...annotation, 'id': id}),
      'annotation cannot replace a book',
    );
    await rejects(
      () => store!.call('putAnnotation', {
        ...annotation,
        'anchor': {'page': 0},
      }),
      'format-specific anchors',
    );
    await rejects(
      () => store!.call('putAnnotation', {
        ...annotation,
        'annotationKind': 'standalone',
      }),
      'annotation types',
    );
    await rejects(
      () => store!.call('putAnnotation', {...annotation, 'color': 'invalid'}),
      'palette validation',
    );
    await store.call('renameCollection', {'id': aId, 'name': 'Renamed'});
    final renamed = await store.call('openCollection', {'id': aId}) as Map;
    check(
      renamed['id'] == aId && renamed['name'] == 'Renamed',
      'rename keeps identity',
    );
    check(
      (renamed['books'] as List).first['progress'] == .4,
      'shared reading state in collection',
    );
    final copy = await epub.copy(p.join(owned.path, 'same.epub'));
    final same = await store.call('openPath', {'path': copy.path}) as Map;
    check(
      (same['books'] as List).single['id'] == id,
      'identical content shares identity',
    );
    await store.call('addBooks', {
      'collectionId': aId,
      'paths': [copy.path],
    });
    check(
      ((await store.call('openCollection', {'id': aId}) as Map)['books']
                  as List)
              .length ==
          2,
      'copies do not duplicate membership',
    );
    final recent = (await store.call('snapshot') as Map)['recent'] as List;
    check(
      recent
              .where(
                (r) => r['resourceKind'] == 'book' && r['resourceId'] == id,
              )
              .length ==
          1,
      'one book Recent across paths/collections',
    );
    check(
      recent.any(
        (r) =>
            r['resourceKind'] == 'collection' &&
            r['resourceId'] == aId &&
            r['title'] == 'Renamed',
      ),
      'recent rename updates',
    );
    await store.call('forgetRecent', {'kind': 'collection', 'id': bId});
    check(
      (await store.call('collections') as List).length == 2,
      'chooser includes nonrecent collections',
    );
    await store.call('removeBook', {'collectionId': aId, 'bookId': id});
    check(
      ((await store.call('openCollection', {'id': bId}) as Map)['books']
                  as List)
              .length ==
          1,
      'other membership survives',
    );
    check(
      (await store.call('annotations', id) as List).length == 2,
      'removal keeps annotations',
    );
    await store.call('deleteCollection', aId);
    check(
      (await store.call('collections') as List).length == 1,
      'delete collection',
    );
    check(
      (await store.call('annotations', id) as List).length == 2,
      'collection deletion keeps reading data',
    );
    check(
      await epub.readAsBytes().then(
        (b) => sha256.convert(b) == sha256.convert(epubBytes),
      ),
      'original unchanged',
    );
    await store.call('relocate', {'id': id, 'path': epub.path});
    await rejects(
      () => store!.call('relocate', {'id': id, 'path': pdf.path}),
      'wrong replacement rejected',
    );
    final moved = await epub.rename(p.join(owned.path, 'external.epub'));
    await copy.delete();
    check(
      (await store.call('book', id) as Map)['status'] == 'missing',
      'missing original retained',
    );
    check(
      (await store.call('annotations', id) as List).length == 2,
      'missing original Notebook query',
    );
    await store.call('updateAnnotation', {
      'id': annotation['id'],
      'bookId': id,
      'changes': {'note': 'Edited while missing'},
    });
    final md = p.join(owned.path, 'notebook.md');
    await store.call('exportMarkdown', {
      'id': id,
      'path': md,
      'overwrite': false,
    });
    final markdown = await File(md).readAsString();
    check(
      markdown.contains('Edited while missing') &&
          markdown.contains('Original quotation'),
      'missing original Markdown export',
    );
    check(
      !markdown.contains('> Bookmark note'),
      'no fabricated bookmark quotation',
    );
    await rejects(
      () => store!.call('backup', {
        'path': epub.path,
        'preferences': {},
        'overwrite': true,
      }),
      'backup cannot write to a missing saved original location',
    );
    check(
      !await File(epub.path).exists(),
      'missing original is not recreated by backup',
    );
    final ownedCover = (await store.call('book', id) as Map)['cover'];
    await store.call('updateBook', {
      'id': id,
      'changes': {'coverEdited': true},
    });
    final backup = p.join(owned.path, 'reading.busybooks');
    await store.call('backup', {
      'path': backup,
      'preferences': {'theme': 'dark'},
      'overwrite': false,
    });
    final zip = ZipDecoder().decodeBytes(await File(backup).readAsBytes());
    check(
      zip.files.length == 1 && zip.files.single.name == 'manifest.json',
      'data-only archive',
    );
    final manifest = jsonDecode(utf8.decode(zip.files.single.content)) as Map;
    check(manifest['schema'] == 3, 'changed backup schema');
    final records = manifest['records'] as List;
    check(
      records.singleWhere(
            (r) => r['kind'] == 'book' && r['id'] == id,
          )['cover'] ==
          ownedCover,
      'edited cover metadata is backed up without originals',
    );
    check(
      !records.any((r) => ['definition', 'move'].contains(r['kind'])),
      'no old definitions or executable recovery',
    );
    check(
      records.any((r) => r['kind'] == 'collection' && r['id'] == bId),
      'collection IDs in backup',
    );
    check(
      records.any((r) => r['kind'] == 'membership' && r['book_id'] == id),
      'membership in backup',
    );
    restored = await ReadingDataStore.open(p.join(owned.path, 'restored'));
    await restored.call('restore', backup);
    check(
      (await restored.call('annotations', id) as List).length == 2,
      'annotations restored without originals',
    );
    check(
      (await restored.call('collections') as List).single['id'] == bId,
      'collection identity restored',
    );
    check(
      (await restored.call('pendingPreferences') as Map)['theme'] == 'dark',
      'settings replay recorded',
    );
    await restored.call('acknowledgePreferences');
    check(
      await restored.call('pendingPreferences') == null,
      'settings replay acknowledgement',
    );
    await restored.call('addBooks', {
      'collectionId': bId,
      'paths': [pdf.path],
    });
    await restored.call('restore', backup);
    check(
      ((await restored.call('openCollection', {'id': bId}) as Map)['books']
                  as List)
              .length ==
          2,
      'logical restore preserves unrelated existing memberships',
    );
    final reconnected =
        await restored.call('relocate', {'id': id, 'path': moved.path}) as Map;
    check(
      reconnected['id'] == id && reconnected['path'] == moved.path,
      'Locate exact content',
    );
    check(
      ((await restored.call('openCollection', {'id': bId}) as Map)['books']
                  as List)
              .singleWhere((b) => b['id'] == id)['path'] ==
          moved.path,
      'Locate updates all collections',
    );
    final originalBefore = await moved.readAsBytes();
    for (final change in <Map<String, dynamic>>[
      {'cover': 42},
      {'cover': 'https://example.invalid/cover.png'},
      {'cover': 'data:image/png;base64,AAAA'},
      {'read': 'yesterday'},
      {'read': -1},
      {'read': 1.5},
      {'read': 8640000000000001},
      {'added': 'yesterday'},
      {'added': -1},
      {'added': 8640000000000001},
      {
        'appearance': {'size': 'large'},
      },
    ]) {
      final values = jsonDecode(jsonEncode(records)) as List;
      (values.firstWhere((r) => r['kind'] == 'book') as Map).addAll(change);
      final encoded = utf8.encode(
        jsonEncode({
          ...manifest,
          'records': values,
          'preferences': {'theme': 'dark'},
        }),
      );
      final archive = Archive()
        ..addFile(ArchiveFile('manifest.json', encoded.length, encoded));
      final path = p.join(owned.path, 'invalid-book.busybooks');
      await File(path).writeAsBytes(ZipEncoder().encode(archive));
      // A valid archive is already pending settings replay. Failed validation
      // must preserve every table and this pending acknowledgement together.
      final before = await readingDataDigest(restored);
      await rejects(
        () => restored!.call('restore', path),
        'malformed book metadata rejected',
      );
      check(
        await readingDataDigest(restored) == before,
        'failed book validation leaves every entity and pending settings replay unchanged',
      );
    }
    for (final mutate in <void Function(List)>[
      (v) => v.add({...annotation, 'id': id, 'kind': 'annotation'}),
      (v) => v.add({
        'kind': 'membership',
        'collection_id': bId,
        'book_id': 'b' * 64,
        'added': 1,
      }),
      (v) => v.add(<String, dynamic>{
        ...(records.firstWhere((r) => r['kind'] == 'membership') as Map)
            .cast<String, dynamic>(),
      }),
      (v) => v.add({
        ...annotation,
        'kind': 'annotation',
        'id': 'annotation-bad',
        'anchor': {'cfi': 'raw'},
      }),
      (v) => v.add({
        ...annotation,
        'kind': 'annotation',
        'id': 'annotation-bad',
        'color': 'raw',
      }),
      (v) => v.add({
        ...annotation,
        'kind': 'annotation',
        'id': 'annotation-bad',
        'bookId': pdfId,
        'anchor': {
          'page': 0,
          'point': ['not finite', 0],
        },
      }),
    ]) {
      final values = jsonDecode(jsonEncode(records)) as List;
      try {
        mutate(values);
        final encoded = utf8.encode(
          jsonEncode({...manifest, 'records': values}),
        );
        final archive = Archive()
          ..addFile(ArchiveFile('manifest.json', encoded.length, encoded));
        final path = p.join(owned.path, 'invalid.busybooks');
        await File(path).writeAsBytes(ZipEncoder().encode(archive));
        await rejects(
          () => restored!.call('restore', path),
          'unsafe restore rejected',
        );
      } on JsonUnsupportedObjectError {
        checks++;
      }
    }
    check(
      (await restored.call('annotations', id) as List).length == 2,
      'failed restore publishes nothing',
    );
    check(
      sha256.convert(await moved.readAsBytes()) ==
          sha256.convert(originalBefore),
      'restore leaves original bytes untouched',
    );
    final target = p.join(owned.path, 'move-destination.epub');
    await restored.call('moveBook', {
      'id': id,
      'source': moved.path,
      'destination': target,
    });
    check(
      !await moved.exists() && await File(target).exists(),
      'same-volume source removed',
    );
    check(
      await File(
        target,
      ).readAsBytes().then((b) => sha256.convert(b).toString() == id),
      'move destination verified',
    );
    check(
      (await restored.call('book', id) as Map)['path'] == target,
      'move location committed',
    );
    check(
      ((await restored.call('snapshot') as Map)['moves'] as List).isEmpty,
      'completed journal retired',
    );
    await rejects(
      () => restored!.call('moveBook', {
        'id': id,
        'source': target,
        'destination': pdf.path,
      }),
      'move no clobber',
    );
    check(
      (await File(pdf.path).readAsBytes()).length == pdfBytes.length,
      'collision preserves destination',
    );
    final noop =
        await restored.call('moveBook', {
              'id': id,
              'source': target,
              'destination': target,
            })
            as Map;
    check(noop['status'] == 'unchanged', 'same-path no-op');
    await store.close();
    store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
    check(
      (await store.call('collections') as List).single['id'] == bId,
      'database collections survive restart',
    );
    check(
      (await store.call('annotations', id) as List).length == 2,
      'notes survive restart',
    );
    return {
      'status': 'passed',
      'checks': checks,
      'scope':
          'real SQLite, original files, database collections, typed restoration and safe same-volume moves; no native rendering',
    };
  } finally {
    await store?.close();
    await restored?.close();
    await owned.delete(recursive: true);
  }
}

Future<String> readingDataDigest(ReadingDataStore store) async {
  await store.call('flush');
  final db = sqlite3.open(p.join(store.root, 'reading-data.sqlite'));
  try {
    db.execute('PRAGMA foreign_keys=ON');
    if (db.select('PRAGMA foreign_keys').single.values.single != 1) {
      throw StateError('Foreign keys unavailable');
    }
    db.execute('BEGIN');
    final values = [
      for (final table in [
        'records',
        'collections',
        'memberships',
        'locations',
        'recent_resources',
        'metadata',
      ])
        db
            .select('SELECT * FROM $table ORDER BY rowid')
            .map((row) => row.values.toList())
            .toList(),
    ];
    db.execute('COMMIT');
    return sha256.convert(utf8.encode(jsonEncode(values))).toString();
  } finally {
    db.close();
  }
}
