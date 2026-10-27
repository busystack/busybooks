import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/busybooks_design.dart';
import '../app/app_router.dart';
import '../app/busybooks_glyphs.dart';
import '../app/busybooks_search_field.dart';
import '../app/busybooks_toast.dart';
import '../app/command_registry.dart';
import '../app/localization.dart';
import '../app/product_actions.dart';
import '../book_workspace/application/book_sidebar_controller.dart';
import '../library/application/collection_view_controller.dart';
import '../notebook/presentation/book_view_selector.dart';
import '../reading/application/reader_controller.dart';
import 'book_search_session.dart';

const searchCategoryCommands = {
  BusyBooksCommandIds.searchBookText: BookSearchCategory.bookText,
  BusyBooksCommandIds.searchNotebook: BookSearchCategory.notebook,
  BusyBooksCommandIds.searchBookmarks: BookSearchCategory.bookmarks,
  BusyBooksCommandIds.searchChapters: BookSearchCategory.chapters,
  BusyBooksCommandIds.searchBooks: BookSearchCategory.books,
  BusyBooksCommandIds.searchRecent: BookSearchCategory.recent,
  BusyBooksCommandIds.commandPalette: BookSearchCategory.actions,
};

String bookSearchCategoryLabel(
  BuildContext context,
  BookSearchCategory category,
) => switch (category) {
  BookSearchCategory.bookText => context.l10n.bookText,
  BookSearchCategory.notebook => context.l10n.notebook,
  BookSearchCategory.bookmarks => context.l10n.bookmarks,
  BookSearchCategory.chapters => context.l10n.chapters,
  BookSearchCategory.books => context.l10n.books,
  BookSearchCategory.recent => context.l10n.recent,
  BookSearchCategory.actions => context.l10n.actions,
};

String bookSearchScopeLabel(BuildContext context, BookSearchScope scope) => [
  switch (scope.kind) {
    BookSearchScopeKind.thisBook => context.l10n.thisBook,
    BookSearchScopeKind.currentCollection => context.l10n.currentCollection,
    BookSearchScopeKind.allSavedBooks => context.l10n.allSavedBooks,
  },
  if (scope.name.isNotEmpty) scope.name,
].join(' · ');

List<BookActionSearchResult> bookSearchActions(
  BuildContext context,
  BusyBooksCommandRegistry registry,
) => [
  for (final command in registry.visibleCommands())
    BookActionSearchResult(
      command,
      command.label(context),
      category: command.category(context),
      description: command.description?.call(context),
      enabled: command.canExecute,
      disabledReason:
          command.disabledReason?.call(context) ?? context.l10n.searchDisabled,
    ),
];

final _activationBusyProvider = Provider((ref) => _ActivationBusy());

class _ActivationBusy {
  bool busy = false;
}

Future<void> submitBookSearch(BuildContext context, WidgetRef ref) async {
  final busy = ref.read(_activationBusyProvider);
  if (busy.busy) return;
  busy.busy = true;
  try {
    final controller = ref.read(bookSearchSessionProvider.notifier);
    if (!await controller.submit() || !context.mounted) return;
    final result = controller.selectedResult;
    if (result != null) {
      await _activate(
        context,
        ref,
        result,
        ref.read(bookSearchSessionProvider).generation,
      );
    }
  } finally {
    busy.busy = false;
  }
}

Future<void> activateBookSearchResult(
  BuildContext context,
  WidgetRef ref,
  BookSearchResult result,
  int generation, {
  bool? passage,
}) async {
  final busy = ref.read(_activationBusyProvider);
  if (busy.busy) return;
  busy.busy = true;
  try {
    await _activate(context, ref, result, generation, passage: passage);
  } finally {
    busy.busy = false;
  }
}

