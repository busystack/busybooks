import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotations/presentation/annotation_presentation.dart';
import '../app/busybooks_design.dart';
import '../app/busybooks_glyphs.dart';
import '../app/busybooks_search_field.dart';
import '../app/command_registry.dart';
import '../app/localization.dart';
import '../app/product_actions.dart';
import '../notebook/presentation/book_view_selector.dart';
import '../reading/application/reader_controller.dart';
import '../workspace/workspace_controller.dart';
import 'book_search_session.dart';

String bookSearchCategoryLabel(
  BuildContext context,
  BookSearchCategory category,
) => switch (category) {
  BookSearchCategory.bookText => context.l10n.bookText,
  BookSearchCategory.notebook => context.l10n.notebook,
  BookSearchCategory.bookmarks => context.l10n.bookmarks,
  BookSearchCategory.chapters => context.l10n.chapters,
  BookSearchCategory.actions => context.l10n.actions,
};
List<BookActionSearchResult> bookSearchActions(
  BuildContext context,
  BusyBooksCommandRegistry registry,
) => [
  for (final command in registry.visibleCommands())
    BookActionSearchResult(command, command.label(context)),
];

Future<void> activateBookSearchResult(
  BuildContext context,
  WidgetRef ref,
  String bookId,
  BookSearchResult result,
  int generation,
) async {
  final search = ref.read(bookSearchProvider(bookId).notifier);
  if (!search.accepts(result, generation)) return;
  await runAppAction(context, () async {
    final reader = ref.read(readerControllerProvider.notifier);
    Future<void> jump(Map<String, dynamic> anchor) =>
        openReading(context, ref, bookId, anchor: anchor);
    switch (result) {
      case BookTextSearchResult():
        if (reader.stateBookId != bookId ||
            reader.sessionId != result.session) {
          search.retry();
          return;
        }
        await jump(result.anchor);
      case AnnotationSearchResult():
        if (ref
                .read(workspaceControllerProvider)
                .annotations
                .any((a) => a.id == result.annotation.id) ||
            ref.read(bookSearchProvider(bookId)).results.contains(result)) {
          if (ref.read(bookSearchProvider(bookId)).category ==
              BookSearchCategory.bookmarks) {
            await jump(result.annotation.anchor);
          } else {
            await openNotebook(
              context,
              ref,
              bookId,
              annotationId: result.annotation.id,
            );
          }
        }
      case ChapterSearchResult():
        if (result.chapter.destination != null) {
          await jump(result.chapter.destination!);
        }
      case BookActionSearchResult():
        if (!result.command.canExecute) return;
        search.close(restoreFocus: false);
        final registry = BusyBooksCommandRegistryScope.read(context);
        if (registry != null) await registry.execute(result.command.id);
    }
  });
}

class BookSearchHeaderField extends ConsumerStatefulWidget {
  const BookSearchHeaderField({
    super.key,
    required this.bookId,
    this.tooltipPositionDelegate,
  });
  final String bookId;
  final TooltipPositionDelegate? tooltipPositionDelegate;
  @override
  ConsumerState<BookSearchHeaderField> createState() =>
      _BookSearchHeaderFieldState();
}

class _BookSearchHeaderFieldState extends ConsumerState<BookSearchHeaderField> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookSearchProvider(widget.bookId));
    if (_text.text != state.query) {
      _text.value = TextEditingValue(
        text: state.query,
        selection: TextSelection.collapsed(offset: state.query.length),
      );
    }
    final controller = ref.read(bookSearchProvider(widget.bookId).notifier);
    return BusyBooksSearchField(
      key: const ValueKey('book-header-search'),
      tooltipPositionDelegate: widget.tooltipPositionDelegate,
      controller: _text,
      hintText: bookSearchCategoryLabel(context, state.category),
      autofocus: state.active,
      focusRequest: state.focusRequest,
      clearOnEscape: false,
      onChanged: controller.query,
      onClear: () => controller.query(''),
      onMoveSelection: controller.moveSelection,
      onEscape: controller.close,
      onSubmitted: (_) {
        final result = controller.selectedResult;
        if (result != null) {
          unawaited(
            activateBookSearchResult(
              context,
              ref,
              widget.bookId,
              result,
              state.generation,
            ),
          );
        }
      },
    );
  }
}

class BookSearchSidebar extends ConsumerStatefulWidget {
  const BookSearchSidebar({super.key, required this.bookId});
  final String bookId;
  @override
  ConsumerState<BookSearchSidebar> createState() => _BookSearchSidebarState();
}

