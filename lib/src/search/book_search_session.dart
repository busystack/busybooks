import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_router.dart';
import '../app/command_registry.dart';
import '../book_workspace/application/book_sidebar_controller.dart';
import '../book_workspace/application/book_presentation.dart';
import '../library/domain/book.dart';
import '../library/data/library_store.dart';
import '../notebook/application/notebook_controller.dart';
import '../reading/application/reader_controller.dart';
import '../reading/domain/publication_outline.dart';
import '../workspace/workspace_controller.dart';
import '../workspace/workspace_model.dart';

enum BookSearchCategory {
  bookText,
  notebook,
  bookmarks,
  chapters,
  books,
  recent,
  actions,
}

enum BookSearchScopeKind { thisBook, currentCollection, allSavedBooks }

@immutable
class BookSearchScope {
  const BookSearchScope(this.kind, {this.id, this.name = ''});
  const BookSearchScope.all()
    : kind = BookSearchScopeKind.allSavedBooks,
      id = null,
      name = '';
  final BookSearchScopeKind kind;
  final String? id;
  final String name;
  @override
  bool operator ==(Object other) =>
      other is BookSearchScope &&
      other.kind == kind &&
      other.id == id &&
      other.name == name;
  @override
  int get hashCode => Object.hash(kind, id, name);
}

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
  const AnnotationSearchResult(
    this.annotation,
    this.note, {
    this.book,
    this.sourceDigest,
    this.match,
  });
  final ReadingAnnotation annotation;
  final String note;
  final Book? book;
  final String? sourceDigest;
  final Map<String, dynamic>? match;
  @override
  String get identity => '${annotation.bookId}:${annotation.id}';
}

final class ChapterSearchResult extends BookSearchResult {
  const ChapterSearchResult(
    this.bookId,
    this.chapter, {
    this.ancestors = const [],
  });
  final String bookId;
  final PublicationOutlineNode chapter;
  final List<String> ancestors;
  @override
  String get identity => '$bookId:${chapter.id}';
}

final class BookMetadataSearchResult extends BookSearchResult {
  const BookMetadataSearchResult(this.book, {this.sourceDigest, this.match});
  final Book book;
  final String? sourceDigest;
  final Map<String, dynamic>? match;
  @override
  String get identity => book.id;
}

final class RecentBookSearchResult extends BookSearchResult {
  const RecentBookSearchResult(this.resource);
  final RecentResource resource;
  @override
  String get identity => '${resource.kind}:${resource.resourceId}';
}

final class BookActionSearchResult extends BookSearchResult {
  const BookActionSearchResult(
    this.command,
    this.title, {
    this.category = '',
    this.description,
    this.disabledReason,
    this.enabled,
  });
  final BusyBooksCommand command;
  final String title, category;
  final String? description, disabledReason;
  final bool? enabled;
  bool get available => enabled ?? command.canExecute;
  @override
  String get identity => command.id;
}

class BookSearchState {
  const BookSearchState({
    this.active = false,
    this.category = BookSearchCategory.books,
    this.scope = const BookSearchScope.all(),
    this.bookId,
    this.originRoute,
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
    this.hasMore = false,
    this.resultOffset = 0,
    this.totalOccurrences,
    this.activeOccurrence,
    this.unavailable,
    this.sourceRevision,
  });
  final bool active, loading, previousOpen, hasMore;
  final BookSearchCategory category;
  final BookSearchScope scope;
  final String? bookId, originRoute;
  final String query;
  final List<BookSearchResult> results;
  final int selected, focusRequest, generation, resultOffset;
  final int? totalOccurrences, activeOccurrence, sourceRevision;
  final String? error, rendererSession, unavailable;
  final double? progress;
  final BookSidebarPanel? previousPanel;
  bool get waitingForInput =>
      query.isEmpty && category != BookSearchCategory.actions;
  bool get showingInitialList =>
      query.isEmpty && category == BookSearchCategory.actions;
  BookSearchState copy({
    bool? active,
    BookSearchCategory? category,
    BookSearchScope? scope,
    String? bookId,
    bool clearBook = false,
    String? originRoute,
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
    bool? hasMore,
    int? resultOffset,
    int? totalOccurrences,
    int? activeOccurrence,
    bool clearOccurrences = false,
    String? unavailable,
    bool clearUnavailable = false,
    int? sourceRevision,
  }) => BookSearchState(
    active: active ?? this.active,
    category: category ?? this.category,
    scope: scope ?? this.scope,
    bookId: clearBook ? null : bookId ?? this.bookId,
    originRoute: originRoute ?? this.originRoute,
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
    hasMore: hasMore ?? this.hasMore,
    resultOffset: resultOffset ?? this.resultOffset,
    totalOccurrences: clearOccurrences
        ? null
        : totalOccurrences ?? this.totalOccurrences,
    activeOccurrence: clearOccurrences
        ? null
        : activeOccurrence ?? this.activeOccurrence,
    unavailable: clearUnavailable ? null : unavailable ?? this.unavailable,
    sourceRevision: sourceRevision ?? this.sourceRevision,
  );
}

class _SearchMemory {
  const _SearchMemory(this.query, this.scope, this.identity);
  final String query;
  final BookSearchScope scope;
  final String? identity;
}

class _Activation {
  _Activation(
    this.generation,
    this.identity,
    this.originRoute,
    this.targetRoute,
    this.targetBookId,
    this.originBookId,
  );
  final int generation;
  final String identity, originRoute;
  final String? targetRoute, targetBookId, originBookId;
  bool arrived = false, dismissed = false;
  ReaderJumpRequest? deferredJump;
}