Future<void> _activate(
  BuildContext context,
  WidgetRef ref,
  BookSearchResult result,
  int generation, {
  bool? passage,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final operationContext =
      rootNavigatorKey.currentState?.overlay?.context ?? context;
  final narrow =
      MediaQuery.sizeOf(context).width <
      BusyBooksSizes.workspaceSidebarBreakpoint;
  final search = container.read(bookSearchSessionProvider.notifier);
  final state = container.read(bookSearchSessionProvider);
  String? targetRoute, targetBookId;
  switch (result) {
    case AnnotationSearchResult():
      targetBookId = result.annotation.bookId;
      targetRoute =
          (passage ?? state.category == BookSearchCategory.bookmarks) &&
              (result.book?.available == true ||
                  result.book?.status == 'unverified')
          ? '/read/$targetBookId'
          : '/notebook/$targetBookId';
    case BookMetadataSearchResult():
      targetBookId = result.book.id;
      targetRoute = '/read/$targetBookId';
    case RecentBookSearchResult():
      targetBookId = result.resource.bookId;
      targetRoute = targetBookId == null ? '/workspace' : '/read/$targetBookId';
    case BookTextSearchResult():
      targetBookId = result.bookId;
      targetRoute = '/read/$targetBookId';
    case ChapterSearchResult():
      targetBookId = result.bookId;
      targetRoute = '/read/$targetBookId';
    case BookActionSearchResult():
      break;
  }
  if (!search.beginActivation(
    result,
    generation,
    targetRoute: targetRoute,
    targetBookId: targetBookId,
  )) {
    return;
  }
  bool current() =>
      operationContext.mounted && search.accepts(result, generation);
  try {
    if (!await search.validateResult(result, generation) || !current()) {
      if (context.mounted) {
        BusyBooksToastOverlay.show(
          context,
          message: context.l10n.searchUnavailable,
        );
      }
      search.retry();
      return;
    }
    if (!context.mounted) return;
    await runAppAction(operationContext, () async {
      switch (result) {
        case BookTextSearchResult():
          final reader = container.read(readerControllerProvider.notifier);
          if (reader.stateBookId != result.bookId ||
              reader.sessionId != result.session) {
            search.retry();
            return;
          }
          await openReading(
            operationContext,
            ref,
            result.bookId,
            anchor: result.anchor,
            canActivate: current,
            validateActivation: () => search.validateResult(result, generation),
          );
          if (current()) search.didActivateResult(result);
        case ChapterSearchResult():
          if (result.chapter.destination != null) {
            await openReading(
              operationContext,
              ref,
              result.bookId,
              anchor: result.chapter.destination,
              canActivate: current,
              validateActivation: () =>
                  search.validateResult(result, generation),
            );
          }
        case AnnotationSearchResult():
          if (targetRoute == '/read/$targetBookId') {
            await openReading(
              operationContext,
              ref,
              targetBookId!,
              anchor: result.annotation.anchor,
              annotationId: result.annotation.id,
              canActivate: current,
              validateActivation: () =>
                  search.validateResult(result, generation),
            );
          } else {
            await openNotebook(
              operationContext,
              ref,
              targetBookId!,
              annotationId: result.annotation.id,
              canActivate: current,
              validateActivation: () =>
                  search.validateResult(result, generation),
            );
          }
        case BookMetadataSearchResult():
          if (narrow) search.dismissForActivation();
          await openBook(
            operationContext,
            ref,
            result.book,
            canActivate: current,
            validateActivation: () => search.validateResult(result, generation),
          );
          if (narrow && current()) {
            await container
                .read(bookSidebarProvider(result.book.id).notifier)
                .setOpen(false);
          }
        case RecentBookSearchResult():
          if (narrow) search.dismissForActivation();
          await openRecent(
            operationContext,
            ref,
            result.resource,
            canActivate: current,
            validateActivation: () => search.validateResult(result, generation),
          );
          if (narrow && current()) {
            final id = result.resource.bookId;
            if (id != null) {
              await container
                  .read(bookSidebarProvider(id).notifier)
                  .setOpen(false);
            } else {
              container
                  .read(
                    collectionViewProvider(result.resource.resourceId).notifier,
                  )
                  .update(sidebarOpen: false);
            }
          }
        case BookActionSearchResult():
          final registry = BusyBooksCommandRegistryScope.read(context);
          final command = registry?[result.command.id];
          if (current() &&
              result.available &&
              command?.visible() == true &&
              command!.canExecute) {
            search.close(restoreFocus: false);
            await registry!.execute(command.id);
          }
      }
    });
  } finally {
    search.endActivation();
  }
}

class BookSearchHeaderField extends ConsumerStatefulWidget {
  const BookSearchHeaderField({super.key, this.tooltipPositionDelegate});
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
    final state = ref.watch(bookSearchSessionProvider);
    if (_text.text != state.query) {
      _text.value = TextEditingValue(
        text: state.query,
        selection: TextSelection.collapsed(offset: state.query.length),
      );
    }
    final controller = ref.read(bookSearchSessionProvider.notifier);
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
      onSubmitted: (_) => unawaited(submitBookSearch(context, ref)),
    );
  }
}

