import 'package:busybooks/src/annotations/presentation/annotation_presentation.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/notebook/application/notebook_view.dart';
import 'package:flutter_test/flutter_test.dart';

ReadingAnnotation record(
  String id,
  int created,
  int page, {
  String kind = 'highlight',
}) => ReadingAnnotation({
  'id': id,
  'created': created,
  'anchor': {'page': page},
  'annotationKind': kind,
});
void main() {
  test('Notebook creation dates preserve epoch microseconds', () {
    final created = DateTime.utc(2026, 10, 26, 14, 13, 8, 529, 698);
    final annotation = record(
      'native-created',
      created.microsecondsSinceEpoch,
      0,
    );
    expect(annotationCreationTime(annotation)?.toUtc(), created);
    expect(annotation.data['created'], created.microsecondsSinceEpoch);
  });
  test(
    'valid stored timestamps outside DateTime retain order without inventing a date',
    () {
      expect(
        annotationCreationTime(record('valid', 0, 0)),
        DateTime.fromMicrosecondsSinceEpoch(0),
      );
      expect(
        annotationCreationTime(record('beyond-date', 9223372036854775807, 0)),
        isNull,
      );
      expect(
        compareNotebookAnnotations(
          record('new', 9223372036854775807, 0),
          record('old', 0, 0),
          NotebookSort.recentlyAdded,
        ),
        lessThan(0),
      );
    },
  );
  test(
    'Notebook defaults to newest creation with deterministic identity ties',
    () {
      final records = [
        record('b', 10, 0),
        record('a', 10, 2),
        record('c', 20, 1),
      ];
      records.sort(
        (a, b) => compareNotebookAnnotations(a, b, NotebookSort.recentlyAdded),
      );
      expect(records.map((a) => a.id), ['c', 'a', 'b']);
      records.sort(
        (a, b) => compareNotebookAnnotations(a, b, NotebookSort.bookOrder),
      );
      expect(records.map((a) => a.id), ['b', 'c', 'a']);
    },
  );
  test('Type sorting is stable and newest-first within each type', () {
    final records = [
      record('a', 10, 0, kind: 'bookmark'),
      record('b', 20, 1, kind: 'bookmark'),
      record('c', 40, 2, kind: 'region'),
      record('d', 30, 3),
    ];
    records.sort((a, b) => compareNotebookAnnotations(a, b, NotebookSort.type));
    expect(records.map((a) => a.id), ['b', 'a', 'd', 'c']);
  });
}
