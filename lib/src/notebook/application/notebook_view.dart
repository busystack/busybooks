import '../../annotations/domain/annotation_order.dart';
import '../../library/domain/book.dart';

enum NotebookSort { recentlyAdded, bookOrder, type }

int compareNotebookAnnotations(
  ReadingAnnotation a,
  ReadingAnnotation b,
  NotebookSort sort,
) {
  final order = switch (sort) {
    NotebookSort.recentlyAdded => (b.data['created'] as int).compareTo(
      a.data['created'] as int,
    ),
    NotebookSort.bookOrder => compareAnnotationLocations(a.data, b.data),
    NotebookSort.type => a.kind.compareTo(b.kind),
  };
  if (order != 0) return order;
  if (sort == NotebookSort.type) {
    final recent = (b.data['created'] as int).compareTo(
      a.data['created'] as int,
    );
    if (recent != 0) return recent;
  }
  return a.id.compareTo(b.id);
}
