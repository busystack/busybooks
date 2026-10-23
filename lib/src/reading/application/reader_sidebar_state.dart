import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/publication_outline.dart';

/// Retained, per-content-identity view state. No additional disk authority.
class ReaderSidebarState {
  const ReaderSidebarState({
    this.panel,
    this.open,
    this.expanded = const {},
    this.knownBranches = const {},
    this.scroll = const {},
    this.focusedOutline,
    this.selectedAnnotation,
    this.filter = 'all',
    this.withNotes = false,
    this.query = '',
    this.matches = const [],
    this.currentMatch = -1,
    this.searchVisible = false,
    this.reveal = 0,
    this.revealed = const {},
  });
  final String? panel, focusedOutline, selectedAnnotation;
  final bool? open;
  final Set<String> expanded, knownBranches;
  final Map<String, double> scroll;
  final String filter, query;
  final List<Map<String, dynamic>> matches;
  final int currentMatch, reveal;
  final Map<String, int> revealed;
  final bool withNotes, searchVisible;
  ReaderSidebarState copy({
    String? panel,
    bool? open,
    Set<String>? expanded,
    Set<String>? knownBranches,
    Map<String, double>? scroll,
    String? focusedOutline,
    String? selectedAnnotation,
    String? filter,
    bool? withNotes,
    String? query,
    List<Map<String, dynamic>>? matches,
    int? currentMatch,
    bool? searchVisible,
    int? reveal,
    Map<String, int>? revealed,
  }) => ReaderSidebarState(
    panel: panel ?? this.panel,
    open: open ?? this.open,
    expanded: expanded ?? this.expanded,
    knownBranches: knownBranches ?? this.knownBranches,
    scroll: scroll ?? this.scroll,
    focusedOutline: focusedOutline ?? this.focusedOutline,
    selectedAnnotation: selectedAnnotation ?? this.selectedAnnotation,
    filter: filter ?? this.filter,
    withNotes: withNotes ?? this.withNotes,
    query: query ?? this.query,
    matches: matches ?? this.matches,
    currentMatch: currentMatch ?? this.currentMatch,
    searchVisible: searchVisible ?? this.searchVisible,
    reveal: reveal ?? this.reveal,
    revealed: revealed ?? this.revealed,
  );
}

class ReaderSidebarController extends Notifier<ReaderSidebarState> {
  @override
  ReaderSidebarState build() => const ReaderSidebarState();
  void remember({
    String? panel,
    bool? open,
    String? query,
    List<Map<String, dynamic>>? matches,
    int? currentMatch,
    bool? searchVisible,
  }) {
    state = state.copy(
      panel: panel,
      open: open,
      query: query,
      matches: matches,
      currentMatch: currentMatch,
      searchVisible: searchVisible,
    );
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

  void filter({String? kind, bool? withNotes}) =>
      state = state.copy(filter: kind, withNotes: withNotes);
  void selectAnnotation(String id) =>
      state = state.copy(selectedAnnotation: id);
}

final readerSidebarProvider =
    NotifierProvider.family<
      ReaderSidebarController,
      ReaderSidebarState,
      String
    >((id) => ReaderSidebarController());
