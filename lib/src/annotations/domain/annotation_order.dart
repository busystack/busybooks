// The same ordering is used by the sidebar and portable annotation export.
int compareAnnotationLocations(Map first, Map second) {
  final a = first['anchor'] as Map, b = second['anchor'] as Map;
  final page = ((a['page'] ?? a['index'] ?? 0) as num).compareTo(
    (b['page'] ?? b['index'] ?? 0) as num,
  );
  if (page != 0) return page;
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
  List<int> steps(Map anchor) => RegExp(r'\d+')
      .allMatches(
        (anchor['cfi']?.toString() ?? '').replaceAll(RegExp(r'\[[^\]]*\]'), ''),
      )
      .map((match) => int.parse(match[0]!))
      .toList();
  final left = steps(a), right = steps(b);
  for (var index = 0; index < left.length && index < right.length; index++) {
    final order = left[index].compareTo(right[index]);
    if (order != 0) return order;
  }
  return (first['created'] as num? ?? 0).compareTo(
    second['created'] as num? ?? 0,
  );
}
