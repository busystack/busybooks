import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../annotations/presentation/annotation_actions.dart' as actions;
import '../../annotations/presentation/annotation_presentation.dart';
import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/busybooks_search_field.dart';
import '../../app/localization.dart';
import '../../app/product_actions.dart';
import '../../library/data/record_validation.dart';
import '../../library/domain/annotation_limits.dart';
import '../../library/domain/book.dart';
import '../../workspace/workspace_controller.dart';
import '../application/notebook_controller.dart';
import 'book_view_selector.dart';
import 'region_preview.dart';

class NotebookItem extends ConsumerStatefulWidget {
  const NotebookItem({
    super.key,
    required this.annotation,
    required this.selected,
    required this.onSelect,
    required this.active,
    required this.focusRequest,
    this.focusOnActivate = true,
    this.onFocus,
  });
  final ReadingAnnotation annotation;
  final bool selected, active, focusOnActivate;
  final int focusRequest;
  final VoidCallback onSelect;
  final VoidCallback? onFocus;
  @override
  ConsumerState<NotebookItem> createState() => _NotebookItemState();
}

class _NotebookItemState extends ConsumerState<NotebookItem> {
  late final TextEditingController _note;
  final _focus = FocusNode(debugLabel: 'Private note');
  bool _expanded = false, _invalidInput = false;
  @override
  void initState() {
    super.initState();
    _note = TextEditingController(
      text: ref
          .read(notebookControllerProvider)
          .effectiveNote(widget.annotation),
    );
    _requestFocus(activation: true);
  }

  void _requestFocus({bool restoring = false, bool activation = false}) {
    if (activation && !widget.focusOnActivate) return;
    if (widget.selected && widget.active && widget.focusRequest > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.selected &&
            widget.active &&
            (!activation || widget.focusOnActivate) &&
            widget.focusRequest > 0 &&
            !(restoring &&
                FocusManager.instance.primaryFocus
                    is BusyBooksSearchFocusNode)) {
          widget.onFocus?.call();
          _focus.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant NotebookItem old) {
    super.didUpdateWidget(old);
    final text = ref
        .read(notebookControllerProvider)
        .effectiveNote(widget.annotation);
    if (_note.text != text) {
      _note.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    if (!old.selected && widget.selected ||
        widget.focusRequest != old.focusRequest ||
        !old.active && widget.active) {
      _requestFocus(
        restoring: old.selected && widget.focusRequest == old.focusRequest,
        activation:
            !old.active &&
            widget.active &&
            widget.focusRequest == old.focusRequest,
      );
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      notebookControllerProvider.select(
        (s) => (
          s.drafts[widget.annotation.id],
          s.saving.contains(widget.annotation.id),
          s.resolving.contains(widget.annotation.id),
        ),
      ),
    );
    final notes = ref.read(notebookControllerProvider),
        a = widget.annotation,
        l = context.l10n,
        draft = notes.drafts[a.id],
        controller = ref.read(notebookControllerProvider.notifier),
        note = notes.effectiveNote(a),
        resolving = notes.resolving.contains(a.id);
    final locale = Localizations.localeOf(context).toString();
    return BusyBooksGroupedSurface(
      focused: widget.selected,
      child: Padding(
        padding: const EdgeInsets.all(BusyBooksSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  a.kind == 'bookmark'
                      ? BusyBooksGlyphs.bookmark
                      : BusyBooksGlyphs.annotations,
                ),
                const SizedBox(width: BusyBooksSpacing.sm),
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: widget.selected,
                    child: InkWell(
                      key: ValueKey('notebook-select-${a.id}'),
                      onTap: widget.onSelect,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${annotationTypeLabel(context, a.kind)} · ${annotationReference(context, a, book: ref.read(workspaceControllerProvider).bookById(a.bookId))}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            annotationCreationTime(a) == null
                                ? l.dateUnavailable
                                : DateFormat.yMMMd(
                                    locale,
                                  ).add_jm().format(annotationCreationTime(a)!),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
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
                    const PopupMenuDivider(),
                    BusyBooksPopupMenuItem(value: 'remove', label: l.delete),
                  ],
                  onSelected: (action) => runAppAction(context, () async {
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
                        annotationId: a.id,
                      );
                      return;
                    }
                    if (action == 'remove') {
                      await actions.deleteAnnotation(context, ref, a);
                      return;
                    }
                    await ref
                        .read(workspaceControllerProvider.notifier)
                        .updateAnnotation(a.id, {
                          'color': action,
                        }, bookId: a.bookId);
                  }),
                ),
              ],
            ),
            if (a.kind == 'region')
              NotebookRegionPreview(annotation: a, active: widget.active),
            if (a.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: BusyBooksSpacing.md,
                ),
                child: Semantics(
                  label: l.savedPassage,
                  child: SelectableText(
                    contextMenuBuilder: busyBooksTextContextMenu,
                    a.text,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            const SizedBox(height: BusyBooksSpacing.sm),
            if (_invalidInput) BusyBooksBanner(title: l.noteInputLimit),
            if (widget.selected) ...[
              BusyBooksGroupedTextEntry(
                key: ValueKey('notebook-note-${a.id}'),
                label: l.privateNote,
                controller: _note,
                focusNode: _focus,
                inputFormatters: [
                  TextInputFormatter.withFunction((old, value) {
                    final invalid = !validAnnotationText(value.text);
                    if (invalid != _invalidInput) {
                      setState(() => _invalidInput = invalid);
                    }
                    return invalid ? old : value;
                  }),
                ],
                minLines: 4,
                maxLines: 16,
                onChanged: (text) => controller.edit(a, text),
              ),
              Wrap(
                spacing: BusyBooksSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      draft?.error != null
                          ? l.noteSaveFailed
                          : draft != null || notes.saving.contains(a.id)
                          ? l.savingNote
                          : l.saved,
                    ),
                  ),
                  if (draft?.error != null)
                    TextButton(
                      onPressed: resolving
                          ? null
                          : () async {
                              try {
                                await controller.save(a.id);
                              } catch (_) {}
                            },
                      child: Text(l.retry),
                    ),
                  if (draft != null)
                    TextButton(
                      onPressed: resolving
                          ? null
                          : () => runAppAction(
                              context,
                              () => controller.discard(
                                a.id,
                                confirm: () => confirm(
                                  context,
                                  l.discard,
                                  l.discardNoteHelp,
                                  acceptLabel: l.discard,
                                ),
                              ),
                            ),
                      child: Text(l.discard),
                    ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.privateNote,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onSelect,
                    child: Text(note.isEmpty ? l.addNote : l.editNote),
                  ),
                ],
              ),
              if (note.isNotEmpty)
                GestureDetector(
                  onDoubleTap: widget.onSelect,
                  child: SelectableText(
                    contextMenuBuilder: busyBooksTextContextMenu,
                    _expanded ? note : _preview(note),
                  ),
                ),
              if (note.length > 600 || '\n'.allMatches(note).length > 4)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? l.showLess : l.showFullNote),
                  ),
                ),
              if (draft?.error != null) Text(l.noteSaveFailed),
            ],
          ],
        ),
      ),
    );
  }

  String _preview(String text) {
    var end = text.length < 600 ? text.length : 600;
    var start = 0;
    for (var line = 0; line < 5; line++) {
      final next = text.indexOf('\n', start);
      if (next < 0 || next >= end) break;
      if (line == 4) {
        end = next;
        break;
      }
      start = next + 1;
    }
    if (end > 0 &&
        text.codeUnitAt(end - 1) >= 0xd800 &&
        text.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    return text.substring(0, end);
  }
}
