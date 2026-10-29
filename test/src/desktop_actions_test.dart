import 'package:busybooks/src/app/busybooks_search_field.dart';
import 'package:busybooks/src/search/book_search_session.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:busybooks/src/app/app_router.dart';
import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/app/busybooks_dialogs.dart';
import 'package:busybooks/src/app/busybooks_toast.dart';
import 'package:busybooks/src/app/command_registry.dart';
import 'package:busybooks/src/app/product_actions.dart';
import 'package:busybooks/src/app/settings_screen.dart';
import 'package:busybooks/src/app/system_accent.dart';
import 'package:busybooks/src/book_workspace/application/book_presentation.dart';
import 'package:busybooks/src/book_workspace/presentation/book_header.dart';
import 'package:busybooks/src/book_workspace/application/book_sidebar_controller.dart';
import 'package:busybooks/src/library/application/collection_view_controller.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/library/presentation/collection_screen.dart';
import 'package:busybooks/src/notebook/application/notebook_controller.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';
import 'package:busybooks/src/reading/presentation/reader_screen.dart';
import 'package:busybooks/src/workspace/presentation/welcome_screen.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
import 'package:busybooks/src/workspace/workspace_model.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/annotation_store_gate.dart';

class _Settings implements LocalSettingsStore {
  _Settings({this.failWrites = false});
  final bool failWrites;
  @override
  Future<Map<String, dynamic>> load() async => {};
  @override
  Future<void> save(Map<String, dynamic> value) async {
    if (failWrites) throw FileSystemException('Fixture settings write failed');
  }
}

// These UI-only native doubles model the renderer's owned pause/resume reply;
// the production controller still waits for the same session and revision.
void _acknowledgeRendererLayout(MethodCall call) {
  if (call.method != 'dispatch') return;
  final command = jsonDecode(call.arguments as String) as Map;
  if (command['action'] != 'layoutVisibility') return;
  scheduleMicrotask(() {
    ServicesBinding.instance.channelBuffers.push(
      readerChannel.name,
      readerChannel.codec.encodeMethodCall(
        MethodCall(
          'event',
          jsonEncode({
            'type': 'layoutVisibility',
            'session': command['session'],
            'request': command['request'],
            'revision': command['revision'],
            'visible': command['visible'],
          }),
        ),
      ),
      (_) {},
    );
  });
}

// Keep the real reader opening, visibility, watch and close implementation;
// readiness/flush acknowledgements normally come from the native renderer.
class _UiReader extends ReaderController {
  final requestedVisibility = <bool>[];
  @override
  Future<void> show(bool value) {
    requestedVisibility.add(value);
    return super.show(value);
  }

  Future<void> Function()? beforeFlush;
  @override
  Future<void> flush() async {
    await beforeFlush?.call();
  }

  @override
  Future<void> open(String id) async {
    await super.open(id);
    state = state.copy(ready: state.error == null);
  }
}

class _NotebookFlushGate extends NotebookController {
  bool armed = false;
  final entered = Completer<void>(), proceed = Completer<void>();
  @override
  Future<void> flush() async {
    if (armed && !entered.isCompleted) {
      entered.complete();
      await proceed.future;
    }
    await super.flush();
  }
}

class _MovePicker extends FileSelectorPlatform {
  _MovePicker(this.destination);
  final String destination;
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => destination;
}

class _Picker extends FileSelectorPlatform {
  _Picker(this.path);
  final String path;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile(path);
}

class _ExportPicker extends FileSelectorPlatform {
  _ExportPicker(this.path);
  final String path;
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => FileSaveLocation(path);
}

// Only gate RPC entry; parsing/validation/restoration still use the real worker.
// This forces restoration to finish after Settings is actually disposed.
class _GatedRestore implements ReadingDataStore {
  _GatedRestore(this.store, {this.action = 'restore'});
  final String action;
  final ReadingDataStore store;
  final entered = Completer<void>(), proceed = Completer<void>();
  @override
  String get root => store.root;
  @override
  Stream<Map<String, dynamic>> get progress => store.progress;
  @override
  Stream<int> get changes => store.changes;
  @override
  int get searchRevision => store.searchRevision;
  @override
  Future<dynamic> call(String action, [Object? argument]) async {
    if (action == this.action) {
      entered.complete();
      await proceed.future;
    }
    return store.call(action, argument);
  }

  @override
  void cancel() => store.cancel();
  @override
  Future<void> close() => store.close();
}

class _BookOpeningGate extends _GatedRestore {
  _BookOpeningGate(super.store, this.bookId, {this.gateAction = 'openMember'});
  final String bookId;
  final String gateAction;
  @override
  Future<dynamic> call(String action, [Object? argument]) async {
    final id = argument is Map ? argument['id'] : argument;
    if (action == gateAction && id == bookId && !entered.isCompleted) {
      entered.complete();
      await proceed.future;
    }
    return store.call(action, argument);
  }
}

