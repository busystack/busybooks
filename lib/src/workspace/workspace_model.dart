import '../library/domain/book.dart';

enum WorkspaceKind { book, collection }

// Books and database collections share the BusyMark workspace shell.
class Workspace {
  Workspace(this.data);
  final Map<String, dynamic> data;
  String get path => data['path'] as String? ?? '';
  String get id => data['id'] as String;
  String get name => data['name'] as String;
  WorkspaceKind get kind => WorkspaceKind.values.byName(data['kind'] as String);
  bool get isBook => kind == WorkspaceKind.book;
  bool get editable => kind == WorkspaceKind.collection;
  List<Book> get books => (data['books'] as List)
      .map((b) => Book((b as Map).cast<String, dynamic>()))
      .toList();
}

class RecentResource {
  RecentResource(this.data);
  final Map<String, dynamic> data;
  String get path => data['path'] as String? ?? '';
  String get resourceId => data['resourceId'] as String;
  String get title => data['title'] as String;
  String get kind => data['resourceKind'] as String;
  String? get bookId => isBook ? resourceId : null;
  bool get isBook => kind == 'book';
}

class WorkspaceException implements Exception {
  const WorkspaceException(this.code, this.path, this.message, {this.bookId});
  final String code, path, message;
  final String? bookId;
  Map<String, dynamic> toJson() => {
    'code': code,
    'path': path,
    'message': message,
    'bookId': bookId,
  };
  factory WorkspaceException.fromJson(Map value) => WorkspaceException(
    value['code'] as String,
    value['path'] as String,
    value['message'] as String,
    bookId: value['bookId'] as String?,
  );
  @override
  String toString() => '$message\n$path';
}
