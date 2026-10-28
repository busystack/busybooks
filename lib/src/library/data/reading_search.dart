/// Literal content matching uses the same Unicode, case-insensitive expression
/// contract as BusyMark's source matcher. Escaping preserves punctuation and
/// whitespace; ranges always address the original UTF-16 text.
class ReadingSearchMatcher {
  ReadingSearchMatcher(String query)
    : expression = query.isEmpty
          ? null
          : RegExp(RegExp.escape(query), caseSensitive: false, unicode: true);

  final RegExp? expression;

  Map<String, dynamic>? first(Map<String, String> fields) {
    for (final entry in fields.entries) {
      final match = expression?.firstMatch(entry.value);
      if (match != null) {
        return {'field': entry.key, 'start': match.start, 'end': match.end};
      }
    }
    return null;
  }
}

/// An excerpt and its emphasis refer to source coordinates before clipping.
/// Never split a supplementary character at a preview boundary.
Map<String, dynamic> readingSearchExcerpt(String text, int start, int end) {
  int safe(int offset) {
    if (offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset - 1) >= 0xd800 &&
        text.codeUnitAt(offset - 1) <= 0xdbff &&
        text.codeUnitAt(offset) >= 0xdc00 &&
        text.codeUnitAt(offset) <= 0xdfff) {
      return offset - 1;
    }
    return offset;
  }

  final from = safe((start - 80).clamp(0, text.length));
  final matchEnd = safe((start + 256).clamp(start, end));
  final to = safe((end + 80).clamp(0, text.length));
  final parts = {
    'before': '${from > 0 ? '…' : ''}${text.substring(from, start)}',
    'match': '${text.substring(start, matchEnd)}${matchEnd < end ? '…' : ''}',
    'after': '${text.substring(end, to)}${to < text.length ? '…' : ''}',
  };
  return {
    'text': parts.values.join(),
    'excerptStart': from,
    'excerptParts': parts,
    'truncated': from > 0 || matchEnd < end || to < text.length,
  };
}

String readingSearchSummary(String text, {int limit = 240}) {
  if (text.length <= limit) return text;
  var end = limit;
  if (text.codeUnitAt(end - 1) >= 0xd800 &&
      text.codeUnitAt(end - 1) <= 0xdbff &&
      text.codeUnitAt(end) >= 0xdc00 &&
      text.codeUnitAt(end) <= 0xdfff) {
    end--;
  }
  return '${text.substring(0, end)}…';
}