/// One window session. Only query/scope/identity memory survives dismissal;
/// result pages, requests and renderer ownership are released on close.
class BookSearchController extends Notifier<BookSearchState> {
  Timer? _timer;
  FocusNode? _returnFocus;
  final _memory = <BookSearchCategory, _SearchMemory>{};
  List<BookActionSearchResult> _actions = const [];
  ({String session, int revision, int generation})? _nativeRequest;
  Completer<void>? _nativeDone;
  Future<void>? _running;
  _ReaderRecovery? _readerRecovery;
  String? _requestToken;
  Map<String, dynamic>? _cursor;
  int _serial = 0, _localCursor = 0;
  bool _submitting = false, _windowLoading = false, _everOpened = false;
  _Activation? _activation;
  bool _refreshAfterActivation = false;
  StreamSubscription<int>? _repositoryChanges;
  ReadingDataStore? _store;
  ProviderSubscription<BookSidebarState>? _outline;
  String? _outlineBook, _actionBookId, _actionWorkspaceId;

  String get _route =>
      ref.read(appRouterProvider).routeInformationProvider.value.uri.path;
  String? get _visibleBookId => bookIdForRoute(_route);

  @override
  BookSearchState build() {
    final events = ref
        .read(readerControllerProvider.notifier)
        .events
        .stream
        .listen((event) {
          if (!ref.mounted ||
              event['type'] != 'searchSelection' ||
              event['bookId'] != _visibleBookId) {
            return;
          }
          final reader = ref.read(readerControllerProvider.notifier);
          if (reader.interactive &&
              reader.sessionId == event['session'] &&
              reader.presentationId == event['presentation']) {
            _activate(
              category: BookSearchCategory.bookText,
              query: event['text'] as String,
            );
          }
        });
    ref.onDispose(() {
      _activation?.deferredJump?.cancel();
      _timer?.cancel();
      _nativeDone?.complete();
      _nativeDone = null;
      _outline?.close();
      unawaited(events.cancel());
      unawaited(_repositoryChanges?.cancel());
      final token = _requestToken;
      if (token != null) {
        unawaited(
          _store?.call('cancelSearch', token).catchError((Object _) {}) ??
              Future.value(),
        );
      }
    });
    ref.listen(readerControllerProvider, (previous, next) {
      if (!state.active || state.category != BookSearchCategory.bookText) {
        return;
      }
      final reader = ref.read(readerControllerProvider.notifier);
      final recovery = _readerRecovery;
      if (recovery != null && next.bookId == recovery.bookId) {
        if (next.error == null) recovery.errorCleared = true;
        // Closing the failed surface can publish visibility changes before
        // retry creates its replacement. Those still belong to the old error.
        if (!recovery.errorCleared && next.error == recovery.error) return;
      }
      if (next.bookId == state.bookId && next.error != null) {
        if (state.unavailable != 'reader-error' || state.loading) {
          _readerFailed(next.error!);
        }
        return;
      }
      var request = _nativeRequest;
      if (_windowLoading &&
          request != null &&
          request.session == reader.sessionId &&
          next.query == state.query) {
        request = (
          session: request.session,
          revision: reader.searchRevision,
          generation: request.generation,
        );
        _nativeRequest = request;
      }
      if (request != null &&
          request.session == reader.sessionId &&
          request.revision == reader.searchRevision &&
          request.generation == state.generation &&
          next.bookId == state.bookId &&
          next.query == state.query) {
        final results = [
          for (final match in next.matches)
            if (match['anchor'] is Map)
              BookTextSearchResult(next.bookId!, request.session, match),
        ];
        final identity = selectedResult?.identity ?? _rememberedIdentity;
        state = state.copy(
          results: List.unmodifiable(results),
          selected: _selection(results, identity),
          loading: next.searching,
          progress: next.searchProgress,
          error: next.searchStatus == 'error' ? 'text-search' : null,
          clearError: next.searchStatus != 'error',
          unavailable: next.searchStatus == 'cancelled'
              ? 'search-cancelled'
              : null,
          clearUnavailable: next.searchStatus != 'cancelled',
          rendererSession: request.session,
          totalOccurrences: next.searchStatus == 'done'
              ? next.searchTotal
              : null,
          clearOccurrences:
              next.searchStatus != 'done' && next.searchStatus != 'searching',
          resultOffset: next.searchOffset,
          hasMore:
              next.searchStatus == 'done' &&
              next.searchOffset + results.length < next.searchTotal,
        );
        if (!next.searching) _finishNative();
      } else if (request != null &&
          request.session == reader.sessionId &&
          next.bookId == state.bookId &&
          next.searchStatus == 'cancelled') {
        _nativeRequest = null;
        _finishNative();
        state = state.copy(
          loading: false,
          results: const [],
          selected: -1,
          hasMore: false,
          unavailable: 'search-cancelled',
          clearOccurrences: true,
        );
      } else if (request != null &&
          (request.session != reader.sessionId ||
              next.bookId != state.bookId)) {
        _sourceChanged();
      } else if (ownsRoute &&
          next.bookId == state.bookId &&
          reader.canSearch &&
          (previous?.ready != true ||
              previous?.bookId != next.bookId ||
              previous?.surfaceVisible != true && next.surfaceVisible)) {
        _sourceChanged();
      }
    });
    ref.listen(workspaceControllerProvider, (previous, next) {
      if (!state.active) return;
      if (state.scope.kind == BookSearchScopeKind.currentCollection &&
          !next.collections.any((c) => c['id'] == state.scope.id)) {
        _invalidate();
        state = state.copy(
          loading: false,
          results: const [],
          selected: -1,
          unavailable: 'collection-unavailable',
        );
        return;
      }
      if (state.category == BookSearchCategory.recent &&
              previous?.recent != next.recent ||
          state.category == BookSearchCategory.notebook ||
          state.category == BookSearchCategory.bookmarks) {
        if (previous?.annotations != next.annotations ||
            state.category == BookSearchCategory.recent &&
                previous?.recent != next.recent) {
          _sourceChanged();
        }
      }
    });
    ref.listen(
      notebookControllerProvider.select((s) => (s.drafts, s.sources)),
      (_, _) {
        if (state.active &&
            (state.category == BookSearchCategory.notebook ||
                state.category == BookSearchCategory.bookmarks)) {
          _sourceChanged();
        }
      },
    );
    final routeSource = ref.read(appRouterProvider).routeInformationProvider;
    void routeChanged() {
      final route = routeSource.value.uri.path;
      final recovery = _readerRecovery;
      if (recovery != null && !sameReaderBookRoutes(route, recovery.route)) {
        recovery.abandoned = true;
      }
      if ((!state.active && _activation == null) ||
          route == state.originRoute) {
        return;
      }
      final activation = _activation;
      if (activation != null &&
          route == activation.targetRoute &&
          state.generation == activation.generation) {
        activation.arrived = true;
        state = state.copy(
          originRoute: route,
          bookId: _visibleBookId,
          clearBook: _visibleBookId == null,
        );
        return;
      }
      if (activation != null) {
        close(restoreFocus: false);
        return;
      }
      if (_visibleBookId != null &&
          _visibleBookId == state.bookId &&
          state.originRoute != '/settings' &&
          bookViewForRoute(route) != null) {
        final previousRoute = state.originRoute;
        state = state.copy(originRoute: route);
        if (state.category == BookSearchCategory.bookText &&
            !sameReaderBookRoutes(previousRoute ?? '', route)) {
          _sourceChanged();
        }
        return;
      }
      close(restoreFocus: false);
    }

    routeSource.addListener(routeChanged);
    ref.onDispose(() => routeSource.removeListener(routeChanged));
    return const BookSearchState();
  }

