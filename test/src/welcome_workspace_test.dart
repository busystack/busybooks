import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:busybooks/src/app/app_router.dart';
import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/app/command_registry.dart';
import 'package:busybooks/src/app/product_actions.dart';
import 'package:busybooks/src/app/system_accent.dart';
import 'package:busybooks/src/book_workspace/presentation/book_workspace_screen.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/notebook/presentation/book_view_selector.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';
import 'package:busybooks/src/workspace/presentation/welcome_screen.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
import 'package:busybooks/src/workspace/workspace_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../support/historical_files_fixture.dart';

class _WelcomeState extends WorkspaceController {
  @override
  WorkspaceState build() => WorkspaceState(
    recent: [
      RecentResource({
        'path': '/fixtures/book.epub',
        'title': 'Standalone book',
        'resourceKind': 'book',
        'resourceId': 'a' * 64,
      }),
      RecentResource({
        'resourceId': 'collection:${'a' * 32}',
        'title': 'Independent collection',
        'resourceKind': 'collection',
      }),
    ],
  );
}

class _NavigationState extends WorkspaceController {
  final first = Completer<void>(), second = Completer<void>();
  @override
  WorkspaceState build() => const WorkspaceState();
  @override
  Future<Workspace> preparePath(
    String path, {
    String? expectedId,
    String? expectedKind,
    bool acceptChanged = false,
  }) async {
    final a = path.endsWith('a.epub');
    await (a ? first : second).future;
    return Workspace({
      'path': path,
      'kind': 'book',
      'name': a ? 'A' : 'B',
      'books': [
        {
          'path': path,
          'id': (a ? 'a' : 'b').padRight(64, a ? 'a' : 'b'),
          'title': a ? 'A' : 'B',
          'format': 'epub',
        },
      ],
    });
  }

  @override
  Future<void> activateWorkspace(Workspace workspace) async {
    state = state.copy(
      workspace: workspace,
      openedBook: workspace.books.single,
    );
  }

  @override
  Future<void> flush() async {}
}

class _NavigationReader extends ReaderController {
  @override
  ReaderState build() {
    ref.onDispose(() => unawaited(events.close()));
    return const ReaderState();
  }

  @override
  Future<void> open(String id) async {
    state = ReaderState(bookId: id, ready: true);
  }

  @override
  Future<void> close() async {
    state = const ReaderState();
  }

  @override
  Future<void> flush() async {}
  @override
  Future<void> show(bool value) async {}
}

class _SettingsStore implements LocalSettingsStore {
  @override
  Future<Map<String, dynamic>> load() async => {};
  @override
  Future<void> save(Map<String, dynamic> value) async {}
}

class _RecoveryState extends _WelcomeState {
  @override
  WorkspaceState build() => super.build().copy(
    error: 'Current reading-data failure',
    moves: [
      {
        'id': 'move-fixture',
        'source': '/fixtures/source.epub',
        'destination': '/fixtures/destination.epub',
        'stage': 'verified',
      },
    ],
  );
}

void _expectHomeActions() {
  for (final key in [
    'welcome-open-book',
    'welcome-create-collection',
    'welcome-open-collection',
  ]) {
    expect(find.byKey(ValueKey(key)), findsOneWidget);
  }
}

