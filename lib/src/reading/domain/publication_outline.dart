/// Publication navigation identities are independent of labels and page numbers.
/// Ordered depth records come from Foliate/PDF.js; they are not book records.
class PublicationOutlineNode {
  const PublicationOutlineNode({
    required this.id,
    required this.title,
    required this.depth,
    required this.children,
    this.parentId,
    this.destination,
    this.pageLabel,
  });
  final String id, title;
  final int depth;
  final String? parentId, pageLabel;
  final Map<String, dynamic>? destination;
  final List<PublicationOutlineNode> children;
}

class PublicationOutline {
  const PublicationOutline.empty()
    : roots = const [],
      ordered = const [],
      byId = const {};
  const PublicationOutline._(this.roots, this.ordered, this.byId);
  final List<PublicationOutlineNode> roots, ordered;
  final Map<String, PublicationOutlineNode> byId;
  factory PublicationOutline.fromRecords(
    List<Map<String, dynamic>> records, {
    required bool pdf,
  }) {
    final parents = <int?>[],
        children = <List<int>>[],
        stack = <int>[],
        roots = <int>[];
    for (var i = 0; i < records.length; i++) {
      final depth = records[i]['depth'] is int
          ? (records[i]['depth'] as int).clamp(0, 100000)
          : 0;
      while (stack.isNotEmpty &&
          ((records[stack.last]['depth'] as num?)?.toInt() ?? 0) >= depth) {
        stack.removeLast();
      }
      parents.add(stack.isEmpty ? null : stack.last);
      children.add([]);
      if (stack.isEmpty) {
        roots.add(i);
      } else {
        children[stack.last].add(i);
      }
      stack.add(i);
    }
    final ids = <String>[], used = <String>{};
    for (var i = 0; i < records.length; i++) {
      final value = records[i]['id'];
      final proposed = value is String && value.isNotEmpty
          ? value
          : 'outline:$i';
      final id = used.contains(proposed) ? '$proposed:$i' : proposed;
      ids.add(id);
      used.add(id);
    }
    final nodes = List<PublicationOutlineNode?>.filled(records.length, null);
    for (var i = records.length - 1; i >= 0; i--) {
      final item = records[i], href = item['href'];
      Map<String, dynamic>? target;
      if (item['anchor'] is Map) {
        target = Map<String, dynamic>.unmodifiable(
          (item['anchor'] as Map).cast<String, dynamic>(),
        );
      } else if (href is String && href.isNotEmpty) {
        if (pdf) {
          final page = int.tryParse(href);
          if (page != null && page >= 0) target = {'page': page};
        } else {
          target = {'href': href};
        }
      }
      nodes[i] = PublicationOutlineNode(
        id: ids[i],
        title: item['label'] as String? ?? '',
        depth: parents[i] == null
            ? 0
            : (records[i]['depth'] as num?)?.toInt() ?? 0,
        parentId: parents[i] == null ? null : ids[parents[i]!],
        destination: target,
        pageLabel: item['pageLabel'] as String?,
        children: List.unmodifiable(children[i].map((n) => nodes[n]!)),
      );
    }
    final ordered = List<PublicationOutlineNode>.unmodifiable(
      nodes.cast<PublicationOutlineNode>(),
    );
    return PublicationOutline._(
      List.unmodifiable(roots.map((i) => ordered[i])),
      ordered,
      Map.unmodifiable({for (final n in ordered) n.id: n}),
    );
  }
  List<PublicationOutlineNode> visible(Set<String> expanded) {
    final result = <PublicationOutlineNode>[],
        pending = roots.reversed.toList();
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      result.add(node);
      if (expanded.contains(node.id)) pending.addAll(node.children.reversed);
    }
    return result;
  }

  String? visibleAncestor(String? active, Set<String> expanded) {
    final node = byId[active];
    if (node == null) return null;
    var visible = node;
    var parent = byId[node.parentId];
    while (parent != null) {
      if (!expanded.contains(parent.id)) visible = parent;
      parent = byId[parent.parentId];
    }
    return visible.id;
  }

  String? activeAt(Map<String, dynamic> location) {
    if (byId.containsKey(location['tocId'])) return location['tocId'] as String;
    // The adapter supplies precise IDs for EPUB fragments and PDF coordinates.
    // A legacy href is useful only if it identifies one destination uniquely.
    final href = location['tocHref'];
    final matches = ordered
        .where((n) => n.destination?['href'] == href && href != null)
        .toList();
    return matches.length == 1 ? matches.single.id : null;
  }
}

class PublicationPageReference {
  const PublicationPageReference({
    this.label,
    this.physicalPage,
    this.totalPages,
  });
  final String? label;
  final int? physicalPage, totalPages;
  String get display => label ?? (physicalPage == null ? '—' : '$physicalPage');
  factory PublicationPageReference.pdf(
    int index,
    int pages,
    List<String> labels,
  ) => PublicationPageReference(
    label: labels.length > index && index >= 0 && labels[index].isNotEmpty
        ? labels[index]
        : null,
    physicalPage: index >= 0 ? index + 1 : null,
    totalPages: pages > 0 ? pages : null,
  );
}
