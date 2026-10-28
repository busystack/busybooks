import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/search/book_search_session.dart';
import 'package:busybooks/src/search/book_search_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'metadata rows retain matches in historical paths and clipped fields',
    () {
      final owner = Book({
        'id': 'owner',
        'title': 'Short display title',
        'author': 'Author',
        'format': 'pdf',
        'path': '/current/book.pdf',
      });
      final historical = BookMetadataSearchResult(
        owner,
        match: {'field': 'path', 'text': '/old/retained_%.*.pdf'},
      );
      expect(
        bookMetadataSearchContext(historical, 'retained_%.*'),
        contains('/old/retained_%.*.pdf'),
      );
      final clipped = BookMetadataSearchResult(
        owner,
        match: {'field': 'title', 'text': '…Unicode 東京 at the end…'},
      );
      expect(
        bookMetadataSearchContext(clipped, '東京'),
        contains('Unicode 東京 at the end'),
      );
      expect(
        bookMetadataSearchContext(clipped, 'Author'),
        isNot(contains('Unicode 東京')),
      );
    },
  );
}
