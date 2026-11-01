import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../annotations/domain/annotation_filter.dart';
import '../../app/app_settings.dart';
import '../../reading/application/reader_controller.dart';
import '../../reading/domain/publication_outline.dart';
import '../../workspace/workspace_controller.dart';
import 'book_session_lifetime.dart';

enum BookSidebarPanel {
  outline('outline'),
  thumbnails('thumbnails'),
  marks('annotations'),
  books('books');

  const BookSidebarPanel(this.preference);
  final String preference;
}

/// Book-owned navigation state. Renderer metadata is a retained snapshot, not
/// an authority for stored marks, filters, expansion, selection or visibility.
class BookSidebarState {
  const BookSidebarState({
    this.panel = BookSidebarPanel.outline,
    this.open = false,
    this.expanded = const {},
    this.knownBranches = const {},
    this.scroll = const {},
    this.focusedOutline,
    this.selectedAnnotation,
    this.filter = AnnotationTypeFilter.all,
    this.withNotes = false,
    this.reveal = 0,
    this.revealed = const {},
    this.outline = const PublicationOutline.empty(),
    this.outlineStatus = 'unavailable',
    this.pages = 0,
    this.labels = const [],
  });
  final BookSidebarPanel panel;
  final bool open, withNotes;
  final Set<String> expanded, knownBranches;
  final Map<String, double> scroll;
  final String? focusedOutline, selectedAnnotation;
  final AnnotationTypeFilter filter;
  final int reveal;
  final Map<String, int> revealed;
  final PublicationOutline outline;
  final String outlineStatus;
  final int pages;
  final List<String> labels;
  BookSidebarState copy({
    BookSidebarPanel? panel,
    bool? open,
    Set<String>? expanded,
    Set<String>? knownBranches,
    Map<String, double>? scroll,
    String? focusedOutline,
    String? selectedAnnotation,
    AnnotationTypeFilter? filter,
    bool? withNotes,
    int? reveal,
    Map<String, int>? revealed,
    PublicationOutline? outline,
    String? outlineStatus,
    int? pages,
    List<String>? labels,
  }) => BookSidebarState(
    panel: panel ?? this.panel,
    open: open ?? this.open,
    expanded: expanded ?? this.expanded,
    knownBranches: knownBranches ?? this.knownBranches,
    scroll: scroll ?? this.scroll,
    focusedOutline: focusedOutline ?? this.focusedOutline,
    selectedAnnotation: selectedAnnotation ?? this.selectedAnnotation,
    filter: filter ?? this.filter,
    withNotes: withNotes ?? this.withNotes,
    reveal: reveal ?? this.reveal,
    revealed: revealed ?? this.revealed,
    outline: outline ?? this.outline,
    outlineStatus: outlineStatus ?? this.outlineStatus,
    pages: pages ?? this.pages,
    labels: labels ?? this.labels,
  );
}

class BookSidebarController extends Notifier<BookSidebarState> {
  BookSidebarController(this.bookId);
  final String bookId;
  @override
  BookSidebarState build() {
    retainActiveBookSession(ref, bookId);
    final settings = ref.read(appSettingsControllerProvider).data;
    final panel = BookSidebarPanel.values
        .where((p) => p.preference == settings['readerPanel'])
        .firstOrNull;
    final book = ref.read(workspaceControllerProvider).bookById(bookId);
    final records = (book?.data['outline'] as List?)
        ?.map((r) => (r as Map).cast<String, dynamic>())
        .toList();
    final outline = records == null
        ? const PublicationOutline.empty()
        : PublicationOutline.fromRecords(records, pdf: book?.format == 'pdf');
    final branches = outline.ordered
        .where((n) => n.children.isNotEmpty)
        .map((n) => n.id)
        .toSet();
    ref.listen(workspaceControllerProvider.select((s) => s.bookById(bookId)), (
      _,
      book,
    ) {
      if (state.outlineStatus == 'unavailable' &&
          book?.data['outline'] is List) {
        publication(
          outline: PublicationOutline.fromRecords(
            (book!.data['outline'] as List)
                .map((r) => (r as Map).cast<String, dynamic>())
                .toList(),
            pdf: book.format == 'pdf',
          ),
          status: 'ready',
          pages: book.data['pages'] as int? ?? 0,
          labels:
              (book.data['pageLabels'] as List?)?.cast<String>() ?? const [],
        );
      }
    });
    return BookSidebarState(
      panel: panel ?? BookSidebarPanel.outline,
      open: settings['readerSidebar'] == true,
      outline: outline,
      outlineStatus: records == null ? 'unavailable' : 'ready',
      expanded: branches,
      knownBranches: branches,
      pages: book?.data['pages'] as int? ?? 0,
      labels: (book?.data['pageLabels'] as List?)?.cast<String>() ?? const [],
    );
  }

