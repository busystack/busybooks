import 'dart:convert';
import 'dart:io';

import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/data/reading_search.dart';
import 'package:busybooks/src/workspace/workspace_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

String bookId(int n) => n.toRadixString(16).padLeft(64, '0');
const collection = 'collection:11111111111111111111111111111111';
const otherCollection = 'collection:22222222222222222222222222222222';

Map<String, dynamic> annotation(int n, {String? note}) => {
  'kind': 'annotation',
  'id': 'annotation-record-$n',
  'bookId': bookId(n),
  'annotationKind': n.isEven ? 'bookmark' : 'highlight',
  'text': n.isEven ? '' : 'Quoted passage $n',
  'note': note ?? 'Stored private note $n',
  'reference': 'Chapter $n',
  'anchor': {'kind': 'pdf', 'page': n},
  'color': 'yellow',
  'created': n,
};

void main() {
  late Directory root;
  late ReadingDataStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('busybooks-search-');
    final initialized = await ReadingDataStore.open(root.path);
    await initialized.close();
    final database = sqlite3.open(p.join(root.path, 'reading-data.sqlite'));
    database.execute('PRAGMA foreign_keys=ON');
    database.execute('INSERT INTO collections VALUES(?,?,?)', [
      collection,
      'First',
      1,
    ]);
    database.execute('INSERT INTO collections VALUES(?,?,?)', [
      otherCollection,
      'Second',
      2,
    ]);
    final record = database.prepare(
      'INSERT INTO records(id,kind,book_id,json) VALUES(?,?,?,?)',
    );
    try {
      database.execute('BEGIN');
      for (var n = 1; n <= 350; n++) {
        record.execute([
          bookId(n),
          'book',
          null,
          jsonEncode({
            'kind': 'book',
            'id': bookId(n),
            'format': 'pdf',
            'title': 'Common title $n',
            'author': 'Author $n',
            'series': n == 1 ? 'Серия 漢字 Café' : '',
            'state': 'unread',
            'paths': ['/missing/original-$n.pdf'],
          }),
        ]);
        record.execute([
          'annotation-record-$n',
          'annotation',
          bookId(n),
          jsonEncode(annotation(n)),
        ]);
        database.execute(
          'INSERT INTO locations(book_id,path,status) VALUES(?,?,?)',
          [bookId(n), '/missing/original-$n.pdf', 'missing'],
        );
      }
      for (final c in [collection, otherCollection]) {
        for (var n = 1; n <= 3; n++) {
          database.execute('INSERT INTO memberships VALUES(?,?,?)', [
            c,
            bookId(n),
            n,
          ]);
        }
      }
      database.execute('INSERT INTO recent_resources VALUES(?,?,?)', [
        'book',
        bookId(1),
        1,
      ]);
      database.execute('COMMIT');
    } finally {
      record.close();
      database.close();
    }
    store = await ReadingDataStore.open(root.path);
    await store.call('snapshot');
  });

  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  Future<Map> search(
    String category,
    String query, [
    Map<String, dynamic> options = const {},
  ]) async =>
      await store.call('searchRecords', {
            'category': category,
            'query': query,
            ...options,
          })
          as Map;

  Future<List<Map>> all(
    String category,
    String query, [
    Map<String, dynamic> options = const {},
  ]) async {
    final result = <Map>[];
    Map? cursor;
    do {
      final page = await search(category, query, {
        ...options,
        if (cursor != null) 'cursor': cursor,
      });
      result.addAll((page['results'] as List).cast<Map>());
      if (page['hasMore'] != true) break;
      cursor = page['cursor'] as Map;
    } while (true);
    return result;
  }

  test(
    'unopened saved books, annotations and missing originals are independent of Recent and collections',
    () async {
      final before = await store.call('snapshot') as Map;
      final revision = store.searchRevision;
      final books = await all('books', 'original-350.pdf');
      expect(books.single['book']['id'], bookId(350));
      final notes = await all('notebook', 'private note 350');
      expect(notes.single['annotation']['id'], 'annotation-record-350');
      expect(notes.single['book']['title'], 'Common title 350');
      expect(await all('bookmarks', 'private note 350'), hasLength(1));
      expect(await all('books', 'СЕРИЯ'), hasLength(1));
      expect(await all('books', '漢字'), hasLength(1));
      expect(await all('books', 'CAFÉ'), hasLength(1));
      expect(await all('books', 'Cafe'), isEmpty);
      expect(store.searchRevision, revision);
      expect(await store.call('snapshot'), before);
    },
  );

  test(
    'actual collection membership deduplicates and changes invalidate cursors',
    () async {
      final scoped = await all('notebook', 'private', {
        'collectionId': collection,
      });
      expect(scoped, hasLength(3));
      expect(await all('notebook', 'private'), hasLength(350));
      final first = await search('books', 'Common', {
        'collectionId': collection,
        'limit': 1,
      });
      await store.call('removeBook', {
        'collectionId': collection,
        'bookId': bookId(2),
      });
      expect(
        () => search('books', 'Common', {
          'collectionId': collection,
          'cursor': first['cursor'],
        }),
        throwsA(
          isA<WorkspaceException>().having(
            (e) => e.code,
            'code',
            'searchStale',
          ),
        ),
      );
      expect(
        await all('notebook', 'private', {'collectionId': collection}),
        hasLength(2),
      );
      expect(
        await all('notebook', 'private', {'collectionId': otherCollection}),
        hasLength(3),
      );
      await store.call('deleteCollection', collection);
      expect(
        () => search('books', 'Common', {'collectionId': collection}),
        throwsA(
          isA<WorkspaceException>().having(
            (e) => e.code,
            'code',
            'searchUnavailable',
          ),
        ),
      );
    },
  );

  test(
    'drafts replace saved note matching and protected creations are deduplicated',
    () async {
      final edit = {
        'annotation': annotation(1),
        'note': 'Unsaved replacement',
        'creating': false,
      };
      final creation = {
        'annotation': {...annotation(2), 'id': 'annotation-failed-creation'},
        'note': 'Unsaved replacement',
        'creating': true,
      };
      final drafts = [edit, creation];
      expect(
        await all('notebook', 'Stored private note 1', {
          'bookId': bookId(1),
          'drafts': drafts,
        }),
        isEmpty,
      );
      expect(
        await all('notebook', 'replacement', {'drafts': drafts}),
        hasLength(2),
      );
      expect(
        await all('notebook', 'Stored private note 1', {'bookId': bookId(1)}),
        hasLength(1),
      );
      await store.call('deleteAnnotation', 'annotation-record-1');
      expect(
        await all('notebook', 'replacement', {'drafts': drafts}),
        hasLength(1),
      );
      await store.call('putAnnotation', {
        ...annotation(2),
        'id': 'annotation-failed-creation',
        'note': 'Unsaved replacement',
      });
      expect(
        await all('notebook', 'replacement', {'drafts': drafts}),
        hasLength(1),
      );
      expect(await store.call('annotations', bookId(1)), isEmpty);
    },
  );

  test(
    'empty queries do not enumerate and batches bound records and results without truncating',
    () async {
      final empty = await search('notebook', '');
      expect(empty['results'], isEmpty);
      expect(empty['scanned'], 0);
      expect(empty['hasMore'], false);
      final first = await search('books', 'Common', {'limit': 17});
      expect(first['results'], hasLength(17));
      expect(first['hasMore'], true);
      expect(first['scanned'], lessThanOrEqualTo(256));
      expect(
        () => search('books', 'Different', {'cursor': first['cursor']}),
        throwsA(
          isA<WorkspaceException>().having(
            (e) => e.code,
            'code',
            'searchStale',
          ),
        ),
      );
      final noMatches = await search('notebook', 'absent');
      expect(noMatches['results'], isEmpty);
      expect(noMatches['scanned'], 256);
      expect(noMatches['hasMore'], true);
      final results = await all('books', 'Common', {'limit': 17});
      expect(results, hasLength(350));
      expect(results.map((r) => r['book']['id']).toSet(), hasLength(350));
    },
  );

  test(
    'activation validates exact record, scope, effective note and metadata, accepting its own Recent update',
    () async {
      final result = (await all('notebook', 'private note 2', {
        'collectionId': collection,
      })).single;
      final args = <String, dynamic>{
        'category': 'notebook',
        'query': 'private note 2',
        'collectionId': collection,
        'targetBookId': bookId(2),
        'annotationId': 'annotation-record-2',
        'sourceDigest': result['sourceDigest'],
      };
      await store.call('touchBook', bookId(2));
      expect(await store.call('validateSearchResult', args), isNotNull);
      expect(
        await store.call('validateSearchResult', {
          ...args,
          'drafts': [
            {'annotation': annotation(2), 'note': 'Changed', 'creating': false},
          ],
        }),
        isNull,
      );
      await store.call('removeBook', {
        'collectionId': collection,
        'bookId': bookId(2),
      });
      expect(await store.call('validateSearchResult', args), isNull);
      await store.call('deleteAnnotation', 'annotation-record-2');
      expect(
        await store.call(
          'validateSearchResult',
          {...args}..remove('collectionId'),
        ),
        isNull,
      );
    },
  );

  test(
    'request cancellation never cancels unrelated writes, and mutations publish revisions',
    () async {
      final changes = <int>[];
      final subscription = store.changes.listen(changes.add);
      try {
        final pending = search('notebook', 'absent', {
          'requestToken': 'cancel-this-request',
        });
        final expectation = expectLater(
          pending,
          throwsA(
            isA<WorkspaceException>().having(
              (e) => e.code,
              'code',
              'searchCancelled',
            ),
          ),
        );
        await store.call('cancelSearch', 'cancel-this-request');
        await store.call('updateAnnotation', {
          'bookId': bookId(1),
          'id': 'annotation-record-1',
          'changes': {'note': 'Saved after cancellation'},
        });
        await expectation;
        await Future<void>.delayed(Duration.zero);
        expect(changes, isNotEmpty);
        expect(
          (await all(
            'notebook',
            'Saved after cancellation',
          )).single['annotation']['id'],
          'annotation-record-1',
        );
      } finally {
        await subscription.cancel();
      }
    },
  );

  test(
    'reading progress and unchanged renderer metadata do not restart repository search',
    () async {
      final first = await search('books', 'Common', {'limit': 1});
      final revision = store.searchRevision;
      await store.call('updateBook', {
        'id': bookId(1),
        'changes': {
          'progress': .2,
          'state': 'reading',
          'anchor': {'kind': 'pdf', 'page': 1},
          'appearance': {'size': 20},
        },
      });
      await store.call('updateBook', {
        'id': bookId(1),
        'changes': {
          'title': 'Common title 1',
          'author': 'Author 1',
          'series': 'Серия 漢字 Café',
        },
      });
      await store.call('touchBook', bookId(1));
      expect(store.searchRevision, revision);
      expect(
        (await search('books', 'Common', {
          'cursor': first['cursor'],
          'limit': 1,
        }))['results'],
        hasLength(1),
      );
      await store.call('updateBook', {
        'id': bookId(1),
        'changes': {'title': 'Renamed'},
      });
      expect(store.searchRevision, greaterThan(revision));
      expect(
        () => search('books', 'Common', {'cursor': first['cursor']}),
        throwsA(
          isA<WorkspaceException>().having(
            (e) => e.code,
            'code',
            'searchStale',
          ),
        ),
      );
    },
  );

  test(
    'restore invalidates a cursor and an activation even when source bytes are equal',
    () async {
      final first = await search('notebook', 'private', {'limit': 1});
      final result = (first['results'] as List).single as Map;
      final target = p.join(root.path, 'search-backup.busybooks');
      await store.call('backup', {
        'path': target,
        'preferences': <String, dynamic>{},
      });
      final revision = store.searchRevision;
      final changed = store.changes.first;
      await store.call('restore', target);
      expect(await changed, greaterThan(revision));
      expect(
        () => search('notebook', 'private', {'cursor': first['cursor']}),
        throwsA(
          isA<WorkspaceException>().having(
            (e) => e.code,
            'code',
            'searchStale',
          ),
        ),
      );
      expect(
        await store.call('validateSearchResult', {
          'category': 'notebook',
          'query': 'private',
          'targetBookId': (result['book'] as Map)['id'],
          'annotationId': (result['annotation'] as Map)['id'],
          'sourceDigest': result['sourceDigest'],
        }),
        isNull,
      );
      final refreshed = await all('notebook', 'private');
      expect(refreshed, hasLength(350));
    },
  );

  test(
    'large notes return a small structured excerpt with original Unicode bounds',
    () async {
      final text = '${'📘' * 10000}Unique phrase${'文' * 10000}';
      await store.call('updateAnnotation', {
        'bookId': bookId(1),
        'id': 'annotation-record-1',
        'changes': {'note': text},
      });
      final result = (await all('notebook', 'unique phrase')).single;
      final match = result['match'] as Map;
      expect(match['start'], 20000);
      expect(match['end'], 20013);
      expect((match['text'] as String).length, lessThan(500));
      expect((result['annotation']['note'] as String).length, lessThan(500));
      expect(match['excerptParts']['match'], 'Unique phrase');
      expect(match['truncated'], true);
      expect(
        text.substring(match['start'] as int, match['end'] as int),
        'Unique phrase',
      );
      expect(
        (await store.call('annotation', {
              'bookId': bookId(1),
              'id': 'annotation-record-1',
            })
            as Map)['note'],
        text,
      );
    },
  );

  test(
    'literal Unicode contract preserves original offsets without folding accents or whitespace',
    () {
      for (final (text, query, expected) in <(String, String, bool)>[
        ('a%_b.*', '%_', true),
        ('anything', '%', false),
        ('Catalog', 'cat', true),
        ('A B', ' ', true),
        ('AB', ' ', false),
        ('Café', 'CAFÉ', true),
        ('cafe\u0301', 'CAFÉ', false),
        ('cafe\u0301', 'e\u0301', true),
        ('СЛОВО', 'сло', true),
        ('漢字', '漢', true),
        ('📘𝔸', '📘', true),
        ('𐐀', '𐐨', true),
        ('Kſς', 'ksσ', true),
        ('İ', 'i', false),
        ('ß', 'ss', false),
      ]) {
        expect(
          ReadingSearchMatcher(query).first({'text': text}) != null,
          expected,
          reason: '$text / $query',
        );
      }
      final result = ReadingSearchMatcher('📘').first({'text': 'a📘b'})!;
      expect(result['start'], 1);
      expect(result['end'], 3);
      expect(
        ReadingSearchMatcher(
          'aa',
        ).expression!.allMatches('aaaaa').map((m) => m.start),
        [0, 2],
      );
    },
  );
}
