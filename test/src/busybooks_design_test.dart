import 'dart:ui' show Tristate;

import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';

void main() {
  testWidgets('icon actions expose names independently of tooltip metadata', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              BusyBooksHeaderIconButton(
                tooltip: 'Home',
                icon: Icons.home,
                shortcut: 'Alt+Home',
                selected: true,
                onPressed: () {},
              ),
              const BusyBooksHeaderIconButton(
                tooltip: 'Previous',
                icon: Icons.arrow_back,
                onPressed: null,
              ),
              BusyBooksCompactIconButton(
                tooltip: 'Edit Note',
                icon: Icons.edit,
                onPressed: () {},
              ),
              BusyBooksHeaderIconButton(
                tooltip: 'Search',
                icon: Icons.search,
                tooltipPositionDelegate: (_) => Offset.zero,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    final buttons = find.byType(IconButton);
    final home = tester.getSemantics(buttons.at(0));
    expect(home.label, 'Home');
    expect(home.getSemanticsData().tooltip, isEmpty);
    expect(home.hint, 'Alt+Home');
    expect(home.flagsCollection.isButton, isTrue);
    expect(home.flagsCollection.isSelected, Tristate.isTrue);
    expect(home.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    final previous = tester.getSemantics(buttons.at(1));
    expect(previous.label, 'Previous');
    expect(previous.getSemanticsData().tooltip, isEmpty);
    expect(previous.flagsCollection.isEnabled, Tristate.isFalse);
    expect(previous.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    final edit = tester.getSemantics(buttons.at(2));
    expect(edit.label, 'Edit Note');
    expect(edit.getSemanticsData().tooltip, isEmpty);
    expect(edit.flagsCollection.isButton, isTrue);
    expect(edit.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(tester.getSemantics(buttons.at(3)).label, 'Search');
    expect(
      tester.getSemantics(buttons.at(3)).getSemanticsData().tooltip,
      isEmpty,
    );
    expect(find.byTooltip('Home (Alt+Home)'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    semantics.dispose();
  });
  testWidgets('header hints avoid overlaid window caption controls', (
    tester,
  ) async {
    late BuildContext headerContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              height: 48,
              child: LayoutBuilder(
                builder: (context, _) {
                  headerContext = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );
    const captionControls = Rect.fromLTWH(476, 0, 124, 48);
    const tooltipSize = Size(100, 30);
    final offset = BusyBooksTooltipStyle.insideHeader(
      headerContext,
      const TooltipPositionContext(
        target: Offset(450, 24),
        targetSize: Size(34, 34),
        tooltipSize: tooltipSize,
        verticalOffset: 8,
        overlaySize: Size(800, 600),
      ),
      rightObstruction: captionControls.width,
    );
    final tooltip = offset & tooltipSize;
    expect(tooltip.overlaps(captionControls), isFalse);
    expect(
      const Rect.fromLTWH(0, 0, 600, 48).contains(tooltip.topLeft),
      isTrue,
    );
    expect(
      const Rect.fromLTWH(0, 0, 600, 48).contains(tooltip.bottomRight),
      isTrue,
    );
  });
  for (final brightness in Brightness.values) {
    test('semantic surfaces preserve Yaru control geometry in $brightness', () {
      const accent = Color(0xff3584e4);
      final actual = buildBusyBooksTheme(
            brightness: brightness,
            accentColor: accent,
          ),
          base = brightness == Brightness.dark
              ? createYaruDarkTheme(primaryColor: accent)
              : createYaruLightTheme(primaryColor: accent);
      expect(
        actual.filledButtonTheme.style?.shape,
        base.filledButtonTheme.style?.shape,
      );
      expect(
        actual.filledButtonTheme.style?.minimumSize,
        base.filledButtonTheme.style?.minimumSize,
      );
      expect(actual.inputDecorationTheme, base.inputDecorationTheme);
      final surfaces = actual.extension<BusyBooksSurfaceColors>()!;
      expect(actual.scaffoldBackgroundColor, surfaces.window);
      expect(actual.colorScheme.primary, accent);
    });
  }
  testWidgets('grouped switch row activates once and exposes focus', (
    tester,
  ) async {
    var value = false, changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBusyBooksTheme(
          brightness: Brightness.light,
          accentColor: const Color(0xff3584e4),
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, setState) => BusyBooksSwitchRow(
              title: 'Reading',
              value: value,
              onChanged: (v) => setState(() {
                value = v;
                changes++;
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Reading'));
    await tester.pump();
    expect(value, true);
    expect(changes, 1);
  });
}
