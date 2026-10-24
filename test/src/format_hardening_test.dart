import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:busybooks/src/import_export/data/archive_guard.dart';
import 'package:busybooks/src/library/data/book_inspection.dart';
import 'package:busybooks/src/library/data/cache_resources.dart';
import 'package:busybooks/src/library/data/comic_book.dart';
import 'package:busybooks/src/library/data/comic_image.dart';
import 'package:busybooks/src/library/data/file_identity.dart';
import 'package:busybooks/src/library/data/image_header.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/data/publication_cache.dart';
import 'package:busybooks/src/library/data/record_validation.dart';
import 'package:busybooks/src/reading/domain/reader_bridge.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('F21: EPUB closure decodes URL path components exactly once', () {
    for (final entry in {
      'chapter%232.xhtml#chapter%3Atwo': 'OPS/chapter#2.xhtml',
      '%70er%25cent.xhtml': 'OPS/per%cent.xhtml',
      'арт.xhtml': 'OPS/арт.xhtml',
      '%d0%b0%d1%80%d1%82.xhtml': 'OPS/арт.xhtml',
      'literal%2523.xhtml': 'OPS/literal%23.xhtml',
      'a%252Fb.xhtml': 'OPS/a%2Fb.xhtml',
    }.entries) {
      expect(epubResourcePath('OPS/book.opf', entry.key), entry.value);
    }
    expect(
      epubResourcePath('OPS/book.opf', 'https://example.org/book.xhtml'),
      isNull,
    );
  });
  test(
    'F18: inspection retains no EPUB bytes and file-backed reads are repeatable',
    () async {
      var retained = false;
      final path = p.absolute('test/fixtures/reflowable.epub');
      await inspectBook(path, () => false, retainBytes: (_) => retained = true);
      expect(retained, isFalse);
      final zip = await FileBackedZip.open(path);
      final owned = await Directory.systemTemp.createTemp('busybooks-stream-');
      try {
        for (final name in ['mimetype', 'META-INF/container.xml']) {
          final expected = zip.read(name)!;
          expect(zip.read(name), expected);
          final output = File(p.join(owned.path, 'resource'));
          final digest = await streamZipEntry(
            zip.entries[name]!,
            output,
            () => false,
          );
          expect(await output.readAsBytes(), expected);
          expect(digest, sha256.convert(expected).toString());
        }
        expect(
          () => zip.read('META-INF/container.xml', maximumBytes: 1),
          throwsFormatException,
        );
        final entry = zip.entries['mimetype']!;
        entry.crc32 ^= 1;
        await expectLater(
          streamZipEntry(
            entry,
            File(p.join(owned.path, 'broken')),
            () => false,
          ),
          throwsFormatException,
        );
      } finally {
        await zip.close();
        await owned.delete(recursive: true);
      }
    },
  );

  test(
    'F19: PDF rendering uses verified snapshot after a timestamp-preserving replacement',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-pinned-pdf-',
      );
      final source = await File(
        'test/fixtures/text.pdf',
      ).copy(p.join(owned.path, 'book.pdf'));
      final store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
      try {
        final workspace =
            await store.call('openPath', {'path': source.path}) as Map;
        final book = (workspace['books'] as List).single as Map;
        final descriptor =
            await store.call('prepare', {
                  'id': book['id'],
                  'path': book['path'],
                  'validationToken': book['validationToken'],
                })
                as Map;
        final bytes = await source.readAsBytes(),
            modified = await source.lastModified();
        expect(descriptor['sourceInstance'], fileInstance(source.path));
        final replacement = File(p.join(owned.path, 'replacement.pdf'));
        final changed = Uint8List.fromList(bytes);
        changed[20] ^= 1;
        await replacement.writeAsBytes(changed);
        await replacement.setLastModified(modified);
        await source.delete();
        await replacement.rename(source.path);
        expect(await source.length(), bytes.length);
        expect(await source.lastModified(), modified);
        expect(fileInstance(source.path), isNot(descriptor['sourceInstance']));
        final rendered = File(descriptor['publicationPath'] as String);
        expect(rendered.path, isNot(source.path));
        expect(await rendered.readAsBytes(), bytes);
        expect(await fileSha256(rendered, () => false), book['id']);
        await expectLater(
          store.call('prepare', {'id': book['id'], 'path': source.path}),
          throwsException,
        );
      } finally {
        await store.close();
        await owned.delete(recursive: true);
      }
    },
  );

  for (final fixture in {
    'epub': 'test/fixtures/reflowable.epub',
    'fb2': 'test/fixtures/formats/fiction-utf8.fb2',
    'cbz': 'test/fixtures/formats/comic-codecs.cbz',
  }.entries) {
    test(
      'F21: ${fixture.key} repairs same-length corruption and a sealed incomplete descriptor',
      () async {
        final owned = await Directory.systemTemp.createTemp(
          'busybooks-cache-integrity-',
        );
        final source = File(p.absolute(fixture.value));
        final id = await fileSha256(source, () => false);
        Future<String> prepare() => preparePublicationCache(
          owned.path,
          id,
          fixture.key,
          sourcePath: source.path,
          cancelled: () => false,
        );
        try {
          final directory = Directory(await prepare());
          final index = File('${directory.path}.json');
          var descriptor = (await readSealedCacheIndex(index))!;
          final resources = descriptor['resources'] as Map;
          final name = resources.keys.cast<String>().firstWhere(
            (name) => fixture.key == 'epub' || fixture.key == 'fb2'
                ? name.endsWith('.xhtml')
                : name.endsWith('.jpg'),
          );
          final resource = resources[name] as Map;
          final file = File(p.join(directory.path, resource['file'] as String));
          final original = await file.readAsBytes();
          final damaged = Uint8List.fromList(original);
          damaged[0] ^= 1;
          await file.writeAsBytes(damaged);
          await prepare();
          expect(await file.readAsBytes(), original);
          descriptor = (await readSealedCacheIndex(index))!;
          (descriptor['resources'] as Map).remove(name);
          await file.delete();
          // Re-seal so this exercises format closure, independently of the seal.
          await writeSealedCacheIndex(index, descriptor);
          await prepare();
          expect(await file.readAsBytes(), original);
          expect(
            ((await readSealedCacheIndex(index))!['resources'] as Map)
                .containsKey(name),
            isTrue,
          );
          if (fixture.key != 'epub') {
            descriptor = (await readSealedCacheIndex(index))!;
            (descriptor[fixture.key == 'fb2' ? 'sections' : 'pages'] as List)
                .removeAt(0);
            await writeSealedCacheIndex(index, descriptor);
            await prepare();
            expect(
              ((await readSealedCacheIndex(index))![fixture.key == 'fb2'
                          ? 'sections'
                          : 'pages']
                      as List)
                  .length,
              greaterThan(
                (descriptor[fixture.key == 'fb2' ? 'sections' : 'pages']
                        as List)
                    .length,
              ),
            );
          }
          final valid = await index.readAsBytes();
          final damagedIndex = Uint8List.fromList(valid);
          damagedIndex[0] ^= 1;
          await index.writeAsBytes(damagedIndex);
          expect(await readSealedCacheIndex(index), isNull);
          await prepare();
          expect(await readSealedCacheIndex(index), isNotNull);
        } finally {
          await owned.delete(recursive: true);
        }
      },
    );
  }

  test(
    'F22: EXIF orientation and geometry share marker-fill and standalone-marker parsing',
    () async {
      final source = p.absolute('test/fixtures/formats/orientation6-fill.cbz');
      final zip = await FileBackedZip.open(source);
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-oriented-',
      );
      try {
        final bytes = zip.read('page.jpg')!;
        expect(comicOrientation(bytes), 6);
        expect(boundedImageInfo(bytes)!.info.width, 600);
        expect(boundedImageInfo(bytes)!.info.height, 900);
        final comic = await extractComic(source, 'cbz', owned, () => false);
        final page = (comic['pages'] as List).single as Map;
        expect(page['width'], 900);
        expect(page['height'], 600);
        expect(comicOrientation(Uint8List.fromList([255, 216, 255, 255])), 1);
      } finally {
        await zip.close();
        await owned.delete(recursive: true);
      }
    },
  );

  test(
    'F20: large Unicode selections, narration and legacy commands fit bounded frames losslessly',
    () {
      final text = '📚' * 400000;
      final anchor = {
        'page': 0,
        'segments': [
          {
            'page': 0,
            'boxes': [
              [0, 0, 10, 10],
            ],
            'start': 0,
            'text': text,
          },
        ],
      };
      validateAnchor(anchor, 'pdf');
      for (final type in ['selection', 'passage', 'pageText']) {
        final message = {
          'type': type,
          'session': 'owned',
          'text': text,
          'anchor': anchor,
        };
        final frames = readerBridgeFrames(message, 1, command: false).toList();
        expect(frames.length, greaterThan(1));
        final assembler = ReaderBridgeAssembler();
        Map<String, dynamic>? received;
        for (final frame in frames) {
          expect(
            utf8.encode(jsonEncode(frame)).length,
            lessThan(readerBridgeFrameBytes),
          );
          received = assembler.accept(frame);
        }
        expect(received, message);
      }
      final command = {'action': 'goto', 'session': 'owned', 'anchor': anchor};
      final frames = readerBridgeFrames(command, 1, command: true).toList();
      expect(
        jsonDecode(frames.map((f) => f['chunk'] as String).join()),
        command,
      );
      final compact = {
        'page': 0,
        'segments': [
          {
            'page': 0,
            'boxes': [
              [0, 0, 10, 10],
            ],
            'start': 0,
            'length': text.length,
          },
        ],
      };
      validateAnchor(compact, 'pdf');
      expect(jsonEncode(compact).length, lessThan(150));
    },
  );

  test(
    'F20: incomplete transfers cannot be acknowledged by flush or cross sessions',
    () {
      final frames = readerBridgeFrames(
        {'type': 'location', 'session': 'first', 'text': 'a' * 200000},
        1,
        command: false,
      ).toList();
      final assembler = ReaderBridgeAssembler();
      expect(assembler.accept(frames.first), isNull);
      expect(
        () => assembler.accept({'type': 'flushed', 'session': 'first'}),
        throwsFormatException,
      );
      expect(assembler.accept(frames.first), isNull); // stale revision
      final next = readerBridgeFrames(
        {'type': 'passage', 'session': 'next', 'text': 'b' * 200000},
        1,
        command: false,
      ).toList();
      Map<String, dynamic>? received;
      for (final frame in next) {
        received = assembler.accept(frame);
      }
      expect(received?['text'], 'b' * 200000);
      expect(assembler.accept(next.last), isNull);
    },
  );
}
