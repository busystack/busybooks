import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:busybooks/src/app/app_router.dart';
import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/app/system_accent.dart';
import 'package:busybooks/src/book_workspace/presentation/book_workspace_screen.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/notebook/application/notebook_controller.dart';
import 'package:busybooks/src/notebook/presentation/book_view_selector.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';
import 'package:busybooks/src/search/book_search_widgets.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Settings implements LocalSettingsStore {
  @override
  Future<Map<String, dynamic>> load() async => {};
  @override
  Future<void> save(Map<String, dynamic> value) async {}
}

void main() {
  testWidgets(
    'cancelling Discard retains the draft and resumes autosave',
    (tester) => _discardRegression(tester, mode: 'cancel'),
  );
  testWidgets(
    'Notebook menu deletion remains deleted through export, backup and reopen',
    (tester) => _discardRegression(tester, mode: 'delete'),
  );

  testWidgets(
    'confirmed Discard outlives autosave and restores the saved note in UI, export, backup and reopen',
    _discardRegression,
  );

  testWidgets(
    'Notebook reads, edits, filters and searches missing-book notes without a native reader',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory owned;
      late ReadingDataStore store;
      late ProviderContainer container;
      late String id;
      await tester.runAsync(() async {
        owned = await Directory.systemTemp.createTemp('busybooks-notebook-ui-');
        final file = await File(
          'test/fixtures/text.pdf',
        ).copy(p.join(owned.path, 'original.pdf'));
        store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
        container = ProviderContainer(
          overrides: [
            readingDataStoreProvider.overrideWithValue(store),
            startupAppSettingsProvider.overrideWithValue(
              StartupAppSettings(AppSettings(), _Settings()),
            ),
          ],
        );
        final workspace = container.read(workspaceControllerProvider.notifier);
        id = (await workspace.openPath(file.path)).books.single.id;
        await workspace.saveAnnotation(
          ReadingAnnotation({
            'id': 'annotation-ui-highlight',
            'bookId': id,
            'annotationKind': 'highlight',
            'anchor': {'page': 0},
            'text': 'Saved quotation',
            'note': 'Initial private note',
            'reference': 'Page 1',
            'color': 'yellow',
            'created': 1,
          }),
        );
        await workspace.saveAnnotation(
          ReadingAnnotation({
            'id': 'annotation-ui-bookmark',
            'bookId': id,
            'annotationKind': 'bookmark',
            'anchor': {'page': 1},
            'text': '',
            'note': 'Bookmark detail',
            'reference': 'Page 2',
            'color': 'blue',
            'created': 2,
          }),
        );
        await file.delete();
        await workspace.loadBook(id, activate: true);
      });
      var nativeOpens = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(readerChannel, (call) async {
        if (call.method == 'open') nativeOpens++;
        return null;
      });
      try {
        container.read(appRouterProvider).go('/notebook/$id');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildBusyBooksTheme(
                brightness: Brightness.light,
                accentColor: busyBooksDefaultAccentColor,
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: BookWorkspaceScreen(view: BookView.notebook, id: id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Saved quotation'), findsOneWidget);
        expect(
          find.textContaining('original book is unavailable'),
          findsOneWidget,
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(
              const ValueKey('notebook-item-annotation-ui-highlight'),
            ),
            matching: find.text('Edit Note'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          'Edited\nmultiline personal note',
        );
        await tester.pump(const Duration(milliseconds: 750));
        final deadline = Stopwatch()..start();
        while (container.read(notebookControllerProvider).drafts.isNotEmpty ||
            container.read(notebookControllerProvider).resolving.isNotEmpty) {
          if (deadline.elapsed > const Duration(seconds: 15)) {
            fail('Notebook save did not complete');
          }
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pumpAndSettle();
        expect(
          container
              .read(workspaceControllerProvider)
              .annotations
              .singleWhere((a) => a.id == 'annotation-ui-highlight')
              .note,
          'Edited\nmultiline personal note',
        );
        await tester.tap(find.byTooltip('Type'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bookmarks'));
        await tester.pumpAndSettle();
        expect(find.text('Saved quotation'), findsNothing);
        expect(find.text('Bookmark detail'), findsOneWidget);
        await tester.tap(find.byTooltip('Type'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('All types'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is BusyBooksHeaderIconButton && w.tooltip == 'Search',
          ),
        );
        await tester.pumpAndSettle();
        final search = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Notebook',
        );
        await tester.enterText(search, 'personal');
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(BookSearchSidebar),
            matching: find.text('Saved quotation'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(BookSearchSidebar),
            matching: find.text('Bookmark detail'),
          ),
          findsNothing,
        );
        expect(nativeOpens, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        messenger.setMockMethodCallHandler(readerChannel, null);
        container.dispose();
        await tester.runAsync(() async {
          await store.close();
          await owned.delete(recursive: true);
        });
      }
    },
  );
}

Future<void> _discardRegression(
  WidgetTester tester, {
  String mode = 'discard',
}) async {
  final expected = mode == 'delete'
      ? null
      : mode == 'cancel'
      ? 'Discarded edit'
      : 'Saved baseline';
  final expectedNotes = expected == null ? <String>[] : [expected];
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late Directory owned;
  late ReadingDataStore store;
  late ProviderContainer container;
  late String id;
  await tester.runAsync(() async {
    owned = await Directory.systemTemp.createTemp('busybooks-discard-ui-');
    store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
    container = ProviderContainer(
      overrides: [
        readingDataStoreProvider.overrideWithValue(store),
        startupAppSettingsProvider.overrideWithValue(
          StartupAppSettings(AppSettings(), _Settings()),
        ),
      ],
    );
    final workspace = container.read(workspaceControllerProvider.notifier);
    id = (await workspace.openPath(
      p.absolute('test/fixtures/text.pdf'),
    )).books.single.id;
    await workspace.saveAnnotation(
      ReadingAnnotation({
        'id': 'annotation-ui-discard',
        'bookId': id,
        'annotationKind': 'bookmark',
        'anchor': {'page': 0},
        'text': '',
        'note': 'Saved baseline',
        'reference': 'Page 1',
        'color': 'yellow',
        'created': 1,
      }),
    );
  });
  try {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildBusyBooksTheme(
            brightness: Brightness.light,
            accentColor: busyBooksDefaultAccentColor,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BookWorkspaceScreen(view: BookView.notebook, id: id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Discarded edit');
    await tester.pump();
    if (mode == 'delete') {
      await tester.tap(find.byTooltip('Annotation Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
    } else {
      await tester.tap(find.text('Discard'));
    }
    await tester.pumpAndSettle();
    expect(find.byType(BusyBooksDialogShell), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.tap(
      find
          .descendant(
            of: find.byType(BusyBooksDialogShell),
            matching: find.text(
              mode == 'delete'
                  ? 'Delete'
                  : mode == 'cancel'
                  ? 'Cancel'
                  : 'Discard',
            ),
          )
          .last,
    );
    await tester.pumpAndSettle();
    if (mode == 'cancel') await tester.pump(const Duration(milliseconds: 750));
    final watch = Stopwatch()..start();
    while (container.read(notebookControllerProvider).drafts.isNotEmpty ||
        container.read(notebookControllerProvider).resolving.isNotEmpty) {
      if (watch.elapsed > const Duration(seconds: 60)) {
        fail('Discard did not finish');
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    if (expected != null) {
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        expected,
      );
    } else {
      expect(find.byType(TextField), findsNothing);
    }
    await tester.runAsync(() async {
      expect(
        (await store.call('annotations', id) as List)
            .map((r) => r['note'])
            .toList(),
        expectedNotes,
      );
      final output = p.join(owned.path, 'notes.md');
      await store.call('exportMarkdown', {'id': id, 'path': output});
      final markdown = await File(output).readAsString();
      if (expected != null) expect(markdown, contains(expected));
      if (mode != 'cancel') expect(markdown, isNot(contains('Discarded edit')));
      if (mode == 'delete') expect(markdown, isNot(contains('Saved baseline')));
      final backup = p.join(owned.path, 'data.busybooks');
      await store.call('backup', {
        'path': backup,
        'preferences': <String, dynamic>{},
      });
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
        (manifest['records'] as List)
            .where((r) => r['kind'] == 'annotation')
            .map((r) => r['note'])
            .toList(),
        expectedNotes,
      );
    });
    await tester.pumpWidget(const SizedBox.shrink());
  } finally {
    container.dispose();
    await tester.runAsync(() async {
      await store.close();
      final reopened = await ReadingDataStore.open(
        p.join(owned.path, 'profile'),
      );
      try {
        expect(
          (await reopened.call('annotations', id) as List)
              .map((r) => r['note'])
              .toList(),
          expectedNotes,
        );
      } finally {
        await reopened.close();
        await owned.delete(recursive: true);
      }
    });
  }
}
