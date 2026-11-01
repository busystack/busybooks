import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../app/busybooks_design.dart';
import '../../app/localization.dart';
import '../../core/typography.dart';
import '../application/reader_controller.dart';

/// A quick preference transaction or entry into the existing Reading Settings.
class ReadingAppearanceChoice {
  const ReadingAppearanceChoice.change(this.changes) : more = false;
  const ReadingAppearanceChoice.more() : changes = const {}, more = true;
  final Map<String, dynamic> changes;
  final bool more;
}

String _number(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// Semantic menu rows shared by every invocation of the appearance command.
List<PopupMenuEntry<ReadingAppearanceChoice>> readingAppearanceMenuItems({
  required AppLocalizations l,
  required Map<String, dynamic> preferences,
  required TypographyCapabilities capabilities,
  required bool pdf,
  required bool comic,
  bool noText = false,
}) {
  final p = preferences;
  BusyBooksPopupMenuItem<ReadingAppearanceChoice> choice(
    String key,
    Object value,
    String label,
  ) => BusyBooksPopupMenuItem(
    value: ReadingAppearanceChoice.change({
      key: value,
      if (key == 'size' || key == 'line') 'publisher': false,
    }),
    label: label,
    trailingCheck: true,
    checked: p[key] == value,
  );
  BusyBooksSubmenuItem<ReadingAppearanceChoice> choices(
    String key,
    String label,
    List<(String, String)> values,
  ) => BusyBooksSubmenuItem(
    label: label,
    items: [for (final (value, title) in values) choice(key, value, title)],
  );
  BusyBooksSubmenuItem<ReadingAppearanceChoice> numbers(
    String key,
    String label,
    List<num> presets,
    String unit,
  ) {
    final values = {...presets, if (p[key] is num) p[key] as num}.toList()
      ..sort();
    return BusyBooksSubmenuItem(
      label: label,
      items: [
        for (final value in values)
          choice(key, value, '${_number(value)}$unit'),
      ],
    );
  }

  return [
    if (pdf && noText) ...[
      BusyBooksPopupMenuItem(
        value: const ReadingAppearanceChoice.change({}),
        label: l.noTextPageStatus,
        enabled: false,
      ),
      const PopupMenuDivider(),
    ],
    if (!comic)
      choices('color', l.pageColor, [
        ('system', l.system),
        ('light', l.light),
        ('dark', l.dark),
        ('sepia', l.sepia),
      ]),
    if (capabilities.textMetrics) ...[
      numbers('size', l.fontSize, [
        12,
        14,
        16,
        18,
        20,
        22,
        24,
        28,
        32,
        36,
        40,
      ], ' px'),
      numbers('line', l.lineSpacing, [1, 1.2, 1.4, 1.5, 1.6, 1.8, 2, 2.2], '×'),
      numbers('width', l.readingWidth, [
        400,
        520,
        640,
        720,
        840,
        960,
        1200,
      ], ' px'),
      numbers('margin', l.margins, [0, 12, 20, 32, 48, 64, 80], ' px'),
      BusyBooksPopupMenuItem(
        value: ReadingAppearanceChoice.change({
          'publisher': p['publisher'] != true,
        }),
        label: l.publisher,
        trailingCheck: true,
        checked: p['publisher'] == true,
        mutuallyExclusive: false,
      ),
    ] else ...[
      choices('zoom', l.zoom, [
        ('fit-page', l.fitPage),
        ('fit-width', l.fitWidth),
        ('.5', '50%'),
        ('.75', '75%'),
        ('1', '100%'),
        ('1.25', '125%'),
        ('1.5', '150%'),
        ('2', '200%'),
        ('3', '300%'),
      ]),
      if (pdf) numbers('rotation', l.rotation, [0, 90, 180, 270], '°'),
      BusyBooksPopupMenuItem(
        value: ReadingAppearanceChoice.change({'spread': p['spread'] != true}),
        label: l.twoPages,
        trailingCheck: true,
        checked: p['spread'] == true,
        mutuallyExclusive: false,
      ),
      if (comic)
        choices('direction', l.readingDirection, [
          ('auto', l.directionAuto),
          ('ltr', l.directionLtr),
          ('rtl', l.directionRtl),
        ]),
    ],
    const PopupMenuDivider(),
    BusyBooksPopupMenuItem(
      value: const ReadingAppearanceChoice.more(),
      label: l.moreReadingSettings,
    ),
  ];
}

Future<void> showReadingAppearanceMenu(
  BuildContext context,
  ReaderController reader, {
  required bool Function() isCurrent,
}) async {
  final menu = BusyBooksMenuSession();
  final previousFocus = FocusManager.instance.primaryFocus;
  final owner = await reader.prepareAppearanceMenu(dismiss: menu.dismiss);
  if (owner == null) return;
  Future<void>? applying;
  try {
    if (!context.mounted || !isCurrent() || !reader.ownsAppearanceMenu(owner)) {
      return;
    }
    // Evaluate the live trigger only after sealing/dismissing the old surface
    // and settling any feedback layout. Overflow and keyboard commands share it.
    final anchor =
        reader.appearanceAnchor?.call() ??
        Rect.fromLTWH(reader.viewport.right - 48, reader.viewport.top, 1, 1);
    if (!anchor.isFinite || anchor.isEmpty) return;
    final selection = await showBusyBooksMenu<ReadingAppearanceChoice>(
      context: context,
      anchorRect: anchor,
      session: menu,
      items: readingAppearanceMenuItems(
        l: context.l10n,
        preferences: reader.appearance,
        capabilities: reader.typographyCapabilities,
        pdf: reader.book?.format == 'pdf',
        comic: reader.regionNotes,
        noText: reader.currentPageHasNoText,
      ),
      focusFirst: true,
    );
    if (selection == null ||
        menu.dismissed ||
        !isCurrent() ||
        !reader.ownsAppearanceMenu(owner)) {
      return;
    }
    if (selection.more) {
      reader.openAppearanceSettings(owner);
    } else {
      // Capture the existing transaction synchronously while this owner is
      // current; release menu input ownership before waiting for render/SQL.
      applying = reader.setAppearance(selection.changes);
    }
  } finally {
    final restore = isCurrent() && reader.ownsAppearanceMenu(owner);
    reader.finishAppearanceMenu(owner);
    if (restore && previousFocus?.context?.mounted == true) {
      previousFocus!.requestFocus();
    }
  }
  // The transaction restores rendering and provides existing localized feedback
  // if the write fails. Do not layer a second error dialog on it.
  try {
    await applying;
  } catch (_) {}
}
