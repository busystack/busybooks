import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:busybooks/src/annotations/domain/annotation_order.dart';
import 'package:busybooks/src/library/data/comic_book.dart';
import 'package:busybooks/src/library/data/fb2_book.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/data/record_validation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:xml/xml.dart';

void main() {
  test(
    'old FB2 caches regenerate without changing existing version-1 locators',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-fb2-cache-upgrade-',
      );
      final store = await ReadingDataStore.open(owned.path);
      try {
        final workspace =
            await store.call('openPath', {
                  'path': p.absolute(
                    'test/fixtures/formats/fiction-idless.fb2',
                  ),
                })
                as Map;
        final book = (workspace['books'] as List).single as Map;
        final anchor = {
          'kind': 'fb2',
          'version': 1,
          'section': 'body:0/part:0',
          'index': 0,
          'cfi': 'epubcfi(/6/2!/4/2/4[passage]/1:2)',
        };
        await store.call('updateBook', {
          'id': book['id'],
          'changes': {'anchor': anchor},
        });
        final old = await Directory(
          p.join(owned.path, 'cache', 'fb2-v1', book['id'] as String),
        ).create(recursive: true);
        await File('${old.path}.json').writeAsString(
          jsonEncode({
            'version': 1,
            'id': book['id'],
            'format': 'fb2',
            'resources': {},
            'sections': [],
            'toc': [
              {'label': 'obsolete', 'href': 'sections/0.xhtml'},
            ],
          }),
        );
        final prepared =
            await store.call('prepare', {
                  'id': book['id'],
                  'path': book['path'],
                  'validationToken': book['validationToken'],
                })
                as Map;
        final index =
            jsonDecode(
                  await File(
                    '${prepared['cacheDirectory']}.json',
                  ).readAsString(),
                )
                as Map;
        final rows = [index['toc'][0], ...index['toc'][0]['subitems'] as List];
        expect(rows.map((row) => row['href']).toSet().length, 3);
        expect((await store.call('book', book['id']) as Map)['anchor'], anchor);
      } finally {
        await store.close();
        await owned.delete(recursive: true);
      }
    },
  );
  test(
    'unnamed FB2 sections have stable distinct collision-free outline targets',
    () async {
      final bytes = await File(
        'test/fixtures/formats/fiction-idless.fb2',
      ).readAsBytes();
      final first = prepareFb2(bytes), second = prepareFb2(bytes);
      final rows = [first.toc.single, ...first.toc.single['subitems'] as List];
      expect(rows.length, 3);
      expect(rows.map((row) => row['href']).toSet().length, 3);
      expect(first.toc, second.toc);
      expect(first.sections.map((row) => row['id']), ['body:0/part:0']);
      final html = utf8.decode(first.resources['sections/0.xhtml']!);
      expect(html, utf8.decode(second.resources['sections/0.xhtml']!));
      final doc = XmlDocument.parse(html);
      final ids = doc.descendants
          .whereType<XmlElement>()
          .map((node) => node.getAttribute('id'))
          .whereType<String>()
          .toList();
      expect(ids.toSet().length, ids.length);
      expect(
        ids,
        contains('busybooks-section-0-0'),
      ); // Authored collision survives.
      for (final row in rows) {
        final fragment = Uri.decodeComponent(
          (row['href'] as String).split('#')[1],
        );
        final node = doc.descendants.whereType<XmlElement>().singleWhere(
          (node) => node.getAttribute('id') == fragment,
        );
        expect(node.getElement('header')!.innerText, row['label']);
      }
    },
  );

  test(
    'AppleDouble metadata does not become pages or shift ComicInfo indices',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-sidecars-',
      );
      try {
        final original = ZipDecoder().decodeBytes(
          await File('test/fixtures/formats/comic-stored.cbz').readAsBytes(),
        );
        final archive = Archive();
        for (final file in original) {
          archive.addFile(ArchiveFile(file.name, file.size, file.content));
        }
        final metadataNames = [
          '__MACOSX/._page1.jpg',
          'pages/._Page2.tiff',
          '.DS_Store',
          '__MACOSX/ComicInfo.xml',
        ];
        for (final name in metadataNames) {
          final bytes = Uint8List.fromList([0, 5, 22, 7, 0, 2, 0, 0]);
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
        }
        final source = await File(
          p.join(owned.path, 'sidecars.cbz'),
        ).writeAsBytes(ZipEncoder().encode(archive));
        final stage = await Directory(p.join(owned.path, 'stage')).create();
        final prepared = await extractComic(
          source.path,
          'cbz',
          stage,
          () => false,
        );
        final pages = prepared['pages'] as List;
        expect(pages.length, 7);
        expect(pages.first['name'], 'pages/Page1.jpg');
        expect(pages[1]['name'], 'pages/Page2.png');
        expect(pages[1]['wide'], true);
        expect(prepared['metadata']['title'], 'Comic Library');
        expect(
          (prepared['resources'] as Map).keys,
          isNot(anyElement(isIn(metadataNames))),
        );
        expect(
          await stage.list().length,
          (prepared['resources'] as Map).length,
        );
        // Ignoring a sidecar never bypasses archive integrity validation.
        final corrupt = Uint8List.fromList(await source.readAsBytes());
        final data = ByteData.sublistView(corrupt);
        var cursor = data.getUint32(corrupt.length - 22 + 16, Endian.little),
            changed = false;
        while (data.getUint32(cursor, Endian.little) == 0x02014b50) {
          final nameLength = data.getUint16(cursor + 28, Endian.little),
              extra = data.getUint16(cursor + 30, Endian.little),
              comment = data.getUint16(cursor + 32, Endian.little);
          if (utf8.decode(
                corrupt.sublist(cursor + 46, cursor + 46 + nameLength),
              ) ==
              metadataNames.first) {
            data.setUint32(
              cursor + 16,
              data.getUint32(cursor + 16, Endian.little) ^ 1,
              Endian.little,
            );
            changed = true;
            break;
          }
          cursor += 46 + nameLength + extra + comment;
        }
        expect(changed, isTrue);
        await source.writeAsBytes(corrupt);
        final badStage = await Directory(
          p.join(owned.path, 'bad-stage'),
        ).create();
        await expectLater(
          extractComic(source.path, 'cbz', badStage, () => false),
          throwsA(anything),
        );
      } finally {
        await owned.delete(recursive: true);
      }
    },
  );

  test(
    'comic fields are typed and legacy comic ties never read PDF coordinates',
    () {
      final anchor = {
        'kind': 'comic',
        'version': 1,
        'format': 'cbz',
        'page': 0,
        'pageId': 'a' * 64,
        'region': [.1, .2, .3, .4],
      };
      for (final field in [
        'point',
        'rect',
        'ref',
        'y',
        'cfi',
        'index',
        'segments',
        'section',
        'textOffset',
        'textLength',
        'unknown',
      ]) {
        expect(
          () => validateAnchor({...anchor, field: []}, 'cbz'),
          throwsFormatException,
          reason: field,
        );
      }
      final a = {
            'anchor': {...anchor, 'point': []},
            'created': 1,
          },
          b = {'anchor': anchor, 'created': 2};
      expect(compareAnnotationLocations(a, b), lessThan(0));
      expect(compareAnnotationLocations(b, a), greaterThan(0));
    },
  );

  test(
    'restore rejects incompatible comic fields atomically; legacy notes still export',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-comic-restore-',
      );
      ReadingDataStore? source, target;
      try {
        source = await ReadingDataStore.open(p.join(owned.path, 'source'));
        final workspace =
            await source.call('openPath', {
                  'path': p.absolute('test/fixtures/formats/comic-stored.cbz'),
                })
                as Map;
        final book = (workspace['books'] as List).single as Map;
        final prepared =
            await source.call('prepare', {
                  'id': book['id'],
                  'path': book['path'],
                  'validationToken': book['validationToken'],
                })
                as Map;
        final index =
            jsonDecode(
                  await File(
                    '${prepared['cacheDirectory']}.json',
                  ).readAsString(),
                )
                as Map;
        final anchor = {
          'kind': 'comic',
          'version': 1,
          'format': 'cbz',
          'page': 0,
          'pageId': index['pages'][0]['file'],
          'region': [.1, .2, .3, .4],
        };
        final notes = [
          for (var i = 1; i <= 2; i++)
            {
              'id': 'annotation-review-$i',
              'bookId': book['id'],
              'annotationKind': 'region',
              'anchor': anchor,
              'text': '',
              'note': 'Private region $i',
              'reference': 'Page 1',
              'color': 'blue',
              'created': i,
            },
        ];
        for (final note in notes) {
          await source.call('putAnnotation', note);
        }
        final backup = p.join(owned.path, 'valid.busybooks');
        await source.call('backup', {'path': backup, 'preferences': {}});
        final archive = ZipDecoder().decodeBytes(
          await File(backup).readAsBytes(),
        );
        final manifest = jsonDecode(utf8.decode(archive.single.content)) as Map;
        final bad =
            (manifest['records'] as List).singleWhere(
                  (row) => row['id'] == notes.last['id'],
                )
                as Map;
        bad['anchor'] = {...bad['anchor'] as Map, 'point': []};
        final encoded = utf8.encode(jsonEncode(manifest));
        final malformed = p.join(owned.path, 'malformed.busybooks');
        await File(malformed).writeAsBytes(
          ZipEncoder().encode(
            Archive()
              ..addFile(ArchiveFile('manifest.json', encoded.length, encoded)),
          ),
        );
        final root = p.join(owned.path, 'target');
        target = await ReadingDataStore.open(root);
        final control =
            await target.call('openPath', {
                  'path': p.absolute('test/fixtures/text.pdf'),
                })
                as Map;
        final controlBook = (control['books'] as List).single as Map;
        final keep = {
          'id': 'annotation-keep',
          'bookId': controlBook['id'],
          'annotationKind': 'bookmark',
          'anchor': {'page': 0},
          'text': '',
          'note': 'Keep this note',
          'reference': 'Page 1',
          'color': 'yellow',
          'created': 1,
        };
        await target.call('putAnnotation', keep);
        await expectLater(
          target.call('restore', malformed),
          throwsA(
            predicate(
              (error) => error.toString().contains('comic locator fields'),
            ),
          ),
        );
        await expectLater(target.call('book', book['id']), throwsA(anything));
        expect(
          (await target.call('annotations', controlBook['id']) as List)
              .single['note'],
          'Keep this note',
        );
        await target.close();
        target = await ReadingDataStore.open(root);
        await expectLater(target.call('book', book['id']), throwsA(anything));
        await target.call('restore', backup);
        expect(
          (await target.call('annotations', book['id']) as List).length,
          2,
        );
        final markdown = p.join(owned.path, 'regions.md');
        await target.call('exportMarkdown', {
          'id': book['id'],
          'path': markdown,
        });
        expect(
          await File(markdown).readAsString(),
          contains('Private region 2'),
        );
        // Simulate records accepted by the previous application, without using
        // the now-protected insertion/restore paths to create invalid records.
        await target.close();
        target = null;
        final db = sqlite3.open(p.join(root, 'reading-data.sqlite'));
        try {
          final legacy = {
            ...notes.first,
            'anchor': {...anchor, 'point': []},
          };
          db.execute('UPDATE records SET json=? WHERE id=?', [
            jsonEncode(legacy),
            legacy['id'],
          ]);
        } finally {
          db.close();
        }
        target = await ReadingDataStore.open(root);
        final restored = (await target.call('annotations', book['id']) as List)
            .cast<Map>();
        restored.sort(compareAnnotationLocations);
        expect(restored.map((row) => row['id']), notes.map((row) => row['id']));
        await target.call('exportMarkdown', {
          'id': book['id'],
          'path': p.join(owned.path, 'legacy.md'),
        });
        expect(
          await File(p.join(owned.path, 'legacy.md')).readAsString(),
          contains('Private region 1'),
        );
      } finally {
        await source?.close();
        await target?.close();
        await owned.delete(recursive: true);
      }
    },
  );
}