  bool get ownsRoute {
    if (_route == state.originRoute) return true;
    final a = _activation;
    return a != null &&
        a.generation == state.generation &&
        _route == a.targetRoute;
  }

  List<BookSearchCategory> get categories {
    if (_route == '/settings') return const [BookSearchCategory.actions];
    final id = _visibleBookId;
    final book = ref.read(workspaceControllerProvider).bookById(id);
    return [
      if (id != null && book?.textInteraction == true)
        BookSearchCategory.bookText,
      BookSearchCategory.notebook,
      BookSearchCategory.bookmarks,
      if (id != null &&
          ref.read(bookSidebarProvider(id)).outline.ordered.isNotEmpty)
        BookSearchCategory.chapters,
      BookSearchCategory.books,
      BookSearchCategory.recent,
      BookSearchCategory.actions,
    ];
  }

  List<BookSearchScope> get scopes {
    final data = ref.read(workspaceControllerProvider), id = _visibleBookId;
    final book = data.bookById(id), workspace = data.workspace;
    return [
      if (state.category != BookSearchCategory.books &&
          id != null &&
          book != null)
        BookSearchScope(BookSearchScopeKind.thisBook, id: id, name: book.title),
      if (workspace != null &&
          !workspace.isBook &&
          _route != '/' &&
          _route != '/settings')
        BookSearchScope(
          BookSearchScopeKind.currentCollection,
          id: workspace.id,
          name: workspace.name,
        ),
      if (state.scope.kind == BookSearchScopeKind.currentCollection &&
          state.scope.id != workspace?.id &&
          data.collections.any((c) => c['id'] == state.scope.id))
        state.scope,
      if (state.scope.kind == BookSearchScopeKind.thisBook &&
          state.category != BookSearchCategory.books &&
          state.scope.id != id)
        state.scope,
      const BookSearchScope.all(),
    ];
  }

  BookSearchResult? get selectedResult =>
      state.selected >= 0 && state.selected < state.results.length
      ? state.results[state.selected]
      : null;
  String? get _rememberedIdentity => _memory[state.category]?.identity;
  void _remember() {
    if (state.originRoute == null) return;
    _memory[state.category] = _SearchMemory(
      state.query,
      state.scope,
      selectedResult?.identity ?? _rememberedIdentity,
    );
  }

