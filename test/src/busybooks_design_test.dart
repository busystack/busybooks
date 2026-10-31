import 'dart:ui' show Tristate;

import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:busybooks/src/platform/native_menu_service.dart';
import 'package:flutter/services.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    testWidgets(
      'text editing uses the $platform native menu and preserves keyboard selection',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final controller = TextEditingController(text: 'Native desktop text');
        final focus = FocusNode();
        Map? menu;
        String? clipboard;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel(nativeMenuChannelName);
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboard?.isNotEmpty == true};
          }
          return null;
        });
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'show') return true;
          menu = call.arguments as Map;
          final rows = menu!['entries'] as List;
          return rows.indexWhere((e) => e['label'] == 'Copy');
        });
        try {
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildBusyBooksTheme(
                brightness: Brightness.light,
                accentColor: const Color(0xff3584e4),
              ),
              home: Scaffold(
                body: BusyBooksGroupedTextEntry(
                  label: 'Destination',
                  controller: controller,
                  focusNode: focus,
                ),
              ),
            ),
          );
          focus.requestFocus();
          await tester.pump();
          controller.selection = const TextSelection(
            baseOffset: 0,
            extentOffset: 6,
          );
          await tester.pump();
          tester
              .state<EditableTextState>(find.byType(EditableText))
              .showToolbar();
          await tester.pumpAndSettle();
          expect(menu, isNotNull);
          expect(
            (menu!['entries'] as List).map((e) => e['label']),
            containsAll(['Copy', 'Cut']),
          );
          expect(clipboard, 'Native');
          expect(controller.text, 'Native desktop text');
          expect(focus.hasFocus, isTrue);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          expect(
            controller.selection,
            const TextSelection(baseOffset: 0, extentOffset: 19),
          );
          expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
          expect(find.byType(MenuAnchor), findsNothing);
          expect(find.byType(PopupMenuItem<int>), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          messenger.setMockMethodCallHandler(channel, null);
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          controller.dispose();
          focus.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets(
    'Go To style entries preserve IME composition and read-only input on physical Enter',
    (tester) async {
      final controller = TextEditingController(text: '23');
      var submits = 0;
      var readOnly = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return BusyBooksGroupedTextEntry(
                  label: 'Page',
                  controller: controller,
                  autofocus: true,
                  readOnly: readOnly,
                  onSubmitted: (_) => submits++,
                );
              },
            ),
          ),
        ),
      );
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 0, end: 2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submits, 0);
      controller.clearComposing();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submits, 1);
      update(() => readOnly = true);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(submits, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