Widget _app(
  ReadingDataStore store,
  LocalSettingsStore settings, {
  bool gateNotebookFlush = false,
}) => ProviderScope(
  overrides: [
    readingDataStoreProvider.overrideWithValue(store),
    startupAppSettingsProvider.overrideWithValue(
      StartupAppSettings(AppSettings(), settings),
    ),
    readerControllerProvider.overrideWith(_UiReader.new),
    if (gateNotebookFlush)
      notebookControllerProvider.overrideWith(_NotebookFlushGate.new),
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
      builder: (c, child) => BusyBooksCommandRegistryScope(
        registry: BusyBooksCommandCatalog.create(
          executions: {
            BusyBooksCommandIds.backToCollection: () =>
                returnToWorkspace(c, ref),
            BusyBooksCommandIds.welcome: () => closeWorkspace(c, ref),
          },
        ),
        child: BusyBooksToastOverlay(child: child!),
      ),
    ),
  ),
);

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final elapsed = Stopwatch()..start();
  while (!condition()) {
    if (elapsed.elapsed > const Duration(seconds: 60)) {
      fail('UI condition timed out');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump();
}

// Let both the real worker and the widget test's queued frames/microtasks run.
Future<void> _action(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  var done = false;
  Object? failure;
  StackTrace? stack;
  await tester.runAsync(() async {
    action().then<void>(
      (_) {
        done = true;
      },
      onError: (Object error, StackTrace trace) {
        failure = error;
        stack = trace;
        done = true;
      },
    );
  });
  await _until(tester, () => done);
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('yaru_window'),
      (call) async => call.method == 'state' ? <String, Object?>{} : null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('yaru_window/events'),
      MockStreamHandler.inline(onListen: (_, _) {}, onCancel: (_) {}),
    );
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('yaru_window'),
      null,
    );
    messenger.setMockStreamHandler(
      const EventChannel('yaru_window/events'),
      null,
    );
  });
  test('Settings accepts only a validated Split book return target', () {
    final id = 'a' * 64;
    expect(safeSettingsReturnTarget('/split/$id'), '/split/$id');
    for (final target in [
      '/split/$id/extra',
      '/split/$id?redirect=https://example.com',
      '/split/unknown',
      'https://example.com/split/$id',
    ]) {
      expect(safeSettingsReturnTarget(target), '/');
    }
  });

  for (final recent in [false, true]) {
    for (final excursion in [false, true]) {
      testWidgets(
        '${recent ? 'Recent' : 'Books'} opening ${excursion ? 'rejects a retained-route excursion' : 'preserves its originating Split target'}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1500, 900);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          late Directory owned;
          late ReadingDataStore store;
          late Book target;
          await tester.runAsync(() async {
            owned = await Directory.systemTemp.createTemp(
              'busybooks-split-open-',
            );
            store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
            final data =
                await store.call('openPath', {
                      'path': p.absolute('test/fixtures/reflowable.epub'),
                    })
                    as Map;
            target = Book(
              ((data['books'] as List).single as Map).cast<String, dynamic>(),
            );
          });
          final gated = _BookOpeningGate(
            store,
            target.id,
            gateAction: recent ? 'book' : 'openMember',
          );
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(readerChannel, (call) async {
            _acknowledgeRendererLayout(call);
            return null;
          });
          Future<void>? pending;
          try {
            await tester.pumpWidget(_app(gated, _Settings()));
            await tester.pumpAndSettle();
            final home = tester.element(find.byType(WelcomeScreen));
            final container = ProviderScope.containerOf(home, listen: false);
            await _action(
              tester,
              () => openPaths(
                home,
                home as WidgetRef,
                paths: [p.absolute('test/fixtures/text.pdf')],
              ),
            );
            await _until(
              tester,
              () => container.read(readerControllerProvider).ready,
            );
            final router = container.read(appRouterProvider);
            final original = container.read(readerControllerProvider).bookId!;
            router.go(BookView.split.routeFor(original));
            await tester.pumpAndSettle();
            final header = tester.element(find.byType(BookHeader));
            await tester.runAsync(() async {
              pending = recent
                  ? openRecent(
                      header,
                      header as WidgetRef,
                      RecentResource({
                        'resourceKind': 'book',
                        'resourceId': target.id,
                        'title': target.title,
                        'path': target.path,
                      }),
                    )
                  : openBook(header, header as WidgetRef, target);
            });
            await _until(tester, () => gated.entered.isCompleted);
            if (excursion) {
              router.go(BookView.reading.routeFor(original));
              await tester.pumpAndSettle();
              router.go(BookView.split.routeFor(original));
              await tester.pumpAndSettle();
              expect(
                header.mounted,
                isTrue,
                reason:
                    'the guard must reject excursions even when the shell survives',
              );
            }
            gated.proceed.complete();
            await _action(tester, () => pending!);
            await _until(tester, () {
              final state = container.read(readerControllerProvider);
              return state.bookId == (excursion ? original : target.id) &&
                  state.ready;
            });
            await tester.pumpAndSettle();
            expect(
              router.routeInformationProvider.value.uri.path,
              BookView.split.routeFor(excursion ? original : target.id),
            );
            expect(
              container.read(workspaceControllerProvider).openedBook!.id,
              excursion ? original : target.id,
            );
            expect(tester.takeException(), isNull);
          } finally {
            if (!gated.proceed.isCompleted) gated.proceed.complete();
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            messenger.setMockMethodCallHandler(readerChannel, null);
            await tester.runAsync(() async {
              await store.close();
              await owned.delete(recursive: true);
            });
          }
        },
      );
    }
  }

  for (final invalidation in ['none', 'query', 'source']) {
    testWidgets(
      'missing book recovery ${invalidation == 'none' ? 'retains Split and saved notes' : 'revalidates $invalidation after its dialog'}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1500, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late Directory owned;
        late ReadingDataStore store;
        late Book target;
        await tester.runAsync(() async {
          owned = await Directory.systemTemp.createTemp(
            'busybooks-split-recovery-',
          );
          store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
          final original = await File(
            'test/fixtures/reflowable.epub',
          ).copy(p.join(owned.path, 'missing.epub'));
          final data =
              await store.call('openPath', {'path': original.path}) as Map;
          target = Book(
            ((data['books'] as List).single as Map).cast<String, dynamic>(),
          ).copy({'status': 'missing'});
          await store.call('putAnnotation', {
            'id': 'annotation-recovery',
            'kind': 'annotation',
            'bookId': target.id,
            'annotationKind': 'bookmark',
            'anchor': {'cfi': 'epubcfi(/6/2!/4/2/1:0)', 'index': 0},
            'text': '',
            'note': 'Saved target note',
            'color': 'yellow',
            'created': 1,
          });
          await original.delete();
        });
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(readerChannel, (call) async {
          _acknowledgeRendererLayout(call);
          return null;
        });
        var queryCurrent = true, sourceCurrent = true, validations = 0;
        try {
          await tester.pumpWidget(_app(store, _Settings()));
          await tester.pumpAndSettle();
          final home = tester.element(find.byType(WelcomeScreen));
          final container = ProviderScope.containerOf(home, listen: false);
          await _action(
            tester,
            () => openPaths(
              home,
              home as WidgetRef,
              paths: [p.absolute('test/fixtures/text.pdf')],
            ),
          );
          await _until(
            tester,
            () => container.read(readerControllerProvider).ready,
          );
          final router = container.read(appRouterProvider);
          final original = container.read(readerControllerProvider).bookId!;
          router.go(BookView.split.routeFor(original));
          await tester.pumpAndSettle();
          final header = tester.element(find.byType(BookHeader));
          late Future<void> pending;
          await tester.runAsync(() async {
            pending = openBook(
              header,
              header as WidgetRef,
              target,
              canActivate: () => queryCurrent,
              validateActivation: () async {
                validations++;
                return sourceCurrent;
              },
            );
          });
          await _until(
            tester,
            () => find.byType(BusyBooksDialogShell).evaluate().isNotEmpty,
          );
          if (invalidation == 'query') queryCurrent = false;
          if (invalidation == 'source') sourceCurrent = false;
          await tester.tap(
            find.descendant(
              of: find.byType(BusyBooksDialogShell),
              matching: find.widgetWithText(BusyBooksDialogButton, 'Notebook'),
            ),
          );
          await _action(tester, () => pending);
          await _until(tester, () {
            final state = container.read(readerControllerProvider);
            return state.bookId ==
                    (invalidation == 'none' ? target.id : original) &&
                (state.ready || state.error != null);
          });
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            BookView.split.routeFor(
              invalidation == 'none' ? target.id : original,
            ),
          );
          if (invalidation == 'none') {
            expect(find.text('Saved target note'), findsOneWidget);
          } else {
            expect(
              container.read(workspaceControllerProvider).openedBook!.id,
              original,
            );
          }
          if (invalidation == 'source') {
            expect(validations, greaterThanOrEqualTo(2));
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          messenger.setMockMethodCallHandler(readerChannel, null);
          await tester.runAsync(() async {
            await store.close();
            await owned.delete(recursive: true);
          });
        }
      },
    );
  }
  for (final handoff in ['owned', 'queued book', 'note flush']) {
    testWidgets('Split move preserves reader ownership during $handoff', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory owned;
      late ReadingDataStore store;
      late File original;
      late Directory destination;
      late Book other;
      await tester.runAsync(() async {
        owned = await Directory.systemTemp.createTemp('busybooks-split-move-');
        store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
        original = await File(
          'test/fixtures/text.pdf',
        ).copy(p.join(owned.path, 'source.pdf'));
        destination = await Directory(
          p.join(owned.path, 'destination'),
        ).create();
        final data =
            await store.call('openPath', {
                  'path': p.absolute('test/fixtures/reflowable.epub'),
                })
                as Map;
        other = Book(
          ((data['books'] as List).single as Map).cast<String, dynamic>(),
        );
      });
      final previousPicker = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _MovePicker(destination.path);
      ReaderController? activeReader;
      final closedBooks = <String?>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(readerChannel, (call) async {
        _acknowledgeRendererLayout(call);
        if (call.method == 'close') closedBooks.add(activeReader?.stateBookId);
        return null;
      });
      final queueEntered = Completer<void>(),
          startOther = Completer<void>(),
          finishOther = Completer<void>();
      _NotebookFlushGate? flushGate;
      try {
        await tester.pumpWidget(
          _app(store, _Settings(), gateNotebookFlush: handoff == 'note flush'),
        );
        await tester.pumpAndSettle();
        final home = tester.element(find.byType(WelcomeScreen));
        final container = ProviderScope.containerOf(home, listen: false);
        activeReader = container.read(readerControllerProvider.notifier);
        final reader = activeReader!;
        final workspace = container.read(workspaceControllerProvider.notifier);
        await _action(
          tester,
          () => openPaths(home, home as WidgetRef, paths: [original.path]),
        );
        await _until(
          tester,
          () => container.read(readerControllerProvider).ready,
        );
        final book = container.read(workspaceControllerProvider).openedBook!;
        final router = container.read(appRouterProvider);
        router.go(BookView.split.routeFor(book.id));
        await tester.pumpAndSettle();
        final header = tester.element(find.byType(BookHeader));
        final note = ReadingAnnotation({
          'id': 'annotation-moving',
          'kind': 'annotation',
          'bookId': book.id,
          'annotationKind': 'bookmark',
          'anchor': {'page': 0},
          'text': '',
          'note': 'Before move',
          'color': 'yellow',
          'created': 1,
        });
        await _action(tester, () => workspace.saveAnnotation(note));
        Future<void>? queued;
        if (handoff == 'queued book') {
          await tester.runAsync(() async {
            queued = workspace.navigate(() async {
              queueEntered.complete();
              await startOther.future;
              final prepared = await workspace.prepareBook(other);
              await reader.close();
              await workspace.activateBook(prepared);
              await reader.open(other.id);
              router.go(BookView.split.routeFor(other.id));
              await finishOther.future;
            });
          });
          await _until(tester, () => queueEntered.isCompleted);
        } else if (handoff == 'note flush') {
          flushGate =
              container.read(notebookControllerProvider.notifier)
                  as _NotebookFlushGate;
          flushGate.armed = true;
        }
        late Future<void> moving;
        await tester.runAsync(() async {
          moving = moveBook(header, header as WidgetRef, book);
        });
        await _until(
          tester,
          () => find.byType(BusyBooksDialogShell).evaluate().isNotEmpty,
        );
        await tester.tap(
          find.descendant(
            of: find.byType(BusyBooksDialogShell),
            matching: find.widgetWithText(BusyBooksDialogButton, 'Move Book'),
          ),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        String? replacementSession;
        if (handoff == 'queued book') {
          startOther.complete();
          await _until(
            tester,
            () =>
                router.routeInformationProvider.value.uri.path ==
                    BookView.split.routeFor(other.id) &&
                container.read(readerControllerProvider).ready,
          );
          await tester.pumpAndSettle();
          closedBooks.clear();
          replacementSession = reader.sessionId;
          finishOther.complete();
        } else if (handoff == 'note flush') {
          await _until(tester, () => flushGate!.entered.isCompleted);
          container
              .read(notebookControllerProvider.notifier)
              .edit(note, 'Saved during moving handoff');
          await _action(tester, () async {
            final prepared = await workspace.prepareBook(other);
            await reader.close();
            await workspace.activateBook(prepared);
            await reader.open(other.id);
            router.go(BookView.split.routeFor(other.id));
          });
          await tester.pumpAndSettle();
          closedBooks.clear();
          replacementSession = reader.sessionId;
          flushGate!.proceed.complete();
        }
        if (queued != null) await _action(tester, () => queued!);
        await _action(tester, () => moving);
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.path,
          BookView.split.routeFor(handoff == 'owned' ? book.id : other.id),
        );
        expect(reader.stateBookId, handoff == 'owned' ? book.id : other.id);
        expect(container.read(readerControllerProvider).ready, isTrue);
        if (replacementSession != null) {
          expect(reader.sessionId, replacementSession);
          expect(closedBooks, isNot(contains(other.id)));
        }
        await tester.runAsync(() async {
          expect(await original.exists(), isFalse);
          expect(
            await File(p.join(destination.path, 'source.pdf')).exists(),
            isTrue,
          );
          if (handoff == 'note flush') {
            expect(
              (await store.call('annotations', book.id) as List).single['note'],
              'Saved during moving handoff',
            );
          }
        });
        expect(tester.takeException(), isNull);
      } finally {
        if (!startOther.isCompleted) startOther.complete();
        if (!finishOther.isCompleted) finishOther.complete();
        if (flushGate != null && !flushGate.proceed.isCompleted) {
          flushGate.proceed.complete();
        }
        FileSelectorPlatform.instance = previousPicker;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        messenger.setMockMethodCallHandler(readerChannel, null);
        await tester.runAsync(() async {
          await store.close();
          await owned.delete(recursive: true);
        });
      }
    });
  }
  for (final operation in ['backup', 'export']) {
    testWidgets(
      '$operation snapshots a note delivered by the reader flush acknowledgement',
      (tester) async {
        late Directory owned;
        late ReadingDataStore store;
        await tester.runAsync(() async {
          owned = await Directory.systemTemp.createTemp(
            'busybooks-backup-late-note-',
          );
          store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
        });
        final previous = FileSelectorPlatform.instance;
        final backup = p.join(owned.path, 'reading.busybooks');
        FileSelectorPlatform.instance = _ExportPicker(backup);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(readerChannel, (call) async {
          _acknowledgeRendererLayout(call);
          return null;
        });
        try {
          await tester.pumpWidget(_app(store, _Settings()));
          await tester.pumpAndSettle();
          final origin = tester.element(find.byType(WelcomeScreen));
          final container = ProviderScope.containerOf(origin, listen: false);
          final workspace = container.read(
            workspaceControllerProvider.notifier,
          );
          late ReadingAnnotation item;
          await _action(tester, () async {
            final id = (await workspace.openPath(
              p.absolute('test/fixtures/text.pdf'),
            )).books.single.id;
            item = ReadingAnnotation({
              'id': 'annotation-late-snapshot',
              'bookId': id,
              'annotationKind': 'bookmark',
              'anchor': {'page': 0},
              'text': '',
              'note': 'Baseline',
              'color': 'yellow',
              'created': 1,
            });
            await workspace.saveAnnotation(item);
          });
          (container.read(readerControllerProvider.notifier) as _UiReader)
              .beforeFlush = () async {
            container
                .read(notebookControllerProvider.notifier)
                .edit(item, 'Delivered during renderer flush');
          };
          await _action(
            tester,
            () => operation == 'backup'
                ? backupReadingData(origin)
                : exportBook(
                    origin,
                    origin as WidgetRef,
                    container
                        .read(workspaceControllerProvider)
                        .bookById(item.bookId)!,
                  ),
          );
          await tester.runAsync(() async {
            if (operation == 'backup') {
              final manifest =
                  jsonDecode(
                        utf8.decode(
                          ZipDecoder()
                              .decodeBytes(await File(backup).readAsBytes())
                              .files
                              .single
                              .content,
                        ),
                      )
                      as Map;
              expect(
                (manifest['records'] as List).singleWhere(
                  (r) => r['kind'] == 'annotation',
                )['note'],
                'Delivered during renderer flush',
              );
            } else {
              expect(
                await File(backup).readAsString(),
                contains('Delivered during renderer flush'),
              );
            }
            expect(
              (await store.call('annotations', item.bookId) as List)
                  .single['note'],
              'Delivered during renderer flush',
            );
          });
        } finally {
          FileSelectorPlatform.instance = previous;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          messenger.setMockMethodCallHandler(readerChannel, null);
          await tester.runAsync(() async {
            await store.close();
            await owned.delete(recursive: true);
          });
        }
      },
    );
  }
  for (final operation in ['backup', 'export']) {
    testWidgets(
      '$operation refuses to omit a pending creation, retains it and succeeds after retry',
      (tester) async {
        late Directory owned;
        late ReadingDataStore store;
        await tester.runAsync(() async {
          owned = await Directory.systemTemp.createTemp(
            'busybooks-pending-creation-output-',
          );
          store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
        });
        final gate = AnnotationStoreGate(store)..failPut = true;
        final output = p.join(
          owned.path,
          operation == 'backup' ? 'reading.busybooks' : 'notes.md',
        );
        await tester.runAsync(
          () => File(output).writeAsString('Previous destination'),
        );
        final previous = FileSelectorPlatform.instance;
        FileSelectorPlatform.instance = _ExportPicker(output);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(readerChannel, (call) async {
          _acknowledgeRendererLayout(call);
          return null;
        });
        try {
          await tester.pumpWidget(_app(gate, _Settings()));
          await tester.pumpAndSettle();
          final origin = tester.element(find.byType(WelcomeScreen));
          final container = ProviderScope.containerOf(origin, listen: false);
          final workspace = container.read(
            workspaceControllerProvider.notifier,
          );
          late String bookId;
          await _action(tester, () async {
            bookId = (await workspace.openPath(
              p.absolute('test/fixtures/text.pdf'),
            )).books.single.id;
          });
          final notes = container.read(notebookControllerProvider.notifier);
          notes.create(
            ReadingAnnotation({
              'id': 'annotation-pending-output',
              'bookId': bookId,
              'annotationKind': 'highlight',
              'anchor': {'page': 0},
              'text': 'Captured quotation',
              'reference': 'Page 1',
              'note': '',
              'color': 'yellow',
              'created': 1,
            }),
            'Protected output note',
          );
          Future<void> produce() => operation == 'backup'
              ? backupReadingData(origin)
              : exportBook(
                  origin,
                  origin as WidgetRef,
                  container.read(workspaceControllerProvider).bookById(bookId)!,
                );
          late Future<void> producing;
          await tester.runAsync(() async {
            producing = produce();
          });
          await _until(
            tester,
            () => find
                .textContaining('Injected insertion failure')
                .evaluate()
                .isNotEmpty,
          );
          expect(
            find.text(operation == 'backup' ? 'Backup saved' : 'Export saved'),
            findsNothing,
          );
          expect(
            container
                .read(notebookControllerProvider)
                .drafts
                .values
                .single
                .text,
            'Protected output note',
          );
          await tester.runAsync(() async {
            expect(await File(output).readAsString(), 'Previous destination');
            expect(await store.call('annotations', bookId), isEmpty);
          });
          await tester.tap(find.widgetWithText(BusyBooksDialogButton, 'Close'));
          await tester.pumpAndSettle();
          await _action(tester, () => producing);
          gate.failPut = false;
          await _action(tester, produce);
          await tester.runAsync(() async {
            expect(
              (await store.call('annotations', bookId) as List).single['note'],
              'Protected output note',
            );
            if (operation == 'backup') {
              final restored = await ReadingDataStore.open(
                p.join(owned.path, 'restored'),
              );
              try {
                await restored.call('restore', output);
                expect(
                  (await restored.call('annotations', bookId) as List)
                      .single['note'],
                  'Protected output note',
                );
              } finally {
                await restored.close();
              }
            } else {
              expect(
                await File(output).readAsString(),
                contains('Protected output note'),
              );
            }
          });
        } finally {
          FileSelectorPlatform.instance = previous;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          messenger.setMockMethodCallHandler(readerChannel, null);
          await tester.runAsync(() async {
            await store.close();
            await owned.delete(recursive: true);
          });
        }
      },
    );
  }
  testWidgets(
    'shared collection search memory and browsing selection survive entering and leaving a book in a narrow window',
    (tester) async {
      tester.view.physicalSize = const Size(640, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory owned;
      late ReadingDataStore store;
      final paths = <String>[];
      await tester.runAsync(() async {
        owned = await Directory.systemTemp.createTemp(
          'busybooks-collection-ui-',
        );
        store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
        final bytes = await File('test/fixtures/text.pdf').readAsBytes();
        for (var i = 0; i < 24; i++) {
          final file = File(p.join(owned.path, 'Fixture book $i.pdf'));
          await file.writeAsBytes([
            ...bytes,
            ...'\n% Fixture edition $i\n'.codeUnits,
          ]);
          paths.add(file.path);
        }
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(readerChannel, (call) async {
        _acknowledgeRendererLayout(call);
        return null;
      });
      try {
        await tester.pumpWidget(_app(store, _Settings()));
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(WelcomeScreen)),
          listen: false,
        );
        final workspace = container.read(workspaceControllerProvider.notifier);
        await _action(tester, () async {
          await workspace.createCollection('Fixture collection');
          await workspace.addBooks(paths);
          await container.read(appSettingsControllerProvider.notifier).update({
            'grid': false,
          });
          container.read(appRouterProvider).go('/workspace');
        });
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is BusyBooksHeaderIconButton && w.tooltip == 'Search',
          ),
        );
        await tester.pumpAndSettle();
        final query = find.descendant(
          of: find.byKey(const ValueKey('book-header-search')),
          matching: find.byType(TextField),
        );
        await tester.enterText(query, 'book');
        container.read(bookSearchSessionProvider.notifier).close();
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();
        final saved = container
            .read(
              collectionViewProvider(
                container.read(workspaceControllerProvider).workspace!.id,
              ),
            )
            .scrollOffset;
        expect(saved, greaterThan(0));
        final visible = find.byType(BookRow).hitTestable().first;
        final selected = tester.widget<BookRow>(visible).book.id;
        await tester.tap(visible);
        await _until(
          tester,
          () => container.read(readerControllerProvider).ready,
        );
        expect(find.byType(ReadingContent), findsOneWidget);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('book-sidebar-toggle')));
        await tester.pumpAndSettle();
        expect(
          container
              .read(
                bookSidebarProvider(
                  container.read(readerControllerProvider).bookId!,
                ),
              )
              .open,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        // Returning to the collection is a book-context operation.
        await tester.tap(find.byTooltip('Book Actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Back to Collection'));
        await tester.pumpAndSettle();
        await _until(
          tester,
          () => find.byType(CollectionScreen).evaluate().isNotEmpty,
        );
        expect(find.byType(BusyBooksSearchField), findsNothing);
        expect(container.read(bookSearchSessionProvider).query, 'book');
        expect(
          container
              .read(
                collectionViewProvider(
                  container.read(workspaceControllerProvider).workspace!.id,
                ),
              )
              .selectedBook,
          selected,
        );
        expect(
          tester
              .widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller!
              .offset,
          closeTo(saved, .01),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        messenger.setMockMethodCallHandler(readerChannel, null);
        await tester.runAsync(() async {
          await store.close();
          await owned.delete(recursive: true);
        });
      }
    },
  );
  testWidgets(
    'reopening the same file reuses its surface and acknowledges current geometry',
    (tester) async {
      late Directory owned;
      late ReadingDataStore store;
      late File book;
      await tester.runAsync(() async {
        owned = await Directory.systemTemp.createTemp(
          'busybooks-surface-reopen-',
        );
        store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
        book = await File(
          'test/fixtures/text.pdf',
        ).copy(p.join(owned.path, 'book.pdf'));
      });
      var visible = false, opens = 0, bounds = 0;
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(readerChannel, (call) async {
        _acknowledgeRendererLayout(call);
        calls.add(
          '${call.method}${call.method == 'visible' ? ':${call.arguments}' : ''}',
        );
        if (call.method == 'close') visible = false;
        if (call.method == 'visible') visible = call.arguments as bool;
        if (call.method == 'open') opens++;
        if (call.method == 'bounds') bounds++;
        return null;
      });
      try {
        await tester.pumpWidget(_app(store, _Settings()));
        await tester.pumpAndSettle();
        var origin = tester.element(find.byType(WelcomeScreen));
        final container = ProviderScope.containerOf(origin, listen: false);
        await _action(
          tester,
          () => openPaths(origin, origin as WidgetRef, paths: [book.path]),
        );
        await _until(
          tester,
          () => container.read(readerControllerProvider).ready,
        );
        await tester.pumpAndSettle();
        final surface = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_NativeReaderSurface',
        );
        final originalSurface = tester.element(surface);
        expect(
          visible,
          isTrue,
          reason:
              '$calls; route visibility: ${(container.read(readerControllerProvider.notifier) as _UiReader).requestedVisibility}',
        );
        final oldBounds = bounds;
        origin = tester.element(find.byType(ReadingContent));
        await _action(
          tester,
          () => openPaths(origin, origin as WidgetRef, paths: [book.path]),
        );
        await tester.pumpAndSettle();
        expect(opens, 2);
        expect(tester.element(surface), same(originalSurface));
        expect(
          bounds,
          greaterThan(oldBounds),
          reason:
              'a replacement renderer must acknowledge even unchanged bounds',
        );
        expect(
          visible,
          isTrue,
          reason:
              'close/open on a retained reader route must restore native visibility',
        );

        // Reopening while a modal is above that same route must remain hidden.
        final dialog = showBusyBooksModalDialog<void>(
          origin,
          builder: (_) => const BusyBooksDialogShell(
            title: 'Fixture modal',
            children: [Text('Modal content')],
          ),
        );
        await tester.pumpAndSettle();
        expect(visible, isFalse);
        await _action(
          tester,
          () => openPaths(origin, origin as WidgetRef, paths: [book.path]),
        );
        await tester.pumpAndSettle();
        expect(opens, 3);
        expect(visible, isFalse);
        rootNavigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        await dialog;
        expect(visible, isTrue);
        container.read(appRouterProvider).go('/settings');
        await tester.pumpAndSettle();
        expect(visible, isFalse);
        final reader = container.read(readerControllerProvider.notifier);
        final id = container.read(readerControllerProvider).bookId!;
        await _action(tester, () async {
          await reader.close();
          await reader.open(id);
        });
        await tester.pumpAndSettle();
        expect(
          visible,
          isFalse,
          reason: 'opening cannot expose a reader behind an inactive route',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        messenger.setMockMethodCallHandler(readerChannel, null);
        await tester.runAsync(() async {
          await store.close();
          await owned.delete(recursive: true);
        });
      }
    },
  );

  for (final outcome in ['success', 'failed write']) {
    testWidgets(
      'export reports $outcome after the initiating reader is disposed',
      (tester) async {
        late Directory owned;
        late ReadingDataStore store;
        await tester.runAsync(() async {
          owned = await Directory.systemTemp.createTemp(
            'busybooks-export-feedback-',
          );
          store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
        });
        final gated = _GatedRestore(store, action: 'exportMarkdown');
        final output = outcome == 'success'
            ? p.join(owned.path, 'passages.md')
            : owned.path;
        final previousPicker = FileSelectorPlatform.instance;
        FileSelectorPlatform.instance = _ExportPicker(output);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(readerChannel, (call) async {
          _acknowledgeRendererLayout(call);
          return null;
        });
        try {
          await tester.pumpWidget(_app(gated, _Settings()));
          await tester.pumpAndSettle();
          var origin = tester.element(find.byType(WelcomeScreen));
          final container = ProviderScope.containerOf(origin, listen: false);
          await _action(
            tester,
            () => openPaths(
              origin,
              origin as WidgetRef,
              paths: [p.absolute('test/fixtures/text.pdf')],
            ),
          );
          await _until(
            tester,
            () => container.read(readerControllerProvider).ready,
          );
          await tester.pumpAndSettle();
          origin = tester.element(find.byType(ReadingContent));
          late Future<void> operation;
          await tester.runAsync(() async {
            operation = exportBook(
              origin,
              origin as WidgetRef,
              container.read(readerControllerProvider.notifier).book!,
            );
          });
          await _until(tester, () => gated.entered.isCompleted);
          container.read(appRouterProvider).go('/');
          await tester.pumpAndSettle();
          expect(origin.mounted, isFalse);
          gated.proceed.complete();
          if (outcome == 'success') {
            await _action(tester, () => operation);
            expect(find.text('Export saved'), findsOneWidget);
            expect(await tester.runAsync(() => File(output).exists()), isTrue);
          } else {
            await _until(
              tester,
              () => find.text('Error').evaluate().isNotEmpty,
            );
            expect(find.byType(SelectableText), findsOneWidget);
            await tester.tap(
              find.widgetWithText(BusyBooksDialogButton, 'Close'),
            );
            await tester.pumpAndSettle();
            await _action(tester, () => operation);
          }
        } finally {
          FileSelectorPlatform.instance = previousPicker;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          messenger.setMockMethodCallHandler(readerChannel, null);
          await tester.runAsync(() async {
            await store.close();
            await owned.delete(recursive: true);
          });
        }
      },
    );
  }
  for (final outcome in ['success', 'invalid backup', 'failed write']) {
    testWidgets('restore reports $outcome after Settings has been disposed', (
      tester,
    ) async {
      late Directory owned;
      late ReadingDataStore store;
      late File backup;
      await tester.runAsync(() async {
        owned = await Directory.systemTemp.createTemp(
          'busybooks-restore-feedback-',
        );
        store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
        backup = File(p.join(owned.path, 'fixture.busybooks'));
        if (outcome == 'invalid backup') {
          await backup.writeAsString('Invalid fixture backup');
        } else {
          await store.call('backup', {
            'path': backup.path,
            'preferences': {'theme': 'dark'},
          });
        }
      });
      final gated = _GatedRestore(store);
      final previousPicker = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _Picker(backup.path);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(readerChannel, (call) async {
        _acknowledgeRendererLayout(call);
        return null;
      });
      try {
        await tester.pumpWidget(
          _app(gated, _Settings(failWrites: outcome == 'failed write')),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(WelcomeScreen)),
          listen: false,
        );
        container.read(appRouterProvider).go('/settings');
        await tester.pumpAndSettle();
        final settingsContext = tester.element(find.byType(SettingsScreen));
        late Future<void> operation;
        await tester.runAsync(() async {
          operation = backupReadingData(settingsContext, restore: true);
        });
        await tester.pumpAndSettle();
        // This is the production confirmation dialog, not a test replacement.
        await tester.tap(
          find.widgetWithText(BusyBooksDialogButton, 'Restore Backup'),
        );
        await _until(tester, () => gated.entered.isCompleted);
        await tester.pumpAndSettle();
        expect(settingsContext.mounted, isFalse);
        expect(find.byType(WelcomeScreen), findsOneWidget);
        gated.proceed.complete();
        if (outcome == 'success') {
          await _action(tester, () => operation);
          await tester.pumpAndSettle();
          expect(find.text('Backup restored'), findsOneWidget);
          expect(
            container.read(appSettingsControllerProvider).data['theme'],
            'dark',
          );
        } else {
          await _until(tester, () => find.text('Error').evaluate().isNotEmpty);
          if (outcome == 'failed write') {
            expect(
              find.textContaining('Fixture settings write failed'),
              findsOneWidget,
            );
          } else {
            expect(find.byType(SelectableText), findsOneWidget);
          }
          await tester.tap(find.widgetWithText(BusyBooksDialogButton, 'Close'));
          await tester.pumpAndSettle();
          await _action(tester, () => operation);
        }
      } finally {
        FileSelectorPlatform.instance = previousPicker;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        messenger.setMockMethodCallHandler(readerChannel, null);
        await tester.runAsync(() async {
          await store.close();
          await owned.delete(recursive: true);
        });
      }
    });
  }
}
