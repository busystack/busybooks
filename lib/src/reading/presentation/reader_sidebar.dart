import 'dart:async';
import 'dart:ui' show SemanticsRole;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/command_registry.dart';
import '../../app/localization.dart';
import '../../app/product_actions.dart';
import '../../annotations/domain/annotation_order.dart';
import '../../annotations/presentation/annotation_presentation.dart';
import '../../annotations/presentation/annotation_actions.dart' as actions;
import '../../library/data/record_validation.dart' show annotationColors;
import '../../library/presentation/collection_screen.dart' show BookRow;
import '../../notebook/application/notebook_controller.dart';
import '../../notebook/presentation/book_view_selector.dart';
import '../../workspace/workspace_controller.dart';
import '../application/reader_controller.dart';
import '../application/reader_sidebar_state.dart';
import '../domain/publication_outline.dart';
import 'publication_location.dart';

String readerPanelLabel(BuildContext c, String panel) => switch (panel) {
  'books' => c.l10n.books,
  'search' => c.l10n.searchResults,
  'annotations' => c.l10n.annotations,
  'thumbnails' => c.l10n.thumbnails,
  _ => c.l10n.outline,
};
IconData _panelIcon(String panel, TextDirection direction) => switch (panel) {
  'books' => BusyBooksGlyphs.previewView,
  'search' => BusyBooksGlyphs.search,
  'annotations' => BusyBooksGlyphs.annotations,
  'thumbnails' => BusyBooksGlyphs.image,
  _ => BusyBooksGlyphs.indentFor(direction),
};
String _panelCommand(String panel) => switch (panel) {
  'books' => BusyBooksCommandIds.readerBooks,
  'search' => BusyBooksCommandIds.search,
  'annotations' => BusyBooksCommandIds.annotations,
  'thumbnails' => BusyBooksCommandIds.thumbnails,
  _ => BusyBooksCommandIds.outline,
};

