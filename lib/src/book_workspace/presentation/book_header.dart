import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/busybooks_main_menu.dart';
import '../../app/command_registry.dart';
import '../../app/linux/linux_header_style.dart';
import '../../app/localization.dart';
import '../../app/product_actions.dart';
import '../../notebook/presentation/book_view_selector.dart';
import '../../platform/gtk_header_icon_service.dart';
import '../../reading/application/reader_controller.dart';
import '../../search/book_search_session.dart';
import '../../search/book_search_widgets.dart';
import '../../workspace/workspace_controller.dart';
import '../application/book_sidebar_controller.dart';
import 'book_context_menu.dart';
import 'reading_location_control.dart';

Rect? bookControlBounds(BuildContext? context) {
  final box = context?.findRenderObject();
  return box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
}

class BookHeader extends ConsumerStatefulWidget {
  const BookHeader({super.key, required this.bookId, required this.view});
  final String bookId;
  final BookView view;
  @override
  ConsumerState<BookHeader> createState() => _BookHeaderState();
}

class _BookHeaderState extends ConsumerState<BookHeader> {
  final _location = GlobalKey(),
      _previous = GlobalKey(),
      _appearance = GlobalKey(),
      _context = GlobalKey();
  late final ReaderController _reader;
  late final Rect? Function() _locationBounds, _appearanceBounds;
  @override
  void initState() {
    super.initState();
    _reader = ref.read(readerControllerProvider.notifier);
    _locationBounds = () => bookControlBounds(
      _location.currentContext ??
          _previous.currentContext ??
          _context.currentContext,
    );
    _appearanceBounds = () => bookControlBounds(
      _appearance.currentContext ?? _context.currentContext,
    );
    _reader.goToAnchor = _locationBounds;
    _reader.appearanceAnchor = _appearanceBounds;
  }

