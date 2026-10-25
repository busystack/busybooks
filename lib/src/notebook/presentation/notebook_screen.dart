import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../annotations/domain/annotation_filter.dart';
import '../../annotations/presentation/annotation_presentation.dart';
import '../../app/busybooks_design.dart';
import '../../app/localization.dart';
import '../../app/product_actions.dart';
import '../../library/domain/book.dart';
import '../../workspace/workspace_controller.dart';
import '../application/notebook_controller.dart';
import '../application/notebook_view.dart';
import 'notebook_item.dart';

String notebookSortLabel(BuildContext context, NotebookSort sort) =>
    switch (sort) {
      NotebookSort.recentlyAdded => context.l10n.recentlyAdded,
      NotebookSort.bookOrder => context.l10n.bookOrder,
      NotebookSort.type => context.l10n.type,
    };

class NotebookContent extends ConsumerStatefulWidget {
  const NotebookContent({super.key, required this.id, required this.active});
  final String id;
  final bool active;
  @override
  ConsumerState<NotebookContent> createState() => _NotebookContentState();
}

class _NotebookContentState extends ConsumerState<NotebookContent> {
  late final ScrollController _scroll;
  final _centerKey = GlobalKey();
  final _listFocus = FocusNode(debugLabel: 'Notebook items');
  int _revealed = -1, _layout = 0;
  String? _unavailable;
  NotebookController get controller =>
      ref.read(notebookControllerProvider.notifier);
  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(
      initialScrollOffset: ref
          .read(notebookControllerProvider)
          .view(widget.id)
          .scroll,
      keepScrollOffset: false,
    )..addListener(_saveScroll);
  }

  void _saveScroll() => controller.view(widget.id, scroll: _scroll.offset);
  @override
  void dispose() {
    _scroll.removeListener(_saveScroll);
    _scroll.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      notebookControllerProvider.select((s) {
        final view = s.view(widget.id);
        return (
          view.filter,
          view.sort,
          view.withNotes,
          view.selected,
          view.revealRequest,
          view.revealAnnotation,
          view.editFocusRequest,
          view.editFocused,
          view.scrollCenter,
          s.drafts,
          s.sources,
        );
      }),
    );
    final data = ref.watch(workspaceControllerProvider),
        notes = ref.read(notebookControllerProvider),
        view = notes.view(widget.id),
        l = context.l10n,
        book = data.bookById(widget.id);
    final source = notes.annotationsFor(widget.id, data.annotations);
    final bareBookmarks = source
        .where(
          (a) => a.kind == 'bookmark' && notes.effectiveNote(a).trim().isEmpty,
        )
        .length;
    final items =
        source
            .where(
              (a) =>
                  view.filter.includes(a) &&
                  (!view.withNotes ||
                      notes.effectiveNote(a).trim().isNotEmpty) &&
                  (view.filter != AnnotationTypeFilter.all ||
                      a.kind != 'bookmark' ||
                      notes.effectiveNote(a).trim().isNotEmpty),
            )
            .toList()
          ..sort((a, b) => compareNotebookAnnotations(a, b, view.sort));
    var center = items.indexWhere((a) => a.id == view.scrollCenter);
    if (center < 0) center = 0;
    if (view.revealRequest != _revealed &&
        view.revealAnnotation != null &&
        widget.active) {
      _revealed = view.revealRequest;
      _layout++;
      final request = view.revealRequest;
      final found = items.any((a) => a.id == view.revealAnnotation);
      _unavailable = found ? null : l.noteItemUnavailable;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            ref
                    .read(notebookControllerProvider)
                    .view(widget.id)
                    .revealRequest !=
                request) {
          return;
        }
        if (_scroll.hasClients && found) _scroll.jumpTo(0);
        controller.acknowledgeReveal(widget.id, request);
      });
    }
    final locale = Localizations.localeOf(context).toString();
    String group(ReadingAnnotation a) => switch (view.sort) {
      NotebookSort.recentlyAdded =>
        annotationCreationTime(a) == null
            ? l.dateUnavailable
            : DateFormat.yMMMMd(locale).format(annotationCreationTime(a)!),
      NotebookSort.bookOrder => annotationReference(
        context,
        a,
        book: book,
      ).split(' · ').first,
      NotebookSort.type => annotationTypeLabel(context, a.kind),
    };
    final indices = {for (var i = 0; i < items.length; i++) items[i].id: i};
    Widget item(int index) {
      final a = items[index];
      return BusyBooksClamp(
        key: ValueKey(a.id),
        maxWidth: BusyBooksSizes.contentWidth,
        scrollable: false,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: BusyBooksSpacing.lg,
          vertical: BusyBooksSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (index == 0 || group(items[index - 1]) != group(a))
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: BusyBooksSpacing.md,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    group(a),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            NotebookItem(
              key: ValueKey('notebook-item-${a.id}'),
              annotation: a,
              selected: view.selected == a.id,
              active: widget.active,
              focusRequest: view.editFocused ? view.editFocusRequest : 0,
              onSelect: () =>
                  controller.view(widget.id, selected: a.id, focusEditor: true),
            ),
          ],
        ),
      );
    }

    return Focus(
      focusNode: _listFocus,
      autofocus: widget.active,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            view.editFocused) {
          controller.view(widget.id, focusEditor: false);
          _listFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (event is! KeyDownEvent ||
            FocusManager.instance.primaryFocus?.context
                    ?.findAncestorWidgetOfExactType<EditableText>() !=
                null) {
          return KeyEventResult.ignored;
        }
        if (items.isEmpty) return KeyEventResult.ignored;
        final selected = items.indexWhere((a) => a.id == view.selected);
        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
            event.logicalKey == LogicalKeyboardKey.arrowUp) {
          final index =
              (selected +
                      (event.logicalKey == LogicalKeyboardKey.arrowDown
                          ? 1
                          : -1))
                  .clamp(0, items.length - 1);
          controller.revealAnnotation(
            widget.id,
            items[index].id,
            focusEditor: false,
          );
          _listFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter && selected >= 0) {
          controller.view(
            widget.id,
            selected: items[selected].id,
            focusEditor: true,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ColoredBox(
        color: BusyBooksSurfaceColors.of(context).view,
        child: Column(
          children: [
            if (book != null && !book.available)
              BusyBooksBanner(
                title: l.missingBookNotebook,
                actionLabel: l.locateBook,
                onAction: () => locateBook(context, ref, book.id),
              ),
            if (_unavailable != null)
              BusyBooksBanner(
                title: _unavailable!,
                actionLabel: l.close,
                onAction: () => setState(() => _unavailable = null),
              ),
            Padding(
              padding: const EdgeInsets.all(BusyBooksSpacing.md),
              child: Wrap(
                spacing: BusyBooksSpacing.sm,
                runSpacing: BusyBooksSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  BusyBooksPopupSelector<NotebookSort>(
                    value: view.sort,
                    label: notebookSortLabel(context, view.sort),
                    tooltip: l.sortBy,
                    options: [
                      for (final sort in NotebookSort.values)
                        BusyBooksPopupSelectorOption(
                          value: sort,
                          label: notebookSortLabel(context, sort),
                        ),
                    ],
                    onSelected: (sort) {
                      controller.view(widget.id, sort: sort);
                      _resetScroll();
                    },
                  ),
                  BusyBooksPopupSelector<AnnotationTypeFilter>(
                    value: view.filter,
                    label: annotationFilterLabel(context, view.filter),
                    tooltip: l.type,
                    options: [
                      for (final filter in AnnotationTypeFilter.values)
                        BusyBooksPopupSelectorOption(
                          value: filter,
                          label: annotationFilterLabel(context, filter),
                        ),
                    ],
                    onSelected: (filter) {
                      controller.view(widget.id, filter: filter);
                      _resetScroll();
                    },
                  ),
                  BusyBooksPopupSelector<bool>(
                    value: view.withNotes,
                    label: view.withNotes ? l.withNotes : l.anyNotes,
                    tooltip: l.privateNote,
                    options: [
                      BusyBooksPopupSelectorOption(
                        value: false,
                        label: l.anyNotes,
                      ),
                      BusyBooksPopupSelectorOption(
                        value: true,
                        label: l.withNotes,
                      ),
                    ],
                    onSelected: (value) {
                      controller.view(widget.id, withNotes: value);
                      _resetScroll();
                    },
                  ),
                  if (bareBookmarks > 0 &&
                      view.filter == AnnotationTypeFilter.all)
                    TextButton(
                      onPressed: () {
                        controller.view(
                          widget.id,
                          filter: AnnotationTypeFilter.bookmarks,
                        );
                        _resetScroll();
                      },
                      child: Text(l.bareBookmarks(bareBookmarks)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(BusyBooksSpacing.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              source.isEmpty
                                  ? l.noAnnotations
                                  : l.noNotebookResults,
                            ),
                            if (source.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  controller.view(
                                    widget.id,
                                    filter: AnnotationTypeFilter.all,
                                    withNotes: false,
                                  );
                                  _resetScroll();
                                },
                                child: Text(l.clearFilters),
                              ),
                          ],
                        ),
                      ),
                    )
                  : CustomScrollView(
                      key: ValueKey(_layout),
                      controller: _scroll,
                      center: _centerKey,
                      anchor: center == 0 ? 0 : .15,
                      slivers: [
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => item(center - 1 - index),
                            childCount: center,
                            findChildIndexCallback: (key) {
                              final index =
                                  indices[(key as ValueKey<String>).value];
                              return index != null && index < center
                                  ? center - 1 - index
                                  : null;
                            },
                          ),
                        ),
                        SliverList(
                          key: _centerKey,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => item(center + index),
                            childCount: items.length - center,
                            findChildIndexCallback: (key) {
                              final index =
                                  indices[(key as ValueKey<String>).value];
                              return index != null && index >= center
                                  ? index - center
                                  : null;
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetScroll() {
    _layout++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }
}
