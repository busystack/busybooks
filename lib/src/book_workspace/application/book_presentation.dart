import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum BookView {
  reading('read'),
  notebook('notebook'),
  split('split');

  const BookView(this.routeSegment);
  final String routeSegment;

  bool get hasReader => this != notebook;
  bool get hasNotebook => this != reading;
  String routeFor(String bookId) => '/$routeSegment/$bookId';
}

BookView? bookViewForRoute(String path) {
  final parts = path.split('/');
  if (parts.length != 3 || parts.first.isNotEmpty || parts.last.isEmpty) {
    return null;
  }
  return BookView.values
      .where((view) => view.routeSegment == parts[1])
      .firstOrNull;
}

String? bookIdForRoute(String path) =>
    bookViewForRoute(path) == null ? null : path.split('/').last;

/// Passage and note handoffs preserve an originating Split workspace. Explicit
/// view commands supply [view] to choose the full-width Reading or Notebook.
String readingTargetRoute(String originPath, String bookId, {BookView? view}) {
  final target =
      view ??
      (bookViewForRoute(originPath) == BookView.split
          ? BookView.split
          : BookView.reading);
  if (!target.hasReader) throw ArgumentError.value(target, 'view');
  return target.routeFor(bookId);
}

String notebookTargetRoute(String originPath, String bookId, {BookView? view}) {
  final target =
      view ??
      (bookViewForRoute(originPath) == BookView.split
          ? BookView.split
          : BookView.notebook);
  if (!target.hasNotebook) throw ArgumentError.value(target, 'view');
  return target.routeFor(bookId);
}

bool sameReaderBookRoutes(String first, String second) =>
    bookViewForRoute(first)?.hasReader == true &&
    bookViewForRoute(second)?.hasReader == true &&
    bookIdForRoute(first) == bookIdForRoute(second);

enum BookPane { reading, notebook }

const bookSplitDividerWidth = 12.0;

/// Logical pane limits apply to the measured content area after the sidebar.
class BookSplitMetrics {
  BookSplitMetrics(double textScale)
    : textScale = textScale.isFinite ? math.max(1.0, textScale) : 1.0;
  final double textScale;
  double get minimumReadingWidth => math.max(400.0, 320.0 * textScale);
  double get minimumNotebookWidth => math.max(360.0, 280.0 * textScale + 64.0);
  double get dividerWidth => bookSplitDividerWidth;
  double get minimumWidth =>
      minimumReadingWidth + minimumNotebookWidth + dividerWidth;
}

/// Lightweight window-session presentation memory. Reading and Notebook own
/// their existing content/controllers; this state owns neither content tree.
class BookPresentationState {
  const BookPresentationState({
    this.bookId,
    this.dividerRatio = .5,
    this.lastPane = BookPane.reading,
    this.availableWidth,
    this.textScale = 1,
  });
  final String? bookId;
  final double dividerRatio;
  final BookPane lastPane;
  final double? availableWidth;
  final double textScale;
  BookSplitMetrics get splitMetrics => BookSplitMetrics(textScale);
  bool get splitAvailable =>
      availableWidth != null && availableWidth! >= splitMetrics.minimumWidth;
}

final bookPresentationProvider =
    NotifierProvider<BookPresentationController, BookPresentationState>(
      BookPresentationController.new,
    );

class BookPresentationController extends Notifier<BookPresentationState> {
  @override
  BookPresentationState build() => const BookPresentationState();

  void enterBook(String bookId, BookView view) {
    final pane = switch (view) {
      BookView.reading => BookPane.reading,
      BookView.notebook => BookPane.notebook,
      BookView.split =>
        state.bookId == bookId ? state.lastPane : BookPane.reading,
    };
    if (state.bookId == bookId && state.lastPane == pane) return;
    state = BookPresentationState(
      bookId: bookId,
      dividerRatio: state.dividerRatio,
      lastPane: pane,
      availableWidth: state.bookId == bookId ? state.availableWidth : null,
      textScale: state.textScale,
    );
  }

  void focusPane(String bookId, BookPane pane) {
    if (state.bookId != bookId || state.lastPane == pane) return;
    state = BookPresentationState(
      bookId: bookId,
      dividerRatio: state.dividerRatio,
      lastPane: pane,
      availableWidth: state.availableWidth,
      textScale: state.textScale,
    );
  }

  void setDividerRatio(String bookId, double ratio) {
    if (state.bookId != bookId || !ratio.isFinite) return;
    final value = ratio.clamp(0.0, 1.0).toDouble();
    if (value == state.dividerRatio) return;
    state = BookPresentationState(
      bookId: bookId,
      dividerRatio: value,
      lastPane: state.lastPane,
      availableWidth: state.availableWidth,
      textScale: state.textScale,
    );
  }

  void updateLayout(
    String bookId, {
    required double availableWidth,
    required double textScale,
  }) {
    if (state.bookId != bookId ||
        !availableWidth.isFinite ||
        availableWidth < 0) {
      return;
    }
    final scale = BookSplitMetrics(textScale).textScale;
    if (state.availableWidth == availableWidth && state.textScale == scale) {
      return;
    }
    state = BookPresentationState(
      bookId: bookId,
      dividerRatio: state.dividerRatio,
      lastPane: state.lastPane,
      availableWidth: availableWidth,
      textScale: scale,
    );
  }
}