// Adapted from BusyMark's _SidebarHeader / Row / Line, without filesystem or
// authoring actions. A collection has a name and identity, never an invented path.
class ReadingSidebarHeader extends ConsumerWidget {
  const ReadingSidebarHeader({super.key, required this.bookId});
  final String bookId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(readerControllerProvider),
        reader = ref.read(readerControllerProvider.notifier),
        workspace = ref.watch(workspaceControllerProvider).workspace,
        book = reader.book;
    final colors = BusyBooksSurfaceColors.of(context),
        registry = BusyBooksCommandRegistryScope.maybeOf(context);
    final collection = workspace?.isBook == false;
    final views = [
      'outline',
      if (reader.panelAvailable('thumbnails')) 'thumbnails',
      'annotations',
      if (reader.panelAvailable('search')) 'search',
      if (collection) 'books',
    ];
    final selected = views.contains(state.panel) ? state.panel : 'outline';
    return Padding(
      padding: BusyBooksInsets.sidebarHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarHeaderRow(
            child: Row(
              children: [
                Expanded(
                  child: _SidebarHeaderLine(
                    icon: collection
                        ? BusyBooksGlyphs.category
                        : BusyBooksGlyphs.previewView,
                    text: collection
                        ? workspace!.name
                        : book?.title ?? context.l10n.book,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: colors.foreground),
                  ),
                ),
                const SizedBox(width: BusyBooksSpacing.sm),
                BusyBooksHeaderPopupMenuButton<String>(
                  key: const ValueKey('reader-sidebar-view-menu'),
                  tooltip: context.l10n.sidebarViewMenu,
                  icon: _panelIcon(selected, Directionality.of(context)),
                  transparent: true,
                  borderRadius: BusyBooksRadius.nativeHeaderButton,
                  highlightWhenOpen: false,
                  itemBuilder: (c) => [
                    for (final view in views)
                      BusyBooksPopupMenuItem(
                        value: view,
                        label: readerPanelLabel(c, view),
                        icon: _panelIcon(view, Directionality.of(c)),
                        checked: selected == view,
                        trailingCheck: true,
                        shortcut:
                            registry?[_panelCommand(view)]?.shortcut?.label,
                      ),
                  ],
                  onSelected: (view) async {
                    if (ref.read(readerControllerProvider).bookId != bookId) {
                      return;
                    }
                    await reader.panel(view);
                    if (view == 'search') {
                      await reader.toggleSearch(visible: true);
                    }
                  },
                ),
              ],
            ),
          ),
          if (collection) ...[
            const SizedBox(height: BusyBooksSpacing.sm),
            _SidebarHeaderRow(
              child: _SidebarHeaderLine(
                icon: BusyBooksGlyphs.previewView,
                text: book?.title ?? context.l10n.book,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SidebarHeaderRow extends StatelessWidget {
  const _SidebarHeaderRow({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: BusyBooksSizes.iconButton),
    child: child,
  );
}

class _SidebarHeaderLine extends StatelessWidget {
  const _SidebarHeaderLine({
    required this.icon,
    required this.text,
    required this.style,
  });
  final IconData icon;
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: text,
    child: Row(
      children: [
        Icon(
          icon,
          size: MediaQuery.textScalerOf(
            context,
          ).scale(style?.fontSize ?? BusyBooksSizes.iconSm),
          color: style?.color,
        ),
        const SizedBox(width: BusyBooksSpacing.sm),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    ),
  );
}

class ReadingSidebarBody extends ConsumerWidget {
  const ReadingSidebarBody({super.key, required this.bookId});
  final String bookId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(readerControllerProvider);
    if (state.bookId != bookId) {
      return Center(child: Text(context.l10n.loadingBook));
    }
    return KeyedSubtree(
      key: ValueKey('$bookId:${state.panel}'),
      child: switch (state.panel) {
        'books' => _BooksPanel(bookId: bookId),
        'search' => _SearchPanel(bookId: bookId),
        'annotations' => _AnnotationsPanel(bookId: bookId),
        'thumbnails' => _ThumbnailPanel(bookId: bookId),
        _ => _OutlinePanel(bookId: bookId),
      },
    );
  }
}

// BusyMark's selected/hovered rounded tree surface and exact normal row density.
// Larger accessibility text can increase the row instead of clipping its title.
double _rowHeight(BuildContext c) => math.max(
  BusyBooksSizes.sidebarTreeRowHeight,
  MediaQuery.textScalerOf(
        c,
      ).scale(Theme.of(c).textTheme.bodyMedium?.fontSize ?? 14) +
      BusyBooksSpacing.sm,
);

class _SidebarRowSurface extends StatelessWidget {
  const _SidebarRowSurface({
    super.key,
    required this.child,
    this.selected = false,
    this.onTap,
    this.height,
    this.focused = false,
    this.canRequestFocus = true,
  });
  final Widget child;
  final bool selected, focused, canRequestFocus;
  final VoidCallback? onTap;
  final double? height;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: BusyBooksStroke.hairline),
    child: Material(
      color: selected
          ? busyBooksSelectedBackground(context)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(BusyBooksRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        canRequestFocus: canRequestFocus,
        hoverColor: busyBooksRowHoverColor(context),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: focused
                ? Border.all(color: Theme.of(context).colorScheme.primary)
                : null,
            borderRadius: BorderRadius.circular(BusyBooksRadius.md),
          ),
          child: SizedBox(height: height ?? _rowHeight(context), child: child),
        ),
      ),
    ),
  );
}

