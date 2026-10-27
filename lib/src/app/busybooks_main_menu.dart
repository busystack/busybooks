import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'busybooks_design.dart';
import 'busybooks_dialogs.dart';
import 'busybooks_glyphs.dart';
import 'busybooks_toast.dart';
import 'command_registry.dart';
import 'localization.dart';
import 'window_control_service.dart';

class BusyBooksMainMenuButton extends ConsumerWidget {
  const BusyBooksMainMenuButton({
    super.key,
    this.bookViewSelectorVisible = false,
  });

  /// The owning header supplies its actual layout decision.
  final bool bookViewSelectorVisible;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry =
            BusyBooksCommandRegistryScope.maybeOf(context) ??
            BusyBooksCommandCatalog.metadata,
        l = context.l10n;
    ref.watch(appLocationProvider);
    final path = ref
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path;
    final fullScreen = ref.watch(
      windowControlServiceProvider.select((s) => s.isFullScreen),
    );
    bool current() =>
        ref.read(appRouterProvider).routeInformationProvider.value.uri.path ==
        path;
    PopupMenuEntry<String> item(String id, IconData icon, {bool? selected}) =>
        BusyBooksPopupMenuItem(
          value: id,
          label: registry[id]!.label(context),
          icon: icon,
          shortcut: registry[id]!.shortcut?.label,
          gtkAccelerator: registry[id]!.shortcut?.gtkAccelerator,
          enabled: registry[id]!.canExecute,
          checked: selected ?? false,
          trailingCheck: selected != null,
          mutuallyExclusive: id != BusyBooksCommandIds.fullScreen,
        );
    return BusyBooksHeaderPopupMenuButton<String>(
      tooltip: l.mainMenu,
      icon: BusyBooksGlyphs.menuVertical,
      onError: (error) {
        debugPrint('Main menu presentation failed: $error');
        if (context.mounted) {
          BusyBooksToastOverlay.show(context, message: l.menuOpenFailed);
        }
      },
      itemBuilder: (_) => [
        item(BusyBooksCommandIds.open, BusyBooksGlyphs.documentOpen),
        item(BusyBooksCommandIds.openCollection, BusyBooksGlyphs.folderOpen),
        item(BusyBooksCommandIds.createCollection, BusyBooksGlyphs.add),
        const PopupMenuDivider(),
        if (!bookViewSelectorVisible &&
            (path.startsWith('/read/') || path.startsWith('/notebook/')))
          BusyBooksSubmenuItem(
            label: l.viewMode,
            items: [
              item(
                BusyBooksCommandIds.viewReading,
                BusyBooksGlyphs.previewView,
                selected: path.startsWith('/read/'),
              ),
              item(
                BusyBooksCommandIds.viewNotebook,
                BusyBooksGlyphs.notebookView,
                selected: path.startsWith('/notebook/'),
              ),
            ],
          ),
        item(
          BusyBooksCommandIds.fullScreen,
          BusyBooksGlyphs.fullScreen,
          selected: fullScreen,
        ),
        const PopupMenuDivider(),
        item(BusyBooksCommandIds.settings, BusyBooksGlyphs.settings),
        BusyBooksPopupMenuItem(
          value: 'about',
          label: l.aboutBusyBooks,
          icon: BusyBooksGlyphs.about,
        ),
      ],
      onSelected: (value) async {
        if (!current()) return;
        if (value != 'about') {
          await registry.execute(value);
          return;
        }
        await showBusyBooksModalDialog<void>(
          context,
          builder: (c) => BusyBooksDialogShell(
            title: c.l10n.aboutBusyBooks,
            actions: [
              BusyBooksDialogButton(
                label: c.l10n.close,
                onPressed: () => Navigator.pop(c),
              ),
            ],
            children: [Text(c.l10n.aboutText)],
          ),
        );
      },
    );
  }
}
