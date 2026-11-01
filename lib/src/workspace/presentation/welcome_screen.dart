import 'package:yaru/yaru.dart';
// Composition adapted from BusyMark Welcome: recent filesystem resources in
// the full-height sidebar; independent create/open actions in grouped rows.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/busybooks_main_menu.dart';
import '../../app/command_registry.dart';
import '../../app/linux/linux_header_style.dart';
import '../../app/linux/linux_page_frame.dart';
import '../../app/localization.dart';
import '../../app/product_actions.dart';
import '../../notebook/presentation/book_view_selector.dart';
import '../../search/book_search_session.dart';
import '../../search/book_search_widgets.dart';
import '../workspace_controller.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _sidebarOpen = false;
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(workspaceControllerProvider), l = context.l10n;
    final search = ref.watch(bookSearchSessionProvider);
    final narrow =
        MediaQuery.sizeOf(context).width <
        BusyBooksSizes.workspaceSidebarBreakpoint;
    return Scaffold(
      body: LinuxPageFrame(
        sidebarAvailable: true,
        sidebarExpanded: !narrow || _sidebarOpen || search.active,
        sidebarOverlay: narrow,
        onSidebarDismiss: () {
          if (search.active) {
            ref.read(bookSearchSessionProvider.notifier).close();
          } else {
            setState(() => _sidebarOpen = false);
          }
        },
        sidebarHeader: const BusyBooksLinuxBrandHeader(),
        sidebarBody: BookSearchSidebarHost(
          child: BusyBooksSidebarNavigation(
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
                        if (context.mounted) {
                          await moveBook(context, ref, book);
                        }
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
        ),
        header: BusyBooksLinuxHeaderLayout(
          leading: BusyBooksLinuxHeaderControlGroup(
            children: [
              if (narrow)
                BusyBooksHeaderIconButton(
                  tooltip: l.sidebar,
                  icon: BusyBooksGlyphs.sidebar,
                  selected: _sidebarOpen || search.active,
                  onPressed: () {
                    if (search.active) {
                      ref.read(bookSearchSessionProvider.notifier).close();
                    } else {
                      setState(() => _sidebarOpen = !_sidebarOpen);
                    }
                  },
                ),
              BusyBooksHeaderIconButton(
                tooltip: l.openBook,
                icon: BusyBooksGlyphs.document,
                onPressed: () => openPaths(context, ref),
              ),
            ],
          ),
          centerAllocation: search.active
              ? BusyBooksLinuxHeaderCenterAllocation.fillBetweenControls
              : BusyBooksLinuxHeaderCenterAllocation.centeredBetweenControls,
          title: search.active
              ? const BookSearchHeaderField()
              : BusyBooksLinuxHeaderTitle(l.appTitle),
          trailing: BusyBooksLinuxHeaderControlGroup(
            children: [
              BusyBooksHeaderIconButton(
                tooltip: l.search,
                icon: BusyBooksGlyphs.search,
                selected: search.active,
                onPressed: () => ref
                    .read(bookSearchSessionProvider.notifier)
                    .toggle(
                      actions: bookSearchActions(
                        context,
                        BusyBooksCommandRegistryScope.maybeOf(context)!,
                      ),
                    ),
              ),
              const BusyBooksMainMenuButton(),
            ],
          ),
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
                    const YaruLinearProgressIndicator(),
                    BusyBooksActionRow(
                      title: l.busy,
                      subtitle: data.progress['name']?.toString(),
                      trailing: BusyBooksPushButton.standard(
                        child: Text(l.cancel),
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