  void setActions(Iterable<BookActionSearchResult> actions) {
    final next = actions.toList(growable: false);
    final changed =
        next.length != _actions.length ||
        next.indexed.any((e) {
          final old = _actions[e.$1], a = e.$2;
          return old.identity != a.identity ||
              old.title != a.title ||
              old.category != a.category ||
              old.description != a.description ||
              old.disabledReason != a.disabledReason ||
              old.available != a.available ||
              old.command.shortcut?.label != a.command.shortcut?.label;
        });
    _actions = next;
    if (changed &&
        state.active &&
        state.category == BookSearchCategory.actions) {
      final generation = state.generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.mounted &&
            state.active &&
            state.category == BookSearchCategory.actions &&
            generation == state.generation) {
          _publishActions();
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  Future<void> open({
    BookSearchCategory? category,
    String? query,
    BookSearchScope? scope,
    Iterable<BookActionSearchResult>? actions,
  }) async {
    final route = _route, reader = ref.read(readerControllerProvider.notifier);
    final id = _visibleBookId;
    if (id != null &&
        reader.stateBookId == id &&
        !await reader.prepareChromeChange()) {
      return;
    }
    if (!ref.mounted || _route != route) return;
    _activate(category: category, query: query, scope: scope, actions: actions);
    if (query != null && _repositoryCategory(state.category)) {
      final requestedCategory = state.category, requestedScope = state.scope;
      Future<void>? pending;
      do {
        pending = _running;
        await pending;
      } while (ref.mounted &&
          state.active &&
          state.query == query &&
          state.category == requestedCategory &&
          state.scope == requestedScope &&
          !identical(pending, _running));
    }
  }

  void _activate({
    BookSearchCategory? category,
    String? query,
    BookSearchScope? scope,
    Iterable<BookActionSearchResult>? actions,
  }) {
    if (!ref.mounted) return;
    _cancelDeferredActivation();
    _activation = null;
    if (actions != null) setActions(actions);
    if (!state.active) _returnFocus = FocusManager.instance.primaryFocus;
    _remember();
    final presentation = ref.read(bookPresentationProvider);
    final view = bookViewForRoute(_route);
    final notebook =
        view == BookView.notebook ||
        view == BookView.split &&
            presentation.bookId == _visibleBookId &&
            presentation.lastPane == BookPane.notebook;
    final initial = notebook
        ? BookSearchCategory.notebook
        : view?.hasReader == true
        ? (categories.contains(BookSearchCategory.bookText)
              ? BookSearchCategory.bookText
              : BookSearchCategory.notebook)
        : _route == '/settings'
        ? BookSearchCategory.actions
        : BookSearchCategory.books;
    final next =
        category ??
        (!_everOpened
            ? initial
            : categories.contains(state.category)
            ? state.category
            : initial);
    _everOpened = true;
    if (next == BookSearchCategory.actions) {
      _actionBookId = _visibleBookId;
      _actionWorkspaceId = _route == '/' || _route == '/settings'
          ? null
          : ref.read(workspaceControllerProvider).workspace?.id;
    }
    // An explicit unsupported Book Text request remains honest and visible.
    if (!categories.contains(next) && next != BookSearchCategory.bookText) {
      return;
    }
    final id = _visibleBookId, data = ref.read(workspaceControllerProvider);
    final memory = _memory[next];
    final defaultScope = next != BookSearchCategory.books && id != null
        ? BookSearchScope(
            BookSearchScopeKind.thisBook,
            id: id,
            name: data.bookById(id)?.title ?? '',
          )
        : _route != '/' &&
              _route != '/settings' &&
              data.workspace?.isBook == false
        ? BookSearchScope(
            BookSearchScopeKind.currentCollection,
            id: data.workspace!.id,
            name: data.workspace!.name,
          )
        : const BookSearchScope.all();
    final rememberedScope = memory?.scope;
    final fixedBook =
        next == BookSearchCategory.bookText ||
        next == BookSearchCategory.chapters;
    final selectedScope = fixedBook
        ? BookSearchScope(
            BookSearchScopeKind.thisBook,
            id: id,
            name: data.bookById(id)?.title ?? '',
          )
        : next == BookSearchCategory.actions ||
              next == BookSearchCategory.recent
        ? const BookSearchScope.all()
        : scope ??
              (rememberedScope != null &&
                      _scopeApplicable(rememberedScope, next)
                  ? rememberedScope
                  : defaultScope);
    final sidebar = id == null ? null : ref.read(bookSidebarProvider(id));
    state = state.copy(
      active: true,
      category: next,
      scope: selectedScope,
      bookId: id,
      clearBook: id == null,
      originRoute: _route,
      results: const [],
      selected: -1,
      query: query ?? memory?.query ?? '',
      focusRequest: state.focusRequest + 1,
      previousPanel: state.active ? state.previousPanel : sidebar?.panel,
      previousOpen: state.active ? state.previousOpen : sidebar?.open,
    );
    if (query != null && query != memory?.query) {
      _memory[next] = _SearchMemory(query, selectedScope, null);
    }
    _observeOutline(next == BookSearchCategory.chapters ? id : null);
    _schedule(immediate: query != null);
  }

  bool _scopeApplicable(BookSearchScope scope, BookSearchCategory category) =>
      switch (scope.kind) {
        BookSearchScopeKind.allSavedBooks => true,
        BookSearchScopeKind.thisBook =>
          category != BookSearchCategory.books &&
              (_visibleBookId == scope.id ||
                  state.active && state.scope == scope),
        BookSearchScopeKind.currentCollection =>
          ref
                  .read(workspaceControllerProvider)
                  .collections
                  .any((c) => c['id'] == scope.id) &&
              (_route != '/' || state.active),
      };

  void _observeOutline(String? id) {
    if (_outlineBook == id) return;
    _outline?.close();
    _outlineBook = id;
    _outline = id == null
        ? null
        : ref.listen(bookSidebarProvider(id), (old, next) {
            if (state.active &&
                state.category == BookSearchCategory.chapters &&
                !identical(old?.outline, next.outline)) {
              _sourceChanged();
            }
          });
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

  void setScope(BookSearchScope scope) {
    if (scope == state.scope || !scopes.contains(scope)) return;
    state = state.copy(scope: scope, results: const [], selected: -1);
    _memory[state.category] = _SearchMemory(state.query, scope, null);
    _schedule();
  }

  void query(String value) {
    if (value == state.query) return;
    state = state.copy(query: value, results: const [], selected: -1);
    _memory[state.category] = _SearchMemory(value, state.scope, null);
    _schedule();
  }

  void _readerFailed(String message) {
    _cancelDeferredActivation();
    _timer?.cancel();
    _timer = null;
    _nativeRequest = null;
    _finishNative();
    state = state.copy(
      generation: state.generation + 1,
      loading: false,
      results: const [],
      selected: -1,
      hasMore: false,
      clearOccurrences: true,
      error: message,
      unavailable: 'reader-error',
    );
  }

  void _finishNative() {
    final done = _nativeDone;
    _nativeDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  void _invalidate({bool incrementGeneration = true}) {
    if (incrementGeneration) _cancelDeferredActivation();
    _timer?.cancel();
    _timer = null;
    _finishNative();
    final request = _nativeRequest;
    _nativeRequest = null;
    final reader = ref.read(readerControllerProvider.notifier);
    if (request != null &&
        reader.stateBookId == state.bookId &&
        reader.sessionId == request.session) {
      unawaited(reader.cancelSearch());
    }
    final token = _requestToken;
    _requestToken = null;
    if (token != null) {
      unawaited(
        ref
            .read(readingDataStoreProvider)
            .call('cancelSearch', token)
            .catchError((Object _) {}),
      );
    }
    _cursor = null;
    _localCursor = 0;
    if (incrementGeneration) {
      state = state.copy(generation: state.generation + 1);
    }
  }

  void close({bool restoreFocus = true}) {
    if (!state.active) {
      if (_activation != null) {
        _cancelDeferredActivation();
        _activation = null;
        state = state.copy(generation: state.generation + 1);
      }
      return;
    }
    _remember();
    _invalidate();
    _activation = null;
    _releaseRepository();
    _outline?.close();
    _outline = null;
    _outlineBook = null;
    state = state.copy(
      active: false,
      results: const [],
      selected: -1,
      loading: false,
      hasMore: false,
      clearError: true,
      clearUnavailable: true,
      clearOccurrences: true,
    );
    final target = _returnFocus, route = _route;
    _returnFocus = null;
    if (restoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ref.mounted || state.active || _route != route) return;
        if (target?.context?.mounted == true && target!.canRequestFocus) {
          target.requestFocus();
        } else {
          final reader = ref.read(readerControllerProvider.notifier);
          if (reader.stateBookId == _visibleBookId && reader.interactive) {
            final generation = state.generation, bookId = _visibleBookId;
            unawaited(
              reader.focusPublication(
                isCurrent: () =>
                    ref.mounted &&
                    !state.active &&
                    state.generation == generation &&
                    _route == route &&
                    _visibleBookId == bookId,
              ),
            );
          }
        }
      });
    }
  }

  void select(int index) {
    if (state.results.isEmpty) return;
    state = state.copy(selected: index.clamp(0, state.results.length - 1));
    _remember();
  }

  void moveSelection(int delta) => select(
    state.selected < 0 && delta < 0
        ? state.results.length - 1
        : state.selected + delta,
  );

  bool accepts(BookSearchResult result, int generation) =>
      ref.mounted &&
      ownsRoute &&
      generation == state.generation &&
      _activationOwnsBook &&
      (state.active && state.results.any((r) => identical(r, result)) ||
          _activation?.dismissed == true &&
              _activation?.generation == generation &&
              _activation?.identity == result.identity) &&
      switch (result) {
        BookTextSearchResult() =>
          result.bookId == state.bookId &&
              ref.read(readerControllerProvider.notifier).sessionId ==
                  result.session,
        BookActionSearchResult() =>
          (result.command.scope != BusyBooksCommandScope.documentView ||
                  _actionBookId != null &&
                      _actionBookId == _visibleBookId &&
                      ref.read(workspaceControllerProvider).openedBook?.id ==
                          _actionBookId) &&
              (_actionWorkspaceId == null ||
                  ref.read(workspaceControllerProvider).workspace?.id ==
                      _actionWorkspaceId),
        ChapterSearchResult() =>
          result.bookId == state.bookId && _sameChapterSource(result),
        _ => true,
      };

  bool _sameChapterSource(ChapterSearchResult result) {
    final outline = ref.read(bookSidebarProvider(result.bookId)).outline;
    final current = outline.byId[result.chapter.id], captured = result.chapter;
    if (current == null ||
        current.title != captured.title ||
        current.depth != captured.depth ||
        current.parentId != captured.parentId ||
        current.pageLabel != captured.pageLabel ||
        jsonEncode(current.destination) != jsonEncode(captured.destination)) {
      return false;
    }
    final ancestors = <String>[];
    var parent = outline.byId[current.parentId];
    while (parent != null) {
      ancestors.insert(0, parent.title);
      parent = outline.byId[parent.parentId];
    }
    return jsonEncode(ancestors) == jsonEncode(result.ancestors);
  }

  bool get _activationOwnsBook {
    final activation = _activation;
    if (activation == null) return true;
    final current = ref.read(workspaceControllerProvider).openedBook?.id;
    return current == activation.originBookId ||
        current == activation.targetBookId;
  }

  bool beginActivation(
    BookSearchResult result,
    int generation, {
    String? targetRoute,
    String? targetBookId,
  }) {
    // A later explicit activation supersedes a handoff still waiting for its
    // renderer. Cancelling it must not release or refresh the new activation.
    if (_activation != null && _activation!.deferredJump == null) return false;
    if (!accepts(result, generation)) return false;
    _cancelDeferredActivation(preserveRefresh: true);
    _activation = _Activation(
      generation,
      result.identity,
      _route,
      targetRoute,
      targetBookId,
      ref.read(workspaceControllerProvider).openedBook?.id,
    );
    return true;
  }

  void _cancelDeferredActivation({bool preserveRefresh = false}) {
    final activation = _activation;
    if (activation?.deferredJump == null) return;
    _activation = null;
    if (!preserveRefresh) _refreshAfterActivation = false;
    activation!.deferredJump!.cancel();
  }

  /// Keep only this activation's ownership until its deferred passage jump is
  /// sent or abandoned. A narrow dismissal may already have released the rows.
  void retainDeferredActivation(ReaderJumpRequest request) {
    final activation = _activation;
    if (activation == null ||
        activation.targetBookId != request.bookId ||
        activation.generation != state.generation) {
      request.cancel();
      return;
    }
    activation.deferredJump?.cancel();
    activation.deferredJump = request;
    unawaited(
      request.finished.then((_) {
        if (!ref.mounted ||
            !identical(_activation, activation) ||
            !identical(activation.deferredJump, request)) {
          return;
        }
        activation.deferredJump = null;
        endActivation();
      }),
    );
  }

  void endActivation() {
    if (_activation?.deferredJump != null) return;
    _activation = null;
    if (_refreshAfterActivation) {
      _refreshAfterActivation = false;
      if (ref.mounted && state.active && ownsRoute) {
        _schedule(immediate: true, preserveResults: true);
      }
    }
  }

  /// A narrow activation releases displayed results while retaining only its
  /// captured request guard until the final native/route handoff completes.
  void dismissForActivation() {
    final activation = _activation;
    if (activation == null) {
      close(restoreFocus: false);
      return;
    }
    if (!state.active) return;
    _remember();
    _invalidate(incrementGeneration: false);
    activation.dismissed = true;
    _releaseRepository();
    _outline?.close();
    _outline = null;
    _outlineBook = null;
    _returnFocus = null;
    state = state.copy(
      active: false,
      results: const [],
      selected: -1,
      loading: false,
      hasMore: false,
    );
  }

  void didActivateResult(BookSearchResult result) {
    if (result is BookTextSearchResult) {
      final index = result.match['index'];
      final local = state.results.indexWhere(
        (r) => r.identity == result.identity,
      );
      final absolute = index is int
          ? index
          : local < 0
          ? null
          : state.resultOffset + local;
      if (absolute != null) state = state.copy(activeOccurrence: absolute);
    }
  }

  Map<String, dynamic> _repositoryArguments() {
    final notes = ref.read(notebookControllerProvider);
    return {
      'category': state.category.name,
      'query': state.query,
      if (state.scope.kind == BookSearchScopeKind.thisBook)
        'bookId': state.scope.id,
      if (state.scope.kind == BookSearchScopeKind.currentCollection)
        'collectionId': state.scope.id,
      'drafts': [
        for (final entry in notes.drafts.entries)
          if (notes.sources[entry.key] case final source?
              when state.scope.kind != BookSearchScopeKind.thisBook ||
                  source.bookId == state.scope.id)
            {
              // Existing saved records remain the authority for quotation and
              // locator data. Transfer only their effective note overlay.
              'annotation': entry.value.creating && !entry.value.creationWritten
                  ? source.data
                  : {'id': source.id, 'bookId': source.bookId},
              'note': entry.value.text,
              'creating': entry.value.creating && !entry.value.creationWritten,
            },
      ],
    };
  }

  Future<bool> validateResult(BookSearchResult result, int generation) async {
    if (!accepts(result, generation)) return false;
    if (result is AnnotationSearchResult ||
        result is BookMetadataSearchResult) {
      final row = await ref
          .read(readingDataStoreProvider)
          .call('validateSearchResult', {
            ..._repositoryArguments(),
            'targetBookId': result is AnnotationSearchResult
                ? result.annotation.bookId
                : (result as BookMetadataSearchResult).book.id,
            if (result is AnnotationSearchResult)
              'annotationId': result.annotation.id,
            'sourceDigest': result is AnnotationSearchResult
                ? result.sourceDigest
                : (result as BookMetadataSearchResult).sourceDigest,
          });
      return row != null && accepts(result, generation);
    }
    if (result is RecentBookSearchResult) {
      return ref
              .read(workspaceControllerProvider)
              .recent
              .any(
                (r) =>
                    r.kind == result.resource.kind &&
                    r.resourceId == result.resource.resourceId,
              ) &&
          accepts(result, generation);
    }
    return accepts(result, generation);
  }

  int _selection(List<BookSearchResult> results, String? identity) {
    if (results.isEmpty) return -1;
    // A removed target must never redirect Enter to the replacement row.
    return identity == null
        ? 0
        : results.indexWhere((r) => r.identity == identity);
  }

  Future<void> retry() async {
    if (!ref.mounted || !state.active || !ownsRoute) return;
    final reader = ref.read(readerControllerProvider.notifier);
    final renderer = ref.read(readerControllerProvider);
    final id = state.bookId, route = _route;
    final pending = _readerRecovery;
    if (state.category == BookSearchCategory.bookText &&
        pending?.bookId == id &&
        pending != null &&
        sameReaderBookRoutes(pending.route, route)) {
      return;
    }
    if (state.category != BookSearchCategory.bookText ||
        id == null ||
        renderer.bookId != id ||
        renderer.error == null) {
      _schedule(immediate: true);
      return;
    }
    // A renderer recovery is owned by the visible publication, independently
    // of query edits. Its readiness listener always submits the latest query.
    // A suspended Notebook reader still requires the explicit Reading action.
    if (bookIdForRoute(route) != id ||
        bookViewForRoute(route)?.hasReader != true ||
        reader.suspended) {
      state = state.copy(
        loading: false,
        clearError: true,
        unavailable: 'needs-reading',
      );
      return;
    }
    final recovery = _ReaderRecovery(id, route, renderer.error!);
    _readerRecovery = recovery;
    bool current() =>
        ref.mounted &&
        !recovery.abandoned &&
        sameReaderBookRoutes(_route, route) &&
        ref.read(workspaceControllerProvider).openedBook?.id == id;
    if (!current()) {
      _readerRecovery = null;
      return;
    }
    _invalidate();
    state = state.copy(
      loading: true,
      clearError: true,
      unavailable: 'reader-loading',
    );
    try {
      await reader.retry(id, isCurrent: current);
    } catch (error) {
      if (current() &&
          state.active &&
          state.category == BookSearchCategory.bookText &&
          state.bookId == id) {
        _readerFailed(error.toString());
      }
    } finally {
      if (identical(_readerRecovery, recovery)) _readerRecovery = null;
    }
  }

  ReadingDataStore _observeRepository() {
    final ReadingDataStore store =
        _store ?? ref.read<ReadingDataStore>(readingDataStoreProvider);
    _store = store;
    _repositoryChanges ??= store.changes.listen((_) {
      if (ref.mounted && state.active && _repositoryCategory(state.category)) {
        _sourceChanged();
      }
    });
    return store;
  }

  void _releaseRepository() {
    unawaited(_repositoryChanges?.cancel());
    _repositoryChanges = null;
    _store = null;
  }

  bool _repositoryCategory(BookSearchCategory c) =>
      c == BookSearchCategory.books ||
      c == BookSearchCategory.notebook ||
      c == BookSearchCategory.bookmarks;
  void _sourceChanged() {
    if (_activation != null) {
      _refreshAfterActivation = true;
      return;
    }
    _schedule();
  }

  void _schedule({bool immediate = false, bool preserveResults = false}) {
    final selected = selectedResult?.identity ?? _rememberedIdentity;
    _invalidate();
    if (!_repositoryCategory(state.category) || state.waitingForInput) {
      _releaseRepository();
    }
    state = state.copy(
      results: preserveResults ? state.results : const [],
      selected: preserveResults ? state.selected : -1,
      loading: !state.waitingForInput,
      hasMore: false,
      resultOffset: 0,
      clearOccurrences: true,
      clearError: true,
      clearUnavailable: true,
    );
    if (!state.active || state.waitingForInput) return;
    final generation = state.generation;
    if (immediate ||
        state.category == BookSearchCategory.actions && state.query.isEmpty) {
      _running = _run(generation, selected);
    } else {
      _timer = Timer(const Duration(milliseconds: 120), () {
        _timer = null;
        _running = _run(generation, selected);
      });
    }
  }

  Future<bool> submit({bool requireSelection = true}) async {
    if (_submitting || !state.active || state.waitingForInput) return false;
    _submitting = true;
    final generation = state.generation;
    try {
      if (_timer?.isActive == true) {
        _timer!.cancel();
        _timer = null;
        _running = _run(generation, _rememberedIdentity);
      }
      await _running;
      return _current(generation) &&
          !state.loading &&
          state.error == null &&
          state.unavailable == null &&
          (!requireSelection || selectedResult != null);
    } finally {
      _submitting = false;
    }
  }

  bool _current(int generation) =>
      ref.mounted &&
      state.active &&
      state.generation == generation &&
      ownsRoute;

  Future<void> _run(
    int generation,
    String? selected, {
    bool append = false,
  }) async {
    if (!_current(generation) || state.waitingForInput) return;
    try {
      if (state.category == BookSearchCategory.bookText) {
        final reader = ref.read(readerControllerProvider.notifier),
            id = state.bookId;
        final book = ref.read(workspaceControllerProvider).bookById(id);
        if (id == null ||
            book?.textInteraction != true ||
            book?.available != true) {
          state = state.copy(
            loading: false,
            unavailable: 'book-text-unavailable',
          );
          return;
        }
        final readerError = ref.read(readerControllerProvider).error;
        if (reader.stateBookId == id && readerError != null) {
          _readerFailed(readerError);
          return;
        }
        if (reader.stateBookId != id || !reader.canSearch) {
          state = state.copy(
            loading:
                reader.stateBookId == id &&
                !reader.suspended &&
                ref.read(readerControllerProvider).error == null,
            unavailable: reader.suspended || reader.stateBookId != id
                ? 'needs-reading'
                : 'reader-loading',
          );
          return;
        }
        state = state.copy(clearUnavailable: true);
        _nativeDone = Completer<void>();
        _nativeRequest = (
          session: reader.sessionId,
          revision: reader.searchRevision + 1,
          generation: generation,
        );
        final finished = _nativeDone!.future;
        reader.search(state.query);
        await finished;
        return;
      }
      if (_repositoryCategory(state.category)) {
        final store = _observeRepository(),
            token = 'window-search:${++_serial}';
        _requestToken = token;
        final results = <BookSearchResult>[if (append) ...state.results];
        var added = 0, hasMore = true;
        do {
          final page =
              await store.call('searchRecords', {
                    ..._repositoryArguments(),
                    'requestToken': token,
                    'limit': 100 - added,
                    if (_cursor != null) 'cursor': _cursor,
                  })
                  as Map;
          if (!_current(generation) || _requestToken != token) return;
          final pageResults = page['results'] as List;
          for (final value in pageResults) {
            final row = value as Map,
                book = Book((row['book'] as Map).cast<String, dynamic>());
            final match = (row['match'] as Map?)?.cast<String, dynamic>();
            results.add(
              row['annotation'] == null
                  ? BookMetadataSearchResult(
                      book,
                      sourceDigest: row['sourceDigest'] as String?,
                      match: match,
                    )
                  : AnnotationSearchResult(
                      ReadingAnnotation(
                        (row['annotation'] as Map).cast<String, dynamic>(),
                      ),
                      (row['annotation'] as Map)['note'] as String? ?? '',
                      book: book,
                      sourceDigest: row['sourceDigest'] as String?,
                      match: match,
                    ),
            );
            added++;
          }
          _cursor = (page['cursor'] as Map?)?.cast<String, dynamic>();
          hasMore = page['hasMore'] == true;
          state = state.copy(sourceRevision: page['sourceRevision'] as int?);
          if (pageResults.isNotEmpty && hasMore) {
            // A later batch can fail after returning useful matches. Keep the
            // bounded completed portion visible and mark it incomplete on error.
            final removed = results.length > 1000 ? results.length - 1000 : 0;
            if (removed > 0) results.removeRange(0, removed);
            state = state.copy(
              results: List.unmodifiable(results),
              selected: _selection(results, selected),
              loading: true,
              hasMore: true,
              resultOffset: state.resultOffset + removed,
            );
          }
        } while (added < 100 && hasMore && _cursor != null);
        if (!_current(generation)) return;
        // Retain a bounded display window, while the cursor continues exactly.
        final removed = results.length > 1000 ? results.length - 1000 : 0;
        if (removed > 0) results.removeRange(0, removed);
        state = state.copy(
          results: List.unmodifiable(results),
          selected: _selection(results, selected),
          loading: false,
          hasMore: hasMore,
          resultOffset: state.resultOffset + removed,
        );
        return;
      }
      if (state.category == BookSearchCategory.actions) {
        _publishActions();
        return;
      }
      final expression = RegExp(
        RegExp.escape(state.query),
        caseSensitive: false,
        unicode: true,
      );
      final results = <BookSearchResult>[if (append) ...state.results];
      var hasMore = false, added = 0;
      if (state.category == BookSearchCategory.recent) {
        for (final resource in ref.read(workspaceControllerProvider).recent) {
          if (expression.hasMatch('${resource.title}\n${resource.path}')) {
            results.add(RecentBookSearchResult(resource));
          }
        }
      } else if (state.category == BookSearchCategory.chapters &&
          state.bookId != null) {
        final outline = ref.read(bookSidebarProvider(state.bookId!)).outline;
        for (
          var index = append ? _localCursor : 0;
          index < outline.ordered.length;
          index++
        ) {
          final chapter = outline.ordered[index];
          if (!expression.hasMatch(chapter.title)) continue;
          if (added == 100) {
            hasMore = true;
            _localCursor = index;
            break;
          }
          final ancestors = <String>[];
          var parent = outline.byId[chapter.parentId];
          while (parent != null) {
            ancestors.insert(0, parent.title);
            parent = outline.byId[parent.parentId];
          }
          results.add(
            ChapterSearchResult(state.bookId!, chapter, ancestors: ancestors),
          );
          added++;
        }
      }
      if (_current(generation)) {
        final removed = results.length > 1000 ? results.length - 1000 : 0;
        if (removed > 0) results.removeRange(0, removed);
        state = state.copy(
          results: List.unmodifiable(results),
          selected: _selection(results, selected),
          loading: false,
          hasMore: hasMore,
          resultOffset: state.resultOffset + removed,
        );
      }
    } on Object catch (error) {
      if (_current(generation)) {
        state = error is WorkspaceException && error.code == 'searchUnavailable'
            ? state.copy(
                loading: false,
                results: const [],
                selected: -1,
                hasMore: false,
                unavailable: 'source-unavailable',
              )
            : state.copy(loading: false, error: error.toString());
      }
    }
  }

  Future<void> showMore() async {
    if (state.loading || !state.hasMore || !ownsRoute) return;
    final generation = state.generation, selected = selectedResult?.identity;
    if (state.category == BookSearchCategory.bookText) {
      final reader = ref.read(readerControllerProvider.notifier);
      _windowLoading = true;
      try {
        await reader.loadSearchWindow(
          state.resultOffset + state.results.length,
        );
      } finally {
        _windowLoading = false;
      }
    } else {
      state = state.copy(loading: true);
      _running = _run(generation, selected, append: true);
      await _running;
    }
  }

  Future<bool> selectOccurrence(int delta) async {
    if (state.category != BookSearchCategory.bookText ||
        !await submit(requireSelection: false)) {
      return false;
    }
    final generation = state.generation,
        reader = ref.read(readerControllerProvider.notifier);
    final total = state.totalOccurrences ?? 0;
    if (total == 0) return false;
    final active = state.activeOccurrence;
    final target = active == null
        ? (delta < 0 ? total - 1 : 0)
        : (active + delta) % total;
    if (target < state.resultOffset ||
        target >= state.resultOffset + state.results.length) {
      _windowLoading = true;
      try {
        if (!await reader.loadSearchWindow(target)) return false;
      } finally {
        _windowLoading = false;
      }
    }
    if (!_current(generation)) return false;
    select(target - state.resultOffset);
    state = state.copy(activeOccurrence: target);
    return selectedResult is BookTextSearchResult;
  }

  void _publishActions() {
    final identity = selectedResult?.identity ?? _rememberedIdentity;
    final query = state.query.trim();
    final categories = _actions.map((a) => a.category).toSet().toList();
    int? rank(BookActionSearchResult a) => _commandRank(a, query);
    final results =
        _actions.where((a) => a.command.visible() && rank(a) != null).toList()
          ..sort((a, b) {
            final primary = query.isEmpty
                ? categories
                      .indexOf(a.category)
                      .compareTo(categories.indexOf(b.category))
                : rank(a)!.compareTo(rank(b)!);
            if (primary != 0) return primary;
            if (a.available != b.available) return a.available ? -1 : 1;
            final title = a.title.compareTo(b.title);
            return title != 0 ? title : a.identity.compareTo(b.identity);
          });
    state = state.copy(
      results: List.unmodifiable(results),
      selected: _selection(results, identity),
      loading: false,
    );
  }
}

// The same command ranking as BusyMark, using BusyBooks-owned metadata.
int? _commandRank(BookActionSearchResult action, String query) {
  final q = query.toLowerCase(), title = action.title.toLowerCase();
  if (q.isEmpty || title == q) return 0;
  if (title.startsWith(q)) return 1;
  final tokens = q.split(RegExp(r'\s+')),
      words = title.split(RegExp(r'[\s\p{P}]+', unicode: true));
  if (tokens.every((t) => words.any((w) => w.startsWith(t)))) return 2;
  if (title.contains(q)) return 3;
  final metadata =
      '$title ${action.category.toLowerCase()} ${action.description?.toLowerCase() ?? ''}';
  if (tokens.every(metadata.contains)) return 4;
  return action.identity.toLowerCase().contains(q) ? 5 : null;
}

class _ReaderRecovery {
  _ReaderRecovery(this.bookId, this.route, this.error);
  final String bookId, route, error;
  bool errorCleared = false, abandoned = false;
}

final bookSearchSessionProvider =
    NotifierProvider<BookSearchController, BookSearchState>(
      BookSearchController.new,
    );
