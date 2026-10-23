import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../reading/application/reader_controller.dart';
import '../notebook/application/notebook_controller.dart';
import 'app_router.dart';
import 'window_control_service.dart';
import 'busybooks_design.dart';
import 'busybooks_glyphs.dart';
import 'busybooks_dialogs.dart';
import 'command_registry.dart';
import 'localization.dart';
import 'product_actions.dart';

class BusyBooksMainMenuButton extends ConsumerWidget {
  const BusyBooksMainMenuButton({
    super.key,
    this.bookViewSelectorVisible = false,
  });

  // Supplied by the owning header's actual layout/search decision.
  final bool bookViewSelectorVisible;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry =
        BusyBooksCommandRegistryScope.maybeOf(context) ??
        BusyBooksCommandCatalog.metadata;
    final l = context.l10n;
    ref.watch(appLocationProvider);
    final path = ref
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path;
    final reader = ref.watch(readerControllerProvider);
    final controller = ref.read(readerControllerProvider.notifier);
    final notebook = ref.watch(notebookControllerProvider);
    final fullScreen = ref.watch(
      windowControlServiceProvider.select((s) => s.isFullScreen),
    );
    final bookId = path.split('/').last;
    bool current() =>
        ref.read(appRouterProvider).routeInformationProvider.value.uri.path ==
        path;
    IconData? icon(String id) => switch (id) {
      BusyBooksCommandIds.welcome => BusyBooksGlyphs.home,
      BusyBooksCommandIds.backToCollection => BusyBooksGlyphs.back,
      BusyBooksCommandIds.open => BusyBooksGlyphs.documentOpen,
      BusyBooksCommandIds.createCollection => BusyBooksGlyphs.add,
      BusyBooksCommandIds.openCollection => BusyBooksGlyphs.folderOpen,
      BusyBooksCommandIds.addBooks => BusyBooksGlyphs.add,
      BusyBooksCommandIds.refreshWorkspace => BusyBooksGlyphs.refresh,
      BusyBooksCommandIds.closeWorkspace => BusyBooksGlyphs.close,
      BusyBooksCommandIds.viewReading => BusyBooksGlyphs.previewView,
      BusyBooksCommandIds.viewNotebook => BusyBooksGlyphs.notebookView,
      BusyBooksCommandIds.bookmark => BusyBooksGlyphs.bookmark,
      BusyBooksCommandIds.appearance =>
        reader.fixed ? BusyBooksGlyphs.fitWidth : BusyBooksGlyphs.font,
      BusyBooksCommandIds.search ||
      BusyBooksCommandIds.searchCollection => BusyBooksGlyphs.search,
      BusyBooksCommandIds.sidebar => BusyBooksGlyphs.sidebar,
      BusyBooksCommandIds.outline => BusyBooksGlyphs.indentFor(
        Directionality.of(context),
      ),
      BusyBooksCommandIds.thumbnails => BusyBooksGlyphs.image,
      BusyBooksCommandIds.annotations => BusyBooksGlyphs.annotations,
      BusyBooksCommandIds.readerBooks => BusyBooksGlyphs.previewView,
      BusyBooksCommandIds.goTo => BusyBooksGlyphs.goTop,
      BusyBooksCommandIds.back ||
      BusyBooksCommandIds.returnToPassage => BusyBooksGlyphs.back,
      BusyBooksCommandIds.forward => BusyBooksGlyphs.forward,
      BusyBooksCommandIds.previous => BusyBooksGlyphs.backFor(
        Directionality.of(context),
      ),
      BusyBooksCommandIds.next => BusyBooksGlyphs.forwardFor(
        Directionality.of(context),
      ),
      BusyBooksCommandIds.export => BusyBooksGlyphs.exportPdf,
      BusyBooksCommandIds.moveBook => BusyBooksGlyphs.folder,
      BusyBooksCommandIds.locateBook => BusyBooksGlyphs.documentOpen,
      BusyBooksCommandIds.readAloud => BusyBooksGlyphs.play,
      BusyBooksCommandIds.dictionary => BusyBooksGlyphs.document,
      BusyBooksCommandIds.fullScreen => BusyBooksGlyphs.fullScreen,
      BusyBooksCommandIds.commandPalette => BusyBooksGlyphs.keyboard,
      BusyBooksCommandIds.settings => BusyBooksGlyphs.settings,
      _ => null,
    };
    final checked = <String, bool>{
      BusyBooksCommandIds.viewReading: path.startsWith('/read/'),
      BusyBooksCommandIds.viewNotebook: path.startsWith('/notebook/'),
      BusyBooksCommandIds.fullScreen: fullScreen,
      BusyBooksCommandIds.sidebar: reader.panelOpen,
      BusyBooksCommandIds.bookmark: controller.bookmarked,
      BusyBooksCommandIds.search: path.startsWith('/notebook/')
          ? notebook.view(bookId).searchVisible
          : reader.searchVisible,
      for (final entry in {
        BusyBooksCommandIds.outline: 'outline',
        BusyBooksCommandIds.thumbnails: 'thumbnails',
        BusyBooksCommandIds.annotations: 'annotations',
        BusyBooksCommandIds.readerBooks: 'books',
      }.entries)
        entry.key: reader.panel == entry.value,
    };
    List<PopupMenuEntry<String>> commands(BuildContext c, List<String> ids) => [
      for (final id in ids)
        if (registry[id]?.visible() == true)
          BusyBooksPopupMenuItem<String>(
            value: id,
            label: registry[id]!.label(c),
            icon: icon(id),
            shortcut: registry[id]!.shortcut?.label,
            gtkAccelerator: registry[id]!.shortcut?.gtkAccelerator,
            enabled: registry[id]!.canExecute,
            checked: checked[id] ?? false,
            trailingCheck: checked.containsKey(id),
            mutuallyExclusive: [
              BusyBooksCommandIds.viewReading,
              BusyBooksCommandIds.viewNotebook,
              BusyBooksCommandIds.outline,
              BusyBooksCommandIds.thumbnails,
              BusyBooksCommandIds.annotations,
              BusyBooksCommandIds.readerBooks,
            ].contains(id),
          ),
    ];
    return BusyBooksHeaderPopupMenuButton<String>(
      tooltip: l.mainMenu,
      icon: BusyBooksGlyphs.menuVertical,
      onError: (error) async {
        if (current()) {
          await runAppAction(
            context,
            () async => throw '${l.menuOpenFailed}\n$error',
          );
        }
      },
      itemBuilder: (c) {
        final groups = <List<PopupMenuEntry<String>>>[
          commands(c, [
            BusyBooksCommandIds.welcome,
            BusyBooksCommandIds.backToCollection,
            BusyBooksCommandIds.open,
            BusyBooksCommandIds.createCollection,
            BusyBooksCommandIds.openCollection,
            BusyBooksCommandIds.addBooks,
            BusyBooksCommandIds.refreshWorkspace,
            BusyBooksCommandIds.closeWorkspace,
          ]),
          commands(c, [
            BusyBooksCommandIds.bookmark,
            BusyBooksCommandIds.appearance,
            BusyBooksCommandIds.search,
            BusyBooksCommandIds.searchCollection,
          ]),
        ];
        for (final (label, ids) in [
          if (!bookViewSelectorVisible &&
              (registry[BusyBooksCommandIds.viewReading]?.canExecute == true ||
                  registry[BusyBooksCommandIds.viewNotebook]?.canExecute ==
                      true) &&
              (path.startsWith('/read/') || path.startsWith('/notebook/')))
            (
              l.viewMode,
              [
                BusyBooksCommandIds.viewReading,
                BusyBooksCommandIds.viewNotebook,
              ],
            ),
          (
            l.sidebar,
            [
              BusyBooksCommandIds.sidebar,
              BusyBooksCommandIds.outline,
              BusyBooksCommandIds.thumbnails,
              BusyBooksCommandIds.annotations,
              BusyBooksCommandIds.readerBooks,
            ],
          ),
          (
            l.navigation,
            [
              BusyBooksCommandIds.goTo,
              BusyBooksCommandIds.previous,
              BusyBooksCommandIds.next,
              BusyBooksCommandIds.back,
              BusyBooksCommandIds.forward,
              BusyBooksCommandIds.returnToPassage,
            ],
          ),
          (
            l.bookDetails,
            [
              BusyBooksCommandIds.moveBook,
              BusyBooksCommandIds.locateBook,
              BusyBooksCommandIds.export,
            ],
          ),
          (
            l.readingAssistance,
            [BusyBooksCommandIds.readAloud, BusyBooksCommandIds.dictionary],
          ),
        ]) {
          final entries = commands(c, ids);
          if (entries.isNotEmpty) {
            groups.add([BusyBooksSubmenuItem(label: label, items: entries)]);
          }
        }
        groups.add(
          commands(c, [
            BusyBooksCommandIds.fullScreen,
            BusyBooksCommandIds.commandPalette,
            BusyBooksCommandIds.settings,
          ]),
        );
        groups.add([
          BusyBooksPopupMenuItem(
            value: 'backup',
            label: l.backup,
            icon: BusyBooksGlyphs.save,
          ),
          BusyBooksPopupMenuItem(
            value: 'restore',
            label: l.restore,
            icon: BusyBooksGlyphs.documentOpen,
          ),
          BusyBooksPopupMenuItem(
            value: 'about',
            label: l.about,
            icon: BusyBooksGlyphs.about,
          ),
        ]);
        final items = <PopupMenuEntry<String>>[];
        for (final group in groups.where((g) => g.isNotEmpty)) {
          if (items.isNotEmpty) items.add(const PopupMenuDivider());
          items.addAll(group);
        }
        return items;
      },
      onSelected: (value) async {
        if (!current()) return;
        await runAppAction(context, () async {
          switch (value) {
            case 'backup':
              await backupReadingData(context);
            case 'restore':
              await backupReadingData(context, restore: true);
            case 'about':
              await showBusyBooksModalDialog<void>(
                context,
                builder: (c) => BusyBooksDialogShell(
                  title: c.l10n.about,
                  actions: [
                    BusyBooksDialogButton(
                      label: c.l10n.close,
                      onPressed: () => Navigator.pop(c),
                    ),
                  ],
                  children: [
                    Text(c.l10n.aboutText),
                    const SizedBox(height: BusyBooksSpacing.lg),
                    const Text(
                      'Apache-2.0 · BusyStack\nFoliate.js · MIT\nPDF.js · Apache-2.0',
                    ),
                  ],
                ),
              );
            default:
              await registry.execute(value);
          }
        });
      },
    );
  }
}