class BookSearchSidebar extends ConsumerWidget {
  const BookSearchSidebar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookSearchSessionProvider),
        controller = ref.read(bookSearchSessionProvider.notifier),
        l = context.l10n;
    ref.watch(readerControllerProvider);
    final registry = BusyBooksCommandRegistryScope.maybeOf(context);
    if (registry != null) {
      controller.setActions(bookSearchActions(context, registry));
    }
    final categories = {...controller.categories, state.category}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final scopes = controller.scopes;
    final textUnavailable =
        state.category == BookSearchCategory.bookText &&
        state.unavailable != null &&
        state.unavailable != 'reader-loading';
    final needsReading = state.unavailable == 'needs-reading';
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          controller.close();
          return KeyEventResult.handled;
        }
        // Selectors and buttons keep their own Enter/arrow behavior.
        var resultFocus = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
          if (e.widget is BookSearchResultList) {
            resultFocus = true;
            return false;
          }
          if (e.widget is IconButton) return false;
          return true;
        });
        if (!resultFocus) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowUp) {
          controller.moveSelection(
            event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1,
          );
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          unawaited(submitBookSearch(context, ref));
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
                Text(l.searchContext),
                const SizedBox(width: BusyBooksSpacing.sm),
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
                          shortcut:
                              registry?[searchCategoryCommands.entries
                                      .firstWhere((e) => e.value == category)
                                      .key]
                                  ?.shortcut
                                  ?.label,
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
          Padding(
            padding: BusyBooksInsets.sectionLabel,
            child:
                const [
                      BookSearchCategory.notebook,
                      BookSearchCategory.bookmarks,
                      BookSearchCategory.books,
                    ].contains(state.category) &&
                    scopes.length > 1
                ? BusyBooksPopupSelector<BookSearchScope>(
                    value: state.scope,
                    label: state.scope.name.isNotEmpty
                        ? state.scope.name
                        : bookSearchScopeLabel(context, state.scope),
                    tooltip:
                        '${l.searchScope} · ${bookSearchScopeLabel(context, state.scope)}',
                    options: [
                      for (final scope in scopes)
                        BusyBooksPopupSelectorOption(
                          value: scope,
                          label: bookSearchScopeLabel(context, scope),
                        ),
                    ],
                    onSelected: controller.setScope,
                  )
                : Text(
                    state.category == BookSearchCategory.bookText ||
                            state.category == BookSearchCategory.chapters
                        ? state.scope.name
                        : state.category == BookSearchCategory.actions ||
                              state.category == BookSearchCategory.recent
                        ? l.appTitle
                        : bookSearchScopeLabel(context, state.scope),
                  ),
          ),
          if (state.loading) LinearProgressIndicator(value: state.progress),
          if (state.error != null)
            BusyBooksBanner(
              title: state.results.isNotEmpty
                  ? l.searchIncomplete
                  : l.searchFailed,
              actionLabel: l.retry,
              onAction: controller.retry,
            ),
          if (state.error == null &&
              state.unavailable != null &&
              !needsReading &&
              state.unavailable != 'reader-loading')
            BusyBooksBanner(
              title: l.searchUnavailable,
              actionLabel: l.retry,
              onAction: controller.retry,
            ),
          if (needsReading && state.query.isNotEmpty && state.bookId != null)
            BusyBooksBanner(
              title: l.searchNeedsReading,
              actionLabel: l.reading,
              onAction: () => openReading(context, ref, state.bookId!),
            ),
          Expanded(
            child: state.results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(BusyBooksSpacing.lg),
                      child: Text(
                        state.error != null
                            ? l.searchFailed
                            : state.unavailable != null &&
                                  !needsReading &&
                                  state.unavailable != 'reader-loading'
                            ? l.searchUnavailable
                            : state.query.isEmpty &&
                                  state.category != BookSearchCategory.actions
                            ? l.enterSearch
                            : state.loading
                            ? l.searching
                            : textUnavailable
                            ? (needsReading
                                  ? l.searchNeedsReading
                                  : l.searchUnavailable)
                            : l.noResults,
                      ),
                    ),
                  )
                : BookSearchResultList(
                    results: state.results,
                    selected: state.selected,
                    generation: state.generation,
                    query: state.query,
                    groupActions:
                        state.category == BookSearchCategory.actions &&
                        state.query.trim().isEmpty,
                  ),
          ),
          if (state.results.isNotEmpty &&
              state.category != BookSearchCategory.actions)
            Padding(
              padding: BusyBooksInsets.sectionLabel,
              child: Text(
                [
                  l.searchLoadedResults(state.results.length),
                  if (state.hasMore) l.searchMoreAvailable,
                  if (state.resultOffset > 0) l.searchEarlierResults,
                ].join(' '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (state.hasMore)
            Padding(
              padding: BusyBooksInsets.sectionLabel,
              child: BusyBooksPushButton.standard(
                onPressed: state.loading ? null : controller.showMore,
                child: Text(l.showMoreResults),
              ),
            ),
        ],
      ),
    );
  }
}

