import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/data/record_validation.dart';
import 'package:busybooks/src/library/domain/book_format.dart';

Future<void> main() async {
  final owned = await Directory.systemTemp.createTemp(
    'busybooks-format-proof-',
  );
  ReadingDataStore? store;
  var checks = 0;
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
    checks++;
  }

  Future<void> rejects(
    Future<dynamic> Function() action,
    String message,
  ) async {
    var rejected = false;
    try {
      await action();
    } catch (_) {
      rejected = true;
    }
    check(rejected, message);
  }

  try {
    final root = p.join(owned.path, 'profile');
    store = await ReadingDataStore.open(root);
    final books = <Map<String, dynamic>>[];
    for (final name in [
      'epub2.epub',
      'epub2-dtbook.epub',
      'epub2-cover-page.epub',
      'epub2-mime-aliases.epub',
      'epub2-xml-island.epub',
      'representative.kepub.epub',
      'reflowable.kepub.epub',
      'fiction-utf8.fb2',
      'fiction-utf16.fb2',
      'fiction-cp1251.fb2',
      'fiction.fb2.zip',
      'fiction.fbz',
      'comic-deflated.cbz',
      'comic-stored.cbz',
      for (final generation in [4, 5])
        for (final profile in ['stored', 'compressed', 'solid'])
          'comic-rar$generation-$profile.cbr',
    ]) {
      final source = await File(
        p.absolute('test/fixtures/formats', name),
      ).copy(p.join(owned.path, name));
      final started = Stopwatch()..start();
      final opened = await store.call('openPath', {'path': source.path}) as Map;
      final book = ((opened['books'] as List).single as Map)
          .cast<String, dynamic>();
      books.add(book);
      check(
        book['id'] == sha256.convert(await source.readAsBytes()).toString(),
        'Full original byte identity: $name',
      );
      check(book['format'] == bookFormatForPath(name), 'Logical format: $name');
      final descriptor =
          await store.call('prepare', {
                'id': book['id'],
                'path': book['path'],
                'validationToken': book['validationToken'],
              })
              as Map;
      final index =
          jsonDecode(
                await File(
                  '${descriptor['cacheDirectory']}.json',
                ).readAsString(),
              )
              as Map;
      Map<String, dynamic> anchor;
      if (book['format'] == 'fb2') {
        final sections = index['sections'] as List,
            section = sections[1] as Map;
        anchor = {
          'kind': 'fb2',
          'version': 1,
          'index': 1,
          'section': section['id'],
          'cfi': 'epubcfi(/6/4!/4/2/2/1:0)',
        };
        final resource = index['resources'][section['path']] as Map;
        final html = await File(
          p.join(
            descriptor['cacheDirectory'] as String,
            resource['file'] as String,
          ),
        ).readAsString();
        check(
          html.contains('Русский текст') &&
              html.contains('library') &&
              html.contains('sections/'),
          'FB2 decoding, text and internal note links: $name',
        );
        check(
          book['author'] == 'First Author, Second Author' &&
              book['series'] == 'Fixture Books',
          'FB2 ordered metadata: $name',
        );
      } else if (isComicFormat(book['format'] as String)) {
        final pages = index['pages'] as List;
        anchor = {
          'kind': 'comic',
          'version': 1,
          'format': book['format'],
          'page': 0,
          'pageId': pages[0]['file'],
        };
        check(
          pages.length == 7 && book['pages'] == 7,
          'Enumerated page count beats ComicInfo: $name',
        );
        check(
          (pages[0]['name'] as String).endsWith('Page1.jpg') &&
              (pages[1]['name'] as String).endsWith('Page2.png') &&
              (pages[3]['name'] as String).endsWith('Page10.webp'),
          'Natural page order: $name',
        );
        check(
          index['metadata']['direction'] == 'rtl',
          'ComicInfo direction: $name',
        );
        final region = {
          ...anchor,
          'region': [.1, .2, .3, .4],
        };
        await store.call('putAnnotation', {
          'id': 'annotation-region-${books.length}',
          'bookId': book['id'],
          'annotationKind': 'region',
          'anchor': region,
          'text': '',
          'note': 'Private region note',
          'reference': 'Page 1',
          'color': 'blue',
          'created': books.length,
        });
        check(
          (await store.call('annotations', book['id']) as List).isNotEmpty,
          'Region creation: $name',
        );
        await rejects(
          () => store!.call('putAnnotation', {
            'id': 'annotation-bad-${books.length}',
            'bookId': book['id'],
            'annotationKind': 'region',
            'anchor': {
              ...anchor,
              'region': [.9, 0, .2, .4],
            },
            'text': '',
            'note': 'bad',
            'reference': '',
            'color': 'blue',
            'created': 1,
          }),
          'Reject out-of-page regions: $name',
        );
      } else {
        anchor = {'cfi': 'epubcfi(/6/4!/4/2/1:0)', 'index': 1};
        check(book['cover'] is String, 'EPUB2 image or XHTML cover: $name');
      }
      validateAnchor(anchor, book['format'] as String);
      await store.call('updateBook', {
        'id': book['id'],
        'changes': {
          'anchor': anchor,
          'progress': .3,
          'appearance': {'size': 26, 'spread': false},
        },
      });
      await store.call('putAnnotation', {
        'id': 'annotation-passage-${books.length}',
        'bookId': book['id'],
        'annotationKind': isComicFormat(book['format'] as String)
            ? 'bookmark'
            : 'highlight',
        'anchor': anchor,
        'text': isComicFormat(book['format'] as String)
            ? ''
            : 'A library passage',
        'note': 'Private saved note',
        'reference': 'Saved fixture passage',
        'color': 'yellow',
        'created': books.length,
      });
      final exported = p.join(
        owned.path,
        'export-${books.length}.${book['originalSuffix']}',
      );
      await store.call('exportOriginal', {
        'id': book['id'],
        'source': source.path,
        'path': exported,
      });
      check(
        sha256.convert(await File(exported).readAsBytes()).toString() ==
            book['id'],
        'Exact-byte original export: $name',
      );
      stdout.writeln(
        jsonEncode({
          'fixture': name,
          'preparedMs': started.elapsedMilliseconds,
          'format': book['format'],
        }),
      );
    }
    for (final name in [
      'ambiguous.fbz',
      'empty.fb2.zip',
      'bad-root.fb2',
      'bad-encoding.fb2',
      'malformed.fb2',
      'comic-corrupt.cbz',
      'comic-unsupported.cbz',
      'comic-animated.cbz',
      'comic-unsafe.cbz',
      'comic-dimensions.cbz',
      'comic-crc.cbz',
      'comic-duplicate.cbz',
      'comic-rar4-encrypted.cbr',
      'comic-rar4-encrypted-headers.cbr',
      'comic-multipart.part1.cbr',
      'comic-encrypted.cbr',
      'comic-encrypted-headers.cbr',
    ]) {
      await rejects(
        () => store!.call('openPath', {
          'path': p.absolute('test/fixtures/formats', name),
        }),
        'Reject $name',
      );
    }
    final comic = books.firstWhere((book) => book['format'] == 'cbz');
    final reopened =
            await store.call('openPath', {'path': comic['path']}) as Map,
        inspected = (reopened['books'] as List).single as Map;
    await rejects(
      () => store!.call('openPath', {
        'path': p.absolute('test/fixtures/formats/bad-root.fb2'),
      }),
      'A failed replacement invalidates its predecessor inspection token',
    );
    await store.call('prepare', {
      'id': comic['id'],
      'path': comic['path'],
      'validationToken': inspected['validationToken'],
      'force': true,
    });
    check(
      (await store.call('annotations', comic['id']) as List).isNotEmpty,
      'Reinspection after failed replacement preserves notes',
    );
    final compressed = books.firstWhere(
      (book) => book['format'] == 'fb2' && book['originalSuffix'] == 'fb2.zip',
    );
    final moved = p.join(owned.path, 'MOVED.FB2.ZIP');
    await store.call('moveBook', {
      'id': compressed['id'],
      'source': compressed['path'],
      'destination': moved,
    });
    check(
      await File(moved).exists() &&
          !await File(compressed['path'] as String).exists(),
      'Compressed FB2 Move preserves the container suffix',
    );
    final located =
        await store.call('relocate', {'id': compressed['id'], 'path': moved})
            as Map;
    check(
      located['id'] == compressed['id'],
      'Locate shares the original container identity',
    );
    final collection =
        await store.call('createCollection', {'name': 'Format references'})
            as Map;
    await store.call('addBooks', {
      'collectionId': collection['id'],
      'paths': [moved, moved],
    });
    check(
      ((await store.call('openCollection', {'id': collection['id']})
                      as Map)['books']
                  as List)
              .length ==
          1,
      'Duplicate format references share collection membership',
    );
    final first = books.firstWhere((book) => book['format'] == 'fb2'),
        original = File(first['path'] as String);
    await Directory(p.join(root, 'cache')).delete(recursive: true);
    await store.call('prepare', {'id': first['id'], 'path': original.path});
    check(
      (await store.call('book', first['id']) as Map)['anchor']['section'] ==
          'body:0/part:1',
      'Cache deletion preserves typed locator',
    );
    final backup = p.join(owned.path, 'reading.busybooks');
    await store.call('backup', {'path': backup, 'preferences': {}});
    final archive = ZipDecoder().decodeBytes(await File(backup).readAsBytes());
    check(
      archive.length == 1 && archive.files.single.name == 'manifest.json',
      'Backup is data-only',
    );
    await store.close();
    store = await ReadingDataStore.open(root);
    check(
      (await store.call('annotations', first['id']) as List).isNotEmpty,
      'Notes survive restart',
    );
    await original.rename('${original.path}.missing');
    await rejects(
      () => store!.call('prepare', {'id': first['id'], 'path': original.path}),
      'Warm cache cannot replace a missing original',
    );
    check(
      (await store.call('annotations', first['id']) as List).isNotEmpty,
      'Missing originals retain Notebook',
    );
    await store.close();
    store = await ReadingDataStore.open(p.join(owned.path, 'restored'));
    await store.call('restore', backup);
    check(
      (await store.call('book', first['id']) as Map)['anchor']['section'] ==
          'body:0/part:1',
      'Restore retains FB2 section identity',
    );
    for (final book in books.where(
      (b) => isComicFormat(b['format'] as String),
    )) {
      check(
        (await store.call('annotations', book['id']) as List).any(
          (a) => a['annotationKind'] == 'region',
        ),
        'Restore region: ${book['format']}',
      );
    }
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'checks': checks,
        'scope':
            'Original-byte identity, inspection, bounded preparation, locators, annotations, original export, cache deletion, restart, missing originals and data-only backup/restore; no rendering claims',
      }),
    );
  } finally {
    await store?.close();
    await owned.delete(recursive: true);
  }
}
