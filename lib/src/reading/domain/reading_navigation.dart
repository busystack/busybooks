/// A bare integer always means a physical page (1-based). Non-numeric labels
/// resolve exactly; =label explicitly selects a numeric or otherwise ambiguous
/// printed label. Repeated labels never choose an arbitrary page.
int? resolvePageDestination(
  String input, {
  required int pages,
  required List<String> labels,
}) {
  final text = input.trim();
  if (text.startsWith('=')) {
    return resolvePdfPage(
      text.substring(1),
      pages: pages,
      labels: labels,
      printedLabel: true,
    );
  }
  if (int.tryParse(text) != null) {
    return resolvePdfPage(
      text,
      pages: pages,
      labels: labels,
      printedLabel: false,
    );
  }
  return resolvePdfPage(text, pages: pages, labels: labels, printedLabel: true);
}

/// Validate user-facing PDF coordinates without accepting renderer identifiers.
int? resolvePdfPage(
  String input, {
  required int pages,
  required List<String> labels,
  required bool printedLabel,
}) {
  final text = input.trim();
  if (printedLabel) {
    // A repeated printed label is ambiguous. Physical page entry is always available.
    final matches = [
      for (var i = 0; i < labels.length && i < pages; i++)
        if (labels[i] == text) i,
    ];
    return text.isNotEmpty && matches.length == 1 ? matches.single : null;
  }
  final number = int.tryParse(text);
  return number != null && number >= 1 && number <= pages ? number - 1 : null;
}

bool sameBookmarkLocation(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a['page'] is int && b['page'] is int) return a['page'] == b['page'];
  return a['cfi'] is String && a['cfi'] == b['cfi'];
}
