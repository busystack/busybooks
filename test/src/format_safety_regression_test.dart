import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:busybooks/src/import_export/data/archive_guard.dart';
import 'package:busybooks/src/library/data/comic_book.dart';
import 'package:busybooks/src/library/data/cover_image.dart';
import 'package:busybooks/src/library/data/epub_cache.dart';
import 'package:busybooks/src/library/data/fb2_book.dart';
import 'package:busybooks/src/library/data/image_header.dart';
import 'package:busybooks/src/library/data/publication_cache.dart';
import 'package:busybooks/src/reading/domain/annotation_transfer.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

Uint8List jpegHeader(int width, int height, {int marker = 0xc0}) =>
    Uint8List.fromList([
      0xff,
      0xd8,
      0xff,
      marker,
      0,
      17,
      8,
      height >> 8,
      height & 255,
      width >> 8,
      width & 255,
      3,
      1,
      0x11,
      0,
      2,
      0x11,
      0,
      3,
      0x11,
      0,
      0xff,
      0xda,
      0,
      2,
      0xff,
      0xd9,
    ]);

Uint8List zipFiles(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('JPEG frame geometry is bounded before coefficient initialization', () {
    for (final marker in [0xc0, 0xc1, 0xc2]) {
      expect(boundedImageInfo(jpegHeader(6000, 6000, marker: marker)), isNull);
      expect(
        boundedImageInfo(jpegHeader(65535, 65535, marker: marker)),
        isNull,
      );
      expect(libraryCover(jpegHeader(6000, 6000, marker: marker), ''), isNull);
      final valid = image.encodeJpg(image.Image(width: 20, height: 30));
      final header = boundedImageInfo(valid)!;
      expect(header.info.width, 20);
      expect(header.info.height, 30);
      expect(libraryCover(valid, 'image/jpeg'), startsWith('data:image/png;'));
    }
    for (var length = 0; length < 25; length++) {
      expect(boundedImageInfo(jpegHeader(10, 20).sublist(0, length)), isNull);
    }
    final badSampling = jpegHeader(20, 30)..[13] = 0xff;
    expect(boundedImageInfo(badSampling), isNull);
  });

  test(
    'oversized comic JPEGs are rejected during resource preparation',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-jpeg-guard-',
      );
      try {
        final source = await File(
          p.join(owned.path, 'oversized.cbz'),
        ).writeAsBytes(zipFiles({'page.jpg': jpegHeader(6000, 6000)}));
        final stage = await Directory(p.join(owned.path, 'stage')).create();
        await expectLater(
          extractComic(source.path, 'cbz', stage, () => false),
          throwsFormatException,
        );
      } finally {
        await owned.delete(recursive: true);
      }
    },
  );

  test('FB2 wrappers ignore metadata only after archive integrity checks', () {
    final document = utf8.encode('<FictionBook/>');
    final files = {
      'book.fb2': document,
      '__MACOSX/._book.fb2': [0, 5, 22, 7],
      'nested/._other.fb2': [0],
      '.DS_Store': [0],
    };
    final bytes = zipFiles(files);
    for (final suffix in ['fb2.zip', 'fbz']) {
      expect(unwrapFb2(bytes, suffix), document);
    }
    expect(
      () => unwrapFb2(zipFiles({...files, 'second.fb2': document}), 'fbz'),
      throwsFormatException,
    );
    final broken = Uint8List.fromList(bytes);
    final data = ByteData.sublistView(broken);
    var at = data.getUint32(broken.length - 6, Endian.little);
    at +=
        46 +
        data.getUint16(at + 28, Endian.little) +
        data.getUint16(at + 30, Endian.little) +
        data.getUint16(at + 32, Endian.little);
    data.setUint32(
      at + 16,
      data.getUint32(at + 16, Endian.little) ^ 1,
      Endian.little,
    );
    expect(() => unwrapFb2(broken, 'fbz'), throwsFormatException);
  });

  test(
    'FB2 encoded image/cover fragments match text links and bad links keep text',
    () {
      final png = image.encodePng(image.Image(width: 2, height: 3));
      final book = prepareFb2(
        Uint8List.fromList(
          utf8.encode('''
<FictionBook xmlns="$fb2Namespace" xmlns:l="$xlinkNamespace">
<description><title-info><book-title>Images</book-title><coverpage><image l:href="#%D0%B0%D1%80%D1%82"/></coverpage></title-info></description>
<body><section id="target"><p>Readable text <a l:href="#%">bad link</a></p><image l:href="#%D0%B0%D1%80%D1%82"/><image l:href="#%"/></section></body>
<binary id="арт" content-type="image/png">${base64Encode(png)}</binary>
<binary id="oversized" content-type="image/jpeg">${base64Encode(jpegHeader(6000, 6000))}</binary>
</FictionBook>'''),
        ),
      );
      expect(book.resources['binary/0'], png);
      expect(book.resources.containsKey('binary/1'), isFalse);
      final text = utf8.decode(book.resources['sections/0.xhtml']!);
      expect(text, contains('src="binary/0"'));
      expect(text, contains('Readable text'));
      expect(text, contains('bad link'));
      expect(book.metadata['cover'], startsWith('data:image/png;'));
    },
  );

  test(
    'ordinary EPUB preparation repairs missing, truncated and invalid cache entries',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-cache-repair-',
      );
      final source = File(p.absolute('test/fixtures/reflowable.epub'));
      final id = sha256.convert(await source.readAsBytes()).toString();
      Future<void> prepare() => prepareEpubCache(
        owned.path,
        id,
        sourcePath: source.path,
        cancelled: () => false,
      );
      try {
        await prepare();
        final index = File(p.join(owned.path, 'cache', 'epub', '$id.json'));
        final metadata = jsonDecode(await index.readAsString()) as Map;
        final resources = metadata['resources'] as Map;
        final entry = resources.entries.firstWhere(
          (e) => (e.key as String).endsWith('.xhtml'),
        );
        final file = File(
          p.join(
            owned.path,
            'cache',
            'epub',
            id,
            entry.value['file'] as String,
          ),
        );
        final original = await file.readAsBytes();
        final unchanged = await index.lastModified();
        await prepare();
        expect(await index.lastModified(), unchanged);
        await file.delete();
        await prepare();
        expect(await file.readAsBytes(), original);
        await file.writeAsBytes([1]);
        await prepare();
        expect(await file.readAsBytes(), original);
        metadata['resources'] = {};
        await index.writeAsString(jsonEncode(metadata));
        await prepare();
        expect(
          (jsonDecode(await index.readAsString())['resources'] as Map).length,
          resources.length,
        );
        if (!Platform.isWindows) {
          await file.delete();
          await Link(file.path).create(source.path);
          await prepare();
          expect(await FileSystemEntity.isLink(file.path), isFalse);
          expect(await file.readAsBytes(), original);
        }
      } finally {
        await owned.delete(recursive: true);
      }
    },
  );

  test(
    'warm publication validation rejects an original changed during cache checks',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-warm-original-',
      );
      try {
        final source = await File(
          'test/fixtures/formats/fiction-utf8.fb2',
        ).copy(p.join(owned.path, 'book.fb2'));
        final bytes = await source.readAsBytes(),
            id = sha256.convert(bytes).toString();
        await preparePublicationCache(
          owned.path,
          id,
          'fb2',
          sourcePath: source.path,
          cancelled: () => false,
        );
        var changed = false;
        await expectLater(
          preparePublicationCache(
            owned.path,
            id,
            'fb2',
            sourcePath: source.path,
            cancelled: () {
              if (!changed) {
                source.writeAsBytesSync([...bytes, 32]);
                changed = true;
              }
              return false;
            },
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(changed, isTrue);
      } finally {
        await owned.delete(recursive: true);
      }
    },
  );

  test(
    'default ZIP preflight rejects an underreported actual central directory',
    () {
      final bytes = zipFiles({for (var i = 0; i < 20001; i++) 'entry$i': []});
      final data = ByteData.sublistView(bytes), end = bytes.length - 22;
      data.setUint16(end + 8, 1, Endian.little);
      data.setUint16(end + 10, 1, Endian.little);
      expect(
        () => checkZipEntryCount(InputMemoryStream(bytes)),
        throwsFormatException,
      );
      expect(() => validatedArchive(bytes), throwsFormatException);
      expect(() => unwrapFb2(bytes, 'fbz'), throwsFormatException);
    },
  );

  test(
    'annotation transfers preserve accumulated and individually oversized records within host limits',
    () {
      for (final records in [
        [
          for (var i = 0; i < 400; i++)
            {
              'id': '$i',
              'text': 'quotation $i ${'x' * 2600}',
              'anchor': {'page': 0},
            },
        ],
        [
          {
            'id': 'large',
            'text': '漢📘\u0001' * 200000,
            'anchor': {'page': 1},
          },
        ],
      ]) {
        final batches = annotationTransfer(records, 42).toList();
        expect(batches.length, greaterThan(1));
        final text = StringBuffer();
        for (final batch in batches) {
          expect(
            utf8
                .encode(
                  jsonEncode({
                    'action': 'annotations',
                    'session': 'fixture',
                    ...batch,
                  }),
                )
                .length,
            lessThan(1048576),
          );
          expect(batch['revision'], 42);
          expect(batch['offset'], text.length);
          final delivered = jsonDecode(jsonEncode(batch)) as Map;
          text.write(delivered['chunk']);
        }
        expect(batches.last['complete'], isTrue);
        expect(jsonDecode(text.toString()), records);
      }
      expect(annotationTransfer([], 43).single, {'revision': 43, 'value': []});
    },
  );
}
