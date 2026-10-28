import 'dart:async';
import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:busybooks/src/app/app_router.dart';
import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/book_workspace/application/book_sidebar_controller.dart';
import 'package:busybooks/src/book_workspace/application/book_presentation.dart';
import 'package:busybooks/src/app/command_registry.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';
import 'package:busybooks/src/reading/domain/publication_outline.dart';
import 'package:busybooks/src/search/book_search_session.dart';
import 'package:busybooks/src/search/book_search_widgets.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
import 'package:busybooks/src/workspace/workspace_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _first =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _second =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
Book _book(String id) =>
    Book({'id': id, 'title': 'Book $id', 'format': 'pdf', 'path': '/$id.pdf'});

class _Workspace extends WorkspaceController {
  _Workspace(this.initial);
  final WorkspaceState initial;
  @override
  WorkspaceState build() => initial;
}

class _Reader extends ReaderController {
  @override
  ReaderState build() {
    ref.onDispose(() => unawaited(events.close()));
    return const ReaderState();
  }
}

class _Sidebar extends BookSidebarController {
  _Sidebar(super.bookId);
  @override
  BookSidebarState build() => const BookSidebarState();
  void replaceOutline(PublicationOutline outline) =>
      state = state.copy(outline: outline, outlineStatus: 'ready');
}

Map<String, dynamic> _passageRow({String id = 'target', int page = 1}) => {
  'book': _book(_second).data,
  'annotation': {
    'id': id,
    'bookId': _second,
    'annotationKind': 'bookmark',
    'text': 'needle',
    'note': '',
    'anchor': {'page': page},
  },
  'sourceDigest': id,
};

class _OccurrenceReader extends _Reader {
  int revision = 0, total = 1201;
  final dispatched = <String>[];
  @override
  ReaderState build() => const ReaderState(bookId: _first, ready: true);
  @override
  bool get canSearch => true;
  @override
  String get sessionId => 'fixture-renderer';
  @override
  int get searchRevision => revision;
  @override
  Future<bool> prepareChromeChange() async => true;
  @override
  void search(String query, {int offset = 0, int limit = 200}) {
    revision++;
    dispatched.add(query);
    state = state.copy(
      query: query,
      searching: false,
      searchStatus: 'done',
      searchTotal: total,
      searchOffset: offset,
      matches: [
        for (var i = offset; i < offset + limit && i < total; i++)
          {
            'anchor': {'page': i},
            'excerpt': query,
            'index': i,
          },
      ],
    );
  }

  @override
  Future<bool> loadSearchWindow(int absoluteIndex) async {
    search(state.query, offset: absoluteIndex ~/ 200 * 200);
    return true;
  }

  @override
  Future<void> cancelSearch() async {}
  void pageWithoutText(bool value) =>
      state = state.copy(location: {'noText': value});
}

class _LoadingReader extends _OccurrenceReader {
  final retried = <String>[];
  Completer<void>? retryGate;
  Completer<void>? recovered;
  @override
  ReaderState build() => const ReaderState(bookId: _first);
  @override
  bool get canSearch => state.ready && state.error == null;
  void fail() => state = state.copy(error: 'Renderer startup failed');
  void ready() => state = const ReaderState(bookId: _first, ready: true);
  @override
  Future<void> retry(String id, {bool Function()? isCurrent}) async {
    if (!(isCurrent?.call() ?? true)) return;
    retried.add(id);
    state = ReaderState(bookId: id);
    final gate = retryGate;
    if (gate != null) await gate.future;
    if (isCurrent?.call() ?? true) ready();
    recovered?.complete();
  }
}

class _SearchFailureReader extends _LoadingReader {
  bool failSearch = true;
  @override
  ReaderState build() => const ReaderState(bookId: _first, ready: true);
  @override
  void search(String query, {int offset = 0, int limit = 200}) {
    if (!failSearch) {
      super.search(query, offset: offset, limit: limit);
      return;
    }
    revision++;
    dispatched.add(query);
    state = state.copy(query: query, searchStatus: 'error');
  }
}

