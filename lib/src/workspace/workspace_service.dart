import '../library/data/library_store.dart';
import '../library/domain/book.dart';
import 'workspace_model.dart';

class WorkspaceService {
  const WorkspaceService(this.store);
  final ReadingDataStore store;
  Workspace _workspace(dynamic value) =>
      Workspace((value as Map).cast<String, dynamic>());
  Future<Workspace> openPath(
    String path, {
    String? expectedId,
    String? expectedKind,
    bool acceptChanged = false,
  }) async => _workspace(
    await store.call('openPath', {
      'path': path,
      'expectedId': expectedId,
      'acceptChanged': acceptChanged,
    }),
  );
  Future<Workspace> openCollection(
    String id, {
    bool recordRecent = true,
  }) async => _workspace(
    await store.call('openCollection', {
      'id': id,
      'recordRecent': recordRecent,
    }),
  );
  Future<Workspace> createCollection(String name) async =>
      _workspace(await store.call('createCollection', {'name': name}));
  Future<Book> openMember(Book book) async => Book(
    (await store.call('openMember', {'path': book.path, 'id': book.id}) as Map)
        .cast<String, dynamic>(),
  );
  Future<Map<String, dynamic>> addBooks(
    Workspace workspace,
    List<String> paths,
  ) async =>
      (await store.call('addBooks', {
                'collectionId': workspace.id,
                'paths': paths,
              })
              as Map)
          .cast<String, dynamic>();
  Future<Workspace> removeBook(Workspace workspace, Book book) async =>
      _workspace(
        await store.call('removeBook', {
          'collectionId': workspace.id,
          'bookId': book.id,
        }),
      );
  Future<Book> relocate(String id, String path) async => Book(
    (await store.call('relocate', {'id': id, 'path': path}) as Map)
        .cast<String, dynamic>(),
  );
}
