import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/localization.dart';
import '../application/reader_controller.dart';

class ReadingSelectionChoice {
  const ReadingSelectionChoice(this.action, {this.color});
  final ReaderSelectionAction action;
  final String? color;
}

List<PopupMenuEntry<ReadingSelectionChoice>> readingSelectionMenuItems({
  required AppLocalizations l,
  required bool hasText,
  required bool bookmark,
  required bool existing,
  required String color,
}) => [
  if (!bookmark) ...[
    BusyBooksPopupMenuItem(
      value: const ReadingSelectionChoice(ReaderSelectionAction.highlight),
      label: l.highlight,
    ),
    BusyBooksSubmenuItem(
      label: l.highlightColor,
      items: [
        for (final (value, label) in [
          ('yellow', l.yellow),
          ('green', l.green),
          ('blue', l.blue),
          ('pink', l.pink),
        ])
          BusyBooksPopupMenuItem(
            value: ReadingSelectionChoice(
              ReaderSelectionAction.highlight,
              color: value,
            ),
            label: label,
            checked: color == value,
            trailingCheck: true,
          ),
      ],
    ),
  ],
  BusyBooksPopupMenuItem(
    value: const ReadingSelectionChoice(ReaderSelectionAction.addNote),
    label: existing ? l.editNote : l.addNote,
  ),
  BusyBooksPopupMenuItem(
    value: const ReadingSelectionChoice(ReaderSelectionAction.copy),
    label: l.copyShort,
    icon: BusyBooksGlyphs.copy,
    enabled: hasText,
  ),
  const PopupMenuDivider(),
  BusyBooksPopupMenuItem(
    value: const ReadingSelectionChoice(ReaderSelectionAction.search),
    label: l.searchThisBook,
    icon: BusyBooksGlyphs.search,
    enabled: hasText,
  ),
  BusyBooksPopupMenuItem(
    value: const ReadingSelectionChoice(ReaderSelectionAction.lookUp),
    label: l.lookUp,
    enabled: hasText,
  ),
  BusyBooksPopupMenuItem(
    value: const ReadingSelectionChoice(ReaderSelectionAction.readAloud),
    label: l.readAloud,
    enabled: hasText,
  ),
];

Future<void> showReadingSelectionMenu(
  BuildContext context,
  ReaderController reader,
  ReaderSelectionTarget target, {
  required bool Function() isCurrent,
}) async {
  final menu = BusyBooksMenuSession();
  final owner = await reader.prepareSelectionMenu(
    target,
    dismiss: menu.dismiss,
  );
  if (owner == null) return;
  try {
    if (!context.mounted || !isCurrent() || !reader.ownsSelectionMenu(owner)) {
      return;
    }
    final annotation = reader.selectionAnnotation(owner.target);
    final anchor =
        owner.target.rect ??
        Rect.fromLTWH(reader.viewport.center.dx, reader.viewport.top, 1, 1);
    if (!anchor.isFinite || anchor.isEmpty) return;
    final choice = await showBusyBooksMenu<ReadingSelectionChoice>(
      context: context,
      anchorRect: anchor,
      session: menu,
      focusFirst: true,
      preferAbove: true,
      items: readingSelectionMenuItems(
        l: context.l10n,
        hasText: owner.target.text.trim().isNotEmpty,
        bookmark: annotation?.kind == 'bookmark',
        existing: annotation != null,
        color: annotation?.color ?? reader.highlightColor,
      ),
    );
    if (choice != null &&
        !menu.dismissed &&
        isCurrent() &&
        reader.ownsSelectionMenu(owner)) {
      await reader.selectionMenuAction(
        owner,
        choice.action,
        color: choice.color,
      );
    }
  } finally {
    reader.finishSelectionMenu(owner, restoreFocus: isCurrent());
  }
}
