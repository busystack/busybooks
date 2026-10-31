import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../library/data/library_store.dart';
import '../library/domain/book.dart';
import '../notebook/application/notebook_controller.dart';
import 'workspace_model.dart';
import 'workspace_service.dart';

final readingDataStoreProvider = Provider<ReadingDataStore>(
  (ref) => throw StateError('Reading data store was not injected'),
);
final workspaceServiceProvider = Provider<WorkspaceService>(
  (ref) => WorkspaceService(ref.read(readingDataStoreProvider)),
);

class WorkspaceState {
  const WorkspaceState({
    this.workspace,
    this.openedBook,
    this.readingData = const {},
    this.annotations = const [],
    this.recent = const [],
    this.collections = const [],
    this.moves = const [],
    this.loading = false,
    this.error,
    this.progress = const {},
  });
  final Workspace? workspace;
  final Book? openedBook;
  final Map<String, Book> readingData;
  final List<ReadingAnnotation> annotations;
  final List<RecentResource> recent;
  final List<Map<String, dynamic>> collections, moves;
  final bool loading;
  final String? error;
  final Map<String, dynamic> progress;
  Book merge(Book book) => Book({
    ...book.data,
    ...?readingData[book.id]?.data,
    if (book.data.containsKey('membershipOrder'))
      'membershipOrder': book.data['membershipOrder'],
  });
  List<Book> get books => workspace?.books.map(merge).toList() ?? [];
  Book? bookById(String? id) => id == null
      ? null
      : readingData[id] ?? (openedBook?.id == id ? openedBook : null);
  WorkspaceState copy({
    Workspace? workspace,
    Book? openedBook,
    bool clearWorkspace = false,
    bool clearBook = false,
    Map<String, Book>? readingData,
    List<ReadingAnnotation>? annotations,
    List<RecentResource>? recent,
    List<Map<String, dynamic>>? collections,
    List<Map<String, dynamic>>? moves,
    bool? loading,
    String? error,
    bool clearError = false,
    Map<String, dynamic>? progress,
  }) => WorkspaceState(
    workspace: clearWorkspace ? null : workspace ?? this.workspace,
    openedBook: clearBook ? null : openedBook ?? this.openedBook,
    readingData: readingData ?? this.readingData,
    annotations: annotations ?? this.annotations,
    recent: recent ?? this.recent,
    collections: collections ?? this.collections,
    moves: moves ?? this.moves,
    loading: loading ?? this.loading,
    error: clearError ? null : error ?? this.error,
    progress: progress ?? this.progress,
  );
}

class WorkspaceController extends Notifier<WorkspaceState> {
  Future<void> _tail = Future.value(), _navigation = Future.value();
  int _availabilityRevision = 0;
  ReadingDataStore get store => ref.read(readingDataStoreProvider);
  WorkspaceService get service => ref.read(workspaceServiceProvider);
  Future<T> navigate<T>(Future<T> Function() action) {
    final next = _navigation.then((_) => action());
    _navigation = next.then<void>((_) {}).catchError((Object _) {});
    return next;
  }