/// A bounded metadata projection may omit the matching historical path or the
/// tail of a long field. Retain the repository's actual matched excerpt too.
String bookMetadataSearchContext(
  BookMetadataSearchResult result,
  String query,
) {
  final fields = [
    result.book.author,
    result.book.series,
    result.book.referencePath,
  ].where((s) => s.isNotEmpty).toList();
  final visible = [result.book.title, ...fields].join('\n');
  final excerpt = result.match?['text'] as String?;
  if (query.isNotEmpty &&
      excerpt != null &&
      !RegExp(
        RegExp.escape(query),
        caseSensitive: false,
        unicode: true,
      ).hasMatch(visible)) {
    fields.add(excerpt);
  }
  return fields.join(' · ');
}

class BookSearchResultList extends ConsumerStatefulWidget {
  const BookSearchResultList({
    super.key,
    required this.results,
    required this.selected,
    required this.generation,
    required this.query,
    required this.groupActions,
  });
  final List<BookSearchResult> results;
  final int selected, generation;
  final String query;
  final bool groupActions;
  @override
  ConsumerState<BookSearchResultList> createState() =>
      _BookSearchResultListState();
}

class _BookSearchResultListState extends ConsumerState<BookSearchResultList> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  final _focus = <String, FocusNode>{};
  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(covariant BookSearchResultList old) {
    super.didUpdateWidget(old);
    if (!identical(old.results, widget.results)) {
      _keys.clear();
      final ids = widget.results.map((r) => r.identity).toSet();
      final removed = [
        for (final id in _focus.keys.toList())
          if (!ids.contains(id)) _focus.remove(id)!,
      ];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in removed) {
          node.dispose();
        }
      });
    }
    if (old.selected != widget.selected ||
        !identical(old.results, widget.results)) {
      _scheduleReveal();
    }
  }

  void _scheduleReveal() {
    final index = widget.selected, rows = widget.results;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_reveal(index, rows)),
    );
  }

  Future<void> _reveal(int index, List<BookSearchResult> rows) async {
    while (mounted &&
        _scroll.hasClients &&
        index >= 0 &&
        widget.selected == index &&
        identical(rows, widget.results)) {
      final target = _keys[index]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: .5,
          duration: const Duration(milliseconds: 80),
        );
        return;
      }
      final mountedRows = _keys.entries.where(
        (e) => e.value.currentContext != null,
      );
      final before = mountedRows.isNotEmpty && index < mountedRows.first.key;
      final p = _scroll.position;
      final offset = (p.pixels + p.viewportDimension * (before ? -.8 : .8))
          .clamp(0.0, p.maxScrollExtent);
      if (offset == p.pixels) return;
      _scroll.jumpTo(offset);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const ValueKey('sidebar-search-results'),
    controller: _scroll,
    itemCount: widget.results.length,
    itemBuilder: (context, index) {
      final result = widget.results[index], l = context.l10n;
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
          [
            result.annotation.text,
            result.note,
          ].where((s) => s.isNotEmpty).join('\n'),
          [
            result.book?.title ?? '',
            result.book?.author ?? '',
            result.book?.referencePath ?? '',
            result.annotation.reference,
          ].where((s) => s.isNotEmpty).join(' · '),
          result.annotation.kind == 'bookmark'
              ? BusyBooksGlyphs.bookmark
              : BusyBooksGlyphs.annotations,
          true,
        ),
        ChapterSearchResult() => (
          result.chapter.title,
          [
            if (result.ancestors.isNotEmpty) result.ancestors.join(' › '),
            if (result.chapter.pageLabel != null) result.chapter.pageLabel!,
            '${result.chapter.depth + 1}',
          ].join(' · '),
          BusyBooksGlyphs.indent,
          result.chapter.destination != null,
        ),
        BookMetadataSearchResult() => (
          result.book.title,
          bookMetadataSearchContext(result, widget.query),
          BusyBooksGlyphs.document,
          true,
        ),
        RecentBookSearchResult() => (
          result.resource.title,
          result.resource.isBook ? result.resource.path : l.collection,
          result.resource.isBook
              ? BusyBooksGlyphs.document
              : BusyBooksGlyphs.folder,
          true,
        ),
        BookActionSearchResult() => (
          result.title,
          [
            if (!widget.groupActions) result.category,
            if (!result.available) result.disabledReason ?? l.searchDisabled,
            if (result.command.shortcut != null) result.command.shortcut!.label,
          ].join(' · '),
          BusyBooksGlyphs.keyboard,
          result.available,
        ),
      };
      final row = BusyBooksSidebarRecordRow<String>(
        key: ValueKey(result.identity),
        geometryKey: _keys.putIfAbsent(index, GlobalKey.new),
        focusNode: _focus.putIfAbsent(result.identity, FocusNode.new),
        onFocusChange: (focused) {
          if (focused) {
            ref.read(bookSearchSessionProvider.notifier).select(index);
          }
        },
        icon: icon,
        selected: index == widget.selected,
        compact: true,
        semanticsLabel: '$title\n$subtitle',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (result is BookTextSearchResult &&
                result.match['excerptParts'] is Map)
              Text.rich(
                TextSpan(
                  children: [
                    for (final name in ['pre', 'match', 'post'])
                      TextSpan(
                        text:
                            (result.match['excerptParts'] as Map)[name]
                                ?.toString() ??
                            '',
                        style: name == 'match'
                            ? const TextStyle(fontWeight: FontWeight.bold)
                            : null,
                      ),
                  ],
                ),
              )
            else
              _HighlightedSearchText(
                title.isEmpty ? subtitle : title,
                query: widget.query,
              ),
            if (subtitle.isNotEmpty)
              _HighlightedSearchText(
                subtitle,
                query: widget.query,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        menuTooltip: result is AnnotationSearchResult ? l.notebook : null,
        menuItemsBuilder: result is AnnotationSearchResult
            ? (_) => [
                BusyBooksPopupMenuItem(value: 'notebook', label: l.notebook),
                BusyBooksPopupMenuItem(
                  value: 'passage',
                  label: l.reading,
                  enabled:
                      result.book?.available == true ||
                      result.book?.status == 'unverified',
                ),
                if (result.book?.available != true)
                  BusyBooksPopupMenuItem(value: 'locate', label: l.locateBook),
              ]
            : null,
        onMenuSelected: result is AnnotationSearchResult
            ? (action) async {
                // Menu actions capture the same record; no row-index redirection.
                final search = ref.read(bookSearchSessionProvider.notifier);
                if (!await search.validateResult(result, widget.generation) ||
                    !context.mounted) {
                  return;
                }
                if (action == 'locate') {
                  await locateBook(context, ref, result.annotation.bookId);
                  return;
                }
                await activateBookSearchResult(
                  context,
                  ref,
                  result,
                  widget.generation,
                  passage: action == 'passage',
                );
              }
            : null,
        onTap: enabled
            ? () {
                ref.read(bookSearchSessionProvider.notifier).select(index);
                unawaited(
                  activateBookSearchResult(
                    context,
                    ref,
                    result,
                    widget.generation,
                  ),
                );
              }
            : null,
      );
      final group =
          widget.groupActions &&
          result is BookActionSearchResult &&
          (index == 0 ||
              (widget.results[index - 1] as BookActionSearchResult).category !=
                  result.category);
      return group
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: BusyBooksInsets.sectionLabel,
                  child: Text(
                    result.category,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                row,
              ],
            )
          : row;
    },
  );
}

class _HighlightedSearchText extends StatelessWidget {
  const _HighlightedSearchText(this.text, {required this.query, this.style});
  final String text, query;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return Text(text, style: style);
    final spans = <TextSpan>[];
    var end = 0;
    for (final m in RegExp(
      RegExp.escape(query),
      caseSensitive: false,
      unicode: true,
    ).allMatches(text)) {
      spans.add(TextSpan(text: text.substring(end, m.start)));
      spans.add(
        TextSpan(
          text: text.substring(m.start, m.end),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      end = m.end;
    }
    spans.add(TextSpan(text: text.substring(end)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

/// Retains browsing widgets, scroll positions and focus state while search is open.
class BookSearchSidebarHost extends ConsumerWidget {
  const BookSearchSidebarHost({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(bookSearchSessionProvider.select((s) => s.active));
    ref.listen(
      bookSearchSessionProvider.select((s) => s.active),
      (_, _) => Tooltip.dismissAllToolTips(),
    );
    return TooltipTheme(
      data: TooltipTheme.of(context).copyWith(
        constraints: BusyBooksTooltipStyle.constraints.copyWith(
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
          if (active) const BookSearchSidebar(),
        ],
      ),
    );
  }
}
