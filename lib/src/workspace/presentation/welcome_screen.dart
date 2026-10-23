// Composition adapted from BusyMark Welcome: recent filesystem resources in
// the full-height sidebar; independent create/open actions in grouped rows.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/busybooks_main_menu.dart';
import '../../app/localization.dart';
import '../../notebook/presentation/book_view_selector.dart';
import '../../app/linux/linux_page_frame.dart';
import '../../app/linux/linux_header_style.dart';
import '../../app/product_actions.dart';
import '../workspace_controller.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(workspaceControllerProvider), l = context.l10n;
    return Scaffold(
      body: LinuxPageFrame(
        sidebarAvailable: true,
        sidebarExpanded: true,
        sidebarHeader: const BusyBooksLinuxBrandHeader(),
        sidebarBody: BusyBooksSidebarNavigation(
          children: [
            Padding(
              padding: BusyBooksInsets.sectionLabel,
              child: Text(
                l.recent,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (data.recent.isEmpty)
              Padding(
                padding: BusyBooksInsets.sectionLabel,
                child: Text(l.noRecent),
              ),
            for (final resource in data.recent)
              BusyBooksSidebarRecordRow<String>(
                icon: resource.isBook
                    ? BusyBooksGlyphs.document
                    : BusyBooksGlyphs.folder,
                semanticsLabel:
                    '${resource.title} · ${resource.isBook ? l.book : l.collection}',
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.readingData[resource.bookId]?.title ??
                          resource.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      resource.isBook
                          ? '${l.book} · ${resource.path}'
                          : l.collection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                onTap: () => openRecent(context, ref, resource),
                menuTooltip:
                    '${resource.isBook ? l.bookDetails : l.collection} · ${resource.title}',
                menuItemsBuilder: (_) => [
                  BusyBooksPopupMenuItem(value: 'open', label: l.open),
                  if (resource.isBook) ...[
                    BusyBooksPopupMenuItem(
                      value: 'notebook',
                      label: l.notebook,
                    ),
                    BusyBooksPopupMenuItem(
                      value: 'locate',
                      label: l.locateBook,
                    ),
                    BusyBooksPopupMenuItem(value: 'move', label: l.moveBook),
                  ],
                  BusyBooksPopupMenuItem(
                    value: 'forget',
                    label: l.removeRecent,
                  ),
                ],
                onMenuSelected: (value) async {
                  try {
                    if (value == 'open') {
                      await openRecent(context, ref, resource);
                    }
                    if (value == 'notebook' && context.mounted) {
                      await openNotebook(context, ref, resource.resourceId);
                    }
                    if (value == 'locate' && context.mounted) {
                      await locateBook(context, ref, resource.resourceId);
                    }
                    if (value == 'move' && context.mounted) {
                      final book = await ref
                          .read(workspaceControllerProvider.notifier)
                          .loadBook(resource.resourceId);
                      if (context.mounted) await moveBook(context, ref, book);
                    }
                    if (value == 'forget') {
                      await ref
                          .read(workspaceControllerProvider.notifier)
                          .forgetRecent(resource);
                    }
                  } catch (e) {
                    if (context.mounted) await showError(context, e);
                  }
                },
              ),
          ],
        ),
        header: BusyBooksLinuxHeaderLayout(
          leading: BusyBooksHeaderIconButton(
            tooltip: l.openBook,
            icon: BusyBooksGlyphs.document,
            onPressed: () => openPaths(context, ref),
          ),
          title: BusyBooksLinuxHeaderTitle(l.appTitle),
          trailing: const BusyBooksMainMenuButton(),
        ),
        body: ColoredBox(
          color: BusyBooksSurfaceColors.of(context).view,
          child: SingleChildScrollView(
            child: BusyBooksClamp(
              maxWidth: BusyBooksSizes.contentWidth,
              margin: EdgeInsets.zero,
              padding: BusyBooksInsets.welcomePage,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BusyBooksGroupedList(
                    title: l.open,
                    filled: true,
                    children: [
                      BusyBooksActionRow(
                        key: const ValueKey('welcome-open-book'),
                        title: l.openBook,
                        subtitle: l.openBookHelp,
                        leading: const Icon(BusyBooksGlyphs.document),
                        trailing: Icon(
                          BusyBooksGlyphs.forwardFor(
                            Directionality.of(context),
                          ),
                        ),
                        onTap: () => openPaths(context, ref),
                      ),
                      BusyBooksActionRow(
                        key: const ValueKey('welcome-open-collection'),
                        title: l.openCollection,
                        subtitle: l.openCollectionHelp,
                        leading: const Icon(BusyBooksGlyphs.folder),
                        trailing: Icon(
                          BusyBooksGlyphs.forwardFor(
                            Directionality.of(context),
                          ),
                        ),
                        onTap: () => openCollection(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: BusyBooksSpacing.lg),
                  BusyBooksGroupedList(
                    title: l.createCollection,
                    filled: true,
                    children: [
                      BusyBooksActionRow(
                        key: const ValueKey('welcome-create-collection'),
                        title: l.createCollection,
                        subtitle: l.createCollectionHelp,
                        leading: const Icon(BusyBooksGlyphs.add),
                        trailing: Icon(
                          BusyBooksGlyphs.forwardFor(
                            Directionality.of(context),
                          ),
                        ),
                        onTap: () => createCollection(context, ref),
                      ),
                    ],
                  ),
                  if (data.loading) ...[
                    const SizedBox(height: BusyBooksSpacing.lg),
                    const LinearProgressIndicator(),
                    BusyBooksActionRow(
                      title: l.busy,
                      subtitle: data.progress['name']?.toString(),
                      trailing: BusyBooksDialogButton(
                        label: l.cancel,
                        onPressed: () => ref
                            .read(workspaceControllerProvider.notifier)
                            .cancel(),
                      ),
                    ),
                  ],
                  for (final operation in data.moves)
                    BusyBooksActionRow(
                      title: l.pendingMove,
                      subtitle:
                          '${operation['source']} → ${operation['destination']} · ${operation['stage']}',
                      onTap: () => resumeMove(context, ref, operation),
                    ),
                  if (data.error != null) ...[
                    const SizedBox(height: BusyBooksSpacing.lg),
                    BusyBooksStatusBox(
                      message: data.error!,
                      kind: BusyBooksStatusKind.error,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
