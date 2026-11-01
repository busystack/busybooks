import 'package:busybooks/src/app/command_focus.dart';
import 'package:busybooks/src/app/command_registry.dart';
import 'package:busybooks/src/app/keymap_controller.dart';
import 'package:busybooks/src/app/shortcut_binding.dart';
import 'package:busybooks/src/app/command_shortcuts.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/app/busybooks_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'new category defaults yield to saved assignments and Marks keeps its binding',
    () {
      final catalog = BusyBooksCommandCatalog.metadata;
      final marks = catalog[BusyBooksCommandIds.annotations]!.shortcut!.label;
      expect(marks, 'Ctrl+Shift+H');
      final registry = effectiveCommandRegistry(catalog, {
        BusyBooksCommandIds.open: const BusyBooksKeyBinding(
          LogicalKeyboardKey.keyD,
          control: true,
          shift: true,
        ),
        BusyBooksCommandIds.settings: const BusyBooksKeyBinding(
          LogicalKeyboardKey.keyR,
          control: true,
          shift: true,
        ),
      });
      expect(registry[BusyBooksCommandIds.searchBooks]!.shortcut, isNull);
      expect(registry[BusyBooksCommandIds.searchRecent]!.shortcut, isNull);
      expect(registry[BusyBooksCommandIds.searchBookmarks]!.shortcut, isNull);
    },
  );

  test(
    'Split is discoverable without stealing a binding and remains configurable',
    () {
      var enabled = false;
      String? reason(BuildContext _) => 'Needs 772 px of content width.';
      final catalog = BusyBooksCommandCatalog.create(
        executions: {BusyBooksCommandIds.viewSplit: () {}},
        enabled: {BusyBooksCommandIds.viewSplit: () => enabled},
        disabledReasons: {BusyBooksCommandIds.viewSplit: reason},
      );
      final split = catalog[BusyBooksCommandIds.viewSplit]!;
      expect(split.shortcut, isNull);
      expect(split.scope, BusyBooksCommandScope.documentView);
      expect(split.canExecute, isFalse);
      final effective = effectiveCommandRegistry(catalog, {
        BusyBooksCommandIds.viewSplit: const BusyBooksKeyBinding(
          LogicalKeyboardKey.digit3,
          control: true,
          alt: true,
        ),
      })[BusyBooksCommandIds.viewSplit]!;
      expect(effective.shortcut!.label, 'Ctrl+Alt+3');
      expect(effective.disabledReason, same(reason));
      enabled = true;
      expect(effective.canExecute, isTrue);
      expect(
        catalog[BusyBooksCommandIds.viewReading]!.shortcut!.label,
        'Ctrl+Alt+1',
      );
      expect(
        catalog[BusyBooksCommandIds.viewNotebook]!.shortcut!.label,
        'Ctrl+Alt+2',
      );
    },
  );

  testWidgets(
    'visible book Search owns Ctrl+F while Collection Search is hidden',
    (tester) async {
      var bookSearches = 0, collectionSearches = 0, bookEnabled = true;
      final registry = BusyBooksCommandCatalog.create(
        executions: {
          BusyBooksCommandIds.search: () => bookSearches++,
          BusyBooksCommandIds.searchCollection: () => collectionSearches++,
        },
        visible: {BusyBooksCommandIds.searchCollection: () => false},
        enabled: {BusyBooksCommandIds.search: () => bookEnabled},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BusyBooksCommandShortcuts(
            shortcuts: registry.shortcutIntents(
              scopes: const {
                BusyBooksCommandScope.application,
                BusyBooksCommandScope.documentView,
              },
              intentFor: BusyBooksCommandIntent.new,
            ),
            child: Actions(
              actions: {
                BusyBooksCommandIntent: CallbackAction<BusyBooksCommandIntent>(
                  onInvoke: (intent) {
                    registry.execute(intent.commandId);
                    return null;
                  },
                ),
              },
              child: const Focus(autofocus: true, child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(bookSearches, 1);
      expect(collectionSearches, 0);
      bookEnabled = false;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(bookSearches, 1);
      expect(collectionSearches, 0);
    },
  );

  testWidgets(
    'paging keys preserve search editing and button activation while publication focus retains paging',
    (tester) async {
      var pages = 0, activated = 0;
      final book = BusyBooksPublicationFocusNode(),
          button = FocusNode(),
          query = TextEditingController(text: 'quiet library');
      addTearDown(book.dispose);
      addTearDown(button.dispose);
      addTearDown(query.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: BusyBooksCommandShortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.space): BusyBooksCommandIntent(
                BusyBooksCommandIds.next,
              ),
              SingleActivator(LogicalKeyboardKey.pageDown):
                  BusyBooksCommandIntent(BusyBooksCommandIds.next),
              SingleActivator(LogicalKeyboardKey.keyA, control: true):
                  BusyBooksCommandIntent(BusyBooksCommandIds.bookmark),
            },
            child: Actions(
              actions: {
                BusyBooksCommandIntent: CallbackAction<BusyBooksCommandIntent>(
                  onInvoke: (_) {
                    pages++;
                    return null;
                  },
                ),
              },
              child: Scaffold(
                body: Column(
                  children: [
                    BusyBooksSearchField(controller: query, autofocus: true),
                    BusyBooksPushButton.standard(
                      focusNode: button,
                      onPressed: () => activated++,
                      child: const Text('Fixture action'),
                    ),
                    Focus(
                      focusNode: book,
                      child: const SizedBox(width: 200, height: 200),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(pages, 0);
      expect(
        query.selection,
        TextSelection(baseOffset: 0, extentOffset: query.text.length),
      );
      button.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(activated, 1);
      expect(pages, 0);
      book.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(pages, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
