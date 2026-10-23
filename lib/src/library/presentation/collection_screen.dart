import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_settings.dart';
import '../../app/command_registry.dart';
import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/busybooks_search_field.dart';
import '../../app/busybooks_main_menu.dart';
import '../../app/localization.dart';
import '../../app/linux/linux_page_frame.dart';
import '../../app/linux/linux_header_style.dart';
import '../../app/product_actions.dart';
import '../../workspace/workspace_controller.dart';
import '../../notebook/presentation/book_view_selector.dart';
import '../domain/book.dart';
import '../application/collection_view_controller.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(
      workspaceControllerProvider.select((s) => s.workspace?.id),
    );
    return path == null
        ? const SizedBox.shrink()
        : _CollectionWorkspace(key: ValueKey(path), path: path);
  }
}

class _CollectionWorkspace extends ConsumerStatefulWidget {
  const _CollectionWorkspace({super.key, required this.path});
  final String path;
  @override
  ConsumerState<_CollectionWorkspace> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<_CollectionWorkspace> {
  late final TextEditingController _query;
  late final ScrollController _scroll;
  CollectionViewController get view =>
      ref.read(collectionViewProvider(widget.path).notifier);
  @override
  void initState() {
    super.initState();
    final saved = ref.read(collectionViewProvider(widget.path));
    _query = TextEditingController(text: saved.query);
    _scroll = ScrollController(initialScrollOffset: saved.scrollOffset);
    _scroll.addListener(_saveScroll);
  }

  void _saveScroll() {
    view.update(scrollOffset: _scroll.offset);
  }

  @override
  void dispose() {
    _scroll.removeListener(_saveScroll);
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(workspaceControllerProvider),
        settings = ref.watch(appSettingsControllerProvider),
        l = context.l10n;
    final presentation = ref.watch(
      collectionViewProvider(widget.path).select(
        (s) => (s.query, s.filter, s.selectedBook, s.focusRequest, s.sort),
      ),
    );
    final query = presentation.$1, filter = presentation.$2;
    void open(Book book) {
      view.update(selectedBook: book.id);
      openBook(context, ref, book);
    }

    final workspace = data.workspace;
    final books = data.books
        .where(
          (b) =>
              (filter == 'all' || filter == b.state) &&
              '${b.title} ${b.author} ${b.series}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    final sort = presentation.$5;
    books.sort((a, b) => compareCollectionBooks(a, b, sort));
    final grid = settings.data['grid'] == true;
    final narrow =
        MediaQuery.sizeOf(context).width <
        BusyBooksSizes.workspaceSidebarBreakpoint;
    return Scaffold(
      body: LinuxPageFrame(
        sidebarOverlay: narrow,
        sidebarAvailable: true,
        sidebarExpanded: true,
        sidebarHeader: const BusyBooksLinuxBrandHeader(),
        sidebarBody: Column(
          children: [
            if (workspace != null)
              BusyBooksActionRow(
                title: workspace.name,
                subtitle: l.collection,
                leading: const Icon(BusyBooksGlyphs.folder),
              ),
            Expanded(
              child: BusyBooksSidebarNavigation(
                children: [
                  for (final item in [
                    ('all', l.allBooks, BusyBooksGlyphs.previewView),
                    ('unread', l.unread, BusyBooksGlyphs.document),
                    ('reading', l.reading, BusyBooksGlyphs.history),
                    ('finished', l.finished, BusyBooksGlyphs.check),
                  ])
                    BusyBooksSidebarNavigationTile(
                      selected: filter == item.$1,
                      leading: Icon(item.$3),
                      title: Text(item.$2),
                      onTap: () => view.update(filter: item.$1),
                    ),
                  if (workspace?.editable == true)
                    BusyBooksActionRow(
                      title: l.addExistingBooks,
                      leading: const Icon(BusyBooksGlyphs.add),
                      onTap: () => addExistingBooks(context, ref),
                    ),
                  BusyBooksActionRow(
                    title: l.renameCollection,
                    leading: const Icon(BusyBooksGlyphs.edit),
                    onTap: () => renameCollection(context, ref),
                  ),
                  BusyBooksActionRow(
                    title: l.deleteCollection,
                    leading: const Icon(BusyBooksGlyphs.delete),
                    onTap: () => deleteCollection(context, ref),
                  ),
                ],
              ),
            ),
            BusyBooksActionRow(
              title: l.settings,
              leading: const Icon(BusyBooksGlyphs.settings),
              onTap: () => openSettings(context, ref),
            ),
          ],
        ),
        header: BusyBooksLinuxHeaderLayout(
          leading: BusyBooksLinuxHeaderControlGroup(
            children: [
              BusyBooksHeaderIconButton(
                key: const ValueKey('collection-home'),
                tooltip: l.welcome,
                icon: BusyBooksGlyphs.home,
                onPressed: () async {
                  final registry = BusyBooksCommandRegistryScope.maybeOf(
                    context,
                  );
                  await (registry?[BusyBooksCommandIds.welcome]?.execute != null
                      ? registry!.execute(BusyBooksCommandIds.welcome)
                      : closeWorkspace(context, ref));
                },
              ),
              if (workspace?.editable == true)
                BusyBooksHeaderIconButton(
                  tooltip: l.addExistingBooks,
                  icon: BusyBooksGlyphs.add,
                  onPressed: data.loading
                      ? null
                      : () => addExistingBooks(context, ref),
                ),
            ],
          ),
          centerAllocation:
              BusyBooksLinuxHeaderCenterAllocation.fillBetweenControls,
          title: BusyBooksSearchField(
            key: const ValueKey('collection-header-search'),
            controller: _query,
            focusRequest: presentation.$4,
            hintText: l.collectionSearchScope,
            onChanged: (v) => view.update(query: v),
          ),
          trailing: const BusyBooksMainMenuButton(),
        ),
        body: Padding(
          padding: EdgeInsetsDirectional.only(
            start: narrow ? BusyBooksSizes.sidebarWidth : 0,
          ),
          child: ColoredBox(
            color: BusyBooksSurfaceColors.of(context).view,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(BusyBooksSpacing.lg),
                  child: Row(
                    children: [
                      BusyBooksPopupSelector<String>(
                        value: sort,
                        label: switch (sort) {
                          'title' => l.title,
                          'author' => l.author,
                          'series' => l.series,
                          'read' => l.recentlyRead,
                          _ => l.recentlyAdded,
                        },
                        tooltip: l.sort,
                        options: [
                          for (final item in [
                            ('title', l.title),
                            ('author', l.author),
                            ('series', l.series),
                            ('read', l.recentlyRead),
                            ('added', l.recentlyAdded),
                          ])
                            BusyBooksPopupSelectorOption(
                              value: item.$1,
                              label: item.$2,
                            ),
                        ],
                        onSelected: (v) => view.update(sort: v),
                      ),
                      BusyBooksHeaderIconButton(
                        tooltip: grid ? l.list : l.grid,
                        icon: grid
                            ? BusyBooksGlyphs.editorView
                            : BusyBooksGlyphs.previewView,
                        onPressed: () => ref
                            .read(appSettingsControllerProvider.notifier)
                            .update({'grid': !grid}),
                      ),
                    ],
                  ),
                ),
                if (data.loading) ...[
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
                Expanded(
                  child: books.isEmpty
                      ? Center(
                          child: Padding(
                            padding: BusyBooksInsets.sectionLabel,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  data.books.isEmpty
                                      ? l.emptyCollection
                                      : l.emptySearchCollection,
                                ),
                                if (data.books.isEmpty &&
                                    workspace?.editable == true) ...[
                                  const SizedBox(height: BusyBooksSpacing.lg),
                                  BusyBooksPushButton.standard(
                                    onPressed: () =>
                                        addExistingBooks(context, ref),
                                    child: Text(l.addExistingBooks),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : CustomScrollView(
                          controller: _scroll,
                          slivers: [
                            if (grid)
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  24,
                                ),
                                sliver: SliverGrid.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: 215,
                                        mainAxisExtent: 308,
                                        crossAxisSpacing: 20,
                                        mainAxisSpacing: 20,
                                      ),
                                  itemCount: books.length,
                                  itemBuilder: (c, i) => _BookCard(
                                    book: books[i],
                                    selected: presentation.$3 == books[i].id,
                                    onOpen: () => open(books[i]),
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  20,
                                ),
                                sliver: SliverList.builder(
                                  itemCount: books.length,
                                  itemBuilder: (c, i) => BookRow(
                                    book: books[i],
                                    selected: presentation.$3 == books[i].id,
                                    onOpen: () => open(books[i]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      '${books.length} ${l.countBooks}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.width = 100,
    this.height = 150,
  });
  final Book book;
  final double width, height;
  @override
  Widget build(BuildContext context) {
    final cover = book.cover;
    Widget image;
    try {
      image = cover == null
          ? const Icon(BusyBooksGlyphs.previewView, size: 48)
          : cover.startsWith('data:image/svg+xml')
          ? SvgPicture.memory(
              base64Decode(cover.split(',').last),
              fit: BoxFit.contain,
            )
          : Image.memory(
              base64Decode(cover.split(',').last),
              fit: BoxFit.contain,
              cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, _, _) =>
                  const Icon(BusyBooksGlyphs.previewView, size: 48),
            );
    } catch (_) {
      image = const Icon(BusyBooksGlyphs.previewView, size: 48);
    }
    return Semantics(
      image: true,
      label: book.title,
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: BusyBooksSurfaceColors.of(context).panel,
          child: image,
        ),
      ),
    );
  }
}

class _BookCard extends ConsumerWidget {
  const _BookCard({
    required this.book,
    required this.onOpen,
    this.selected = false,
  });
  final Book book;
  final VoidCallback onOpen;
  final bool selected;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    selected: selected,
    child: BusyBooksGroupedSurface(
      focused: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: BusyBooksPushButton.standard(
              onPressed: onOpen,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Expanded(
                      child: BookCover(book: book, width: 145, height: 195),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      book.author.isEmpty
                          ? context.l10n.unknownAuthor
                          : book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    book.available
                        ? '${book.format.toUpperCase()} · ${(book.progress * 100).round()}%'
                        : book.status == 'unverified'
                        ? context.l10n.checkingBook
                        : context.l10n.fileUnavailable,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                _BookMenu(book: book),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class BookRow extends StatelessWidget {
  const BookRow({
    super.key,
    required this.book,
    required this.onOpen,
    this.selected = false,
  });
  final Book book;
  final VoidCallback onOpen;
  final bool selected;
  @override
  Widget build(BuildContext context) => BusyBooksSidebarRecordRow<void>(
    selected: selected,
    icon: BusyBooksGlyphs.previewView,
    onTap: onOpen,
    content: Row(
      children: [
        BookCover(book: book, width: 42, height: 60),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                [
                  if (!book.available)
                    book.status == 'unverified'
                        ? context.l10n.checkingBook
                        : context.l10n.fileUnavailable,
                  book.author,
                  if (book.series.isNotEmpty)
                    '${book.series} ${book.seriesOrder}',
                  book.format.toUpperCase(),
                  '${(book.progress * 100).round()}%',
                ].where((x) => x.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
    trailing: _BookMenu(book: book),
  );
}

class _BookMenu extends ConsumerWidget {
  const _BookMenu({required this.book});
  final Book book;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n, data = ref.watch(workspaceControllerProvider);
    final known = data.readingData.containsKey(book.id);
    return BusyBooksHeaderPopupMenuButton<String>(
      tooltip: l.bookDetails,
      icon: BusyBooksGlyphs.menuVertical,
      itemBuilder: (_) => [
        if (known) ...[
          BusyBooksPopupMenuItem(value: 'notebook', label: l.notebook),
          BusyBooksPopupMenuItem(value: 'move', label: l.moveBook),
          BusyBooksPopupMenuItem(value: 'properties', label: l.properties),
          BusyBooksPopupMenuItem(value: 'original', label: l.exportOriginal),
          BusyBooksPopupMenuItem(value: 'markdown', label: l.exportAnnotations),
          BusyBooksPopupMenuItem(value: 'locate', label: l.locateBook),
          for (final item in [
            ('unread', l.unread),
            ('reading', l.reading),
            ('finished', l.finished),
          ])
            BusyBooksPopupMenuItem(
              value: item.$1,
              label: item.$2,
              checked: book.state == item.$1,
            ),
        ],
        if (data.workspace?.editable == true)
          BusyBooksPopupMenuItem(
            value: 'remove',
            label: l.removeReference,
            icon: BusyBooksGlyphs.delete,
          ),
      ],
      onSelected: (value) async {
        try {
          switch (value) {
            case 'notebook':
              await openNotebook(context, ref, book.id);
            case 'move':
              await moveBook(context, ref, book);
            case 'properties':
              await bookProperties(context, ref, book);
            case 'original':
              await exportBook(context, ref, book, original: true);
            case 'markdown':
              await exportBook(context, ref, book);
            case 'locate':
              await locateBook(context, ref, book.id, entry: book);
            case 'unread':
            case 'reading':
            case 'finished':
              await ref.read(workspaceControllerProvider.notifier).updateBook(
                book.id,
                {'state': value},
              );
            case 'remove':
              if (await confirm(
                context,
                l.removeReference,
                l.removeReferenceHelp,
                acceptLabel: l.removeReference,
              )) {
                await ref
                    .read(workspaceControllerProvider.notifier)
                    .removeBook(book);
              }
          }
        } catch (error) {
          if (context.mounted) await showError(context, error);
        }
      },
    );
  }
}
