import 'dart:async';
import 'dart:convert';
import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/core/reading_preferences.dart';
import 'package:busybooks/src/core/typography.dart';
import 'package:busybooks/src/reading/fonts/reading_font_service.dart';
import 'package:busybooks/src/reading/presentation/appearance_panel.dart';
import 'package:busybooks/src/reading/presentation/font_chooser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
);

class _Fonts extends ReadingFontService {
  Completer<FontCatalogue>? pending;
  bool fail = false;
  int loads = 0;
  final previews = <String>[];
  final previewWeights = <int>[];
  final previewGates = <String, Completer<Uint8List>>{};
  List<InstalledFontFamily> families = const [
    InstalledFontFamily('A Family', 'A Family'),
    InstalledFontFamily('日本語 "B", \\', '日本語 "B", \\'),
    InstalledFontFamily('C Family', 'C Family'),
  ];
  @override
  Future<FontCatalogue> catalogue({bool refresh = false}) async {
    loads++;
    if (pending != null) return pending!.future;
    if (fail) throw StateError('Fixture discovery failure');
    return FontCatalogue(families);
  }

  @override
  Future<FontResolution> resolve(FontChoice choice) async => FontResolution(
    choice: choice,
    availability: FontAvailability.available,
    family: choice.name,
    faces: const [
      LocalFontFace(['FixtureFace'], 400, false),
    ],
  );
  @override
  Future<Uint8List> preview(
    FontResolution resolved, {
    required String prose,
    required String bold,
    required String italic,
    required int width,
    required int height,
    required double scale,
    required int foreground,
    required int background,
    double size = 20,
    int weight = 400,
    double line = 1.5,
  }) async {
    previews.add(resolved.family);
    previewWeights.add(weight);
    return previewGates[resolved.family]?.future ?? Future.value(_png);
  }
}

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
  theme: buildBusyBooksTheme(
    brightness: Brightness.light,
    accentColor: Colors.blue,
  ),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);
