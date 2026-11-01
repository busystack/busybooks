import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/book.dart';

class CollectionViewState {
  const CollectionViewState({
    this.filter = 'all',
    this.selectedBook,
    this.scrollOffset = 0,
    this.sort = 'added',
    this.sidebarOpen = false,
  });
  final String filter, sort;
  final bool sidebarOpen;
  final String? selectedBook;
  final double scrollOffset;
}

/// Presentation session state belongs to a collection ID, never to the
/// global reading-data catalogue. Kept when the reader route replaces the grid.
class CollectionViewController extends Notifier<CollectionViewState> {
  CollectionViewController(this.path);
  final String path;
  @override
  CollectionViewState build() => const CollectionViewState();
  void update({
    String? filter,
    String? sort,
    String? selectedBook,
    double? scrollOffset,
    bool? sidebarOpen,
  }) {
    state = CollectionViewState(
      sidebarOpen: sidebarOpen ?? state.sidebarOpen,
      filter: filter ?? state.filter,
      sort: sort ?? state.sort,
      selectedBook: selectedBook ?? state.selectedBook,
      scrollOffset: scrollOffset ?? state.scrollOffset,
    );
  }
}

final collectionViewProvider =
    NotifierProvider.family<
      CollectionViewController,
      CollectionViewState,
      String
    >(CollectionViewController.new);

int compareCollectionBooks(Book a, Book b, String sort) => switch (sort) {
  'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  'author' => a.author.toLowerCase().compareTo(b.author.toLowerCase()),
  'series' =>
    a.series == b.series
        ? a.seriesOrder.compareTo(b.seriesOrder)
        : a.series.compareTo(b.series),
  'read' => b.read.compareTo(a.read),
  _ => ((b.data['membershipOrder'] as int?) ?? 0).compareTo(
    (a.data['membershipOrder'] as int?) ?? 0,
  ),
};