// Existing desktop-test bridge: pump callbacks on the widget clock while the
// primary controller awaits its real serialized storage worker.
Future<void> _workspaceAction(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  var done = false;
  Object? failure;
  StackTrace? trace;
  await tester.runAsync(() async {
    action().then<void>(
      (_) => done = true,
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        done = true;
      },
    );
  });
  final deadline = Stopwatch()..start();
  while (!done) {
    if (deadline.elapsed > const Duration(seconds: 30)) {
      fail('Workspace operation did not complete');
    }
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

Future<void> _profileHome(WidgetTester tester, bool historical) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late Directory owned;
  late HistoricalFilesFixture preserved;
  late ReadingDataStore store;
  late ProviderContainer container;
  late String id, collectionId;
  const note = 'Existing private note';
  const anchor = {'cfi': 'epubcfi(/6/2!/4/2/1:6)', 'index': 0};
  ProviderContainer providers() => ProviderContainer(
    overrides: [
      readingDataStoreProvider.overrideWithValue(store),
      startupAppSettingsProvider.overrideWithValue(
        StartupAppSettings(AppSettings(), _SettingsStore()),
      ),
    ],
  );
  WorkspaceController controller() =>
      container.read(workspaceControllerProvider.notifier);
  Future<void> home() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WelcomeScreen(),
        ),
      ),
    );
    await _workspaceAction(tester, () => controller().refresh());
    await tester.pumpAndSettle();
    _expectHomeActions();
    expect(find.byType(BusyBooksStatusBox), findsNothing);
  }

  await _workspaceAction(tester, () async {
    owned = await Directory.systemTemp.createTemp('busybooks-profile-home-');
    final profile = p.join(owned.path, 'profile');
    preserved = await HistoricalFilesFixture.create(
      profile,
      present: historical,
    );
    store = await ReadingDataStore.open(profile);
    container = providers();
  });
  try {
    await home();
    expect(
      find.text('Recently opened books and collections will appear here.'),
      findsOneWidget,
    );
    await _workspaceAction(tester, () async {
      final snapshot = await store.call('snapshot') as Map;
      expectSync(
        snapshot.keys,
        unorderedEquals(['recent', 'collections', 'moves']),
      );
      expectSync(
        snapshot.values.every((value) => (value as List).isEmpty),
        isTrue,
      );
      final original = await File(
        'test/fixtures/reflowable.epub',
      ).copy(p.join(owned.path, 'original.epub'));
      id = (await controller().openPath(original.path)).books.single.id;
      await controller().updateBook(id, {'anchor': anchor, 'progress': .37});
      await controller().saveAnnotation(
        ReadingAnnotation({
          'id': 'annotation-profile-home',
          'bookId': id,
          'annotationKind': 'bookmark',
          'anchor': anchor,
          'text': '',
          'note': note,
          'reference': 'Chapter 1',
          'color': 'yellow',
          'created': 1,
        }),
      );
      await controller().createCollection('Profile collection');
      collectionId = container.read(workspaceControllerProvider).workspace!.id;
      await controller().addBooks([original.path]);
      preserved.expectUnaccessed();
    });
    await home();
    final title = container
        .read(workspaceControllerProvider)
        .bookById(id)!
        .title;
    expect(find.text(title), findsOneWidget);
    expect(find.text('Profile collection'), findsOneWidget);

    // Recreate the complete primary session over the populated current DB.
    await tester.pumpWidget(const SizedBox.shrink());
    await _workspaceAction(tester, () async {
      container.dispose();
      await store.close();
      store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
      container = providers();
      await controller().openCollection(collectionId);
      await controller().loadBook(id);
      final state = container.read(workspaceControllerProvider);
      expectSync(state.books.single.id, id);
      expectSync(state.bookById(id)!.anchor, anchor);
      expectSync(state.bookById(id)!.progress, .37);
      expectSync(state.annotations.single.note, note);
      expectSync(state.recent.map((r) => r.kind).toSet(), {
        'book',
        'collection',
      });
      preserved.expectUnaccessed();
      await File(p.join(owned.path, 'original.epub')).delete();
      final missing = await controller().loadBook(id);
      expectSync(missing.available, isFalse);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BookWorkspaceScreen(view: BookView.notebook, id: id),
        ),
      ),
    );
    await _workspaceAction(tester, () => controller().flush());
    await tester.pumpAndSettle();
    expect(find.textContaining('original book is unavailable'), findsOneWidget);
    expect(find.text(note), findsOneWidget);
    await home();
    await _workspaceAction(tester, () async {
      final backup = p.join(owned.path, 'reading-data.busybooks');
      await store.call('backup', {'path': backup, 'preferences': {}});
      await store.call('restore', backup);
      await controller().afterRestore();
      await controller().loadBook(id);
      final state = container.read(workspaceControllerProvider);
      expectSync(state.collections.single['id'], collectionId);
      expectSync(state.annotations.single.note, note);
      expectSync(state.bookById(id)!.anchor, anchor);
      expectSync(state.recent.length, 2);
      preserved.expectUnaccessed();
    });
    await home();
    expect(find.text(title), findsOneWidget);
    expect(find.text('Profile collection'), findsOneWidget);
    await _workspaceAction(tester, () async {
      Object? failure;
      try {
        await controller().preparePath(p.join(owned.path, 'unavailable.epub'));
      } catch (error) {
        failure = error;
      }
      expectSync(failure, isNotNull);
      await controller().flush();
    });
    await tester.pumpAndSettle();
    final error = container.read(workspaceControllerProvider).error;
    expect(error, isNotNull);
    expect(find.byType(BusyBooksStatusBox), findsOneWidget);
    expect(find.text(error!), findsOneWidget);
    _expectHomeActions();
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await _workspaceAction(tester, () async {
      container.dispose();
      await store.close();
      try {
        await preserved.verifyUnchanged();
      } finally {
        preserved.close();
        await owned.delete(recursive: true);
      }
    });
  }
}

