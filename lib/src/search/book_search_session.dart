import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_router.dart';
import '../app/command_registry.dart';
import '../book_workspace/application/book_sidebar_controller.dart';
import '../library/domain/book.dart';
import '../notebook/application/notebook_controller.dart';
import '../reading/application/reader_controller.dart';
import '../reading/domain/publication_outline.dart';
import '../workspace/workspace_controller.dart';

enum BookSearchCategory { bookText, notebook, bookmarks, chapters, actions }

sealed class BookSearchResult {
  const BookSearchResult();
  String get identity;
}

final class BookTextSearchResult extends BookSearchResult {
  const BookTextSearchResult(this.bookId, this.session, this.match);
  final String bookId, session;
  final Map<String, dynamic> match;
  Map<String, dynamic> get anchor =>
      (match['anchor'] as Map).cast<String, dynamic>();
  @override
  String get identity => '$bookId:$session:${jsonEncode(match['anchor'])}';
}

final class AnnotationSearchResult extends BookSearchResult {
  const AnnotationSearchResult(this.annotation, this.note);
  final ReadingAnnotation annotation;
  final String note;
  @override
  String get identity => annotation.id;
}

final class ChapterSearchResult extends BookSearchResult {
  const ChapterSearchResult(this.bookId, this.chapter);
  final String bookId;
  final PublicationOutlineNode chapter;
  @override
  String get identity => '$bookId:${chapter.id}';
}

final class BookActionSearchResult extends BookSearchResult {
  const BookActionSearchResult(this.command, this.title);
  final BusyBooksCommand command;
  final String title;
  @override
  String get identity => command.id;
}

/// The empty identity is the application's Actions session outside a book.
const applicationSearchId = '';

class BookSearchState {
  const BookSearchState({
    this.active = false,
    this.category = BookSearchCategory.notebook,
    this.query = '',
    this.results = const [],
    this.selected = -1,
    this.focusRequest = 0,
    this.generation = 0,
    this.loading = false,
    this.error,
    this.previousPanel,
    this.previousOpen = false,
    this.rendererSession,
    this.progress,
  });
  final bool active, loading, previousOpen;
  final BookSearchCategory category;
  final String query;
  final List<BookSearchResult> results;
  final int selected, focusRequest, generation;
  final String? error, rendererSession;
  final double? progress;
  final BookSidebarPanel? previousPanel;
  BookSearchState copy({
    bool? active,
    BookSearchCategory? category,
    String? query,
    List<BookSearchResult>? results,
    int? selected,
    int? focusRequest,
    int? generation,
    bool? loading,
    String? error,
    bool clearError = false,
    BookSidebarPanel? previousPanel,
    bool? previousOpen,
    String? rendererSession,
    double? progress,
  }) => BookSearchState(
    active: active ?? this.active,
    category: category ?? this.category,
    query: query ?? this.query,
    results: results ?? this.results,
    selected: selected ?? this.selected,
    focusRequest: focusRequest ?? this.focusRequest,
    generation: generation ?? this.generation,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
    previousPanel: previousPanel ?? this.previousPanel,
    previousOpen: previousOpen ?? this.previousOpen,
    rendererSession: rendererSession ?? this.rendererSession,
    progress: progress,
  );
}

