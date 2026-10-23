import 'package:busybooks/src/app/command_focus.dart';
import 'package:busybooks/src/app/command_registry.dart';
import 'package:busybooks/src/app/command_shortcuts.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/app/busybooks_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
