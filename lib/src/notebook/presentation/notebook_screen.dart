import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../annotations/domain/annotation_order.dart';
import '../../annotations/presentation/annotation_presentation.dart';
import '../../app/busybooks_design.dart';
import '../../app/command_registry.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/busybooks_main_menu.dart';
import '../../app/busybooks_search_field.dart';
import '../../app/localization.dart';
import '../../app/linux/linux_page_frame.dart';
import '../../app/linux/linux_header_style.dart';
import '../../app/product_actions.dart';
import '../../library/domain/book.dart';
import '../../library/data/record_validation.dart';
import '../../workspace/workspace_controller.dart';
import '../application/notebook_controller.dart';
import 'book_view_selector.dart';

String? _sectionKey(ReadingAnnotation a) {
  if (a.anchor['page'] is int) return 'page:${a.anchor['page']}';
  if (a.anchor['index'] is int) return 'section:${a.anchor['index']}';
  final match = RegExp(
    r'^epubcfi\(/6/(\d+)',
  ).firstMatch(a.anchor['cfi']?.toString() ?? '');
  return match == null ? null : 'spine:${match[1]}';
}

class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  late final TextEditingController _query;
  late final ScrollController _scroll;
  final _revealKey = GlobalKey();
  final _builtForReveal = <int>{};
  int _revealRequest = -1, _revealPass = 0, _seekingRequest = -1;
  double? _revealLow, _revealHigh;
  void _revealItem(int index, int count, NotebookViewState view) {
    if (_revealRequest == view.revealRequest || view.revealRequest == 0) return;
    if (_seekingRequest != view.revealRequest) {
      _seekingRequest = view.revealRequest;
      _revealPass = 0;
      _revealLow = null;
      _revealHigh = null;
      _builtForReveal.clear();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          ref.read(notebookControllerProvider).view(widget.id).revealRequest !=
              view.revealRequest) {
        return;
      }
      final target = _revealKey.currentContext;
      if (target != null) {
        _revealRequest = view.revealRequest;
        unawaited(Scrollable.ensureVisible(target, alignment: .25));
        controller.acknowledgeReveal(widget.id, view.revealRequest);
        return;
      }
      if (!_scroll.hasClients || _revealPass++ >= 24) {
        _revealRequest = view.revealRequest;
        return;
      }
      final position = _scroll.position;
      if (_builtForReveal.isNotEmpty) {
        final minimum = _builtForReveal.reduce((a, b) => a < b ? a : b),
            maximum = _builtForReveal.reduce((a, b) => a > b ? a : b);
        if (index > maximum) _revealLow = position.pixels;
        if (index < minimum) _revealHigh = position.pixels;
      }
      final low = (_revealLow ?? 0).clamp(0.0, position.maxScrollExtent),
          high = (_revealHigh ?? position.maxScrollExtent).clamp(
            low,
            position.maxScrollExtent,
          );
      final estimated = _revealPass == 1
          ? position.maxScrollExtent * index / (count > 1 ? count - 1 : 1)
          : (low + high) / 2;
      _builtForReveal.clear();
      _scroll.jumpTo(estimated.clamp(0.0, position.maxScrollExtent));
      if (mounted) setState(() {});
    });
  }

  NotebookController get controller =>
      ref.read(notebookControllerProvider.notifier);
  @override
  void initState() {
    super.initState();
    final view = ref.read(notebookControllerProvider).view(widget.id);
    _query = TextEditingController(text: view.query);
    _scroll = ScrollController(initialScrollOffset: view.scroll)
      ..addListener(_saveScroll);
    Future.microtask(() async {
      try {
        await ref
            .read(workspaceControllerProvider.notifier)
            .loadBook(widget.id);
      } catch (e) {
        if (mounted) await showError(context, e);
      }
    });
  }

  void _saveScroll() => controller.view(widget.id, scroll: _scroll.offset);
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
        notebook = ref.watch(notebookControllerProvider),
        view = notebook.view(widget.id),
        l = context.l10n;
    final book = data.bookById(widget.id);
    final showViewSelector = book != null && !view.searchVisible;
    final sourceItems = notebook.annotationsFor(widget.id, data.annotations);
    final items = sourceItems.where((a) {
      if (a.bookId != widget.id ||
          view.filter != 'all' && a.kind != view.filter) {
        return false;
      }
      final note = notebook.effectiveNote(a);
      return (!view.withNotes || note.trim().isNotEmpty) &&
          '${a.text}\n$note'.toLowerCase().contains(view.query.toLowerCase());
    }).toList()..sort((a, b) => compareAnnotationLocations(a.data, b.data));
    final target = items.indexWhere((a) => a.id == view.revealAnnotation);
    if (target >= 0) _revealItem(target, items.length, view);
    return Scaffold(
      body: LinuxPageFrame(
        sidebarAvailable: false,
        sidebarExpanded: false,
        header: BusyBooksLinuxHeaderLayout(
          leading: BusyBooksHeaderIconButton(
            key: const ValueKey('notebook-home'),
            tooltip: l.welcome,
            icon: BusyBooksGlyphs.home,
            onPressed: () async {
              final registry = BusyBooksCommandRegistryScope.maybeOf(context);
              await (registry?[BusyBooksCommandIds.welcome]?.execute != null
                  ? registry!.execute(BusyBooksCommandIds.welcome)
                  : closeWorkspace(context, ref));
            },
          ),
          centerAllocation: view.searchVisible
              ? BusyBooksLinuxHeaderCenterAllocation.fillBetweenControls
              : BusyBooksLinuxHeaderCenterAllocation.centeredBetweenControls,
          title: view.searchVisible
              ? BusyBooksSearchField(
                  controller: _query,
                  hintText: l.searchNotebook,
                  focusRequest: view.focusRequest,
                  autofocus: true,
                  onChanged: (v) => controller.view(widget.id, query: v),
                  onEscape: () =>
                      controller.view(widget.id, searchVisible: false),
                )
              : BusyBooksLinuxHeaderTitle(
                  '${book?.title ?? l.book} · ${l.notebook}',
                ),
          trailing: BusyBooksLinuxHeaderControlGroup(
            children: [
              if (showViewSelector)
                BookViewSelector(id: widget.id, view: BookView.notebook),
              BusyBooksHeaderIconButton(
                tooltip: l.searchNotebook,
                icon: BusyBooksGlyphs.search,
                selected: view.searchVisible,
                shortcut: BusyBooksCommandRegistryScope.maybeOf(
                  context,
                )?[BusyBooksCommandIds.search]?.shortcut?.label,
                onPressed: () {
                  final registry = BusyBooksCommandRegistryScope.maybeOf(
                    context,
                  );
                  if (registry?[BusyBooksCommandIds.search]?.execute != null) {
                    registry!.execute(BusyBooksCommandIds.search);
                  } else {
                    controller.view(
                      widget.id,
                      searchVisible: !view.searchVisible,
                      focus: true,
                    );
                  }
                },
              ),
              BusyBooksMainMenuButton(
                bookViewSelectorVisible: showViewSelector,
              ),
            ],
          ),
        ),
        body: Semantics(
          label: l.notebook,
          container: true,
          child: ColoredBox(
            color: BusyBooksSurfaceColors.of(context).view,
            child: Column(
              children: [
                if (data.loading) ...[
                  LinearProgressIndicator(
                    value: (data.progress['total'] as int? ?? 0) > 0
                        ? (data.progress['done'] as int) /
                              (data.progress['total'] as int)
                        : null,
                  ),
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
                if (book != null && !book.available)
                  BusyBooksBanner(
                    title: l.missingBookNotebook,
                    actionLabel: l.locateBook,
                    onAction: () => locateBook(context, ref, book.id),
                  ),
                Padding(
                  padding: const EdgeInsets.all(BusyBooksSpacing.md),
                  child: Row(
                    children: [
                      for (final filter in [
                        ('all', l.allItems),
                        ('highlight', l.highlights),
                        ('bookmark', l.bookmarks),
                      ])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: BusyBooksPushButton.standard(
                            onPressed: () =>
                                controller.view(widget.id, filter: filter.$1),
                            child: Semantics(
                              selected: view.filter == filter.$1,
                              child: Text(
                                '${view.filter == filter.$1 ? '✓ ' : ''}${filter.$2}',
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 12),
                      Checkbox(
                        value: view.withNotes,
                        onChanged: (v) =>
                            controller.view(widget.id, withNotes: v),
                      ),
                      Flexible(child: Text(l.withNotes)),
                    ],
                  ),
                ),
                if (view.searchVisible)
                  Padding(
                    padding: BusyBooksInsets.sectionLabel,
                    child: Text(l.notebookSearchScope),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? Center(child: Text(l.notebookEmpty))
                      : ListView.builder(
                          controller: _scroll,
                          itemCount: items.length,
                          itemBuilder: (c, i) {
                            _builtForReveal.add(i);
                            final a = items[i];
                            final card = BusyBooksClamp(
                              maxWidth: 1000,
                              scrollable: false,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 10,
                                ),
                                child: _NotebookItem(
                                  key: ValueKey(a.id),
                                  annotation: a,
                                  selected: view.selected == a.id,
                                  onSelect: () => controller.view(
                                    widget.id,
                                    selected: a.id,
                                  ),
                                ),
                              ),
                            );
                            final section = _sectionKey(a);
                            final heading =
                                section != null &&
                                (i == 0 ||
                                    _sectionKey(items[i - 1]) != section);
                            return Column(
                              key: a.id == view.revealAnnotation
                                  ? _revealKey
                                  : null,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (heading)
                                  BusyBooksClamp(
                                    scrollable: false,
                                    maxWidth: 1000,
                                    child: Semantics(
                                      header: true,
                                      child: Text(
                                        annotationReference(
                                          c,
                                          a,
                                          book: book,
                                        ).split(' · ').first,
                                        style: Theme.of(
                                          c,
                                        ).textTheme.titleMedium,
                                      ),
                                    ),
                                  ),
                                card,
                              ],
                            );
                          },
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

class _NotebookItem extends ConsumerStatefulWidget {
  const _NotebookItem({
    super.key,
    required this.annotation,
    required this.selected,
    required this.onSelect,
  });
  final ReadingAnnotation annotation;
  final bool selected;
  final VoidCallback onSelect;
  @override
  ConsumerState<_NotebookItem> createState() => _NotebookItemState();
}

class _NotebookItemState extends ConsumerState<_NotebookItem> {
  late final TextEditingController _note;
  @override
  void initState() {
    super.initState();
    _note = TextEditingController(
      text: ref
          .read(notebookControllerProvider)
          .effectiveNote(widget.annotation),
    );
  }

  @override
  void didUpdateWidget(covariant _NotebookItem old) {
    super.didUpdateWidget(old);
    final value = ref
        .read(notebookControllerProvider)
        .effectiveNote(widget.annotation);
    if (_note.text != value) _note.text = value;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notebookControllerProvider);
    final a = widget.annotation,
        l = context.l10n,
        draft = notes.drafts[a.id],
        resolving = notes.resolving.contains(a.id),
        controller = ref.read(notebookControllerProvider.notifier);
    return BusyBooksGroupedSurface(
      focused: widget.selected,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  a.kind == 'highlight'
                      ? BusyBooksGlyphs.edit
                      : BusyBooksGlyphs.bookmark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${a.kind == 'highlight' ? l.highlight : l.bookmark} · ${annotationReference(context, a, book: ref.read(workspaceControllerProvider).bookById(a.bookId))}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                BusyBooksHeaderPopupMenuButton<String>(
                  tooltip: l.annotationActions,
                  icon: BusyBooksGlyphs.menuVertical,
                  itemBuilder: (_) => [
                    BusyBooksPopupMenuItem(
                      value: 'jump',
                      label: l.showInReading,
                    ),
                    BusyBooksPopupMenuItem(value: 'edit', label: l.editNote),
                    if (a.kind == 'highlight')
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
                    BusyBooksPopupMenuItem(value: 'remove', label: l.delete),
                  ],
                  onSelected: (action) async {
                    try {
                      if (action == 'edit') {
                        widget.onSelect();
                        return;
                      }
                      if (action == 'jump') {
                        await openReading(
                          context,
                          ref,
                          a.bookId,
                          anchor: a.anchor,
                        );
                        return;
                      }
                      if (action == 'remove') {
                        if (await confirm(
                          context,
                          l.delete,
                          l.removeAnnotationHelp,
                          destructive: true,
                        )) {
                          await ref
                              .read(workspaceControllerProvider.notifier)
                              .deleteAnnotation(a.id);
                        }
                      } else {
                        await ref
                            .read(workspaceControllerProvider.notifier)
                            .updateAnnotation(a.id, {
                              'color': action,
                            }, bookId: a.bookId);
                      }
                    } catch (e) {
                      if (context.mounted) await showError(context, e);
                    }
                  },
                ),
              ],
            ),
            if (a.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(
                  label: l.savedPassage,
                  child: SelectableText(
                    a.text,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (widget.selected) ...[
              BusyBooksGroupedTextEntry(
                label: l.privateNote,
                controller: _note,
                minLines: 4,
                maxLines: 16,
                onChanged: (v) => controller.edit(a, v),
              ),
              Row(
                children: [
                  BusyBooksDialogButton(
                    label: l.save,
                    onPressed: resolving
                        ? null
                        : () async {
                            try {
                              await controller.save(a.id);
                            } catch (_) {}
                          },
                  ),
                  if (draft != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        draft.error == null
                            ? l.unsavedNote
                            : draft.actionFailed
                            ? l.noteActionFailed
                            : l.noteSaveFailed,
                      ),
                    ),
                    BusyBooksDialogButton(
                      label: l.discard,
                      onPressed: resolving
                          ? null
                          : () async {
                              try {
                                await controller.discard(
                                  a.id,
                                  confirm: () => confirm(
                                    context,
                                    l.discard,
                                    l.discardNoteHelp,
                                    acceptLabel: l.discard,
                                  ),
                                );
                              } catch (error) {
                                if (context.mounted) {
                                  await showError(context, error);
                                }
                              }
                            },
                    ),
                  ],
                ],
              ),
              if (draft?.error != null) SelectableText(draft!.error!),
            ] else
              BusyBooksActionRow(
                title: l.privateNote,
                subtitle: (draft?.text ?? a.note).isEmpty
                    ? l.addNote
                    : draft?.text ?? a.note,
                onTap: widget.onSelect,
              ),
          ],
        ),
      ),
    );
  }
}
