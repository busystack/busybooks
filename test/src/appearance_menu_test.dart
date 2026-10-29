import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:busybooks/l10n/generated/app_localizations_en.dart';
import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/core/reading_preferences.dart';
import 'package:busybooks/src/core/typography.dart';
import 'package:busybooks/src/reading/presentation/appearance_menu.dart';
import 'package:busybooks/src/reading/presentation/appearance_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l = AppLocalizationsEn();
  List<PopupMenuEntry<ReadingAppearanceChoice>> items({
    bool pdf = false,
    bool comic = false,
    bool text = false,
    bool noText = false,
    Map<String, dynamic> changes = const {},
  }) => readingAppearanceMenuItems(
    l: l,
    preferences: {...defaultReadingAppearance, ...changes},
    capabilities: text
        ? TypographyCapabilities.reflowable
        : TypographyCapabilities.none,
    pdf: pdf,
    comic: comic,
    noText: noText,
  );
  List<String> labels(List<PopupMenuEntry<ReadingAppearanceChoice>> rows) => [
    for (final row in rows)
      if (row is BusyBooksSubmenuItem<ReadingAppearanceChoice>)
        row.label
      else if (row is BusyBooksPopupMenuItem<ReadingAppearanceChoice>)
        row.label,
  ];
  test('quick choices follow renderer capabilities and publication format', () {
    expect(labels(items(pdf: true)), [
      l.pageColor,
      l.zoom,
      l.rotation,
      l.twoPages,
      l.moreReadingSettings,
    ]);
    expect(labels(items()), [
      l.pageColor,
      l.zoom,
      l.twoPages,
      l.moreReadingSettings,
    ]);
    expect(labels(items(comic: true)), [
      l.zoom,
      l.twoPages,
      l.readingDirection,
      l.moreReadingSettings,
    ]);
    expect(labels(items(text: true)), [
      l.pageColor,
      l.fontSize,
      l.lineSpacing,
      l.readingWidth,
      l.margins,
      l.publisher,
      l.moreReadingSettings,
    ]);
    expect(
      labels(items(pdf: true, noText: true)),
      contains(l.noTextPageStatus),
    );
    expect(labels(items(noText: true)), isNot(contains(l.noTextPageStatus)));
    final status =
        items(pdf: true, noText: true).first
            as BusyBooksPopupMenuItem<ReadingAppearanceChoice>;
    expect(status.enabled, false);
  });
  test(
    'nonpreset metrics retain exact checked values and publisher transaction',
    () {
      final rows = items(
        text: true,
        changes: {'size': 20.5, 'line': 1.55, 'width': 731.5, 'margin': 31.5},
      );
      for (final (label, key, value) in [
        (l.fontSize, 'size', 20.5),
        (l.lineSpacing, 'line', 1.55),
        (l.readingWidth, 'width', 731.5),
        (l.margins, 'margin', 31.5),
      ]) {
        final submenu = rows
            .whereType<BusyBooksSubmenuItem<ReadingAppearanceChoice>>()
            .singleWhere((row) => row.label == label);
        final selected = submenu.items
            .whereType<BusyBooksPopupMenuItem<ReadingAppearanceChoice>>()
            .singleWhere((row) => row.checked);
        expect(selected.label, contains('$value'));
        expect(selected.menuValue.changes[key], value);
        expect(
          selected.menuValue.changes['publisher'],
          key == 'size' || key == 'line' ? false : null,
        );
        expect(selected.trailingCheck, true);
      }
    },
  );
  for (final (pdf, defaults, noText, visible) in [
    (true, false, true, true),
    (true, false, false, false),
    (true, true, true, false),
    (false, false, true, false),
  ]) {
    testWidgets(
      'no-text explanation respects PDF page and preference scope ($pdf/$defaults/$noText)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildBusyBooksTheme(
              brightness: Brightness.light,
              accentColor: const Color(0xff3584e4),
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReadingAppearanceControls(
                preferences: defaultPdfAppearance,
                capabilities: TypographyCapabilities.none,
                pdf: pdf,
                defaults: defaults,
                noText: noText,
                onChanged: (_) async {},
                onReset: () async {},
                onSaveDefaults: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l.noText), visible ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