  @override
  void dispose() {
    if (identical(_reader.goToAnchor, _locationBounds)) {
      _reader.goToAnchor = null;
    }
    if (identical(_reader.appearanceAnchor, _appearanceBounds)) {
      _reader.appearanceAnchor = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerControllerProvider),
        sidebar = ref.watch(bookSidebarProvider(widget.bookId)),
        search = ref.watch(bookSearchProvider(widget.bookId)),
        book = ref.watch(workspaceControllerProvider).bookById(widget.bookId),
        l = context.l10n;
    final registry =
        BusyBooksCommandRegistryScope.maybeOf(context) ??
        BusyBooksCommandCatalog.metadata;
    final reading = widget.view == BookView.reading;
    _reader.popoverTextScale = MediaQuery.textScalerOf(context).scale(1);
    String? binding(String id) => registry[id]?.shortcut?.label;
    return LayoutBuilder(
      builder: (context, constraints) {
        Offset tooltipPosition(TooltipPositionContext info) =>
            BusyBooksTooltipStyle.insideHeader(context, info);
        final insets = LinuxPageHeaderInsetsScope.of(context);
        final available =
            constraints.maxWidth -
            insets.leftObstruction -
            insets.rightObstruction -
            BusyBooksSpacing.headerInset * 2;
        final button = BusyBooksSizes.iconButton + BusyBooksSpacing.xs;
        final compact =
            available <
            button * (reading ? 10 : 7) +
                MediaQuery.textScalerOf(context).scale(120);
        final paging = reading && !search.active && available >= button * 8;
        final location = paging && !compact;
        final selector = book != null && !search.active && !compact;
        final readingControls = reading && selector;
        return BusyBooksLinuxHeaderLayout(
          centerAllocation: search.active
              ? BusyBooksLinuxHeaderCenterAllocation.fillBetweenControls
              : BusyBooksLinuxHeaderCenterAllocation.centeredBetweenControls,
          leading: BusyBooksLinuxHeaderControlGroup(
            tooltipPositionDelegate: tooltipPosition,
            children: [
              BusyBooksHeaderIconButton(
                key: const ValueKey('book-sidebar-toggle'),
                tooltip: l.sidebar,
                shortcut: binding(BusyBooksCommandIds.sidebar),
                icon: BusyBooksGlyphs.sidebar,
                selected: sidebar.open || search.active,
                onPressed: () => runAppAction(context, () async {
                  if (search.active) {
                    ref
                        .read(bookSearchProvider(widget.bookId).notifier)
                        .close();
                  } else {
                    await ref
                        .read(bookSidebarProvider(widget.bookId).notifier)
                        .toggleOpen();
                  }
                }),
              ),
              BusyBooksHeaderIconButton(
                key: const ValueKey('book-home'),
                tooltip: l.home,
                icon: BusyBooksGlyphs.home,
                onPressed: () =>
                    registry[BusyBooksCommandIds.welcome]?.execute != null
                    ? registry.execute(BusyBooksCommandIds.welcome)
                    : closeWorkspace(context, ref),
              ),
              if (paging) ...[
                KeyedSubtree(
                  key: _previous,
                  child: BusyBooksLinuxHeaderIconButton(
                    key: const ValueKey('reader-previous'),
                    tooltip: l.previousPage,
                    shortcut: binding(BusyBooksCommandIds.previous),
                    icon: BusyBooksGlyphs.headerBackFor(
                      Directionality.of(context),
                    ),
                    nativeIcon: BusyBooksLinuxHeaderIcon.previous,
                    onPressed:
                        state.canPrevious &&
                            _reader.interactive &&
                            registry[BusyBooksCommandIds.previous]
                                    ?.canExecute ==
                                true
                        ? () => registry.execute(BusyBooksCommandIds.previous)
                        : null,
                  ),
                ),
                if (location)
                  KeyedSubtree(key: _location, child: ReadingLocationControl()),
                BusyBooksLinuxHeaderIconButton(
                  key: const ValueKey('reader-next'),
                  tooltip: l.nextPage,
                  shortcut: binding(BusyBooksCommandIds.next),
                  icon: BusyBooksGlyphs.forwardFor(Directionality.of(context)),
                  nativeIcon: BusyBooksLinuxHeaderIcon.next,
                  onPressed:
                      state.canNext &&
                          _reader.interactive &&
                          registry[BusyBooksCommandIds.next]?.canExecute == true
                      ? () => registry.execute(BusyBooksCommandIds.next)
                      : null,
                ),
              ],
            ],
          ),
          title: search.active
              ? BookSearchHeaderField(
                  bookId: widget.bookId,
                  tooltipPositionDelegate: tooltipPosition,
                )
              : BusyBooksLinuxHeaderTitle(
                  reading
                      ? book?.title ?? l.reader
                      : '${l.notebook} · ${book?.title ?? l.book}',
                ),
          trailing: BusyBooksLinuxHeaderControlGroup(
            tooltipPositionDelegate: tooltipPosition,
            children: [
              if (selector)
                BookViewSelector(id: widget.bookId, view: widget.view),
              if (readingControls) ...[
                Semantics(
                  value: _reader.bookmarkPending ? l.busy : null,
                  child: BusyBooksHeaderIconButton(
                    key: const ValueKey('reader-bookmark'),
                    tooltip: _reader.bookmarked ? l.removeBookmark : l.bookmark,
                    shortcut: binding(BusyBooksCommandIds.bookmark),
                    icon: BusyBooksGlyphs.bookmark,
                    selected: _reader.bookmarked,
                    onPressed:
                        registry[BusyBooksCommandIds.bookmark]?.canExecute ==
                            true
                        ? () => registry.execute(BusyBooksCommandIds.bookmark)
                        : null,
                  ),
                ),
                KeyedSubtree(
                  key: _appearance,
                  child: BusyBooksHeaderIconButton(
                    tooltip: state.fixed ? l.viewOptions : l.appearance,
                    shortcut: binding(BusyBooksCommandIds.appearance),
                    icon: state.fixed
                        ? BusyBooksGlyphs.fitWidth
                        : BusyBooksGlyphs.font,
                    onPressed:
                        registry[BusyBooksCommandIds.appearance]?.canExecute ==
                            true
                        ? () => registry.execute(BusyBooksCommandIds.appearance)
                        : null,
                  ),
                ),
              ],
              KeyedSubtree(
                key: _context,
                child: BookContextMenu(
                  reading: reading,
                  readingControlsVisible: readingControls,
                  pageControlsVisible: paging,
                  locationVisible: location,
                ),
              ),
              BusyBooksHeaderIconButton(
                tooltip: l.search,
                shortcut: binding(BusyBooksCommandIds.search),
                icon: BusyBooksGlyphs.search,
                selected: search.active,
                onPressed: () => ref
                    .read(bookSearchProvider(widget.bookId).notifier)
                    .toggle(
                      category:
                          reading &&
                              ref
                                  .read(
                                    bookSearchProvider(widget.bookId).notifier,
                                  )
                                  .categories
                                  .contains(BookSearchCategory.bookText)
                          ? BookSearchCategory.bookText
                          : BookSearchCategory.notebook,
                      actions: bookSearchActions(context, registry),
                    ),
              ),
              BusyBooksMainMenuButton(bookViewSelectorVisible: selector),
            ],
          ),
        );
      },
    );
  }
}