class _SearchStore implements ReadingDataStore {
  final updates = StreamController<int>.broadcast(sync: true);
  final requests = <Map<String, dynamic>>[];
  final cancelled = <String>[];
  List<Map<String, dynamic>> rows = [];
  Completer<void>? gate;
  final pages = <Object>[];
  @override
  int searchRevision = 0;
  @override
  String get root => '';
  @override
  Stream<int> get changes => updates.stream;
  @override
  Stream<Map<String, dynamic>> get progress => const Stream.empty();
  void changed() => updates.add(++searchRevision);
  @override
  Future<dynamic> call(String action, [Object? argument]) async {
    if (action == 'cancelSearch') {
      cancelled.add(argument as String);
      return null;
    }
    if (action == 'validateSearchResult') return rows.firstOrNull;
    if (action != 'searchRecords') throw StateError(action);
    requests.add(Map<String, dynamic>.from(argument as Map));
    final pending = gate;
    if (pending != null) await pending.future;
    if (pages.isNotEmpty) {
      final page = pages.removeAt(0);
      if (page is Map<String, dynamic>) return page;
      throw page;
    }
    return {
      'results': List.of(rows),
      'hasMore': false,
      'cursor': null,
      'sourceRevision': searchRevision,
    };
  }

  @override
  void cancel() => throw StateError('Search must not cancel unrelated work');
  @override
  Future<void> close() => updates.close();
}

class _Fixture {
  _Fixture({
    WorkspaceState state = const WorkspaceState(),
    ReaderController? reader,
  }) {
    container = ProviderContainer(
      overrides: [
        readingDataStoreProvider.overrideWithValue(store),
        workspaceControllerProvider.overrideWith(() => _Workspace(state)),
        readerControllerProvider.overrideWith(() => reader ?? _Reader()),
        bookSidebarProvider.overrideWith2(_Sidebar.new),
      ],
    );
    container.read(appRouterProvider);
    search = container.read(bookSearchSessionProvider.notifier);
  }
  final store = _SearchStore();
  late final ProviderContainer container;
  late final BookSearchController search;
  BookSearchState get state => container.read(bookSearchSessionProvider);
  Future<void> close() async {
    container.dispose();
    await store.close();
  }
}

