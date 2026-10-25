import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:busybooks/src/import_export/data/archive_guard.dart';
import 'package:busybooks/src/library/data/book_inspection.dart';
import 'package:busybooks/src/library/data/book_xml.dart';
import 'package:busybooks/src/library/data/cache_resources.dart';
import 'package:busybooks/src/library/data/comic_book.dart';
import 'package:busybooks/src/library/data/comic_resources.dart';
import 'package:busybooks/src/library/data/disk_space.dart';
import 'package:busybooks/src/library/data/fb2_book.dart';
import 'package:busybooks/src/library/data/file_identity.dart';
import 'package:busybooks/src/library/data/publication_cache.dart';
import 'package:busybooks/src/library/data/publication_resource_limits.dart';
import 'package:busybooks/src/library/domain/book_format.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

Uint8List zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Map<String, List<int>> epub(
  List<int> chapter, {
  String additional = '',
  Map<String, List<int>> resources = const {},
}) => {
  'mimetype': utf8.encode('application/epub+zip'),
  'META-INF/container.xml': utf8.encode(
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
  ),
  'OPS/book.opf': utf8.encode(
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Limits</dc:title></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>$additional</manifest><spine><itemref idref="chapter"/></spine></package>',
  ),
  'OPS/chapter.xhtml': chapter,
  ...resources,
};
List<int> document(int bytes) {
  final prefix = utf8.encode(
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Bounds</title></head><body><p>Readable</p>',
  );
  final suffix = utf8.encode('</body></html>');
  return Uint8List(bytes)
    ..fillRange(0, bytes, 32)
    ..setAll(0, prefix)
    ..setAll(bytes - suffix.length, suffix);
}

Future<void> useDirectory(Future<void> Function(Directory) action) async {
  final owned = await Directory.systemTemp.createTemp(
    'busybooks-resource-budget-',
  );
  try {
    await action(owned);
  } finally {
    await owned.delete(recursive: true);
  }
}