class _SidebarTreeRow extends StatelessWidget {
  const _SidebarTreeRow({
    required this.node,
    required this.expanded,
    required this.selected,
    required this.focused,
    required this.trailing,
    required this.location,
    required this.onFocus,
    this.onToggle,
    this.onTap,
  });
  final PublicationOutlineNode node;
  final bool expanded, selected, focused;
  final Widget trailing;
  final String location;
  final VoidCallback onFocus;
  final VoidCallback? onToggle, onTap;
  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context),
        direction = Directionality.of(context),
        hasChildren = node.children.isNotEmpty;
    final foreground = selected ? colors.foreground : colors.mutedForeground;
    return Semantics(
      key: ValueKey('outline-semantics-${node.id}'),
      container: true,
      selected: selected,
      focusable: true,
      focused: focused,
      expanded: hasChildren ? expanded : null,
      label: node.title,
      value: '${context.l10n.outlineLevel(node.depth + 1)} · $location',
      onTap: onTap,
      onExpand: hasChildren && !expanded ? onToggle : null,
      onCollapse: hasChildren && expanded ? onToggle : null,
      child: ExcludeSemantics(
        child: _SidebarRowSurface(
          selected: selected,
          focused: focused,
          canRequestFocus: false,
          onTap: () {
            onFocus();
            onTap?.call();
          },
          child: Row(
            children: [
              SizedBox(
                width:
                    BusyBooksSizes.sidebarTreeDepthBase +
                    node.depth * BusyBooksSizes.sidebarTreeDepthIndent,
              ),
              SizedBox.square(
                dimension: BusyBooksSizes.sidebarTreeControl,
                child: hasChildren
                    ? Tooltip(
                        message:
                            '${expanded ? context.l10n.collapseSection : context.l10n.expandSection} · ${node.title}',
                        child: GestureDetector(
                          key: ValueKey('outline-disclosure-${node.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            onFocus();
                            onToggle?.call();
                          },
                          child: AnimatedRotation(
                            turns: expanded
                                ? (direction == TextDirection.rtl ? -.25 : .25)
                                : 0,
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : BusyBooksMotion.sidebarExpand,
                            child: Icon(
                              BusyBooksGlyphs.collapsedTreeArrowFor(direction),
                              size: BusyBooksSizes.sidebarTreeArrow,
                              color: foreground,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: BusyBooksSpacing.xs),
              Expanded(
                child: Tooltip(
                  message: node.title,
                  child: Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: colors.foreground),
                  ),
                ),
              ),
              trailing,
              const SizedBox(width: BusyBooksSpacing.xs),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlinePanel extends ConsumerStatefulWidget {
  const _OutlinePanel({required this.bookId});
  final String bookId;
  @override
  ConsumerState<_OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends ConsumerState<_OutlinePanel> {
  late final ScrollController _scroll;
  final _focus = FocusNode(debugLabel: 'Publication outline');
  bool _focused = false;
  int? _revealed;
  PublicationOutline? _visibleOutline;
  Set<String>? _visibleExpansion;
  List<PublicationOutlineNode> _visibleEntries = const [];
  List<PublicationOutlineNode> _visible(
    PublicationOutline outline,
    Set<String> expanded,
  ) {
    if (!identical(outline, _visibleOutline) ||
        !identical(expanded, _visibleExpansion)) {
      _visibleOutline = outline;
      _visibleExpansion = expanded;
      _visibleEntries = outline.visible(expanded);
    }
    return _visibleEntries;
  }

  ReaderSidebarController get view =>
      ref.read(readerSidebarProvider(widget.bookId).notifier);
  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(
      initialScrollOffset:
          ref.read(readerSidebarProvider(widget.bookId)).scroll['outline'] ?? 0,
    )..addListener(_save);
  }

  void _save() => view.scrolled('outline', _scroll.offset);
  @override
  void dispose() {
    _scroll.removeListener(_save);
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reveal(int index, double extent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final top = BusyBooksInsets.sidebarList.top + index * extent,
          position = _scroll.position;
      if (top < position.pixels ||
          top + extent > position.pixels + position.viewportDimension) {
        _scroll.jumpTo(
          (top - position.viewportDimension * .35).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      readerSidebarProvider(
        widget.bookId,
      ).select((v) => (v.expanded, v.focusedOutline, v.reveal)),
    );
    final state = ref.watch(readerControllerProvider),
        ui = ref.read(readerSidebarProvider(widget.bookId)),
        outline = state.outline,
        entries = _visible(outline, ui.expanded),
        reader = ref.read(readerControllerProvider.notifier);
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(BusyBooksSpacing.lg),
        child: state.outlineStatus == 'error'
            ? Column(
                children: [
                  Text(context.l10n.outlineFailed),
                  BusyBooksPushButton.standard(
                    onPressed: state.ready
                        ? () => reader.reloadOutline(bookId: widget.bookId)
                        : null,
                    child: Text(context.l10n.retry),
                  ),
                ],
              )
            : Text(
                state.outlineStatus == 'loading'
                    ? context.l10n.loadingOutline
                    : context.l10n.noOutline,
              ),
      );
    }
    final active = outline.visibleAncestor(
      outline.activeAt(state.location),
      ui.expanded,
    );
    final extent = _rowHeight(context) + BusyBooksStroke.hairline * 2;
    if (_revealed != ui.reveal &&
        ui.revealed['outline'] != ui.reveal &&
        active != null) {
      _revealed = ui.reveal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) view.acknowledgeReveal('outline', ui.reveal);
      });
      final index = entries.indexWhere((n) => n.id == active);
      if (index >= 0) _reveal(index, extent);
    }
    void focusNode(PublicationOutlineNode node) {
      view.focus(node.id);
      _focus.requestFocus();
    }

    void activate(PublicationOutlineNode node) {
      if (node.destination != null) {
        unawaited(
          reader.navigateFromSidebar(node.destination!, bookId: widget.bookId),
        );
      }
    }

    return Focus(
      focusNode: _focus,
      onFocusChange: (v) => setState(() => _focused = v),
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent ||
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isAltPressed) {
          return KeyEventResult.ignored;
        }
        final currentState = ref.read(readerControllerProvider);
        if (currentState.bookId != widget.bookId) return KeyEventResult.ignored;
        final ui = ref.read(readerSidebarProvider(widget.bookId));
        final outline = currentState.outline,
            entries = _visible(outline, ui.expanded);
        if (entries.isEmpty) return KeyEventResult.ignored;
        final active = outline.visibleAncestor(
          outline.activeAt(currentState.location),
          ui.expanded,
        );
        final chosen = entries.indexWhere((n) => n.id == ui.focusedOutline);
        var index = chosen < 0
            ? math.max(0, entries.indexWhere((n) => n.id == active))
            : chosen;
        final node = entries[index],
            key = event.logicalKey,
            rtl = Directionality.of(context) == TextDirection.rtl;
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp) {
          index = (index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1))
              .clamp(0, entries.length - 1);
        } else if (key ==
            (rtl
                ? LogicalKeyboardKey.arrowLeft
                : LogicalKeyboardKey.arrowRight)) {
          if (node.children.isNotEmpty && !ui.expanded.contains(node.id)) {
            view.toggle(node.id);
          } else if (node.children.isNotEmpty) {
            index = (index + 1).clamp(0, entries.length - 1);
          }
        } else if (key ==
            (rtl
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft)) {
          if (node.children.isNotEmpty && ui.expanded.contains(node.id)) {
            view.toggle(node.id);
          } else {
            final parent = entries.indexWhere((n) => n.id == node.parentId);
            if (parent >= 0) index = parent;
          }
        } else if (key == LogicalKeyboardKey.home) {
          index = 0;
        } else if (key == LogicalKeyboardKey.end) {
          index = entries.length - 1;
        } else if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
          activate(node);
          return KeyEventResult.handled;
        } else {
          return KeyEventResult.ignored;
        }
        view.focus(entries[index].id);
        _reveal(index, extent);
        return KeyEventResult.handled;
      },
      child: LayoutBuilder(
        builder: (c, constraints) {
          // Normal rows keep their trailing column inside the sidebar. Extremely
          // deep publication hierarchies retain indentation with horizontal scrolling.
          final depth = entries.fold<int>(0, (n, e) => math.max(n, e.depth));
          final width = math.max(
            constraints.maxWidth,
            depth * BusyBooksSizes.sidebarTreeDepthIndent +
                BusyBooksSizes.sidebarWidth * .6,
          );
          final labelWidth = math.min(
            width * .28,
            MediaQuery.textScalerOf(c).scale(BusyBooksSizes.iconButton * 2),
          );
          return Semantics(
            role: SemanticsRole.list,
            label: context.l10n.outline,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: ListView.builder(
                  key: ValueKey('outline-tree-${widget.bookId}'),
                  controller: _scroll,
                  padding: BusyBooksInsets.sidebarList,
                  itemExtent: extent,
                  itemCount: entries.length,
                  itemBuilder: (c, i) {
                    final node = entries[i], page = node.destination?['page'];
                    final reference =
                        reader.book?.pageBased == true && page is int
                        ? PublicationPageReference.pdf(
                            page,
                            state.pages,
                            state.labels,
                          )
                        : PublicationPageReference(label: node.pageLabel);
                    final description = describePublicationPage(
                      c.l10n,
                      reference,
                      grouping: node.destination == null,
                    );
                    return KeyedSubtree(
                      key: ValueKey('outline-row-${node.id}'),
                      child: _SidebarTreeRow(
                        node: node,
                        expanded: ui.expanded.contains(node.id),
                        selected: node.id == active,
                        focused: _focused && node.id == ui.focusedOutline,
                        location: description,
                        onFocus: () => focusNode(node),
                        onToggle: node.children.isEmpty
                            ? null
                            : () => view.toggle(node.id),
                        onTap: node.destination == null
                            ? null
                            : () => activate(node),
                        trailing: Tooltip(
                          message: description,
                          child: SizedBox(
                            width: labelWidth,
                            child: Text(
                              reference.display,
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(c).textTheme.bodySmall?.copyWith(
                                color: BusyBooksSurfaceColors.of(
                                  c,
                                ).mutedForeground,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

abstract class _RetainedPanelState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  String get bookId;
  String get panel;
  late final ScrollController scroll;
  @override
  void initState() {
    super.initState();
    scroll = ScrollController(
      initialScrollOffset:
          ref.read(readerSidebarProvider(bookId)).scroll[panel] ?? 0,
    )..addListener(saveScroll);
  }

  void saveScroll() => ref
      .read(readerSidebarProvider(bookId).notifier)
      .scrolled(panel, scroll.offset);
  @override
  void dispose() {
    scroll.removeListener(saveScroll);
    scroll.dispose();
    super.dispose();
  }
}

class _BooksPanel extends ConsumerStatefulWidget {
  const _BooksPanel({required this.bookId});
  final String bookId;
  @override
  ConsumerState<_BooksPanel> createState() => _BooksPanelState();
}

class _BooksPanelState extends _RetainedPanelState<_BooksPanel> {
  @override
  String get bookId => widget.bookId;
  @override
  String get panel => 'books';
  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceControllerProvider);
    return ListView.builder(
      controller: scroll,
      padding: BusyBooksInsets.sidebarList,
      itemCount: workspace.books.length,
      itemBuilder: (c, i) => BookRow(
        book: workspace.books[i],
        onOpen: () => openBook(context, ref, workspace.books[i]),
      ),
    );
  }
}

class _SearchPanel extends ConsumerStatefulWidget {
  const _SearchPanel({required this.bookId});
  final String bookId;
  @override
  ConsumerState<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends _RetainedPanelState<_SearchPanel> {
  @override
  String get bookId => widget.bookId;
  @override
  String get panel => 'search';
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerControllerProvider),
        reader = ref.read(readerControllerProvider.notifier),
        l = context.l10n;
    return Column(
      children: [
        if (state.searching) ...[
          LinearProgressIndicator(value: state.searchProgress),
          BusyBooksActionRow(title: l.cancel, onTap: reader.cancelSearch),
        ],
        if (state.matches.isNotEmpty)
          Row(
            children: [
              BusyBooksHeaderIconButton(
                tooltip: l.previousResult,
                icon: BusyBooksGlyphs.upArrow,
                onPressed: state.ready ? () => reader.stepMatch(-1) : null,
              ),
              Expanded(
                child: Text(
                  '${state.currentMatch + 1} / ${state.matches.length}',
                  textAlign: TextAlign.center,
                ),
              ),
              BusyBooksHeaderIconButton(
                tooltip: l.nextResult,
                icon: BusyBooksGlyphs.downArrow,
                onPressed: state.ready ? () => reader.stepMatch(1) : null,
              ),
            ],
          ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: BusyBooksInsets.sidebarList,
            itemCount: math.max(1, state.matches.length),
            itemBuilder: (c, i) {
              if (state.matches.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(BusyBooksSpacing.lg),
                  child: Text(switch (state.searchStatus) {
                    'idle' => l.searchHint,
                    'cancelled' => l.searchCancelled,
                    'error' => l.searchFailed,
                    'searching' => l.busy,
                    _ => l.noSearchResults,
                  }),
                );
              }
              final match = state.matches[i];
              return BusyBooksSidebarRecordRow<void>(
                icon: BusyBooksGlyphs.search,
                title: match['excerpt']?.toString() ?? '',
                subtitle: match['reference']?.toString() ?? '',
                selected: state.currentMatch == i,
                onTap: state.ready ? () => reader.selectMatch(i) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AnnotationsPanel extends ConsumerStatefulWidget {
  const _AnnotationsPanel({required this.bookId});
  final String bookId;
  @override
  ConsumerState<_AnnotationsPanel> createState() => _AnnotationsPanelState();
}

class _AnnotationsPanelState extends _RetainedPanelState<_AnnotationsPanel> {
  @override
  String get bookId => widget.bookId;
  @override
  String get panel => 'annotations';
  @override
  Widget build(BuildContext context) {
    ref.watch(workspaceControllerProvider);
    ref.watch(
      readerSidebarProvider(
        bookId,
      ).select((v) => (v.filter, v.withNotes, v.selectedAnnotation)),
    );
    final notes = ref.watch(notebookControllerProvider),
        ui = ref.read(readerSidebarProvider(bookId)),
        state = ref.watch(readerControllerProvider),
        reader = ref.read(readerControllerProvider.notifier),
        view = ref.read(readerSidebarProvider(bookId).notifier),
        l = context.l10n;
    final annotations =
        notes
            .annotationsFor(bookId, reader.annotations)
            .where(
              (a) =>
                  (ui.filter == 'all' || a.kind == ui.filter) &&
                  (!ui.withNotes || notes.effectiveNote(a).trim().isNotEmpty),
            )
            .toList()
          ..sort((a, b) => compareAnnotationLocations(a.data, b.data));
    return Column(
      children: [
        Padding(
          padding: BusyBooksInsets.sidebarList,
          child: BusyBooksPopupSelector<String>(
            value: ui.filter,
            label: switch (ui.filter) {
              'highlight' => l.highlights,
              'bookmark' => l.bookmarks,
              'region' => l.regionNotes,
              _ => l.allItems,
            },
            tooltip: l.annotations,
            options: [
              for (final (value, label) in [
                ('all', l.allItems),
                ('highlight', l.highlights),
                ('bookmark', l.bookmarks),
                ('region', l.regionNotes),
              ])
                BusyBooksPopupSelectorOption(value: value, label: label),
              BusyBooksPopupSelectorOption(value: 'notes', label: l.withNotes),
            ],
            onSelected: (v) => v == 'notes'
                ? view.filter(withNotes: !ui.withNotes)
                : view.filter(kind: v),
          ),
        ),
        if (ui.withNotes)
          BusyBooksActionRow(
            title: l.withNotes,
            onTap: () => view.filter(withNotes: false),
          ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: BusyBooksInsets.sidebarList,
            itemCount: math.max(1, annotations.length),
            itemBuilder: (c, i) {
              if (annotations.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(BusyBooksSpacing.lg),
                  child: Text(l.noAnnotations),
                );
              }
              final a = annotations[i],
                  note = annotationPreview(notes.effectiveNote(a));
              final page = a.anchor['page'];
              final refText = page is int
                  ? describePublicationPage(
                      l,
                      PublicationPageReference.pdf(
                        page,
                        state.pages,
                        state.labels,
                      ),
                    )
                  : annotationReference(c, a, book: reader.book);
              final title = a.text.isEmpty
                  ? refText
                  : annotationPreview(a.text);
              return _SidebarRowSurface(
                key: ValueKey('annotation-row-${a.id}'),
                selected: ui.selectedAnnotation == a.id,
                height: _rowHeight(c) * (note.isEmpty ? 2 : 2.5),
                onTap: () {
                  view.selectAnnotation(a.id);
                  unawaited(
                    reader.navigateFromSidebar(a.anchor, bookId: bookId),
                  );
                },
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: BusyBooksSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        a.kind == 'bookmark'
                            ? BusyBooksGlyphs.bookmark
                            : BusyBooksGlyphs.edit,
                        size: BusyBooksSizes.iconSm,
                        color: a.kind != 'bookmark'
                            ? annotationHighlightColor(a.color)
                            : null,
                      ),
                      const SizedBox(width: BusyBooksSpacing.sm),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(c).textTheme.bodyMedium,
                            ),
                            if (note.isNotEmpty)
                              Text(
                                note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(c).textTheme.bodySmall,
                              ),
                            Text(
                              '${a.kind == 'region'
                                  ? l.regionNote
                                  : a.kind == 'bookmark'
                                  ? l.bookmark
                                  : l.highlight} · $refText${notes.drafts.containsKey(a.id) ? ' · ${l.unsavedNote}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(c).textTheme.bodySmall?.copyWith(
                                color: BusyBooksSurfaceColors.of(
                                  c,
                                ).mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      BusyBooksHeaderPopupMenuButton<String>(
                        tooltip: l.moreActions,
                        icon: BusyBooksGlyphs.menuVertical,
                        itemBuilder: (_) => [
                          BusyBooksPopupMenuItem(
                            value: 'notebook',
                            label: l.openInNotebook,
                            icon: BusyBooksGlyphs.annotations,
                          ),
                          BusyBooksPopupMenuItem(
                            value: 'edit',
                            label: l.editNote,
                          ),
                          if (a.kind != 'bookmark')
                            for (final color in annotationColors)
                              BusyBooksPopupMenuItem(
                                value: color,
                                label: switch (color) {
                                  'green' => l.green,
                                  'blue' => l.blue,
                                  'pink' => l.pink,
                                  'purple' => l.purple,
                                  _ => l.yellow,
                                },
                                checked: color == a.color,
                                trailingCheck: true,
                              ),
                          BusyBooksPopupMenuItem(
                            value: 'delete',
                            label: l.delete,
                          ),
                        ],
                        onSelected: (action) async {
                          try {
                            if (reader.stateBookId != bookId) return;
                            if (action == 'notebook') {
                              ref
                                  .read(notebookControllerProvider.notifier)
                                  .view(
                                    bookId,
                                    selected: a.id,
                                    query: '',
                                    filter: 'all',
                                    withNotes: false,
                                  );
                              await openNotebook(
                                context,
                                ref,
                                bookId,
                                annotationId: a.id,
                              );
                            } else if (action == 'edit') {
                              await openNotebook(
                                context,
                                ref,
                                bookId,
                                annotationId: a.id,
                              );
                            } else if (action == 'delete') {
                              await actions.deleteAnnotation(context, ref, a);
                              await reader.syncAnnotations();
                            } else {
                              await ref
                                  .read(workspaceControllerProvider.notifier)
                                  .updateAnnotation(a.id, {
                                    'color': action,
                                  }, bookId: a.bookId);
                              await reader.syncAnnotations();
                            }
                          } catch (error) {
                            if (c.mounted) await showError(c, error);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ThumbnailPanel extends ConsumerStatefulWidget {
  const _ThumbnailPanel({required this.bookId});
  final String bookId;
  @override
  ConsumerState<_ThumbnailPanel> createState() => _ThumbnailPanelState();
}

class _ThumbnailPanelState extends _RetainedPanelState<_ThumbnailPanel> {
  @override
  String get bookId => widget.bookId;
  @override
  String get panel => 'thumbnails';
  double _extent = 0;
  bool _queued = false;
  int? _reveal;
  @override
  void saveScroll() {
    super.saveScroll();
    _schedule();
  }

  void _schedule() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || !scroll.hasClients || _extent <= 0) return;
      final reader = ref.read(readerControllerProvider.notifier),
          state = ref.read(readerControllerProvider);
      if (state.bookId != bookId ||
          !state.panelOpen ||
          state.panel != 'thumbnails') {
        return;
      }
      final start = math.max(0, (scroll.offset / _extent).floor() - 1),
          end = math.min(
            state.pages,
            ((scroll.offset + scroll.position.viewportDimension) / _extent)
                    .ceil() +
                1,
          );
      reader.requestThumbnailWindow(
        Iterable.generate(math.max(0, end - start), (i) => start + i),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(readerSidebarProvider(bookId).select((v) => v.reveal));
    final state = ref.watch(readerControllerProvider),
        ui = ref.read(readerSidebarProvider(bookId)),
        reader = ref.read(readerControllerProvider.notifier),
        l = context.l10n;
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(BusyBooksSpacing.lg),
        child: Text(l.thumbnailUnavailable),
      );
    }
    final current = (state.location['anchor'] as Map?)?['page'] as int?;
    _extent =
        BusyBooksSizes.sidebarWidth * .55 +
        _rowHeight(context) +
        BusyBooksSpacing.md * 2;
    if (_reveal != ui.reveal && ui.revealed[panel] != ui.reveal) {
      _reveal = ui.reveal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scroll.hasClients || current == null) return;
        if (!ui.scroll.containsKey(panel) || ui.revealed[panel] != ui.reveal) {
          scroll.jumpTo(
            (current * _extent).clamp(
              scroll.position.minScrollExtent,
              scroll.position.maxScrollExtent,
            ),
          );
        }
        ref
            .read(readerSidebarProvider(bookId).notifier)
            .acknowledgeReveal(panel, ui.reveal);
        _schedule();
      });
    }
    _schedule();
    return ListView.builder(
      key: ValueKey('page-previews-$bookId'),
      controller: scroll,
      itemExtent: _extent,
      padding: BusyBooksInsets.sidebarList,
      itemCount: state.pages,
      itemBuilder: (c, i) {
        final preview = state.thumbnails[i],
            error = state.thumbnailErrors[i],
            reference = PublicationPageReference.pdf(
              i,
              state.pages,
              state.labels,
            ),
            description = describePublicationPage(l, reference);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: BusyBooksSpacing.sm),
          child: Semantics(
            selected: current == i,
            label: description,
            button: true,
            child: _SidebarRowSurface(
              selected: current == i,
              height: _extent - BusyBooksSpacing.md,
              onTap: () =>
                  reader.navigateFromSidebar({'page': i}, bookId: bookId),
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(BusyBooksSpacing.sm),
                      child: preview != null
                          ? Image.memory(
                              preview.bytes,
                              fit: BoxFit.contain,
                              cacheWidth: preview.width.round(),
                              semanticLabel: description,
                              errorBuilder: (c, _, _) => BusyBooksActionRow(
                                title: l.thumbnailFailed,
                                onTap: () => reader.retryThumbnail(
                                  i,
                                  bookId: widget.bookId,
                                ),
                              ),
                            )
                          : error != null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(error, textAlign: TextAlign.center),
                                BusyBooksPushButton.standard(
                                  onPressed: () => reader.retryThumbnail(
                                    i,
                                    bookId: widget.bookId,
                                  ),
                                  child: Text(l.retry),
                                ),
                              ],
                            )
                          : const Center(
                              child: SizedBox.square(
                                dimension: BusyBooksSizes.iconButton,
                                child: CircularProgressIndicator(),
                              ),
                            ),
                    ),
                  ),
                  Tooltip(
                    message: description,
                    child: Text(
                      '${l.page} ${reference.display}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(c).textTheme.bodySmall?.copyWith(
                        color: BusyBooksSurfaceColors.of(c).mutedForeground,
                      ),
                    ),
                  ),
                  const SizedBox(height: BusyBooksSpacing.sm),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
