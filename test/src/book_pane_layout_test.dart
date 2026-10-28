import 'package:busybooks/src/book_workspace/application/book_presentation.dart';
import 'package:busybooks/src/book_workspace/presentation/book_pane_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RetainedPane extends StatefulWidget {
  const _RetainedPane({super.key});
  @override
  State<_RetainedPane> createState() => _RetainedPaneState();
}

class _RetainedPaneState extends State<_RetainedPane> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Material(child: TextField(controller: controller));
}

void main() {
  testWidgets(
    'view allocations retain both content elements and editing state',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var view = BookView.reading;
      var ratio = .5;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return BookPaneLayout(
                view: view,
                ratio: ratio,
                readingMinWidth: 400,
                notebookMinWidth: 360,
                dividerLabel: 'Resize panes',
                dividerHint: 'Use arrow keys',
                ratioLabel: (reading, notebook) => '$reading / $notebook',
                prepareResize: () async => true,
                onRatioChanged: (value) => setState(() => ratio = value),
                reading: const _RetainedPane(key: ValueKey('reader-slot')),
                notebook: const _RetainedPane(key: ValueKey('notebook-slot')),
              );
            },
          ),
        ),
      );
      final reader = tester.state<_RetainedPaneState>(
        find.byKey(const ValueKey('reader-slot'), skipOffstage: false),
      );
      final notebook = tester.state<_RetainedPaneState>(
        find.byKey(const ValueKey('notebook-slot'), skipOffstage: false),
      );
      notebook.controller.text = 'Protected draft survives allocations.';
      for (final mode in [
        BookView.notebook,
        BookView.split,
        BookView.reading,
        BookView.split,
      ]) {
        update(() => view = mode);
        await tester.pumpAndSettle();
        expect(
          tester.state(
            find.byKey(const ValueKey('reader-slot'), skipOffstage: false),
          ),
          same(reader),
        );
        expect(
          tester.state(
            find.byKey(const ValueKey('notebook-slot'), skipOffstage: false),
          ),
          same(notebook),
        );
        expect(
          notebook.controller.text,
          'Protected draft survives allocations.',
        );
      }
      expect(
        tester.getSize(find.byKey(const ValueKey('reader-slot'))).width,
        closeTo((1400 - 12) / 2, .01),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('notebook-slot'))).dx,
        closeTo((1400 - 12) / 2 + 12, .01),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('divider keyboard and accessible adjustments obey pane minima', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      var ratio = .5;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => BookPaneLayout(
              view: BookView.split,
              ratio: ratio,
              readingMinWidth: 400,
              notebookMinWidth: 360,
              dividerLabel: 'Resize panes',
              dividerHint: 'Use arrow keys',
              ratioLabel: (reading, notebook) => '$reading / $notebook',
              prepareResize: () async => true,
              onRatioChanged: (value) => update(() => ratio = value),
              reading: const SizedBox.expand(key: ValueKey('reader-slot')),
              notebook: const SizedBox.expand(key: ValueKey('notebook-slot')),
            ),
          ),
        ),
      );
      final divider = find.byKey(const ValueKey('book-split-divider'));
      final focus = tester
          .widget<Focus>(
            find.descendant(of: divider, matching: find.byType(Focus)).first,
          )
          .focusNode!;
      focus.requestFocus();
      await tester.pump();
      final before = tester
          .getSize(find.byKey(const ValueKey('reader-slot')))
          .width;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('reader-slot'))).width,
        closeTo(before + 16, .01),
      );
      for (var index = 0; index < 40; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      }
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('reader-slot'))).width,
        400,
      );
      final data = tester.getSemantics(divider).getSemanticsData();
      expect(data.value, isNotEmpty);
      expect(data.increasedValue, isNotEmpty);
      expect(data.decreasedValue, isNotEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