Future<void> _mountSearch(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp(
        theme: buildBusyBooksTheme(
          brightness: Brightness.light,
          accentColor: Colors.orange,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Column(
            children: [
              BookSearchHeaderField(),
              Expanded(child: BookSearchSidebar()),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

BookActionSearchResult _action(
  String id,
  String title,
  String category, {
  bool enabled = true,
}) => BookActionSearchResult(
  BusyBooksCommand(
    id: id,
    label: (_) => title,
    category: (_) => category,
    scope: BusyBooksCommandScope.application,
    execute: () {},
    enabled: () => enabled,
  ),
  title,
  category: category,
  enabled: enabled,
);
void main() {
  test(
    'Reading and Split retain the same native search results and generation',
    () async {
      final reader = _OccurrenceReader()..total = 1;
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      addTearDown(f.close);
      final router = f.container.read(appRouterProvider);
      router.go('/read/$_first');
      await f.search.open(
        category: BookSearchCategory.bookText,
        query: '  needle  ',
      );
      expect(await f.search.submit(), true);
      final generation = f.state.generation, results = f.state.results;
      for (final route in ['/split/$_first', '/read/$_first']) {
        router.go(route);
        expect(f.state.active, true);
        expect(f.state.originRoute, route);
        expect(f.state.generation, generation);
        expect(identical(f.state.results, results), true);
        expect(f.state.query, '  needle  ');
      }
      expect(reader.dispatched, ['  needle  ']);
    },
  );
  test('first Split search follows the last focused content pane', () async {
    final f = _Fixture(
      state: WorkspaceState(
        openedBook: _book(_first),
        readingData: {_first: _book(_first)},
      ),
    );
    addTearDown(f.close);
    f.container.read(appRouterProvider).go('/split/$_first');
    final presentation = f.container.read(bookPresentationProvider.notifier);
    presentation.enterBook(_first, BookView.split);
    presentation.focusPane(_first, BookPane.notebook);
    await f.search.open();
    expect(f.state.category, BookSearchCategory.notebook);
    expect(f.state.scope.id, _first);
    expect(f.state.results, isEmpty);
    expect(f.store.requests, isEmpty);
  });
  test(
    'Split renderer retry survives its same-book Reading handoff with the latest query',
    () async {
      final reader = _LoadingReader()..retryGate = Completer<void>();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      addTearDown(f.close);
      final router = f.container.read(appRouterProvider);
      router.go('/split/$_first');
      reader.fail();
      await f.search.open(category: BookSearchCategory.bookText, query: 'old');
      final retry = f.search.retry();
      router.go('/read/$_first');
      f.search.query('  latest  ');
      reader.retryGate!.complete();
      await retry;
      expect(await f.search.submit(), true);
      expect(reader.retried, [_first]);
      expect(reader.dispatched, ['  latest  ']);
      expect(f.state.originRoute, '/read/$_first');
    },
  );
  test(
    'Split retry stays abandoned after Notebook and a return to the same book',
    () async {
      final reader = _LoadingReader()..retryGate = Completer<void>();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      addTearDown(f.close);
      final router = f.container.read(appRouterProvider);
      router.go('/split/$_first');
      reader.fail();
      await f.search.open(
        category: BookSearchCategory.bookText,
        query: 'needle',
      );
      final retry = f.search.retry();
      router.go('/notebook/$_first');
      router.go('/split/$_first');
      reader.retryGate!.complete();
      await retry;
      expect(reader.retried, [_first]);
      expect(reader.canSearch, false);
      expect(reader.dispatched, isEmpty);
    },
  );
  test(
    'cross-book Split activation retains its scope and owned deferred lease',
    () async {
      final reader = _Reader();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first), _second: _book(_second)},
        ),
      );
      addTearDown(f.close);
      final router = f.container.read(appRouterProvider);
      router.go('/split/$_first');
      f.store.rows = [_passageRow()];
      await f.search.open(
        category: BookSearchCategory.bookmarks,
        scope: const BookSearchScope.all(),
        query: 'needle',
      );
      final result = f.state.results.single, generation = f.state.generation;
      final target = readingTargetRoute('/split/$_first', _second);
      expect(
        f.search.beginActivation(
          result,
          generation,
          targetBookId: _second,
          targetRoute: target,
        ),
        true,
      );
      final request = reader.deferJump(bookId: _second, anchor: {'page': 1});
      f.search.retainDeferredActivation(request);
      router.go(target);
      f.search.endActivation();
      expect(f.state.originRoute, '/split/$_second');
      expect(f.state.scope, const BookSearchScope.all());
      expect(f.state.query, 'needle');
      expect(f.search.accepts(result, generation), true);
      expect(await f.search.validateResult(result, generation), true);
      router.go('/notebook/$_first');
      await request.finished;
      expect(f.search.accepts(result, generation), false);
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Home exposes resource categories and only Actions enumerates an empty query',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      expect(f.search.categories, [
        BookSearchCategory.notebook,
        BookSearchCategory.bookmarks,
        BookSearchCategory.books,
        BookSearchCategory.recent,
        BookSearchCategory.actions,
      ]);
      for (final category in f.search.categories.where(
        (c) => c != BookSearchCategory.actions,
      )) {
        await f.search.open(category: category);
        expect(f.state.waitingForInput, true);
        expect(f.state.results, isEmpty);
        expect(f.state.loading, false);
      }
      expect(f.store.requests, isEmpty);
      await f.search.open(
        category: BookSearchCategory.actions,
        actions: [
          _action('app.second', 'Second', 'Window'),
          _action('app.first', 'First', 'Book'),
        ],
      );
      expect(f.state.showingInitialList, true);
      expect(f.state.results, hasLength(2));
      expect(f.store.requests, isEmpty);
    },
  );
  test('Enter flushes debounce and awaits exactly the owned request', () async {
    final f = _Fixture();
    addTearDown(f.close);
    f.store.rows = [
      {'book': _book(_first).data, 'sourceDigest': 'one'},
    ];
    await f.search.open(category: BookSearchCategory.books);
    f.search.query('  literal .*  ');
    expect(f.store.requests, isEmpty);
    f.store.gate = Completer<void>();
    final submitted = f.search.submit();
    await Future<void>.delayed(Duration.zero);
    expect(f.store.requests.single['query'], '  literal .*  ');
    expect(await f.search.submit(), false);
    f.store.gate!.complete();
    expect(await submitted, true);
    expect(f.state.results.single, isA<BookMetadataSearchResult>());
  });
  for (final change in ['query', 'category', 'scope', 'close']) {
    test(
      'submission rejects a $change change during its awaited request',
      () async {
        final collection = Workspace({
          'id': 'collection',
          'name': 'Shelf',
          'kind': 'collection',
          'books': [],
        });
        final f = _Fixture(
          state: WorkspaceState(
            workspace: collection,
            collections: const [
              {'id': 'collection', 'name': 'Shelf'},
            ],
          ),
        );
        addTearDown(f.close);
        f.container.read(appRouterProvider).go('/workspace');
        f.store.rows = [
          {'book': _book(_first).data, 'sourceDigest': 'one'},
        ];
        await f.search.open(category: BookSearchCategory.books);
        f.search.query('needle');
        f.store.gate = Completer<void>();
        final submitted = f.search.submit();
        await Future<void>.delayed(Duration.zero);
        switch (change) {
          case 'query':
            f.search.query('different');
          case 'category':
            await f.search.open(category: BookSearchCategory.actions);
          case 'scope':
            f.search.setScope(const BookSearchScope.all());
          case 'close':
            f.search.close();
        }
        f.store.gate!.complete();
        expect(await submitted, false);
        expect(f.store.cancelled, isNotEmpty);
      },
    );
  }
  test(
    'clear cancels work without content enumeration and retains the open session',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.search.open(
        category: BookSearchCategory.notebook,
        query: 'needle',
      );
      await f.search.submit();
      final count = f.store.requests.length;
      f.search.query('');
      expect(f.state.active, true);
      expect(f.state.loading, false);
      expect(f.state.results, isEmpty);
      expect(f.state.selected, -1);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(f.store.requests, hasLength(count));
    },
  );
  test(
    'owned cross-book handoff retains collection scope and unrelated route invalidates it',
    () async {
      final workspace = Workspace({
        'id': 'collection',
        'name': 'Shelf',
        'kind': 'collection',
        'books': [],
      });
      final f = _Fixture(
        state: WorkspaceState(
          workspace: workspace,
          collections: const [
            {'id': 'collection', 'name': 'Shelf'},
          ],
        ),
      );
      addTearDown(f.close);
      final router = f.container.read(appRouterProvider);
      router.go('/workspace');
      f.store.rows = [
        {'book': _book(_first).data, 'sourceDigest': 'one'},
      ];
      await f.search.open(category: BookSearchCategory.books, query: 'Book');
      await f.search.submit();
      final result = f.state.results.single,
          generation = f.state.generation,
          scope = f.state.scope;
      expect(scope.kind, BookSearchScopeKind.currentCollection);
      expect(
        f.search.beginActivation(
          result,
          generation,
          targetBookId: _first,
          targetRoute: '/notebook/$_first',
        ),
        true,
      );
      router.go('/notebook/$_first');
      f.search.endActivation();
      expect(f.state.active, true);
      expect(f.state.scope, scope);
      expect(f.state.query, 'Book');
      expect(f.search.accepts(result, generation), true);
      router.go('/notebook/$_second');
      expect(f.search.accepts(result, generation), false);
      expect(f.state.active, false);
    },
  );
  testWidgets(
    'action metadata refresh preserves identity and never selects a replacement for removal',
    (tester) async {
      final f = _Fixture();
      addTearDown(f.close);
      final first = _action('app.first', 'First', 'Book'),
          second = _action('app.second', 'Second', 'Book');
      await f.search.open(
        category: BookSearchCategory.actions,
        actions: [first, second],
      );
      f.search.select(1);
      f.search.setActions([
        _action('app.second', 'A renamed command', 'Book'),
        first,
      ]);
      await tester.pump();
      expect(f.search.selectedResult?.identity, 'app.second');
      f.search.setActions([first]);
      await tester.pump();
      expect(f.search.selectedResult, isNull);
      expect(await f.search.submit(), false);
    },
  );
  test(
    'source changes refresh records while preserving stable selection',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      f.store.rows = [
        for (final id in [_first, _second])
          {'book': _book(id).data, 'sourceDigest': id},
      ];
      await f.search.open(category: BookSearchCategory.books, query: 'Book');
      await f.search.submit();
      f.search.select(1);
      f.store.rows = [f.store.rows.first];
      f.store.changed();
      await f.search.submit();
      expect(f.state.results, hasLength(1));
      expect(f.state.selected, -1);
      expect(await f.search.submit(), false);
      f.search.close();
      expect(f.state.results, isEmpty);
      await f.search.open();
      expect(f.state.query, 'Book');
      expect(f.state.category, BookSearchCategory.books);
    },
  );
  test('Settings exposes Actions without borrowing a retained book', () async {
    final f = _Fixture(
      state: WorkspaceState(
        openedBook: _book(_first),
        readingData: {_first: _book(_first)},
      ),
    );
    addTearDown(f.close);
    f.container.read(appRouterProvider).go('/settings');
    expect(f.search.categories, [BookSearchCategory.actions]);
    await f.search.open();
    expect(f.state.category, BookSearchCategory.actions);
    expect(f.state.bookId, isNull);
  });
  test(
    'PDF page text does not alter publication category query or scanned outcome',
    () async {
      final reader = _OccurrenceReader();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      addTearDown(f.close);
      f.container.read(appRouterProvider).go('/read/$_first');
      reader.pageWithoutText(true);
      expect(f.search.categories, contains(BookSearchCategory.bookText));
      await f.search.open(
        category: BookSearchCategory.bookText,
        query: '  body text  ',
      );
      expect(await f.search.submit(), true);
      final generation = f.state.generation;
      reader.pageWithoutText(false);
      reader.pageWithoutText(true);
      expect(f.state.category, BookSearchCategory.bookText);
      expect(f.state.query, '  body text  ');
      expect(f.state.generation, generation);
      expect(reader.dispatched, ['  body text  ']);
      reader.total = 0;
      await f.search.open(
        category: BookSearchCategory.bookText,
        query: 'scanned',
      );
      expect(await f.search.submit(), false);
      expect(f.state.totalOccurrences, 0);
      expect(f.state.results, isEmpty);
      expect(f.state.error, isNull);
      expect(f.state.unavailable, isNull);
    },
  );

  test(
    'Book Text previous without active occurrence loads final window and wraps only at book boundary',
    () async {
      final reader = _OccurrenceReader();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      addTearDown(f.close);
      f.container.read(appRouterProvider).go('/read/$_first');
      await f.search.open(
        category: BookSearchCategory.bookText,
        query: 'needle',
      );
      expect(await f.search.submit(), true);
      expect(f.state.results, hasLength(200));
      expect(f.state.totalOccurrences, 1201);
      expect(await f.search.selectOccurrence(-1), true);
      expect(f.state.activeOccurrence, 1200);
      expect(f.state.resultOffset, 1200);
      expect(f.state.results, hasLength(1));
      expect(
        (f.search.selectedResult as BookTextSearchResult).anchor['page'],
        1200,
      );
      expect(await f.search.selectOccurrence(1), true);
      expect(f.state.activeOccurrence, 0);
      expect(f.state.resultOffset, 0);
      expect(await f.search.selectOccurrence(1), true);
      expect(f.state.activeOccurrence, 1);
    },
  );
  test(
    'cross-book Notebook handoff releases origin outline controller',
    () async {
      final f = _Fixture(
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first), _second: _book(_second)},
        ),
      );
      addTearDown(f.close);
      final router = f.container.read(appRouterProvider);
      router.go('/notebook/$_first');
      f.store.rows = [
        {
          'book': _book(_second).data,
          'annotation': {
            'id': 'annotation-target',
            'bookId': _second,
            'annotationKind': 'highlight',
            'text': 'needle',
            'note': '',
            'anchor': {'page': 1},
          },
          'sourceDigest': 'target',
        },
      ];
      await f.search.open(
        category: BookSearchCategory.notebook,
        scope: const BookSearchScope.all(),
        query: 'needle',
      );
      final result = f.state.results.single, generation = f.state.generation;
      final target = f.container.listen(
        bookSidebarProvider(_second),
        (_, _) {},
      );
      addTearDown(target.close);
      expect(
        f.search.beginActivation(
          result,
          generation,
          targetBookId: _second,
          targetRoute: '/notebook/$_second',
        ),
        true,
      );
      router.go('/notebook/$_second');
      f.search.endActivation();
      await f.container.pump();
      expect(f.container.exists(bookSidebarProvider(_first)), false);
      expect(f.container.exists(bookSidebarProvider(_second)), true);
      expect(f.state.results.single.identity, result.identity);
      expect(f.state.active, true);
    },
  );
  test(
    'later repository batch failure preserves obtained incomplete results',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      f.store.pages.addAll([
        <String, dynamic>{
          'results': [
            {'book': _book(_first).data, 'sourceDigest': 'one'},
          ],
          'cursor': {'row': 256},
          'hasMore': true,
          'sourceRevision': 0,
        },
        StateError('Storage read failed after the first batch'),
      ]);
      await f.search.open(category: BookSearchCategory.books, query: 'Book');
      expect(f.state.loading, false);
      expect(f.state.error, contains('Storage read failed'));
      expect(f.state.results.single.identity, _first);
      expect(f.state.hasMore, true);
      expect(await f.search.submit(), false);
    },
  );
  test(
    'Book Text renderer loading failure recovers through reader retry and retains query',
    () async {
      final reader = _LoadingReader();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      addTearDown(f.close);
      f.container.read(appRouterProvider).go('/read/$_first');
      await f.search.open(
        category: BookSearchCategory.bookText,
        query: '  intended query  ',
      );
      expect(f.state.loading, true);
      expect(reader.dispatched, isEmpty);
      reader.fail();
      expect(f.state.loading, false);
      expect(f.state.error, isNotNull);
      expect(f.state.unavailable, 'reader-error');
      expect(f.state.query, '  intended query  ');
      await f.search.retry();
      expect(reader.retried, [_first]);
      expect(await f.search.submit(), true);
      expect(reader.dispatched, ['  intended query  ']);
      expect(f.state.error, isNull);
      expect(f.state.unavailable, isNull);
    },
  );
  testWidgets(
    'the search banner Retry restarts the failed reader and resubmits its literal query',
    (tester) async {
      final reader = _LoadingReader()
        ..total = 1
        ..retryGate = Completer<void>()
        ..recovered = Completer<void>();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      try {
        f.container.read(appRouterProvider).go('/read/$_first');
        reader.fail();
        await f.search.open(
          category: BookSearchCategory.bookText,
          query: '  saved query  ',
        );
        await _mountSearch(tester, f);
        final retry = find.descendant(
          of: find.byType(BusyBooksBanner),
          matching: find.text('Retry'),
        );
        expect(retry, findsOneWidget);
        await tester.tap(retry);
        await tester.pump();
        expect(reader.retried, [_first]);
        expect(f.state.query, '  saved query  ');
        expect(f.state.loading, true);
        expect(f.state.error, isNull);
        expect(reader.dispatched, isEmpty);
        await tester.runAsync(() async {
          reader.retryGate!.complete();
          await reader.recovered!.future;
          expect(await f.search.submit(), true);
        });
        await tester.pumpAndSettle();
        expect(reader.dispatched, ['  saved query  ']);
        expect(f.state.error, isNull);
        expect(f.state.results, hasLength(1));
        expect(retry, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!reader.retryGate!.isCompleted) reader.retryGate!.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        await f.close();
      }
    },
  );
  testWidgets(
    'the search banner Retry keeps ordinary search failures search-only',
    (tester) async {
      final reader = _SearchFailureReader()..total = 1;
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      try {
        f.container.read(appRouterProvider).go('/read/$_first');
        await f.search.open(
          category: BookSearchCategory.bookText,
          query: 'needle',
        );
        await _mountSearch(tester, f);
        expect(f.state.error, 'text-search');
        reader.failSearch = false;
        await tester.tap(
          find.descendant(
            of: find.byType(BusyBooksBanner),
            matching: find.text('Retry'),
          ),
        );
        await tester.pumpAndSettle();
        expect(reader.retried, isEmpty);
        expect(reader.dispatched, ['needle', 'needle']);
        expect(f.state.results, hasLength(1));
        expect(f.state.error, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await f.close();
      }
    },
  );
  test(
    'reader retry resumes the latest query after edits during recovery',
    () async {
      final reader = _LoadingReader()
        ..total = 1
        ..retryGate = Completer<void>();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      addTearDown(f.close);
      f.container.read(appRouterProvider).go('/read/$_first');
      reader.fail();
      await f.search.open(category: BookSearchCategory.bookText, query: 'old');
      final retry = f.search.retry();
      f.search.query('  latest query  ');
      reader.retryGate!.complete();
      await retry;
      expect(await f.search.submit(), true);
      expect(reader.retried, [_first]);
      expect(reader.dispatched, ['  latest query  ']);
    },
  );
  test(
    'reader retry cannot recover its old target after unrelated navigation',
    () async {
      final reader = _LoadingReader()..retryGate = Completer<void>();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      addTearDown(f.close);
      f.container.read(appRouterProvider).go('/read/$_first');
      reader.fail();
      await f.search.open(category: BookSearchCategory.bookText, query: 'old');
      final retry = f.search.retry();
      f.container.read(appRouterProvider).go('/notebook/$_second');
      reader.retryGate!.complete();
      await retry;
      expect(f.state.active, false);
      expect(reader.canSearch, false);
      expect(reader.dispatched, isEmpty);
    },
  );
  test('reader retry stays abandoned after navigating away and back', () async {
    final reader = _LoadingReader()..retryGate = Completer<void>();
    final f = _Fixture(
      reader: reader,
      state: WorkspaceState(
        openedBook: _book(_first),
        readingData: {_first: _book(_first)},
      ),
    );
    addTearDown(f.close);
    final router = f.container.read(appRouterProvider);
    router.go('/read/$_first');
    reader.fail();
    await f.search.open(category: BookSearchCategory.bookText, query: 'old');
    final retry = f.search.retry();
    router.go('/notebook/$_second');
    router.go('/read/$_first');
    reader.retryGate!.complete();
    await retry;
    expect(reader.retried, [_first]);
    expect(f.state.active, false);
    expect(reader.canSearch, false);
    expect(reader.dispatched, isEmpty);
  });
  for (final narrow in [false, true]) {
    test(
      'deferred passage retains ${narrow ? 'dismissed' : 'visible'} search ownership through its own route handoff',
      () async {
        final reader = _Reader();
        final f = _Fixture(
          reader: reader,
          state: WorkspaceState(
            openedBook: _book(_first),
            readingData: {_first: _book(_first), _second: _book(_second)},
          ),
        );
        addTearDown(f.close);
        final router = f.container.read(appRouterProvider);
        router.go('/notebook/$_first');
        f.store.rows = [_passageRow()];
        await f.search.open(
          category: BookSearchCategory.bookmarks,
          scope: const BookSearchScope.all(),
          query: 'needle',
        );
        final result = f.state.results.single, generation = f.state.generation;
        expect(
          f.search.beginActivation(
            result,
            generation,
            targetBookId: _second,
            targetRoute: '/read/$_second',
          ),
          true,
        );
        final request = reader.deferJump(
          bookId: _second,
          anchor: const {'page': 1},
        );
        f.search.retainDeferredActivation(request);
        if (narrow) f.search.dismissForActivation();
        router.go('/read/$_second');
        f.search.endActivation();
        expect(f.state.active, !narrow);
        expect(f.state.query, 'needle');
        expect(f.state.scope, const BookSearchScope.all());
        expect(f.search.accepts(result, generation), true);
        expect(await f.search.validateResult(result, generation), true);
        request.cancel();
        await request.finished;
        await f.container.pump();
        if (narrow) {
          expect(f.search.accepts(result, generation), false);
        } else {
          expect(
            f.search.beginActivation(
              result,
              generation,
              targetBookId: _second,
              targetRoute: '/read/$_second',
            ),
            true,
          );
          f.search.endActivation();
        }
      },
    );
  }
  for (final invalidation in ['query', 'category', 'scope', 'close', 'route']) {
    test(
      '$invalidation changes cancel a passage still waiting for its renderer',
      () async {
        final reader = _Reader();
        final f = _Fixture(
          reader: reader,
          state: WorkspaceState(
            openedBook: _book(_first),
            readingData: {_first: _book(_first), _second: _book(_second)},
          ),
        );
        addTearDown(f.close);
        final router = f.container.read(appRouterProvider);
        router.go('/notebook/$_first');
        f.store.rows = [_passageRow()];
        await f.search.open(
          category: BookSearchCategory.bookmarks,
          scope: const BookSearchScope.all(),
          query: 'needle',
        );
        final result = f.state.results.single, generation = f.state.generation;
        expect(
          f.search.beginActivation(
            result,
            generation,
            targetBookId: _second,
            targetRoute: '/read/$_second',
          ),
          true,
        );
        var released = false;
        final request = reader.deferJump(
          bookId: _second,
          anchor: const {'page': 1},
          onReleased: () => released = true,
        );
        f.search.retainDeferredActivation(request);
        router.go('/read/$_second');
        f.search.endActivation();
        switch (invalidation) {
          case 'query':
            f.search.query('new query');
          case 'category':
            await f.search.open(category: BookSearchCategory.books);
          case 'scope':
            f.search.setScope(
              f.search.scopes.firstWhere(
                (scope) => scope.kind == BookSearchScopeKind.thisBook,
              ),
            );
          case 'close':
            f.search.close(restoreFocus: false);
          case 'route':
            router.go('/');
        }
        expect(released, true);
        expect(f.search.accepts(result, generation), false);
        await request.finished;
      },
    );
  }
  test(
    'a deleted annotation fails deferred validation before source refresh runs',
    () async {
      final reader = _Reader();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first), _second: _book(_second)},
        ),
      );
      addTearDown(f.close);
      final router = f.container.read(appRouterProvider);
      router.go('/notebook/$_first');
      f.store.rows = [_passageRow()];
      await f.search.open(
        category: BookSearchCategory.bookmarks,
        scope: const BookSearchScope.all(),
        query: 'needle',
      );
      final result = f.state.results.single, generation = f.state.generation;
      expect(
        f.search.beginActivation(
          result,
          generation,
          targetBookId: _second,
          targetRoute: '/read/$_second',
        ),
        true,
      );
      final request = reader.deferJump(
        bookId: _second,
        anchor: const {'page': 1},
      );
      f.search.retainDeferredActivation(request);
      router.go('/read/$_second');
      f.search.endActivation();
      f.store.rows = [];
      f.store.changed();
      expect(f.state.generation, generation);
      expect(await f.search.validateResult(result, generation), false);
      request.cancel();
      await request.finished;
      await f.search.submit();
      expect(f.state.results, isEmpty);
    },
  );
  test(
    'a superseded deferred completion cannot release the newer passage ownership',
    () async {
      final reader = _Reader();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first), _second: _book(_second)},
        ),
      );
      addTearDown(f.close);
      final router = f.container.read(appRouterProvider);
      router.go('/notebook/$_first');
      f.store.rows = [_passageRow(), _passageRow(id: 'later', page: 2)];
      await f.search.open(
        category: BookSearchCategory.bookmarks,
        scope: const BookSearchScope.all(),
        query: 'needle',
      );
      final first = f.state.results.first,
          next = f.state.results.last,
          generation = f.state.generation;
      expect(
        f.search.beginActivation(
          first,
          generation,
          targetBookId: _second,
          targetRoute: '/read/$_second',
        ),
        true,
      );
      var firstReleased = false;
      final firstRequest = reader.deferJump(
        bookId: _second,
        anchor: const {'page': 1},
        onReleased: () => firstReleased = true,
      );
      f.search.retainDeferredActivation(firstRequest);
      router.go('/read/$_second');
      f.search.endActivation();
      f.store.changed();
      expect(
        f.search.beginActivation(
          next,
          generation,
          targetBookId: _second,
          targetRoute: '/read/$_second',
        ),
        true,
      );
      expect(firstReleased, true);
      final nextRequest = reader.deferJump(
        bookId: _second,
        anchor: const {'page': 2},
      );
      f.search.retainDeferredActivation(nextRequest);
      f.search.endActivation();
      await firstRequest.finished;
      await f.container.pump();
      f.search.dismissForActivation();
      expect(f.state.active, false);
      expect(f.state.generation, generation);
      expect(f.search.accepts(next, generation), true);
      nextRequest.cancel();
      await nextRequest.finished;
      await f.container.pump();
      expect(f.search.accepts(next, generation), false);
    },
  );
  test(
    'deferred chapter navigation accepts an equivalent outline reload and rejects changed destinations',
    () async {
      final reader = _Reader();
      final f = _Fixture(
        reader: reader,
        state: WorkspaceState(
          openedBook: _book(_first),
          readingData: {_first: _book(_first)},
        ),
      );
      addTearDown(f.close);
      f.container.read(appRouterProvider).go('/notebook/$_first');
      final subscription = f.container.listen(
        bookSidebarProvider(_first),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final sidebar =
          f.container.read(bookSidebarProvider(_first).notifier) as _Sidebar;
      PublicationOutline outline(int page) => PublicationOutline.fromRecords([
        {'id': 'parent', 'label': 'Part', 'depth': 0},
        {
          'id': 'chapter',
          'label': 'needle',
          'depth': 1,
          'anchor': {'page': page},
        },
      ], pdf: true);
      sidebar.replaceOutline(outline(1));
      await f.search.open(
        category: BookSearchCategory.chapters,
        query: 'needle',
      );
      final result = f.state.results.single, generation = f.state.generation;
      expect(
        f.search.beginActivation(
          result,
          generation,
          targetBookId: _first,
          targetRoute: '/read/$_first',
        ),
        true,
      );
      final request = reader.deferJump(
        bookId: _first,
        anchor: const {'page': 1},
      );
      f.search.retainDeferredActivation(request);
      f.container.read(appRouterProvider).go('/read/$_first');
      f.search.endActivation();
      sidebar.replaceOutline(outline(1));
      expect(f.state.generation, generation);
      expect(f.search.accepts(result, generation), true);
      sidebar.replaceOutline(outline(2));
      expect(f.search.accepts(result, generation), false);
      request.cancel();
      await request.finished;
    },
  );
}