class _BookSearchSidebarState extends ConsumerState<BookSearchSidebar> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookSearchProvider(widget.bookId)),
        controller = ref.read(bookSearchProvider(widget.bookId).notifier),
        l = context.l10n;
    ref.watch(readerControllerProvider);
    final registry = BusyBooksCommandRegistryScope.maybeOf(context);
    if (registry != null) {
      controller.setActions(bookSearchActions(context, registry));
    }
    final categories = {...controller.categories, state.category}.toList();
    final extent = math.max(
      80.0,
      MediaQuery.textScalerOf(context).scale(14) * 4 + BusyBooksSpacing.md,
    );
    ref.listen(
      bookSearchProvider(
        widget.bookId,
      ).select((s) => (s.selected, s.generation)),
      (_, value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients || value.$1 < 0) return;
          final top = value.$1 * extent, position = _scroll.position;
          if (top < position.pixels ||
              top + extent > position.pixels + position.viewportDimension) {
            _scroll.jumpTo(
              (top - position.viewportDimension * .3).clamp(
                0.0,
                position.maxScrollExtent,
              ),
            );
          }
        });
      },
    );
    final textUnavailable =
        state.category == BookSearchCategory.bookText &&
        !ref.read(readerControllerProvider.notifier).canSearch;
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          controller.close();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowUp) {
          controller.moveSelection(
            event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1,
          );
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            controller.selectedResult != null) {
          unawaited(
            activateBookSearchResult(
              context,
              ref,
              widget.bookId,
              controller.selectedResult!,
              state.generation,
            ),
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: BusyBooksInsets.sidebarHeader,
            child: Row(
              children: [
                Expanded(
                  child: BusyBooksPopupSelector<BookSearchCategory>(
                    value: state.category,
                    label: bookSearchCategoryLabel(context, state.category),
                    tooltip: l.searchCategory,
                    options: [
                      for (final category in categories)
                        BusyBooksPopupSelectorOption(
                          value: category,
                          label: bookSearchCategoryLabel(context, category),
                        ),
                    ],
                    onSelected: (category) =>
                        controller.open(category: category),
                  ),
                ),
                BusyBooksHeaderIconButton(
                  tooltip: l.closeSearch,
                  tooltipPositionDelegate: (info) =>
                      BusyBooksTooltipStyle.positionWithin(context, info),
                  icon: BusyBooksGlyphs.close,
                  onPressed: controller.close,
                ),
              ],
            ),
          ),
          if (state.loading) LinearProgressIndicator(value: state.progress),
          if (state.error != null)
            BusyBooksBanner(
              title: l.searchFailed,
              actionLabel: l.retry,
              onAction: controller.retry,
            ),
          if (textUnavailable)
            BusyBooksBanner(
              title: l.searchNeedsReading,
              actionLabel: l.reading,
              onAction: () => openReading(context, ref, widget.bookId),
            ),
          Expanded(
            child: state.results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(BusyBooksSpacing.lg),
                      child: Text(
                        state.loading
                            ? l.searching
                            : state.query.isEmpty &&
                                  state.category == BookSearchCategory.bookText
                            ? l.enterSearch
                            : l.noResults,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemExtent: extent,
                    itemCount: state.results.length,
                    itemBuilder: (context, index) {
                      final result = state.results[index];
                      final (title, subtitle, icon, enabled) = switch (result) {
                        BookTextSearchResult() => (
                          result.match['excerpt']?.toString() ??
                              result.match['text']?.toString() ??
                              l.bookText,
                          result.match['reference']?.toString() ?? '',
                          BusyBooksGlyphs.text,
                          true,
                        ),
                        AnnotationSearchResult() => (
                          result.annotation.text.isEmpty
                              ? result.annotation.reference
                              : annotationPreview(result.annotation.text),
                          annotationPreview(result.note),
                          result.annotation.kind == 'bookmark'
                              ? BusyBooksGlyphs.bookmark
                              : BusyBooksGlyphs.annotations,
                          true,
                        ),
                        ChapterSearchResult() => (
                          result.chapter.title,
                          result.chapter.pageLabel ?? '',
                          BusyBooksGlyphs.indent,
                          result.chapter.destination != null,
                        ),
                        BookActionSearchResult() => (
                          result.title,
                          result.command.shortcut?.label ?? '',
                          BusyBooksGlyphs.keyboard,
                          result.command.canExecute,
                        ),
                      };
                      return BusyBooksSidebarRecordRow<String>(
                        key: ValueKey(result.identity),
                        icon: icon,
                        selected: index == state.selected,
                        compact: true,
                        semanticsLabel: '$title\n$subtitle',
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        onTap: enabled
                            ? () async {
                                controller.select(index);
                                await activateBookSearchResult(
                                  context,
                                  ref,
                                  widget.bookId,
                                  result,
                                  state.generation,
                                );
                              }
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Search temporarily replaces navigation without disposing its scroll/focus
/// state. Hidden navigation cannot participate in traversal or semantics.
class BookSearchSidebarHost extends ConsumerWidget {
  const BookSearchSidebarHost({
    super.key,
    required this.bookId,
    required this.child,
  });
  final String bookId;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      bookSearchProvider(bookId).select((s) => s.active),
    );
    ref.listen(bookSearchProvider(bookId).select((s) => s.active), (_, _) {
      Tooltip.dismissAllToolTips();
    });
    final tooltipTheme = TooltipTheme.of(context);
    return TooltipTheme(
      data: tooltipTheme.copyWith(
        constraints:
            (tooltipTheme.constraints ?? BusyBooksTooltipStyle.constraints)
                .copyWith(
                  maxWidth: BusyBooksSizes.sidebarWidth - BusyBooksSpacing.md,
                ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: active,
            child: ExcludeSemantics(
              excluding: active,
              child: TickerMode(
                enabled: !active,
                child: TooltipVisibility(
                  visible: !active,
                  child: Offstage(offstage: active, child: child),
                ),
              ),
            ),
          ),
          if (active) BookSearchSidebar(bookId: bookId),
        ],
      ),
    );
  }
}
