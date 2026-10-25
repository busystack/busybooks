import 'dart:convert';
import 'dart:io';

import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/data/region_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

void main() {
  test(
    'region artwork uses the sealed oriented cache without its original and never changes the note',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'busybooks-region-preview-',
      );
      final store = await ReadingDataStore.open(
        p.join(directory.path, 'profile'),
      );
      try {
        final original = await File(
          'test/fixtures/formats/comic-codecs.cbz',
        ).copy(p.join(directory.path, 'original.cbz'));
        final workspace =
            await store.call('openPath', {'path': original.path}) as Map;
        final book = (workspace['books'] as List).single as Map,
            id = book['id'] as String;
        final prepared =
            await store.call('prepare', {'id': id, 'path': original.path})
                as Map;
        final cache = prepared['cacheDirectory'] as String;
        final index =
            jsonDecode(await File('$cache.json').readAsString()) as Map;
        await original.delete();
        for (var page = 0; page < (index['pages'] as List).length; page++) {
          final descriptor = index['pages'][page] as Map;
          final anchor = <String, dynamic>{
            'kind': 'comic',
            'version': 1,
            'format': 'cbz',
            'page': page,
            'pageId': descriptor['file'],
            'region': [.25, .25, .5, .5],
          };
          final bytes = await store.call('regionPreview', {
            'bookId': id,
            'anchor': anchor,
          });
          expect(bytes, isNotNull);
          final thumbnail = image.decodePng(bytes)!;
          expect(thumbnail.width, lessThanOrEqualTo(640));
          expect(thumbnail.height, lessThanOrEqualTo(360));
          expect(bytes.length, lessThanOrEqualTo(1024 * 1024));
          final source = image.bakeOrientation(
            image.decodeImage(
              await File(
                p.join(cache, descriptor['file'] as String),
              ).readAsBytes(),
            )!,
          );
          expect(source.width, descriptor['width']);
          expect(source.height, descriptor['height']);
          final expected = source.getPixel(
                source.width ~/ 2,
                source.height ~/ 2,
              ),
              actual = thumbnail.getPixel(
                thumbnail.width ~/ 2,
                thumbnail.height ~/ 2,
              );
          for (final channel in [
            image.Channel.red,
            image.Channel.green,
            image.Channel.blue,
          ]) {
            expect(
              actual.getChannel(channel),
              closeTo(expected.getChannel(channel), 8),
            );
          }
          const note =
              'Private region note.\nIts complete text stays in the existing record.';
          final annotation = {
            'id': 'annotation-preview-$page',
            'bookId': id,
            'annotationKind': 'region',
            'anchor': anchor,
            'text': '',
            'note': note,
            'color': 'yellow',
            'reference': 'Page ${page + 1}',
            'created': page,
          };
          await store.call('putAnnotation', annotation);
          await store.call('regionPreview', {'bookId': id, 'anchor': anchor});
          expect(
            (await store.call('annotation', {
                  'id': annotation['id'],
                  'bookId': id,
                })
                as Map)['note'],
            note,
          );
        }
        final first = (index['pages'] as List).first as Map;
        final anchor = <String, dynamic>{
          'kind': 'comic',
          'version': 1,
          'format': 'cbz',
          'page': 0,
          'pageId': first['file'],
          'region': [.1, .1, .3, .3],
        };
        expect(
          await store.call('regionPreview', {
            'bookId': id,
            'anchor': {...anchor, 'page': 1},
          }),
          isNull,
        );
        final file = File(p.join(cache, first['file'] as String));
        final tampered = await file.readAsBytes();
        tampered[tampered.length ~/ 2] ^= 1;
        await file.writeAsBytes(tampered);
        expect(
          await store.call('regionPreview', {'bookId': id, 'anchor': anchor}),
          isNull,
        );
        expect(
          (await store.call('annotations', id) as List).length,
          (index['pages'] as List).length,
        );
        await expectLater(
          cachedRegionPreview(store.root, id, 'cbz', {
            ...anchor,
            'pageId': '../outside',
          }),
          throwsFormatException,
        );
        await expectLater(
          cachedRegionPreview(store.root, id, 'cbz', {
            ...anchor,
            'region': [.5, .5, 1, 1],
          }),
          throwsFormatException,
        );
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
