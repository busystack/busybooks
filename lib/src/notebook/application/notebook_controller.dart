import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../annotations/domain/annotation_filter.dart';
import '../../library/domain/book.dart';
import '../../workspace/workspace_controller.dart';
import 'notebook_view.dart';

class NoteDraft {
  const NoteDraft(
    this.text,
    this.revision, {
    required this.baseline,
    this.creating = false,
    this.creationWritten = false,
    this.error,
    this.actionFailed = false,
  });
  final String text;
  final String? baseline;
  // Only an explicit captured creation may insert. Existing-note drafts always
  // use a conditional update, even when their book is not the active book.
  final bool creating;
  // A confirmation can hold a creation whose insertion has already finished.
  // Remember that commit so retries update it and failed discard can remove it.
  final bool creationWritten;
  final int revision;
  final String? error;
  final bool actionFailed;
}

class NotebookViewState {
  const NotebookViewState({
    this.filter = AnnotationTypeFilter.all,
    this.sort = NotebookSort.recentlyAdded,
    this.withNotes = false,
    this.selected,
    this.scroll = 0,
    this.scrollCenter,
    this.revealRequest = 0,
    this.editFocusRequest = 0,
    this.editFocused = false,
    this.revealAnnotation,
  });
  final AnnotationTypeFilter filter;
  final NotebookSort sort;
  final bool withNotes, editFocused;
  final String? selected, scrollCenter;
  final double scroll;
  final int revealRequest, editFocusRequest;
  final String? revealAnnotation;
}

class NotebookState {
  const NotebookState({
    this.views = const {},
    this.drafts = const {},
    this.sources = const {},
    this.resolving = const {},
    this.saving = const {},
  });
  final Map<String, NotebookViewState> views;
  final Map<String, NoteDraft> drafts;
  final Map<String, ReadingAnnotation> sources;
  final Set<String> resolving, saving;
  NotebookState copy({
    Map<String, NotebookViewState>? views,
    Map<String, NoteDraft>? drafts,
    Map<String, ReadingAnnotation>? sources,
    Set<String>? resolving,
    Set<String>? saving,
  }) => NotebookState(
    views: views ?? this.views,
    drafts: drafts ?? this.drafts,
    sources: sources ?? this.sources,
    resolving: resolving ?? this.resolving,
    saving: saving ?? this.saving,
  );
  NotebookViewState view(String id) => views[id] ?? const NotebookViewState();
  String effectiveNote(ReadingAnnotation annotation) =>
      drafts[annotation.id]?.text ?? annotation.note;
  ReadingAnnotation? findAnnotation(
    String bookId,
    String annotationId,
    Iterable<ReadingAnnotation> saved,
  ) {
    final stored = saved
        .where((a) => a.bookId == bookId && a.id == annotationId)
        .firstOrNull;
    if (stored != null) return stored;
    final source = sources[annotationId];
    return source?.bookId == bookId && drafts.containsKey(annotationId)
        ? source
        : null;
  }

  List<ReadingAnnotation> annotationsFor(
    String bookId,
    Iterable<ReadingAnnotation> saved,
  ) => [
    ...saved.where((a) => a.bookId == bookId),
    ...sources.values.where(
      (a) =>
          a.bookId == bookId &&
          drafts.containsKey(a.id) &&
          !saved.any((s) => s.id == a.id),
    ),
  ];
}