  @override
  WorkspaceState build() {
    final subscription = store.progress.listen((p) {
      if (ref.mounted) state = state.copy(progress: p);
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    Future.microtask(() => refresh().catchError((Object _) {}));
    return const WorkspaceState();
  }

  Future<T> _perform<T>(
    Future<T> Function() body, {
    bool loading = false,
    bool publishError = true,
  }) {
    final operation = _tail.then((_) async {
      if (loading) {
        state = state.copy(loading: true, progress: {}, clearError: true);
      }
      try {
        return await body();
      } finally {
        if (loading && ref.mounted) state = state.copy(loading: false);
      }
    });
    _tail = operation.then<void>((_) {}).catchError((Object error) {
      if (publishError && ref.mounted) {
        state = state.copy(error: error.toString());
      }
    });
    return operation;
  }

  Future<void> _refresh() async {
    final data = await store.call('snapshot') as Map;
    if (!ref.mounted) return;
    state = state.copy(
      moves: (data['moves'] as List)
          .map((m) => (m as Map).cast<String, dynamic>())
          .toList(),
      recent: (data['recent'] as List)
          .map((r) => RecentResource((r as Map).cast<String, dynamic>()))
          .toList(),
      collections: (data['collections'] as List)
          .map((r) => (r as Map).cast<String, dynamic>())
          .toList(),
    );
  }

  Future<void> afterRestore() => _perform(() async {
    _availabilityRevision++;
    state = state.copy(
      clearWorkspace: true,
      clearBook: true,
      readingData: {},
      annotations: [],
      clearError: true,
    );
    await _refresh();
  });
  Future<void> refresh() => _perform(_refresh);
  Future<Workspace> preparePath(
    String path, {
    String? expectedId,
    String? expectedKind,
    bool acceptChanged = false,
  }) => _perform(
    () => service.openPath(
      path,
      expectedId: expectedId,
      acceptChanged: acceptChanged,
    ),
    loading: true,
  );
  Future<Workspace> prepareCollection(String name) =>
      _perform(() => service.createCollection(name), loading: true);
  Future<void> createCollection(String name) async =>
      activateWorkspace(await prepareCollection(name));
  Future<void> openCollection(String id) async => activateWorkspace(
    await _perform(() => service.openCollection(id), loading: true),
  );
  Future<Workspace> openPath(
    String path, {
    String? expectedId,
    String? expectedKind,
    bool acceptChanged = false,
  }) async {
    final workspace = await preparePath(
      path,
      expectedId: expectedId,
      acceptChanged: acceptChanged,
    );
    await activateWorkspace(workspace);
    return workspace;
  }

  void _cacheBooks(Iterable<Book> books) {
    final values = books.toList();
    state = state.copy(
      readingData: {...state.readingData, for (final b in values) b.id: b},
    );
    final workspace = state.workspace;
    if (workspace?.isBook == true) {
      final book = values.where((b) => b.id == workspace!.id).firstOrNull;
      if (book != null) {
        state = state.copy(
          workspace: Workspace({
            'id': book.id,
            'kind': 'book',
            'path': book.path,
            'name': book.title,
            'books': [book.data],
          }),
        );
      }
    }
  }

  Future<void> activateWorkspace(Workspace workspace) => _perform(() async {
    _availabilityRevision++;
    state = state.copy(
      workspace: workspace,
      openedBook: workspace.isBook ? workspace.books.single : null,
      clearBook: !workspace.isBook,
    );
    _cacheBooks(workspace.books);
    await _refresh();
    if (workspace.isBook) {
      await _loadAnnotations(workspace.books.single.id);
    } else {
      unawaited(_checkAvailability(workspace));
    }
  });
  Future<void> _checkAvailability(Workspace workspace) async {
    final revision = _availabilityRevision;
    for (var start = 0; start < workspace.books.length; start += 64) {
      if (!ref.mounted || revision != _availabilityRevision) return;
      final chunk = workspace.books
          .skip(start)
          .take(64)
          .map((b) => b.id)
          .toList();
      final values = await store.call('availability', chunk) as List;
      if (!ref.mounted || revision != _availabilityRevision) return;
      _cacheBooks(values.map((b) => Book((b as Map).cast<String, dynamic>())));
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<Book> prepareBook(Book book) =>
      _perform(() => service.openMember(book), loading: true);
  Future<Book> loadBook(
    String id, {
    bool activate = false,
    bool Function()? isCurrent,
  }) => _perform(() async {
    final book = Book(
      (await store.call('book', id) as Map).cast<String, dynamic>(),
    );
    if (isCurrent != null && !isCurrent()) return book;
    _cacheBooks([book]);
    if (activate) {
      state = state.copy(
        openedBook: book,
        workspace: state.workspace == null || state.workspace!.isBook
            ? Workspace({
                'id': book.id,
                'kind': 'book',
                'path': book.path,
                'name': book.title,
                'books': [book.data],
              })
            : null,
      );
    }
    await _loadAnnotations(id);
    return book;
  });
  Future<void> activateBook(Book book) => _perform(() async {
    final standalone = state.workspace == null || state.workspace!.isBook;
    state = state.copy(
      openedBook: book,
      workspace: standalone
          ? Workspace({
              'id': book.id,
              'kind': 'book',
              'path': book.path,
              'name': book.title,
              'books': [book.data],
            })
          : null,
    );
    _cacheBooks([book]);
    await _loadAnnotations(book.id);
    await _refresh();
  });
  Future<void> openBook(Book book) async =>
      activateBook(await prepareBook(book));
  Future<void> _loadAnnotations(String id) async {
    final values = await store.call('annotations', id) as List;
    state = state.copy(
      annotations: [
        ...state.annotations.where((a) => a.bookId != id),
        ...values.map(
          (a) => ReadingAnnotation((a as Map).cast<String, dynamic>()),
        ),
      ],
    );
  }

  Future<void> refreshWorkspace() => _perform(() async {
    final workspace = state.workspace;
    if (workspace != null && !workspace.isBook) {
      final next = await service.openCollection(
        workspace.id,
        recordRecent: false,
      );
      state = state.copy(workspace: next);
      _cacheBooks(next.books);
      unawaited(_checkAvailability(next));
    }
    await _refresh();
  }, loading: true);
  Future<List<Map<String, dynamic>>> addBooks(List<String> paths) =>
      _perform(() async {
        final result = await service.addBooks(state.workspace!, paths);
        final workspace = Workspace(
          (result['workspace'] as Map).cast<String, dynamic>(),
        );
        state = state.copy(workspace: workspace);
        _cacheBooks(workspace.books);
        unawaited(_checkAvailability(workspace));
        await _refresh();
        return (result['results'] as List)
            .map((r) => (r as Map).cast<String, dynamic>())
            .toList();
      }, loading: true);
  Future<void> removeBook(Book book) => _perform(() async {
    state = state.copy(
      workspace: await service.removeBook(state.workspace!, book),
    );
  });
  Future<void> renameCollection(String id, String name) => _perform(() async {
    final workspace = Workspace(
      (await store.call('renameCollection', {'id': id, 'name': name}) as Map)
          .cast<String, dynamic>(),
    );
    if (state.workspace?.id == id) state = state.copy(workspace: workspace);
    await _refresh();
  });
  Future<void> deleteCollection(String id) => _perform(() async {
    await store.call('deleteCollection', id);
    if (state.workspace?.id == id) {
      state = state.copy(clearWorkspace: true, clearBook: true);
    }
    await _refresh();
  });
  Future<Book> relocate(String id, String path, {Book? entry}) =>
      _perform(() async {
        final book = await service.relocate(id, path);
        _cacheBooks([book]);
        if (state.openedBook?.id == id) state = state.copy(openedBook: book);
        await _refresh();
        return book;
      }, loading: true);
  Future<Book> moveBook(Book selected, String destination) =>
      _perform(() async {
        String? moveStatus;
        late Book book;
        try {
          final result =
              await store.call('moveBook', {
                    'id': selected.id,
                    'source': selected.path,
                    'destination': destination,
                  })
                  as Map;
          moveStatus = result['status'] as String;
        } finally {
          await _refresh();
          book = Book(
            (await store.call('book', selected.id) as Map)
                .cast<String, dynamic>(),
          );
          _cacheBooks([book]);
        }
        return book.copy({'moveStatus': moveStatus});
      }, loading: true);
  Future<void> dismissMove(String id) => _perform(() async {
    await store.call('dismissMove', id);
    await _refresh();
  }, loading: true);
  Future<void> recordBookOpen(String id) => _perform(() async {
    await store.call('touchBook', id);
    await _refresh();
  });
  Future<void> forgetRecent(RecentResource resource) => _perform(() async {
    await store.call('forgetRecent', {
      'kind': resource.kind,
      'id': resource.resourceId,
    });
    await _refresh();
  });
  void cancel() => store.cancel();
  Future<void> closeWorkspace() => _perform(() async {
    _availabilityRevision++;
    state = state.copy(clearWorkspace: true, clearBook: true);
  });
  Future<void> updateBook(String id, Map<String, dynamic> changes) =>
      _perform(() async {
        final value =
            (await store.call('updateBook', {'id': id, 'changes': changes})
                    as Map)
                .cast<String, dynamic>();
        _cacheBooks([
          Book({...?state.bookById(id)?.data, ...value}),
        ]);
      });
  Future<ReadingAnnotation> readAnnotation(
    String id, {
    required String bookId,
  }) async {
    final repository = store;
    await _tail;
    return ReadingAnnotation(
      (await repository.call('annotation', {'id': id, 'bookId': bookId}) as Map)
          .cast<String, dynamic>(),
    );
  }

  // Drafts and annotation actions own these failures. Returning the error keeps
  // their retry/transaction contracts without publishing private SQL on Home.
  Future<void> saveAnnotation(ReadingAnnotation annotation) =>
      _perform(() async {
        await store.call('putAnnotation', annotation.data);
        state = state.copy(
          annotations: [
            for (final a in state.annotations)
              if (a.id != annotation.id) a,
            annotation,
          ],
        );
      }, publishError: false);
  Future<void> updateAnnotation(
    String id,
    Map<String, dynamic> changes, {
    required String bookId,
  }) => _perform(() async {
    final value = ReadingAnnotation(
      (await store.call('updateAnnotation', {
                'id': id,
                'bookId': bookId,
                'changes': changes,
              })
              as Map)
          .cast<String, dynamic>(),
    );
    state = state.copy(
      annotations: [
        for (final a in state.annotations)
          if (a.id == id) value else a,
      ],
    );
  }, publishError: false);
  Future<void> deleteAnnotation(
    String id, {
    Future<bool> Function()? confirm,
    int? discardedCreationRevision,
  }) => ref
      .read(notebookControllerProvider.notifier)
      .delete(
        id,
        () => _perform(() async {
          await store.call('deleteAnnotation', id);
          state = state.copy(
            annotations: state.annotations.where((a) => a.id != id).toList(),
          );
        }, publishError: false),
        confirm: confirm,
        discardedCreationRevision: discardedCreationRevision,
      );
  Future<void> flush() async {
    await _tail;
    await store.call('flush');
  }
}

final workspaceControllerProvider =
    NotifierProvider<WorkspaceController, WorkspaceState>(
      WorkspaceController.new,
    );