void main() {
  for (final historical in [false, true]) {
    testWidgets(
      'Home and current reading data are independent of historical files (present: $historical)',
      (tester) => _profileHome(tester, historical),
    );
  }
  testWidgets('Home retains current errors and pending Move Book recovery', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceControllerProvider.overrideWith(_RecoveryState.new),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WelcomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectHomeActions();
    expect(find.byType(BusyBooksStatusBox), findsOneWidget);
    expect(find.text('Current reading-data failure'), findsOneWidget);
    expect(
      find.text(
        '/fixtures/source.epub → /fixtures/destination.epub · verified',
      ),
      findsOneWidget,
    );
  });

  test(
    'Current reading schema migration ignores unrelated historical files',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-current-migration-',
      );
      final profile = p.join(owned.path, 'profile');
      final preserved = await HistoricalFilesFixture.create(
        profile,
        present: true,
      );
      ReadingDataStore? store;
      const anchor = {'cfi': 'epubcfi(/6/2!/4/2/1:6)', 'index': 0};
      try {
        final original = await File(
          'test/fixtures/reflowable.epub',
        ).copy(p.join(owned.path, 'original.epub'));
        final id = sha256.convert(await original.readAsBytes()).toString();
        final current = sqlite3.open(p.join(profile, 'reading-data.sqlite'));
        try {
          current.execute('PRAGMA foreign_keys=ON');
          expect(current.select('PRAGMA foreign_keys').single.values.single, 1);
          current.execute(
            'CREATE TABLE records(id TEXT PRIMARY KEY,kind TEXT NOT NULL,book_id TEXT,json TEXT NOT NULL)',
          );
          current.execute(
            'CREATE TABLE metadata(key TEXT PRIMARY KEY,json TEXT NOT NULL)',
          );
          for (final record in [
            {
              'id': id,
              'kind': 'book',
              'title': 'Current schema book',
              'format': 'epub',
              'paths': [original.path],
              'anchor': anchor,
              'progress': .37,
            },
            {
              'id': 'annotation-current-migration',
              'kind': 'annotation',
              'bookId': id,
              'annotationKind': 'bookmark',
              'anchor': anchor,
              'text': '',
              'note': 'Current schema note',
              'color': 'yellow',
              'created': 1,
            },
            {
              'id': 'recent-current-migration',
              'kind': 'recent',
              'resourceKind': 'book',
              'bookId': id,
              'opened': 2,
            },
          ]) {
            current.execute(
              'INSERT INTO records(id,kind,book_id,json) VALUES(?,?,?,?)',
              [
                record['id'],
                record['kind'],
                record['kind'] == 'annotation' ? id : null,
                jsonEncode(record),
              ],
            );
          }
          current.execute('PRAGMA user_version=1');
        } finally {
          current.close();
        }
        store = await ReadingDataStore.open(profile);
        final snapshot = await store.call('snapshot') as Map;
        expect(
          snapshot.keys,
          unorderedEquals(['recent', 'collections', 'moves']),
        );
        expect((snapshot['recent'] as List).single['resourceId'], id);
        expect((await store.call('book', id) as Map)['anchor'], anchor);
        expect(
          (await store.call('annotations', id) as List).single['note'],
          'Current schema note',
        );
        await store.close();
        final migrated = sqlite3.open(p.join(profile, 'reading-data.sqlite'));
        try {
          migrated.execute('PRAGMA foreign_keys=ON');
          expect(
            migrated.select('PRAGMA foreign_keys').single.values.single,
            1,
          );
          expect(
            migrated.select('PRAGMA user_version').single.values.single,
            2,
          );
          expect(migrated.select('SELECT path,status FROM locations').single, {
            'path': original.path,
            'status': 'unverified',
          });
        } finally {
          migrated.close();
        }
        await preserved.verifyUnchanged();
      } finally {
        await store?.close();
        preserved.close();
        await owned.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'Home offers book and database collection actions and typed Recent',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceControllerProvider.overrideWith(_WelcomeState.new),
          ],
          child: MaterialApp(
            theme: buildBusyBooksTheme(
              brightness: Brightness.light,
              accentColor: busyBooksDefaultAccentColor,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const WelcomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('welcome-open-book')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('welcome-create-collection')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('welcome-open-collection')),
        findsOneWidget,
      );
      expect(find.text('Standalone book'), findsOneWidget);
      expect(find.text('Independent collection'), findsOneWidget);
      expect(find.text('Book · /fixtures/book.epub'), findsOneWidget);
      expect(find.text('/fixtures/collection'), findsNothing);
      expect(find.text('Collection'), findsOneWidget);
      expect(find.text('Welcome'), findsNothing);
      expect(find.textContaining('Import'), findsNothing);
      final registry = BusyBooksCommandCatalog.metadata;
      expect(registry.commands.any((c) => c.id.contains('import')), isFalse);
      for (final id in [
        BusyBooksCommandIds.open,
        BusyBooksCommandIds.openCollection,
        BusyBooksCommandIds.createCollection,
        BusyBooksCommandIds.addBooks,
      ]) {
        expect(registry[id], isNotNull);
      }
    },
  );
  testWidgets(
    'queued opens finish after their originating Welcome route is disposed',
    (tester) async {
      final model = _NavigationState();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(readerChannel, (_) async => null);
      addTearDown(
        () => messenger.setMockMethodCallHandler(readerChannel, null),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceControllerProvider.overrideWith(() => model),
            readerControllerProvider.overrideWith(_NavigationReader.new),
            startupAppSettingsProvider.overrideWithValue(
              StartupAppSettings(AppSettings(), _SettingsStore()),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp.router(
              theme: buildBusyBooksTheme(
                brightness: Brightness.light,
                accentColor: busyBooksDefaultAccentColor,
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: ref.watch(appRouterProvider),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = tester.element(find.byType(WelcomeScreen));
      final originRef = origin as WidgetRef;
      final container = ProviderScope.containerOf(origin, listen: false);
      final a = openPaths(origin, originRef, paths: ['/fixtures/a.epub']);
      final b = openPaths(origin, originRef, paths: ['/fixtures/b.epub']);
      model.first.complete();
      await tester.pumpAndSettle();
      expect(origin.mounted, isFalse);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/read/${'a'.padRight(64, 'a')}',
      );
      model.second.complete();
      await tester.pumpAndSettle();
      await Future.wait([a, b]);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/read/${'b'.padRight(64, 'b')}',
      );
      expect(
        container.read(workspaceControllerProvider).workspace!.path,
        '/fixtures/b.epub',
      );
      expect(
        container.read(readerControllerProvider).bookId,
        'b'.padRight(64, 'b'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