/// One retained, book-scoped search session. Sidebar navigation is never changed
/// by search; its previous presentation is therefore restored without rebuilding
/// or trying to reconstruct tree/filter/scroll state when search closes.
class BookSearchController extends Notifier<BookSearchState> {
  BookSearchController(this.bookId);
  final String bookId;
  Timer? _timer;
  FocusNode? _returnFocus;
  String? _originRoute;
  final _queries = <BookSearchCategory, String>{};
  final _selectedIdentities = <BookSearchCategory, String>{};
  List<BookActionSearchResult> _actions = const [];
  ({String session, int revision, int generation})? _nativeRequest;
  @override
  BookSearchState build() {
    final intents = ref
        .read(readerControllerProvider.notifier)
        .events
        .stream
        .listen((event) {
          if (event['type'] != 'searchSelection' ||
              event['bookId'] != bookId ||
              !ownsRoute) {
            return;
          }
          final reader = ref.read(readerControllerProvider.notifier);
          if (!reader.interactive ||
              reader.sessionId != event['session'] ||
              reader.presentationId != event['presentation']) {
            return;
          }
          _activate(
            category: BookSearchCategory.bookText,
            query: (event['text'] as String).trim(),
          );
        });
    ref.onDispose(() {
      _timer?.cancel();
      unawaited(intents.cancel());
    });
    ref.listen(readerControllerProvider, (previous, next) {
      if (!state.active || state.category != BookSearchCategory.bookText) {
        return;
      }
      final reader = ref.read(readerControllerProvider.notifier);
      if (next.bookId == bookId &&
          next.ready &&
          next.location['noText'] == true) {
        state = state.copy(
          category: BookSearchCategory.notebook,
          query: _queries[BookSearchCategory.notebook] ?? '',
        );
        _schedule();
        return;
      }
      final request = _nativeRequest;
      if (request != null &&
          request.session == reader.sessionId &&
          request.revision == reader.searchRevision &&
          request.generation == state.generation &&
          next.bookId == bookId &&
          next.query.trim() == state.query.trim()) {
        final results = [
          for (final match in next.matches)
            if (match['anchor'] is Map)
              BookTextSearchResult(bookId, request.session, match),
        ];
        final identity =
            _selectedIdentities[state.category] ?? selectedResult?.identity;
        state = state.copy(
          results: results,
          selected: _selection(results, identity),
          loading: next.searching,
          progress: next.searchProgress,
          error: next.searchStatus == 'error' ? 'text-search' : null,
          clearError: next.searchStatus != 'error',
          rendererSession: request.session,
        );
      } else if (ownsRoute &&
          reader.canSearch &&
          next.bookId == bookId &&
          (previous?.ready != true ||
              previous?.bookId != next.bookId ||
              previous?.surfaceVisible != true && next.surfaceVisible)) {
        _schedule();
      }
    });
    ref.listen(workspaceControllerProvider.select((s) => s.annotations), (
      _,
      next,
    ) {
      if (state.active &&
          (state.category == BookSearchCategory.notebook ||
              state.category == BookSearchCategory.bookmarks)) {
        _schedule();
      }
    });
    ref.listen(notebookControllerProvider.select((s) => s.drafts), (_, next) {
      if (state.active && state.category == BookSearchCategory.notebook) {
        _schedule();
      }
    });
    ref.listen(appLocationProvider, (_, next) {
      final route = next.asData?.value.path;
      if (route == null || !state.active) return;
      if (bookId.isEmpty && route != _originRoute) {
        close(restoreFocus: false);
      } else if (!ownsRoute) {
        _cancelNative();
      } else {
        _schedule();
      }
    });
    return BookSearchState(
      category: bookId.isEmpty
          ? BookSearchCategory.actions
          : BookSearchCategory.notebook,
    );
  }

  bool get ownsRoute {
    final path = ref
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path;
    return bookId.isEmpty
        ? path == _originRoute
        : path == '/read/$bookId' || path == '/notebook/$bookId';
  }

  List<BookSearchCategory> get categories {
    if (bookId.isEmpty) return const [BookSearchCategory.actions];
    final reader = ref.read(readerControllerProvider),
        book = ref.read(workspaceControllerProvider).bookById(bookId);
    final sidebar = ref.read(bookSidebarProvider(bookId));
    return [
      if (book?.available == true &&
          book?.textInteraction == true &&
          reader.bookId == bookId &&
          reader.ready &&
          reader.location['noText'] != true)
        BookSearchCategory.bookText,
      BookSearchCategory.notebook,
      BookSearchCategory.bookmarks,
      if (sidebar.outline.ordered.isNotEmpty) BookSearchCategory.chapters,
      BookSearchCategory.actions,
    ];
  }

  BookSearchResult? get selectedResult =>
      state.selected >= 0 && state.selected < state.results.length
      ? state.results[state.selected]
      : null;
  void setActions(Iterable<BookActionSearchResult> actions) =>
      _actions = actions.toList(growable: false);
  Future<void> open({
    BookSearchCategory? category,
    String? query,
    Iterable<BookActionSearchResult>? actions,
  }) async {
    final reader = ref.read(readerControllerProvider.notifier);
    if (reader.stateBookId == bookId && !await reader.prepareChromeChange()) {
      return;
    }
    _activate(category: category, query: query, actions: actions);
  }

  void _activate({
    BookSearchCategory? category,
    String? query,
    Iterable<BookActionSearchResult>? actions,
  }) {
    if (!ref.mounted) return;
    _originRoute = ref
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path;
    if (!ownsRoute) return;
    if (actions != null) setActions(actions);
    if (!state.active) _returnFocus = FocusManager.instance.primaryFocus;
    _queries[state.category] = state.query;
    if (selectedResult != null) {
      _selectedIdentities[state.category] = selectedResult!.identity;
    }
    final next =
        category ??
        (categories.contains(state.category)
            ? state.category
            : categories.first);
    if (!categories.contains(next)) return;
    if (query != null && query != _queries[next]) {
      _selectedIdentities.remove(next);
    }
    final sidebar = bookId.isEmpty
        ? null
        : ref.read(bookSidebarProvider(bookId));
    state = state.copy(
      active: true,
      category: next,
      results: const [],
      selected: -1,
      query: query ?? _queries[next] ?? '',
      focusRequest: state.focusRequest + 1,
      previousPanel: state.active ? state.previousPanel : sidebar?.panel,
      previousOpen: state.active ? state.previousOpen : sidebar?.open,
    );
    _schedule(immediate: query != null);
  }

  Future<void> toggle({
    BookSearchCategory? category,
    Iterable<BookActionSearchResult>? actions,
  }) async {
    if (state.active) {
      close();
    } else {
      await open(category: category, actions: actions);
    }
  }

  void query(String value) {
    if (value == state.query) return;
    _selectedIdentities.remove(state.category);
    state = state.copy(query: value, results: const [], selected: -1);
    _queries[state.category] = value;
    _schedule();
  }