void main() {
  testWidgets('preview follows the existing body weight when it changes', (
    tester,
  ) async {
    final fonts = _Fonts();
    Widget sample(int weight) => _app(
      SizedBox(
        width: 320,
        height: 160,
        child: FontSample(
          service: fonts,
          choice: FontChoice.serif,
          preferences: {...defaultReadingAppearance, 'weight': weight},
        ),
      ),
    );
    await tester.pumpWidget(sample(300));
    await tester.pumpAndSettle();
    await tester.pumpWidget(sample(600));
    await tester.pumpAndSettle();
    expect(fonts.previewWeights, [300, 600]);
  });
  testWidgets('font rows announce their name and the applied selected state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _app(
          ReadingFontChooser(
            service: _Fonts(),
            selected: FontChoice.serif,
            preferences: defaultReadingAppearance,
            onSelected: (_) async {},
            onDismiss: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final selected = tester.getSemantics(
        find.byKey(ValueKey(FontChoice.serif.key)),
      );
      expect(
        selected,
        matchesSemantics(
          isSelected: true,
          hasSelectedState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: 'Serif\nGeneric category\nCurrent selection',
        ),
      );
      expect(find.bySemanticsLabel(RegExp('Serif')), findsWidgets);
      final other = tester.getSemantics(
        find.byKey(
          ValueKey(const FontChoice.generic(GenericFont.sansSerif).key),
        ),
      );
      expect(
        other,
        matchesSemantics(
          isSelected: false,
          hasSelectedState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: 'Sans Serif\nGeneric category',
        ),
      );
      expect(find.bySemanticsLabel(RegExp('Font preview:')), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
  for (final scale in [1.5, 2.0]) {
    testWidgets('short narrow chooser stays scrollable at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fonts = _Fonts()..fail = true;
      await tester.pumpWidget(
        _app(
          ReadingFontChooser(
            service: fonts,
            selected: FontChoice.serif,
            preferences: defaultReadingAppearance,
            onSelected: (_) async {},
            onDismiss: () {},
          ),
          scale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Close'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'a searched candidate activates with an empty committed composition range',
    (tester) async {
      final fonts = _Fonts(), applied = <FontChoice>[];
      await tester.pumpWidget(
        _app(
          ReadingFontChooser(
            service: fonts,
            selected: FontChoice.serif,
            preferences: defaultReadingAppearance,
            onSelected: (c) async => applied.add(c),
            onDismiss: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'C Family');
      await tester.pumpAndSettle();
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      controller.value = const TextEditingValue(
        text: 'C Family',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 8, end: 8),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(applied, [const FontChoice.named('C Family')]);
    },
  );
  testWidgets('a delayed activation cannot close or focus a newer chooser', (
    tester,
  ) async {
    final fonts = _Fonts(), gate = Completer<void>();
    await tester.pumpWidget(
      _app(
        ReadingAppearanceControls(
          preferences: defaultReadingAppearance,
          capabilities: TypographyCapabilities.reflowable,
          pdf: false,
          fonts: fonts,
          onChanged: (_) => gate.future,
          onReset: () async {},
          onSaveDefaults: () async {},
        ),
      ),
    );
    await tester.tap(find.text('Font family'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A Family'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Font family'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'C Family');
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('font-search')), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'C Family',
    );
    expect(Focus.of(tester.element(find.byType(EditableText))).hasFocus, true);
  });
  testWidgets(
    'search, IME confirmation, candidates and explicit activation keep preferences separate',
    (tester) async {
      final fonts = _Fonts(), applied = <FontChoice>[];
      var closed = 0;
      await tester.pumpWidget(
        _app(
          ReadingFontChooser(
            service: fonts,
            selected: FontChoice.serif,
            preferences: defaultReadingAppearance,
            onSelected: (c) async => applied.add(c),
            onDismiss: () => closed++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '日本語');
      await tester.pumpAndSettle();
      expect(find.text('日本語 "B", \\'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(applied, isEmpty);
      expect(fonts.previews.last, '日本語 "B", \\');
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.value = const TextEditingValue(
        text: '日本語',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(applied, isEmpty);
      field.controller!.value = const TextEditingValue(
        text: '日本語',
        selection: TextSelection.collapsed(offset: 3),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(applied, [const FontChoice.named('日本語 "B", \\')]);
      expect(closed, 0);
    },
  );
  for (final failed in [false, true]) {
    testWidgets(
      'focused Close still dismisses after delayed ${failed ? 'failure' : 'catalogue'}',
      (tester) async {
        final fonts = _Fonts()..pending = Completer<FontCatalogue>();
        var closed = 0;
        final applied = <FontChoice>[];
        await tester.pumpWidget(
          _app(
            ReadingFontChooser(
              service: fonts,
              selected: FontChoice.serif,
              preferences: defaultReadingAppearance,
              onSelected: (c) async => applied.add(c),
              onDismiss: () => closed++,
            ),
          ),
        );
        await tester.pump();
        Focus.of(tester.element(find.text('Close'))).requestFocus();
        await tester.pump();
        if (failed) {
          fonts.pending!.completeError(StateError('Fixture failure'));
        } else {
          fonts.pending!.complete(FontCatalogue(fonts.families));
        }
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(closed, 1);
        expect(applied, isEmpty);
      },
    );
  }
  testWidgets(
    'catalogue failure, Retry and a meaningful empty search keep generics available',
    (tester) async {
      final fonts = _Fonts()..fail = true;
      await tester.pumpWidget(
        _app(
          ReadingFontChooser(
            service: fonts,
            selected: FontChoice.serif,
            preferences: defaultReadingAppearance,
            onSelected: (_) async {},
            onDismiss: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Serif'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      fonts.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('A Family'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'no font here');
      await tester.pumpAndSettle();
      expect(find.text('No matching fonts. Try another name.'), findsOneWidget);
      expect(fonts.loads, 2);
    },
  );
  testWidgets(
    'large catalogue is lazy and remains bounded in a narrow scaled window',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fonts = _Fonts()
        ..families = [
          for (int i = 0; i < 10000; i++)
            InstalledFontFamily('Family $i', 'Family $i'),
        ];
      await tester.pumpWidget(
        _app(
          ReadingFontChooser(
            service: fonts,
            selected: FontChoice.serif,
            preferences: defaultReadingAppearance,
            onSelected: (_) async {},
            onDismiss: () {},
          ),
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Family 9999'), findsNothing);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'Family 9999');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('family:Family 9999')), findsOneWidget);
    },
  );
  testWidgets(
    'late preview cannot replace a newer candidate or update after close',
    (tester) async {
      final fonts = _Fonts();
      fonts.previewGates['A Family'] = Completer<Uint8List>();
      await tester.pumpWidget(
        _app(
          ReadingFontChooser(
            service: fonts,
            selected: const FontChoice.named('A Family'),
            preferences: defaultReadingAppearance,
            onSelected: (_) async {},
            onDismiss: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'C Family');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final before = tester.widget<Image>(find.byType(Image)).image;
      fonts.previewGates['A Family']!.complete(_png);
      await tester.pumpAndSettle();
      expect(tester.widget<Image>(find.byType(Image)).image, before);
      fonts.previewGates['C Family'] = Completer<Uint8List>();
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
      fonts.previewGates['C Family']!.complete(_png);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'shared Appearance browsing, publisher choice, cancellation, defaults and reset',
    (tester) async {
      final fonts = _Fonts(), changes = <Map<String, dynamic>>[];
      var preferences = {...defaultReadingAppearance};
      var defaults = 0, resets = 0;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => ReadingAppearanceControls(
              preferences: preferences,
              capabilities: TypographyCapabilities.reflowable,
              pdf: false,
              fonts: fonts,
              onChanged: (v) async {
                changes.add(v);
                setState(() => preferences = {...preferences, ...v});
              },
              onReset: () async {
                resets++;
              },
              onSaveDefaults: () async {
                defaults++;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Font family'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(preferences['publisher'], true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('font-family')), findsOneWidget);
      expect(changes, isEmpty);
      await tester.tap(find.text('Font family'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A Family'));
      await tester.pumpAndSettle();
      expect(preferences['font'], {'family': 'A Family'});
      expect(preferences['publisher'], false);
      expect(preferences['size'], 20);
      expect(changes.length, 1);
      await tester.scrollUntilVisible(
        find.text('Save as Reading Defaults'),
        200,
      );
      await tester.tap(find.text('Save as Reading Defaults'));
      expect(defaults, 1);
      await tester.scrollUntilVisible(find.text('Reset Book Appearance'), 200);
      await tester.tap(find.text('Reset Book Appearance'));
      expect(resets, 1);
    },
  );
}
