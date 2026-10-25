import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/command_registry.dart';
import '../../app/localization.dart';
import '../../reading/application/reader_controller.dart';

class BookContextMenu extends ConsumerWidget {
  const BookContextMenu({
    super.key,
    required this.reading,
    required this.readingControlsVisible,
    required this.pageControlsVisible,
    required this.locationVisible,
  });
  final bool reading,
      readingControlsVisible,
      pageControlsVisible,
      locationVisible;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry =
            BusyBooksCommandRegistryScope.maybeOf(context) ??
            BusyBooksCommandCatalog.metadata,
        l = context.l10n;
    final reader = ref.watch(readerControllerProvider);
    PopupMenuEntry<String> item(String id, {IconData? icon}) =>
        BusyBooksPopupMenuItem(
          value: id,
          label: registry[id]!.label(context),
          icon: icon,
          shortcut: registry[id]!.shortcut?.label,
          gtkAccelerator: registry[id]!.shortcut?.gtkAccelerator,
          enabled: registry[id]!.canExecute,
        );
    return BusyBooksHeaderPopupMenuButton<String>(
      tooltip: l.bookActions,
      icon: BusyBooksGlyphs.menuHorizontal,
      itemBuilder: (_) => [
        if (reading) ...[
          if (!pageControlsVisible) ...[
            item(BusyBooksCommandIds.previous, icon: BusyBooksGlyphs.back),
            item(BusyBooksCommandIds.next, icon: BusyBooksGlyphs.forward),
          ],
          if (!locationVisible) item(BusyBooksCommandIds.goTo),
          if (!readingControlsVisible) ...[
            item(BusyBooksCommandIds.bookmark, icon: BusyBooksGlyphs.bookmark),
            item(
              BusyBooksCommandIds.appearance,
              icon: reader.fixed
                  ? BusyBooksGlyphs.fitWidth
                  : BusyBooksGlyphs.font,
            ),
          ],
          item(BusyBooksCommandIds.back),
          item(BusyBooksCommandIds.forward),
          if (registry[BusyBooksCommandIds.readAloud]?.visible() == true)
            item(BusyBooksCommandIds.readAloud, icon: BusyBooksGlyphs.play),
          if (registry[BusyBooksCommandIds.dictionary]?.visible() == true)
            item(BusyBooksCommandIds.dictionary),
          if (registry[BusyBooksCommandIds.addNote]?.visible() == true)
            item(
              BusyBooksCommandIds.addNote,
              icon: BusyBooksGlyphs.annotations,
            ),
          const PopupMenuDivider(),
        ],
        if (registry[BusyBooksCommandIds.backToCollection]?.visible() == true)
          item(
            BusyBooksCommandIds.backToCollection,
            icon: BusyBooksGlyphs.folder,
          ),
        item(BusyBooksCommandIds.export, icon: BusyBooksGlyphs.exportPdf),
        item(BusyBooksCommandIds.moveBook, icon: BusyBooksGlyphs.folder),
        item(
          BusyBooksCommandIds.locateBook,
          icon: BusyBooksGlyphs.documentOpen,
        ),
      ],
      onSelected: (id) => registry.execute(id),
    );
  }
}