  bool available(BookSidebarPanel panel) => switch (panel) {
    BookSidebarPanel.thumbnails =>
      ref.read(workspaceControllerProvider).bookById(bookId)?.pageBased == true,
    BookSidebarPanel.books =>
      ref.read(workspaceControllerProvider).workspace?.isBook == false,
    _ => true,
  };
  Future<void> selectPanel(BookSidebarPanel panel) async {
    if (!available(panel)) return;
    final reader = ref.read(readerControllerProvider.notifier);
    if (reader.stateBookId == bookId && !await reader.prepareChromeChange()) {
      return;
    }
    if (!ref.mounted) return;
    state = state.copy(panel: panel, open: true);
    if (panel != BookSidebarPanel.thumbnails) {
      reader.requestThumbnailWindow(const []);
    }
    await _persist();
  }

  Future<void> toggleOpen() => setOpen(!state.open);
  Future<void> setOpen(bool open) async {
    final reader = ref.read(readerControllerProvider.notifier);
    if (reader.stateBookId == bookId && !await reader.prepareChromeChange()) {
      return;
    }
    if (!ref.mounted) return;
    state = state.copy(open: open);
    if (!open) reader.requestThumbnailWindow(const []);
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await ref.read(appSettingsControllerProvider.notifier).update({
        'readerSidebar': state.open,
        'readerPanel': state.panel.preference,
      });
    } catch (error) {
      debugPrint('Book sidebar preferences could not be saved: $error');
    }
  }

  void publication({
    required PublicationOutline outline,
    required String status,
    required int pages,
    required List<String> labels,
  }) {
    state = state.copy(
      outline: outline,
      outlineStatus: status,
      pages: pages,
      labels: labels,
    );
    reconcile(outline);
  }

  void reconcile(PublicationOutline outline) {
    final branches = outline.ordered
        .where((n) => n.children.isNotEmpty)
        .map((n) => n.id)
        .toSet();
    // BusyMark initially expands branches. Later metadata never reopens a branch
    // that the user has collapsed, including an initially unresolved destination.
    final added = branches.difference(state.knownBranches);
    if (added.isEmpty) return;
    state = state.copy(
      expanded: {...state.expanded, ...added},
      knownBranches: {...state.knownBranches, ...branches},
    );
  }

  void toggle(String id) {
    final next = {...state.expanded};
    if (!next.remove(id)) next.add(id);
    state = state.copy(expanded: next, focusedOutline: id);
  }

  void focus(String id) => state = state.copy(focusedOutline: id);
  void reveal() => state = state.copy(reveal: state.reveal + 1);
  void acknowledgeReveal(String panel, int revision) =>
      state = state.copy(revealed: {...state.revealed, panel: revision});
  void scrolled(String panel, double offset) {
    if (offset.isFinite && offset >= 0) {
      state = state.copy(scroll: {...state.scroll, panel: offset});
    }
  }

  void filter({AnnotationTypeFilter? type, bool? withNotes}) =>
      state = state.copy(filter: type, withNotes: withNotes);
  void selectAnnotation(String id) =>
      state = state.copy(selectedAnnotation: id);
}

final bookSidebarProvider = NotifierProvider.autoDispose
    .family<BookSidebarController, BookSidebarState, String>(
      BookSidebarController.new,
    );
