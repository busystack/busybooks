import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/data/cover_image.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/library/application/collection_view_controller.dart';
import 'package:busybooks/src/library/presentation/collection_screen.dart';
import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/system_accent.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:busybooks/src/library/data/record_validation.dart';

void main() {
  test(
    'publication outline identities, page labels and destination rectangles are typed before restore',
    () {
      final book = <String, dynamic>{
        'id': 'a' * 64,
        'format': 'pdf',
        'title': 'Fixture',
        'author': 'Author',
        'state': 'unread',
        'paths': <String>[],
      };
      final group = <String, dynamic>{
        'id': 'group',
        'label': 'Contents',
        'depth': 0,
      };
      final node = <String, dynamic>{
        'id': 'section',
        'label': 'Same',
        'depth': 1,
        'pageLabel': 'iv',
        'anchor': {
          'page': 2,
          'rect': [10, 20, 200, 500],
        },
      };
      expect(
        () => validateBook({
          ...book,
          'outline': [group, node],
        }),
        returnsNormally,
      );
      for (final changes in <Map<String, dynamic>>[
        {'id': 42},
        {'id': 'x' * 161},
        {'depth': -1},
        {'depth': '1'},
        {'depth': 100001},
        {'href': 42},
        {'pageLabel': 42},
        {'pageLabel': 'x' * 1025},
        {
          'anchor': {
            'page': 2,
            'rect': [10, 20, 200],
          },
        },
        {
          'anchor': {
            'page': 2,
            'rect': [10, 20, 200, double.infinity],
          },
        },
        {
          'anchor': {
            'page': 2,
            'rect': [200, 20, 10, 500],
          },
        },
      ]) {
        expect(
          () => validateBook({
            ...book,
            'outline': [
              group,
              {...node, ...changes},
            ],
          }),
          throwsFormatException,
        );
      }
      expect(
        () => validateBook({
          ...book,
          'outline': [
            group,
            {...node, 'id': 'group'},
          ],
        }),
        throwsFormatException,
      );
    },
  );

  test('edited covers must already satisfy sanitization and bounded resources', () {
    final safe = libraryCover(
      Uint8List.fromList(
        utf8.encode(
          '<svg width="10" height="20"><rect width="10" height="20" fill="red"/></svg>',
        ),
      ),
      'image/svg+xml',
    )!;
    expect(() => validateLibraryCover(safe), returnsNormally);
    for (final value in [
      'data:image/svg+xml;base64,${base64Encode(utf8.encode('<svg><script>alert(1)</script></svg>'))}',
      'data:image/svg+xml;base64,${base64Encode(utf8.encode('<svg><image href="file:///original.pdf"/></svg>'))}',
      'data:image/png;base64,${'A' * (6 * 1024 * 1024)}',
    ]) {
      expect(() => validateLibraryCover(value), throwsFormatException);
    }
  });
  testWidgets(
    'valid restored book metadata reaches typed getters, collection sorting and the actual cover widget',
    (tester) async {
      late Directory dir;
      late Book restoredBook;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('busybooks-typed-book-');
        final store = await ReadingDataStore.open(p.join(dir.path, 'source'));
        final restored = await ReadingDataStore.open(
          p.join(dir.path, 'restored'),
        );
        try {
          final opened =
              await store.call('openPath', {
                    'path': p.absolute('test/fixtures/text.pdf'),
                  })
                  as Map;
          final id = (opened['books'] as List).single['id'];
          final collection =
              await store.call('createCollection', {'name': 'Validated'})
                  as Map;
          await store.call('addBooks', {
            'collectionId': collection['id'],
            'paths': [p.absolute('test/fixtures/text.pdf')],
          });
          final cover = libraryCover(
            Uint8List.fromList(
              utf8.encode(
                '<svg width="10" height="20"><rect width="10" height="20" fill="red"/></svg>',
              ),
            ),
            'image/svg+xml',
          );
          await store.call('updateBook', {
            'id': id,
            'changes': {
              'read': 123,
              'cover': cover,
              'coverEdited': true,
              'appearance': {'size': 24},
            },
          });
          final path = p.join(dir.path, 'data.busybooks');
          await store.call('backup', {'path': path, 'preferences': {}});
          await restored.call('restore', path);
          final value =
              await restored.call('openCollection', {'id': collection['id']})
                  as Map;
          restoredBook = Book(
            (value['books'] as List).single.cast<String, dynamic>(),
          );
          expect(restoredBook.cover, cover);
          expect(restoredBook.read, 123);
          expect(restoredBook.added, greaterThan(0));
          expect(restoredBook.appearance!['size'], 24);
          expect(restoredBook.title, isNotEmpty);
          expect(restoredBook.author, isA<String>());
          expect(restoredBook.series, isA<String>());
          expect(restoredBook.seriesOrder, isA<num>());
          expect(restoredBook.language, isA<String>());
          expect(restoredBook.format, 'pdf');
          expect(restoredBook.progress, inInclusiveRange(0, 1));
          final omitted = Book({'id': id, 'format': 'pdf'});
          expect(omitted.cover, isNull);
          expect(omitted.read, 0);
          expect(omitted.added, 0);
          final sorted = [omitted, restoredBook]
            ..sort((a, b) => compareCollectionBooks(a, b, 'read'));
          expect(sorted.first, restoredBook);
          for (final sort in ['title', 'author', 'series', 'added']) {
            sorted.sort((a, b) => compareCollectionBooks(a, b, sort));
          }
        } finally {
          await store.close();
          await restored.close();
        }
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildBusyBooksTheme(
              brightness: Brightness.light,
              accentColor: busyBooksDefaultAccentColor,
            ),
            home: BookCover(book: restoredBook),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(BookCover), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await tester.runAsync(() => dir.delete(recursive: true));
      }
    },
  );

  test('book cover and millisecond timestamps are typed and bounded', () {
    final book = <String, dynamic>{
      'id': 'a' * 64,
      'format': 'pdf',
      'title': 'Fixture',
      'author': 'Author',
      'state': 'unread',
      'paths': <String>[],
    };
    expect(() => validateBook(book), returnsNormally);
    for (final field in ['cover', 'read', 'added']) {
      final invalidValues = field == 'cover'
          ? <Object>[
              42,
              'https://example.invalid/cover.png',
              'data:image/png;base64,AAAA',
            ]
          : <Object>['yesterday', -1, 1.5, 8640000000000001];
      for (final value in invalidValues) {
        expect(
          () => validateBook({...book, field: value}),
          throwsFormatException,
          reason: '$field=$value',
        );
      }
    }
    expect(
      () => validateBook({
        ...book,
        'read': 0,
        'added': 8640000000000000,
        'cover': null,
      }),
      returnsNormally,
    );
  });

  test(
    'typed anchors reject nonfinite, invalid and cross-format locations',
    () {
      for (final anchor in [
        {'page': -1},
        {'page': 0, 'y': 2},
        {
          'page': 0,
          'point': [double.nan, 0],
        },
        {
          'page': 0,
          'point': [0],
        },
        {'cfi': 'epubcfi(/6/2!)'},
        {
          'page': 0,
          'segments': [
            {'start': -1, 'text': 'x', 'boxes': []},
          ],
        },
      ]) {
        expect(() => validateAnchor(anchor, 'pdf'), throwsFormatException);
      }
      expect(
        () => validateAnchor({'cfi': 'epubcfi(/6/2!/4/2/1:6)'}, 'epub'),
        returnsNormally,
      );
      expect(
        () => validateAnchor({
          'cfi': 'epubcfi(/6/2!/4/2@12.345678901234:45.678901234567)',
        }, 'epub'),
        returnsNormally,
      );
      expect(
        () => validateAnchor({
          'page': 4,
          'point': [100, 400],
        }, 'pdf'),
        returnsNormally,
      );
    },
  );
}
