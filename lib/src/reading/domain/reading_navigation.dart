bool sameBookmarkLocation(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a['page'] is int && b['page'] is int) return a['page'] == b['page'];
  return a['cfi'] is String && a['cfi'] == b['cfi'];
}
