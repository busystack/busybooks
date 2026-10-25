import 'dart:convert';
import 'dart:io';

import 'package:busybooks/src/library/data/library_store.dart';
import 'package:path/path.dart' as p;

/// Seed only a new, disposable profile through the production data boundary.
Future<void> main(List<String> args) async {
  if (args.length != 1 || !p.isAbsolute(args.single)) {
    throw ArgumentError('Supply an absolute empty probe directory');
  }
  final root = Directory(args.single);
  if (await root.exists() && !await root.list().isEmpty) {
    throw ArgumentError('The probe directory must be empty');
  }
  await root.create(recursive: true);
  final store = await ReadingDataStore.open(p.join(root.path, 'profile'));
  try {
    final books = <Map>[];
    for (final name in [
      'reflowable.epub',
      'fixed-layout.epub',
      'text.pdf',
      'image-only.pdf',
      'formats/epub2.epub',
      'formats/representative.kepub.epub',
      'formats/fiction-utf8.fb2',
      'formats/fiction.fbz',
      'formats/comic-deflated.cbz',
      'formats/comic-rar5-solid.cbr',
    ]) {
      final original = await File(
        p.join('test/fixtures', name),
      ).copy(p.join(root.path, p.basename(name)));
      final workspace =
          await store.call('openPath', {'path': original.path}) as Map;
      books.add((workspace['books'] as List).single as Map);
    }
    final collection =
        await store.call('createCollection', {'name': 'Reading Desk'}) as Map;
    await store.call('addBooks', {
      'collectionId': collection['id'],
      'paths': books.map((b) => b['path']).toList(),
    });
    final now = DateTime(2026, 10, 25, 10).millisecondsSinceEpoch;
    for (final book in books.where(
      (b) => ['epub', 'pdf', 'cbz'].contains(b['format']),
    )) {
      Map? comicIndex;
      if (book['format'] == 'cbz') {
        final descriptor =
            await store.call('prepare', {
                  'id': book['id'],
                  'path': book['path'],
                })
                as Map;
        comicIndex =
            jsonDecode(
                  await File(
                    '${descriptor['cacheDirectory']}.json',
                  ).readAsString(),
                )
                as Map;
      }
      for (var index = 0; index < 6; index++) {
        final comic = book['format'] == 'cbz';
        await store.call('putAnnotation', {
          'id': 'annotation-probe-${book['id']}-$index',
          'bookId': book['id'],
          'annotationKind': index == 0
              ? 'bookmark'
              : comic
              ? 'region'
              : 'highlight',
          'anchor': comic
              ? {
                  'kind': 'comic',
                  'version': 1,
                  'format': 'cbz',
                  'pageId': comicIndex!['pages'][0]['file'],
                  'page': 0,
                  if (index > 0) 'region': [.1, .1, .3, .3],
                }
              : book['format'] == 'pdf'
              ? {'page': 0}
              : {'cfi': 'epubcfi(/6/2!/4/2/1:0)', 'index': 0},
          'text': index == 0 || comic
              ? ''
              : 'A saved passage for thoughtful reading — record $index.',
          'note': index == 0
              ? ''
              : index == 5
              ? 'A private note with line breaks.\nSecond paragraph: ideas to revisit.\n\n${'A longer observation about this passage. ' * 35}\nFinal line remains intact.'
              : 'My reading note $index.\nA second line remains intact.',
          'reference': 'Page 1',
          'color': [
            'yellow',
            'green',
            'blue',
            'pink',
            'yellow',
            'yellow',
          ][index],
          'created': now + index * 1000,
        });
      }
    }
    await File(p.join(root.path, 'input.json')).writeAsString(
      jsonEncode({'books': books, 'collection': collection['id']}),
    );
    stdout.writeln(p.join(root.path, 'input.json'));
  } finally {
    await store.close();
  }
}
