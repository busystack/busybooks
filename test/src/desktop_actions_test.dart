import 'dart:async';
import 'package:busybooks/src/app/command_registry.dart';
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/notebook/application/notebook_controller.dart';
import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:busybooks/src/app/app_router.dart';
import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/busybooks_dialogs.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/app/busybooks_toast.dart';
import 'package:busybooks/src/app/product_actions.dart';
import 'package:busybooks/src/app/settings_screen.dart';
import 'package:busybooks/src/app/system_accent.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/application/collection_view_controller.dart';
import 'package:busybooks/src/library/presentation/collection_screen.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';
import 'package:busybooks/src/reading/presentation/reader_screen.dart';
import 'package:busybooks/src/workspace/presentation/welcome_screen.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
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

Widget _app(ReadingDataStore store, LocalSettingsStore settings) =>
    ProviderScope(
      overrides: [
        readingDataStoreProvider.overrideWithValue(store),
        startupAppSettingsProvider.overrideWithValue(
          StartupAppSettings(AppSettings(), settings),
        ),
        readerControllerProvider.overrideWith(_UiReader.new),
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
        messenger.setMockMethodCallHandler(readerChannel, (_) async => null);
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
        messenger.setMockMethodCallHandler(readerChannel, (_) async => null);
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
    'collection header query, selection and scroll survive entering and leaving a book in a narrow window',
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
      messenger.setMockMethodCallHandler(readerChannel, (_) async => null);
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
        final query = find.descendant(
          of: find.byKey(const ValueKey('collection-header-search')),
          matching: find.byType(TextField),
        );
        await tester.enterText(query, 'book');
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
        expect(find.byType(ReaderScreen), findsOneWidget);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reader-sidebar-toggle')));
        await tester.pumpAndSettle();
        expect(container.read(readerControllerProvider).panelOpen, isTrue);
        expect(tester.takeException(), isNull);
        // Application navigation moved from Reading's leading arrow to the menu.
        await tester.tap(find.byTooltip('Main Menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Back to Collection'));
        await tester.pumpAndSettle();
        await _until(
          tester,
          () => find.byType(CollectionScreen).evaluate().isNotEmpty,
        );
        expect(tester.widget<TextField>(query).controller!.text, 'book');
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
    'reopening the same file reuses its surface and restores visibility without resizing',
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
        origin = tester.element(find.byType(ReaderScreen));
        await _action(
          tester,
          () => openPaths(origin, origin as WidgetRef, paths: [book.path]),
        );
        await tester.pumpAndSettle();
        expect(opens, 2);
        expect(tester.element(surface), same(originalSurface));
        expect(bounds, oldBounds);
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
        messenger.setMockMethodCallHandler(readerChannel, (_) async => null);
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
          origin = tester.element(find.byType(ReaderScreen));
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
      messenger.setMockMethodCallHandler(readerChannel, (_) async => null);
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
        await tester.tap(find.widgetWithText(BusyBooksDialogButton, 'Open'));
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