void main() {
  test(
    'F23: EPUB media and navigation budgets also constrain misleading filenames',
    () {
      expect(epubResourceLimit('chapter.xhtml'), epubTextBytes);
      expect(
        epubResourceLimit('chapter.bin', mediaType: 'application/xhtml+xml'),
        epubTextBytes,
      );
      expect(
        epubResourceLimit('cover.xhtml', mediaType: 'image/png'),
        epubTextBytes,
      );
      expect(
        epubResourceLimit('cover.bin', mediaType: 'image/png'),
        epubImageBytes,
      );
      expect(
        epubResourceLimit('font.bin', mediaType: 'application/vnd.ms-opentype'),
        epubFontBytes,
      );
      expect(
        epubResourceLimit(
          'nav.xhtml',
          mediaType: 'application/xhtml+xml',
          navigation: true,
        ),
        epubNavigationBytes,
      );
      expect(epubResourceLimit('stylesheet.css'), epubNavigationBytes);
      expect(epubResourceLimit('toc.ncx'), epubNavigationBytes);
      expect(epubResourceLimit('art.svg'), epubTextBytes);
    },
  );
  for (final entry in {
    'chapter': epubTextBytes,
    'nav': epubNavigationBytes,
    'css': epubNavigationBytes,
    'svg': epubTextBytes,
  }.entries) {
    test(
      'F23: oversized ${entry.key} is rejected before publishing a cache',
      () async => useDirectory((root) async {
        final extra = entry.key == 'chapter'
            ? const <String, List<int>>{}
            : {
                'OPS/extra.${entry.key == 'nav' ? 'xhtml' : entry.key}':
                    document(entry.value + 1),
              };
        final manifest = entry.key == 'chapter'
            ? ''
            : '<item id="extra" href="extra.${entry.key == 'nav' ? 'xhtml' : entry.key}" media-type="${entry.key == 'css'
                  ? 'text/css'
                  : entry.key == 'svg'
                  ? 'image/svg+xml'
                  : 'application/xhtml+xml'}" ${entry.key == 'nav' ? 'properties="nav"' : ''}/>';
        final source = File(p.join(root.path, 'book.epub'));
        final bytes = zip(
          epub(
            document(entry.key == 'chapter' ? entry.value + 1 : 256),
            additional: manifest,
            resources: extra,
          ),
        );
        await source.writeAsBytes(bytes);
        final id = sha256.convert(bytes).toString();
        await expectLater(
          preparePublicationCache(
            root.path,
            id,
            'epub',
            sourcePath: source.path,
            cancelled: () => false,
          ),
          throwsFormatException,
        );
        expect(
          await File(
            '${publicationCachePath(root.path, 'epub', id)}.json',
          ).exists(),
          isFalse,
        );
        expect(
          await Directory(publicationCachePath(root.path, 'epub', id)).exists(),
          isFalse,
        );
      }),
    );
  }
  test(
    'F23: small but pathological XML is rejected before a renderer DOM exists',
    () async => useDirectory((root) async {
      final bytes = zip(
        epub(
          utf8.encode(
            '<html xmlns="http://www.w3.org/1999/xhtml"><head/><body>${'<p/>' * 100001}</body></html>',
          ),
        ),
      );
      final source = File(p.join(root.path, 'book.epub'));
      await source.writeAsBytes(bytes);
      await expectLater(
        preparePublicationCache(
          root.path,
          sha256.convert(bytes).toString(),
          'epub',
          sourcePath: source.path,
          cancelled: () => false,
        ),
        throwsFormatException,
      );
    }),
  );
  test(
    'F23: warm caches cannot increase the validated media budget',
    () async => useDirectory((root) async {
      final source = File(p.absolute('test/fixtures/reflowable.epub'));
      final id = await fileSha256(source, () => false);
      Future<String> prepare() => preparePublicationCache(
        root.path,
        id,
        'epub',
        sourcePath: source.path,
        cancelled: () => false,
      );
      final directory = await prepare(), index = File('$directory.json');
      final metadata = (await readSealedCacheIndex(index))!,
          resources = metadata['resources'] as Map;
      final entry = resources.entries.firstWhere(
        (e) => (e.key as String).endsWith('.xhtml'),
      );
      final file = File(p.join(directory, entry.value['file'] as String)),
          original = await File(
            p.join(directory, entry.value['file'] as String),
          ).readAsBytes();
      final handle = await file.open(mode: FileMode.append);
      await handle.truncate(epubTextBytes + 1);
      await handle.close();
      entry.value['size'] = epubTextBytes + 1;
      entry.value['maximumBytes'] = epubImageBytes;
      entry.value['sha256'] = await fileSha256(file, () => false);
      await writeSealedCacheIndex(index, metadata);
      await prepare();
      expect(await file.readAsBytes(), original);
    }),
  );
  test(
    'F24: irrelevant comic payloads are verified and never retained',
    () async => useDirectory((root) async {
      final source = File(p.join(root.path, 'book.cbz'));
      await source.writeAsBytes(
        zip({
          'page.png': image.encodePng(image.Image(width: 10, height: 10)),
          'payload.bin': List.filled(1024 * 1024, 7),
          'readme.txt': utf8.encode('not a page'),
          '__MACOSX/._page.png': [0, 5, 22, 7],
        }),
      );
      final stage = await Directory(p.join(root.path, 'stage')).create();
      final result = await extractComic(source.path, 'cbz', stage, () => false);
      expect((result['resources'] as Map).keys, ['page.png']);
      expect(await stage.list().length, 1);
      expect(
        await stage.list().cast<File>().single.then((f) => f.length()),
        lessThan(1024),
      );
    }),
  );
  test(
    'F24: ignored payload CRC failures still reject the archive',
    () async => useDirectory((root) async {
      final bytes = zip({
        'page.png': image.encodePng(image.Image(width: 10, height: 10)),
        'payload.bin': [1, 2, 3, 4],
      });
      final data = ByteData.sublistView(bytes);
      var at = data.getUint32(bytes.length - 6, Endian.little);
      for (var i = 0; i < 2; i++) {
        final length = data.getUint16(at + 28, Endian.little),
            name = utf8.decode(bytes.sublist(at + 46, at + 46 + length));
        if (name == 'payload.bin') {
          data.setUint32(
            at + 16,
            data.getUint32(at + 16, Endian.little) ^ 1,
            Endian.little,
          );
        }
        at +=
            46 +
            length +
            data.getUint16(at + 30, Endian.little) +
            data.getUint16(at + 32, Endian.little);
      }
      final source = File(p.join(root.path, 'broken.cbz'));
      await source.writeAsBytes(bytes);
      final stage = await Directory(p.join(root.path, 'stage')).create();
      await expectLater(
        extractComic(source.path, 'cbz', stage, () => false),
        throwsFormatException,
      );
    }),
  );
  test(
    'F24: page, discarded data, ComicInfo and disk reserve have separate bounds',
    () {
      final budget = ComicResourceBudget();
      expect(budget.add('page.png', 64 * 1024 * 1024), ComicResource.page);
      expect(budget.add('one.bin', 64 * 1024 * 1024), ComicResource.discard);
      expect(budget.add('two.bin', 64 * 1024 * 1024), ComicResource.discard);
      expect(budget.retainedBytes, 64 * 1024 * 1024);
      expect(() => budget.add('three.bin', 1), throwsFormatException);
      expect(
        () => ComicResourceBudget().add('ComicInfo.xml', comicInfoBytes + 1),
        throwsFormatException,
      );
      final duplicate = ComicResourceBudget()..add('ComicInfo.xml', 1);
      expect(
        () => duplicate.add('nested/ComicInfo.xml', 1),
        throwsFormatException,
      );
      expect(() => comicResource('page.tiff'), throwsFormatException);
      final manyPages = ComicResourceBudget();
      for (var i = 0; i < 10000; i++) {
        manyPages.add('page$i.png', 0);
      }
      expect(() => manyPages.add('last.png', 0), throwsFormatException);
      expect(
        () => requireComicDiskSpace(
          '/unused',
          100,
          available: comicDiskReserveBytes + 99,
        ),
        throwsA(isA<FileSystemException>()),
      );
      requireComicDiskSpace(
        '/unused',
        100,
        available: comicDiskReserveBytes + 100,
      );
    },
  );
  test(
    'F25: FB2 source size is rejected before hashing, buffering or parsing',
    () async => useDirectory((root) async {
      expect(maximumBookBytes('fb2'), fb2XmlBytes);
      final source = File(p.join(root.path, 'oversized.fb2'));
      final handle = await source.open(mode: FileMode.write);
      await handle.truncate(fb2XmlBytes + 1);
      await handle.close();
      var identified = false, prepared = false;
      await expectLater(
        inspectBook(
          source.path,
          () => false,
          identified: (_) => identified = true,
          retainFb2: (_) => prepared = true,
        ),
        throwsFormatException,
      );
      expect(identified, isFalse);
      expect(prepared, isFalse);
    }),
  );
  test(
    'F25: impossible encoded sizes fail before fingerprinting',
    () async => useDirectory((root) async {
      for (final entry in {
        'UTF-16': fb2DecodedUnits * 2 + 2,
        'windows-1251': fb2DecodedUnits,
        'UTF-8': fb2DecodedUnits * 3 + 3,
      }.entries) {
        final file = File(p.join(root.path, '${entry.key}.fb2'));
        final declaration = '<?xml version="1.0" encoding="${entry.key}"?>';
        final prefix = entry.key == 'UTF-16'
            ? <int>[
                255,
                254,
                for (final unit in declaration.codeUnits) ...[
                  unit & 255,
                  unit >> 8,
                ],
              ]
            : utf8.encode(declaration);
        final handle = await file.open(mode: FileMode.write);
        await handle.writeFrom(prefix);
        await handle.truncate(entry.value + 1);
        await handle.close();
        var fingerprinted = false;
        await expectLater(
          inspectBook(
            file.path,
            () => false,
            identified: (_) => fingerprinted = true,
          ),
          throwsFormatException,
        );
        expect(fingerprinted, isFalse, reason: entry.key);
      }
    }),
  );
  for (final fixture in [
    'fiction-utf8.fb2',
    'fiction-utf16.fb2',
    'fiction-cp1251.fb2',
    'fiction.fb2.zip',
    'fiction.fbz',
  ]) {
    test(
      'F25: $fixture streams once and preserves its original prepared representation',
      () async => useDirectory((root) async {
        final source = p.absolute('test/fixtures/formats', fixture);
        PreparedFb2? retained;
        final book = await inspectBook(
          source,
          () => false,
          retainFb2: (value) => retained = value,
        );
        expect(retained, isNotNull);
        final expected = prepareFb2(
          unwrapFb2(
            await File(source).readAsBytes(),
            originalBookSuffix(source)!,
          ),
        );
        expect(retained!.sections, expected.sections);
        expect(retained!.toc, expected.toc);
        for (final entry in expected.resources.entries) {
          expect(retained!.resources[entry.key], entry.value);
        }
        retained!.metadata['title'] = 'Owned prepared representation';
        final path = await preparePublicationCache(
          root.path,
          book['id'] as String,
          'fb2',
          sourcePath: source,
          verifiedFb2: retained,
          cancelled: () => false,
        );
        expect(
          (await readSealedCacheIndex(
            File('$path.json'),
          ))!['metadata']['title'],
          'Owned prepared representation',
        );
      }),
    );
  }
  test(
    'F25: decoding is correct at individual UTF-16 bytes, surrogate pairs and text-node boundaries',
    () async {
      final text =
          '<?xml version="1.0" encoding="UTF-16"?><FictionBook xmlns="$fb2Namespace"><body><section><p>${'word' * 20000}📚 סוף</p></section></body></FictionBook>';
      final units = text.codeUnits;
      final bytes = <int>[
        255,
        254,
        for (final unit in units) ...[unit & 255, unit >> 8],
      ];
      final parsed = await streamedFb2Xml(
        Stream.fromIterable(bytes.map((b) => [b])),
        () => false,
      );
      final normal = prepareFb2(Uint8List.fromList(bytes)),
          streamed = prepareFb2Document(parsed);
      expect(streamed.resources, normal.resources);
      await expectLater(
        streamedFb2Xml(
          Stream.fromIterable([
            [255, 254, 0, 216],
          ]),
          () => false,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'F26: every FILE_ID_128 bit and the full volume serial participate in identity',
    () {
      final first = Uint8List.fromList(List.generate(24, (i) => i));
      final upper = Uint8List.fromList(first);
      upper[23] ^= 1;
      final volume = Uint8List.fromList(first);
      volume[7] ^= 1;
      expect(windowsFileInstance(first), isNot(windowsFileInstance(upper)));
      expect(windowsFileInstance(first), isNot(windowsFileInstance(volume)));
      expect(windowsFileInstance(first).length, 55);
      expect(() => windowsFileInstance(Uint8List(16)), throwsFormatException);
    },
  );
  test(
    'F26: Windows returns a full stable identity and detects replacements',
    () async => useDirectory((root) async {
      final first = File(p.join(root.path, 'one'));
      await first.writeAsString('first');
      final id = fileInstance(first.path);
      expect(id, startsWith('win128:'));
      final renamed = await first.rename(p.join(root.path, 'renamed'));
      expect(fileInstance(renamed.path), id);
      final replacement = File(first.path);
      await replacement.writeAsString('other');
      expect(fileInstance(replacement.path), isNot(id));
    }),
    skip: !Platform.isWindows,
  );
}
