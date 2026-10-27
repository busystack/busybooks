import '../../library/domain/book.dart';

enum AnnotationTypeFilter {
  all(null),
  highlights('highlight'),
  bookmarks('bookmark'),
  regions('region');

  const AnnotationTypeFilter(this.kind);
  final String? kind;
  bool includes(ReadingAnnotation annotation) =>
      kind == null || annotation.kind == kind;
}
