// The same ordering is used by the sidebar and portable annotation export.
int compareAnnotationLocations(Map first, Map second) {
  final a = first['anchor'] as Map, b = second['anchor'] as Map;
  final page = ((a['page'] ?? a['index'] ?? 0) as num).compareTo(
    (b['page'] ?? b['index'] ?? 0) as num,
  );
  if (page != 0) return page;
  if (a['kind'] == 'comic' && b['kind'] == 'comic') {
    final ra = a['region'] as List?, rb = b['region'] as List?;
    if (ra == null && rb != null) return -1;
    if (ra != null && rb == null) return 1;
    if (ra != null && rb != null) {
      final vertical = (ra[1] as num).compareTo(rb[1] as num);
      if (vertical != 0) return vertical;
      final horizontal = (ra[0] as num).compareTo(rb[0] as num);
      if (horizontal != 0) return horizontal;
    }
  }
  if (a['page'] != null && b['page'] != null) {
    final left = (a['segments'] as List?)?.firstOrNull as Map?;
    final right = (b['segments'] as List?)?.firstOrNull as Map?;
    if (left != null && right != null) {
      final offset = ((left['start'] ?? 0) as num).compareTo(
        (right['start'] ?? 0) as num,
      );
      if (offset != 0) return offset;
    } else {
      num top(Map anchor, Map? segment) {
        final boxes = segment?['boxes'] as List?;
        if (boxes?.isNotEmpty == true) return (boxes!.first as List)[1] as num;
        return (anchor['point'] as List?)?[1] as num? ?? double.infinity;
      }

      final position = top(b, right).compareTo(top(a, left));
      if (position != 0) return position;
    }
  }
  for (final end in [false, true]) {
    final left = _cfiSteps(a['cfi'] as String? ?? '', end),
        right = _cfiSteps(b['cfi'] as String? ?? '', end);
    for (var index = 0; index < left.length && index < right.length; index++) {
      final order = left[index].compareTo(right[index]);
      if (order != 0) return order;
    }
    final length = left.length.compareTo(right.length);
    if (length != 0) return length;
  }
  return (first['created'] as num? ?? 0).compareTo(
    second['created'] as num? ?? 0,
  );
}

List<num> _cfiSteps(String cfi, bool end) {
  final path = StringBuffer();
  var assertion = false, escaped = false;
  for (final rune in cfi.runes) {
    final char = String.fromCharCode(rune);
    if (escaped) {
      escaped = false;
    } else if (char == '^') {
      escaped = true;
    } else if (char == '[') {
      assertion = true;
    } else if (char == ']') {
      assertion = false;
    } else if (!assertion) {
      path.write(char);
    }
  }
  final range = path.toString().split(',');
  // Relative endpoints extend the common parent, including an empty endpoint.
  // Comparing their concatenated digits would instead mix start/end positions.
  final point = range.first + (range.length == 3 ? range[end ? 2 : 1] : '');
  return RegExp(
    r'\d+(?:\.\d+)?',
  ).allMatches(point).map((m) => num.parse(m[0]!)).toList();
}
