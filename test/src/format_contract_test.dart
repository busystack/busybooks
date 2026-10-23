import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:busybooks/src/library/data/book_xml.dart';
import 'package:busybooks/src/library/data/comic_book.dart';
import 'package:busybooks/src/library/data/fb2_book.dart';
import 'package:busybooks/src/library/data/record_validation.dart';
import 'package:busybooks/src/library/domain/book_format.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/app/product_actions.dart' show bookFileTypes;
import 'package:busybooks/src/annotations/domain/annotation_order.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test(
    'eligible names keep logical format separate from original container',
    () {
      for (final suffix in bookSuffixes) {
        expect(originalBookSuffix('Book.${suffix.toUpperCase()}'), suffix);
      }
      expect(bookFormatForPath('BOOK.FB2.ZIP'), 'fb2');
      if (Platform.isLinux) {
        expect(
          bookFileTypes.extensions,
          containsAll(['fB2.ZiP', 'FBz', 'cBr']),
        );
      }
      expect(bookFileTypes.extensions, isNot(contains('zip')));
      expect(bookFileTypes.extensions, isNot(contains('rar')));
      expect(
        Book({
          'format': 'fb2',
          'path': '/books/BOOK.FBZ',
          'originalSuffix': 'fb2.zip',
        }).originalSuffix,
        'fbz',
      );
      for (final name in [
        'book.zip',
        'book.rar',
        'book.xml',
        'book.kepub',
        'book.mobi',
        'book.fb3',
        'book.txt',
        'book.html',
      ]) {
        expect(bookFormatForPath(name), isNull);
      }
      expect(bookFormatForPath('representative.kepub.epub'), 'epub');
      expect(maximumBookBytes('epub'), 256 * 1024 * 1024);
      expect(maximumBookBytes('pdf'), 256 * 1024 * 1024);
      expect(maximumBookBytes('cbz'), 1024 * 1024 * 1024);
    },
  );
  test(
    'OPF2 fixture contains genuine NCX, guide and legacy cover metadata',
    () async {
      final archive = ZipDecoder().decodeBytes(
        await File('test/fixtures/formats/epub2.epub').readAsBytes(),
      );
      final opf = XmlDocument.parse(
        decodeBookXml(archive.findFile('OPS/book.opf')!.content),
      );
      expect(opf.rootElement.getAttribute('version'), '2.0');
      final elements = opf.descendants.whereType<XmlElement>();
      expect(
        elements.where((e) => e.getAttribute('properties') != null),
        isEmpty,
      );
      expect(
        elements.where(
          (e) => e.name.local == 'meta' && e.getAttribute('property') != null,
        ),
        isEmpty,
      );
      expect(
        elements
            .where((e) => e.name.local == 'spine')
            .single
            .getAttribute('toc'),
        'ncx',
      );
      expect(elements.where((e) => e.name.local == 'reference').length, 2);
      final ncx = XmlDocument.parse(
        decodeBookXml(archive.findFile('OPS/toc.ncx')!.content),
      );
      expect(
        ncx.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'navPoint')
            .length,
        3,
      );
      expect(
        ncx.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'pageTarget')
            .length,
        2,
      );
    },
  );
  test('FB2 encodings, wrappers and one deterministic section tree', () async {
    final books = <PreparedFb2>[];
    for (final name in [
      'fiction-utf8.fb2',
      'fiction-utf16.fb2',
      'fiction-cp1251.fb2',
      'fiction.fb2.zip',
      'fiction.fbz',
    ]) {
      final bytes = await File('test/fixtures/formats/$name').readAsBytes();
      books.add(prepareFb2(unwrapFb2(bytes, originalBookSuffix(name)!)));
    }
    final littleEndian = await File(
      'test/fixtures/formats/fiction-utf16.fb2',
    ).readAsBytes();
    final bigEndian = Uint8List(littleEndian.length);
    for (var offset = 0; offset < littleEndian.length; offset += 2) {
      bigEndian[offset] = littleEndian[offset + 1];
      bigEndian[offset + 1] = littleEndian[offset];
    }
    books.add(prepareFb2(bigEndian));
    for (final book in books) {
      expect(book.metadata['author'], 'First Author, Second Author');
      expect(
        book.sections.map((s) => s['id']),
        books.first.sections.map((s) => s['id']),
      );
      expect(book.resources.keys, books.first.resources.keys);
      for (final key in book.resources.keys) {
        expect(book.resources[key], books.first.resources[key]);
      }
      final html = utf8.decode(book.resources['sections/1.xhtml']!);
      expect(html, contains('Русский текст'));
      expect(html, contains('doc-noteref'));
      expect(
        XmlDocument.parse(html).descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'table')
            .length,
        1,
      );
      expect(html, contains('class="poem"'));
    }
    for (final name in [
      'ambiguous.fbz',
      'empty.fb2.zip',
      'bad-root.fb2',
      'bad-encoding.fb2',
      'malformed.fb2',
    ]) {
      final bytes = await File('test/fixtures/formats/$name').readAsBytes();
      expect(
        () => prepareFb2(unwrapFb2(bytes, originalBookSuffix(name)!)),
        throwsA(isA<Exception>()),
      );
    }
    final original = await File(
      'test/fixtures/formats/fiction-utf8.fb2',
    ).readAsString();
    final duplicate = original.replaceFirst(
      '<binary id="cover"',
      '<binary id="cover" content-type="image/unsupported">AA==</binary><binary id="cover"',
    );
    expect(
      () => prepareFb2(Uint8List.fromList(utf8.encode(duplicate))),
      throwsFormatException,
    );
  });
  test(
    'XML rejects unsupported encoding, invalid UTF16, entities and excessive nesting',
    () {
      for (final bytes in [
        Uint8List.fromList([255, 254, 60]),
        Uint8List.fromList(
          utf8.encode('<?xml version="1.0" encoding="KOI8-R"?><x/>'),
        ),
        Uint8List.fromList(
          utf8.encode('<!DOCTYPE x [<!ENTITY e "x">]><x>&e;</x>'),
        ),
        Uint8List.fromList(utf8.encode('${'<x>' * 129}${'</x>' * 129}')),
        Uint8List.fromList(utf8.encode('${'<x>' * 20000}${'</x>' * 20000}')),
        Uint8List.fromList(utf8.encode('<x a="${'a' * (256 * 1024 + 1)}"/>')),
        Uint8List.fromList(
          utf8.encode(
            '<x ${List.generate(300, (i) => 'a$i="1"').join(' ')}/> ',
          ),
        ),
      ]) {
        expect(() => boundedBookXml(bytes), throwsA(isA<Exception>()));
      }
    },
  );
  test('comic order is natural, exact, locale independent and transitive', () {
    final names = [
      'p/10.png',
      'p/2.png',
      'p/02.png',
      'p/1.png',
      'p/Ä3.png',
      'p/ä3.png',
      'P/2.png',
    ];
    final sorted = [...names]..sort(compareComicPaths);
    expect(sorted.indexOf('p/2.png'), lessThan(sorted.indexOf('p/10.png')));
    expect(sorted.indexOf('p/1.png'), lessThan(sorted.indexOf('p/2.png')));
    for (final a in names) {
      for (final b in names) {
        expect(compareComicPaths(a, b).sign, -compareComicPaths(b, a).sign);
      }
    }
    for (final a in names) {
      for (final b in names) {
        for (final c in names) {
          if (compareComicPaths(a, b) < 0 && compareComicPaths(b, c) < 0) {
            expect(compareComicPaths(a, c), lessThan(0));
          }
        }
      }
    }
  });
  test(
    'native CFI ranges persist empty endpoints and retain passage order',
    () {
      Map<String, dynamic> fb2(String cfi) => {
        'kind': 'fb2',
        'version': 1,
        'index': 0,
        'section': 'body:0/part:0',
        'cfi': cfi,
      };
      for (final cfi in [
        'epubcfi(/6/2!/4/2,,/2/1:11)',
        'epubcfi(/6/2!/4/2,/1:0,)',
        'epubcfi(/6/2!/4/2/1,:0,:11)',
        'epubcfi(/6/2!/4/0)',
      ]) {
        expect(() => validateAnchor(fb2(cfi), 'fb2'), returnsNormally);
        expect(() => validateAnchor({'cfi': cfi}, 'epub'), returnsNormally);
      }
      for (final cfi in [
        'epubcfi(,,)',
        'epubcfi(/6/2!)',
        'epubcfi(/6/2!/4/2,,,)',
        'epubcfi(/6/2!/4/-2)',
        'epubcfi(/6/2!/4/02)',
        'epubcfi(/6/2!/4/2:1000000001)',
      ]) {
        expect(() => validateAnchor(fb2(cfi), 'fb2'), throwsFormatException);
      }
      expect(
        compareAnnotationLocations(
          {'anchor': fb2('epubcfi(/6/2!/4/2,,/2/1:11)')},
          {'anchor': fb2('epubcfi(/6/2!/4/2/1:5)')},
        ),
        lessThan(0),
      );
    },
  );
  test(
    'typed FB2 and comic anchors reject format mismatch and invalid geometry',
    () {
      final fb2 = {
        'kind': 'fb2',
        'version': 1,
        'index': 1,
        'section': 'body:0/part:1',
        'cfi': 'epubcfi(/6/4!/4/2/1:5)',
      };
      expect(() => validateAnchor(fb2, 'fb2'), returnsNormally);
      for (final anchor in [
        {...fb2, 'kind': 'epub'},
        {...fb2, 'index': 2},
        {...fb2, 'version': 2},
        {...fb2, 'section': 'blob:temporary'},
        {...fb2, 'section': 'body:00/part:1'},
        {...fb2, 'section': 'body:0/part:${'1' * 100000}'},
      ]) {
        expect(() => validateAnchor(anchor, 'fb2'), throwsFormatException);
      }
      final page = {
        'kind': 'comic',
        'version': 1,
        'format': 'cbr',
        'page': 0,
        'pageId': 'a' * 64,
      };
      expect(() => validateAnchor(page, 'cbr'), returnsNormally);
      expect(() => validateAnchor(page, 'cbz'), throwsFormatException);
      expect(() => validateAnchor(page, 'pdf'), throwsFormatException);
      expect(() => validateAnchor(page, 'epub'), throwsFormatException);
      for (final region in [
        [0, 0, 0, 1],
        [0, 0, 1, -1],
        [.9, 0, .2, 1],
        [0, double.nan, 1, 1],
        [0, 0, double.infinity, 1],
      ]) {
        expect(
          () => validateAnchor({...page, 'region': region}, 'cbr'),
          throwsFormatException,
        );
      }
      final region = {
        ...page,
        'region': [.1, .2, .3, .4],
      };
      expect(() => validateAnchor(region, 'cbr'), returnsNormally);
      final annotation = {
        'id': 'annotation-fixture',
        'bookId': 'a' * 64,
        'annotationKind': 'region',
        'anchor': region,
        'text': '',
        'note': 'Private',
        'color': 'yellow',
        'created': 1,
      };
      expect(
        () => validateAnnotation(annotation, {'id': 'a' * 64, 'format': 'cbr'}),
        returnsNormally,
      );
      expect(
        () => validateAnnotation(
          {...annotation, 'text': 'fabricated quotation'},
          {'id': 'a' * 64, 'format': 'cbr'},
        ),
        throwsFormatException,
      );
      expect(
        compareAnnotationLocations({'anchor': page}, {'anchor': region}),
        lessThan(0),
      );
    },
  );
}