  void _cancelNative() {
    _timer?.cancel();
    final request = _nativeRequest;
    _nativeRequest = null;
    final reader = ref.read(readerControllerProvider.notifier);
    if (request != null &&
        reader.stateBookId == bookId &&
        reader.sessionId == request.session) {
      unawaited(reader.cancelSearch());
    }
  }

  void close({bool restoreFocus = true}) {
    if (!state.active) return;
    _queries[state.category] = state.query;
    if (selectedResult != null) {
      _selectedIdentities[state.category] = selectedResult!.identity;
    }
    _cancelNative();
    state = state.copy(
      active: false,
      results: const [],
      selected: -1,
      loading: false,
      generation: state.generation + 1,
      clearError: true,
    );
    final target = _returnFocus;
    _returnFocus = null;
    if (restoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ref.mounted || state.active || !ownsRoute) return;
        if (target?.context?.mounted == true && target!.canRequestFocus) {
          target.requestFocus();
        } else {
          final reader = ref.read(readerControllerProvider.notifier);
          if (reader.stateBookId == bookId && reader.interactive) {
            unawaited(reader.send('focus'));
          }
        }
      });
    }
  }

  void select(int index) {
    if (state.results.isEmpty) return;
    state = state.copy(selected: index.clamp(0, state.results.length - 1));
    _selectedIdentities[state.category] = selectedResult!.identity;
  }

  void moveSelection(int delta) => select(state.selected + delta);
  bool accepts(BookSearchResult result, int generation) =>
      state.active &&
      ownsRoute &&
      generation == state.generation &&
      state.results.any((r) => identical(r, result));
  int _selection(List<BookSearchResult> results, String? identity) {
    if (results.isEmpty) return -1;
    final index = identity == null
        ? -1
        : results.indexWhere((r) => r.identity == identity);
    return index < 0 ? 0 : index;
  }

  void retry() => _schedule();
  void _schedule({bool immediate = false}) {
    final selected =
        selectedResult?.identity ?? _selectedIdentities[state.category];
    _cancelNative();
    final generation = state.generation + 1;
    state = state.copy(
      generation: generation,
      results: const [],
      selected: -1,
      loading: true,
      progress: state.category == BookSearchCategory.bookText ? 0 : null,
      clearError: true,
    );
    if (immediate || state.query.isEmpty) {
      _run(generation, selected);
    } else {
      _timer = Timer(
        const Duration(milliseconds: 220),
        () => _run(generation, selected),
      );
    }
  }

  Future<void> _run(int generation, String? selected) async {
    if (!ref.mounted ||
        !state.active ||
        generation != state.generation ||
        !ownsRoute) {
      return;
    }
    final query = state.query.trim().toLowerCase(), category = state.category;
    bool current() =>
        ref.mounted &&
        state.active &&
        state.generation == generation &&
        ownsRoute;
    var scanned = 0;
    if (state.category == BookSearchCategory.bookText) {
      final reader = ref.read(readerControllerProvider.notifier);
      if (query.isEmpty ||
          reader.stateBookId != bookId ||
          !reader.canSearch ||
          !categories.contains(BookSearchCategory.bookText)) {
        state = state.copy(loading: false);
        return;
      }
      reader.search(state.query);
      _nativeRequest = (
        session: reader.sessionId,
        revision: reader.searchRevision,
        generation: generation,
      );
      return;
    }
    final data = ref.read(workspaceControllerProvider),
        notes = ref.read(notebookControllerProvider);
    final results = <BookSearchResult>[];
    switch (category) {
      case BookSearchCategory.notebook:
      case BookSearchCategory.bookmarks:
        for (final a in notes.annotationsFor(bookId, data.annotations)) {
          if (++scanned % 16 == 0) {
            await Future<void>.delayed(Duration.zero);
            if (!current()) return;
          }
          if (category == BookSearchCategory.bookmarks &&
              a.kind != 'bookmark') {
            continue;
          }
          final note = notes.effectiveNote(a);
          if (query.isEmpty ||
              '${a.text}\n$note\n${a.reference}'.toLowerCase().contains(
                query,
              )) {
            results.add(AnnotationSearchResult(a, note));
          }
        }
      case BookSearchCategory.chapters:
        for (final chapter
            in ref.read(bookSidebarProvider(bookId)).outline.ordered) {
          if (++scanned % 64 == 0) {
            await Future<void>.delayed(Duration.zero);
            if (!current()) return;
          }
          if (chapter.title.toLowerCase().contains(query)) {
            results.add(ChapterSearchResult(bookId, chapter));
          }
        }
      case BookSearchCategory.actions:
        results.addAll(
          _actions.where(
            (a) => a.command.visible() && a.title.toLowerCase().contains(query),
          ),
        );
      case BookSearchCategory.bookText:
        break;
    }
    if (!current()) return;
    state = state.copy(
      results: results,
      selected: _selection(results, selected),
      loading: false,
    );
  }
}

final bookSearchProvider =
    NotifierProvider.family<BookSearchController, BookSearchState, String>(
      BookSearchController.new,
    );