// Drafts outlive widgets, filters, books, and routes. Writes are serialized by
// the shared repository. A failed write never acknowledges/removes the draft.
class NotebookController extends Notifier<NotebookState> {
  final _timers = <String, Timer>{};
  final _saving = <String, Future<void>>{};
  final _baselines = <String, Future<ReadingAnnotation>>{};
  final _resolving = <String, Completer<void>>{};
  int _revision = 0;
  @override
  NotebookState build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
    });
    return const NotebookState();
  }

  void view(
    String id, {
    AnnotationTypeFilter? filter,
    NotebookSort? sort,
    bool? withNotes,
    String? selected,
    double? scroll,
    String? scrollCenter,
    String? revealAnnotation,
    bool clearReveal = false,
    bool? focusEditor,
  }) {
    final old = state.view(id);
    final reset =
        filter != null && filter != old.filter ||
        sort != null && sort != old.sort ||
        withNotes != null && withNotes != old.withNotes;
    state = state.copy(
      views: {
        ...state.views,
        id: NotebookViewState(
          filter: filter ?? old.filter,
          sort: sort ?? old.sort,
          withNotes: withNotes ?? old.withNotes,
          selected: selected ?? old.selected,
          scroll: scroll ?? (reset ? 0 : old.scroll),
          scrollCenter: scrollCenter ?? (reset ? null : old.scrollCenter),
          revealRequest: old.revealRequest + (revealAnnotation == null ? 0 : 1),
          editFocusRequest:
              old.editFocusRequest + (focusEditor == true ? 1 : 0),
          editFocused: focusEditor ?? old.editFocused,
          revealAnnotation: clearReveal
              ? null
              : revealAnnotation ?? old.revealAnnotation,
        ),
      },
    );
  }

  void acknowledgeReveal(String bookId, int request) {
    if (state.view(bookId).revealRequest == request) {
      view(bookId, clearReveal: true);
    }
  }

  void revealAnnotation(
    String bookId,
    String annotationId, {
    bool focusEditor = true,
  }) {
    final a = state.findAnnotation(
      bookId,
      annotationId,
      ref.read(workspaceControllerProvider).annotations,
    );
    view(
      bookId,
      selected: annotationId,
      filter: a?.kind == 'bookmark'
          ? AnnotationTypeFilter.bookmarks
          : AnnotationTypeFilter.all,
      withNotes: false,
      revealAnnotation: annotationId,
      scrollCenter: annotationId,
      scroll: 0,
      focusEditor: focusEditor,
    );
  }

  void edit(ReadingAnnotation annotation, String text) {
    final previous = state.drafts[annotation.id];
    state = state.copy(
      sources: {
        ...state.sources,
        annotation.id: state.sources[annotation.id] ?? annotation,
      },
      drafts: {
        ...state.drafts,
        annotation.id: NoteDraft(
          text,
          ++_revision,
          baseline: previous?.baseline,
          creating: previous?.creating ?? false,
          creationWritten: previous?.creationWritten ?? false,
        ),
      },
    );
    if (previous?.creating != true &&
        (previous == null || previous.baseline == null)) {
      _loadBaseline(annotation.id);
    }
    _schedule(annotation.id);
  }

  void create(ReadingAnnotation annotation, String text) {
    if (state.drafts.containsKey(annotation.id) ||
        state.sources.containsKey(annotation.id)) {
      throw StateError(
        'This passage already has a pending note. Edit that note instead.',
      );
    }
    state = state.copy(
      sources: {...state.sources, annotation.id: annotation},
      drafts: {
        ...state.drafts,
        annotation.id: NoteDraft(
          text,
          ++_revision,
          baseline: null,
          creating: true,
        ),
      },
    );
    _schedule(annotation.id);
  }

  Future<ReadingAnnotation> _loadBaseline(String id) {
    final pending = _baselines[id];
    if (pending != null) return pending;
    final source = state.sources[id]!;
    final lookup = ref
        .read(workspaceControllerProvider.notifier)
        .readAnnotation(id, bookId: source.bookId);
    _baselines[id] = lookup;
    unawaited(
      lookup.then<void>(
        (value) {
          if (!ref.mounted || !identical(_baselines[id], lookup)) return;
          final current = state.drafts[id];
          if (current == null || current.baseline != null) return;
          state = state.copy(
            sources: {...state.sources, id: value},
            drafts: {
              ...state.drafts,
              id: NoteDraft(
                current.text,
                current.revision,
                baseline: value.note,
                error: current.error,
                actionFailed: current.actionFailed,
              ),
            },
          );
        },
        onError: (Object error, StackTrace trace) {
          if (!ref.mounted || !identical(_baselines[id], lookup)) return;
          _baselines.remove(id);
          _failed(id, error);
        },
      ),
    );
    return lookup;
  }

  void _schedule(String id) {
    _timers.remove(id)?.cancel();
    if (_resolving.containsKey(id) || !state.drafts.containsKey(id)) return;
    _timers[id] = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(save(id).catchError((Object _) {})),
    );
  }

  void _remove(String id) {
    _baselines.remove(id);
    _timers.remove(id)?.cancel();
    state = state.copy(
      drafts: {...state.drafts}..remove(id),
      sources: {...state.sources}..remove(id),
    );
  }

  void _failed(String id, Object error, {bool actionFailed = false}) {
    final current = state.drafts[id];
    if (current == null) return;
    state = state.copy(
      drafts: {
        ...state.drafts,
        id: NoteDraft(
          current.text,
          current.revision,
          baseline: current.baseline,
          creating: current.creating,
          creationWritten: current.creationWritten,
          error: error.toString(),
          actionFailed: actionFailed,
        ),
      },
    );
  }

  Future<void> save(String id) async {
    final resolving = _resolving[id];
    if (resolving != null) {
      await resolving.future;
      return save(id);
    }
    final pending = _saving[id];
    if (pending != null) {
      await pending;
      if (state.drafts.containsKey(id)) return save(id);
      return;
    }
    final draft = state.drafts[id], source = state.sources[id];
    if (draft == null) return;
    if (!draft.creating && draft.baseline == null) {
      await _loadBaseline(id);
      return save(id);
    }
    _timers.remove(id)?.cancel();
    final operation = () async {
      try {
        if (source == null) {
          throw StateError(
            'The saved item is no longer available. The note draft is retained.',
          );
        }
        final workspace = ref.read(workspaceControllerProvider.notifier);
        if (draft.creating && !draft.creationWritten) {
          await workspace.saveAnnotation(source.copy({'note': draft.text}));
        } else {
          await workspace.updateAnnotation(id, {
            'note': draft.text,
          }, bookId: source.bookId);
        }
        final current = state.drafts[id];
        if (current != null) {
          if (!_resolving.containsKey(id) &&
              current.revision == draft.revision) {
            _remove(id);
          } else {
            state = state.copy(
              drafts: {
                ...state.drafts,
                id: NoteDraft(
                  current.text,
                  current.revision,
                  baseline: draft.text,
                  creating: current.creating && _resolving.containsKey(id),
                  creationWritten:
                      current.creating && _resolving.containsKey(id),
                  error: current.error,
                  actionFailed: current.actionFailed,
                ),
              },
            );
          }
        }
      } catch (error) {
        _failed(id, error);
        rethrow;
      }
    }();
    _saving[id] = operation;
    state = state.copy(saving: {...state.saving, id});
    try {
      await operation;
    } finally {
      if (identical(_saving[id], operation)) {
        _saving.remove(id);
        state = state.copy(saving: {...state.saving}..remove(id));
      }
    }
  }

  Future<void> _waitForResolution(String id) async {
    while (_resolving[id] != null) {
      await _resolving[id]!.future;
    }
  }

  Completer<void> _hold(String id) {
    _timers.remove(id)?.cancel();
    final hold = Completer<void>();
    _resolving[id] = hold;
    unawaited(hold.future.catchError((Object _) {}));
    state = state.copy(resolving: {...state.resolving, id});
    return hold;
  }

  void _release(String id, Completer<void> hold, {Object? failure}) {
    _resolving.remove(id);
    state = state.copy(resolving: {...state.resolving}..remove(id));
    final message = state.drafts[id]?.error;
    final error = failure ?? (message == null ? null : StateError(message));
    if (error == null) {
      hold.complete();
      _schedule(id);
    } else {
      hold.completeError(error);
    }
  }

  Future<void> _settleSave(String id) async {
    try {
      await _saving[id];
    } catch (_) {
      /* The actual draft/error remains. */
    }
  }

  Future<void> discard(
    String id, {
    required Future<bool> Function() confirm,
  }) async {
    if (_resolving.containsKey(id)) {
      throw StateError(
        'A note action is already in progress. Try again when it finishes.',
      );
    }
    final target = state.drafts[id], source = state.sources[id];
    if (target == null || source == null) return;
    if (target.creating) {
      // The hold starts before confirmation and settles any insertion. Only
      // this explicit creation can be removed; later edits keep their intent.
      return ref
          .read(workspaceControllerProvider.notifier)
          .deleteAnnotation(
            id,
            confirm: confirm,
            discardedCreationRevision: target.revision,
          );
    }
    // Capture the edit and its baseline before displaying the confirmation.
    final hold = _hold(id);
    final baselineLookup = target.baseline == null ? _loadBaseline(id) : null;
    String? baseline = target.baseline;
    Object? failure;
    try {
      final accepted = await confirm();
      await _settleSave(id);
      if (!accepted) return;
      baseline ??= (await baselineLookup!).note;
      await ref.read(workspaceControllerProvider.notifier).updateAnnotation(
        id,
        {'note': baseline},
        bookId: source.bookId,
      );
      final current = state.drafts[id];
      if (current?.revision == target.revision) {
        _remove(id);
      } else if (current != null) {
        state = state.copy(
          drafts: {
            ...state.drafts,
            id: NoteDraft(current.text, current.revision, baseline: baseline),
          },
        );
      }
    } catch (error) {
      failure = error;
      final current = state.drafts[id];
      if (current != null) {
        state = state.copy(
          drafts: {
            ...state.drafts,
            id: NoteDraft(
              current.text,
              current.revision,
              baseline: baseline,
              error: error.toString(),
              actionFailed: true,
            ),
          },
        );
      }
      rethrow;
    } finally {
      _release(id, hold, failure: failure);
    }
  }

  // WorkspaceController uses this outside its mutation queue, so an in-flight
  // note update can finish before the conditional deletion is queued.
  Future<void> delete(
    String id,
    Future<void> Function() remove, {
    Future<bool> Function()? confirm,
    int? discardedCreationRevision,
  }) async {
    if (_resolving.containsKey(id)) await _waitForResolution(id);
    final hold = _hold(id);
    Object? failure;
    try {
      final accepted = await (confirm?.call() ?? Future.value(true));
      await _settleSave(id);
      if (!accepted) return;
      await remove();
      final current = state.drafts[id];
      if (discardedCreationRevision != null &&
          current != null &&
          current.revision != discardedCreationRevision) {
        _baselines.remove(id);
        state = state.copy(
          drafts: {
            ...state.drafts,
            id: NoteDraft(
              current.text,
              current.revision,
              baseline: null,
              creating: true,
            ),
          },
        );
      } else {
        _remove(id);
      }
    } catch (error) {
      failure = error;
      _failed(id, error, actionFailed: true);
      rethrow;
    } finally {
      _release(id, hold, failure: failure);
    }
  }

  Future<void> flush() async {
    while (_resolving.isNotEmpty ||
        _saving.isNotEmpty ||
        state.drafts.isNotEmpty) {
      if (_resolving.isNotEmpty) {
        await Future.wait(
          _resolving.values.map((hold) => hold.future).toList(),
        );
      } else if (_saving.isNotEmpty) {
        await Future.wait(_saving.values.toList());
      } else {
        await save(state.drafts.keys.first);
      }
    }
  }
}

final notebookControllerProvider =
    NotifierProvider<NotebookController, NotebookState>(NotebookController.new);
