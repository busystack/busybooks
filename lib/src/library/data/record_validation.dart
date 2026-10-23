import 'book_paths.dart';
import 'cover_image.dart';
import '../domain/annotation_limits.dart';
import '../../core/typography.dart';

final bookIdentity = RegExp(r'^[a-f0-9]{64}$');
final collectionIdentity = RegExp(r'^collection:[a-f0-9]{32}$');
final annotationIdentity = RegExp(r'^annotation-[a-zA-Z0-9-]{1,100}$');
const annotationColors = ['yellow', 'green', 'blue', 'pink'];

Never invalid(String field) =>
    throw FormatException('Invalid reading data: $field');
void boundedText(
  dynamic value,
  String field, {
  int limit = 65536,
  bool empty = true,
}) {
  if (value is! String ||
      value.length > limit ||
      value.contains('\u0000') ||
      (!empty && value.trim().isEmpty)) {
    invalid(field);
  }
}

void finiteNumber(
  dynamic value,
  String field, {
  double min = -10000000,
  double max = 10000000,
}) {
  if (value is! num || !value.isFinite || value < min || value > max) {
    invalid(field);
  }
}

void validateAnchor(dynamic value, String format) {
  if (value is! Map) invalid('anchor');
  if (format == 'epub') {
    final cfi = value['cfi'];
    boundedText(cfi, 'EPUB CFI', limit: 32768, empty: false);
    if (value['kind'] != null && value['kind'] != 'epub') {
      invalid('EPUB anchor kind');
    }
    if (!(cfi as String).startsWith('epubcfi(') ||
        !cfi.endsWith(')') ||
        value.containsKey('page')) {
      invalid('EPUB anchor');
    }
    final stripped = StringBuffer();
    var assertion = false, escaped = false;
    for (final rune in cfi.substring(8, cfi.length - 1).runes) {
      final char = String.fromCharCode(rune);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '^') {
        escaped = true;
        continue;
      }
      if (char == '[') {
        if (assertion) invalid('CFI assertion');
        assertion = true;
        continue;
      }
      if (char == ']') {
        if (!assertion) invalid('CFI assertion');
        assertion = false;
        continue;
      }
      if (!assertion) stripped.write(char);
    }
    if (assertion || escaped) invalid('CFI assertion');
    final range = stripped.toString().split(',');
    if (range.length != 1 && range.length != 3) invalid('CFI range');
    final pathPattern = RegExp(
      r'^/[1-9]\d*(?:/[1-9]\d*)*(?::\d+)?(?:~\d+(?:\.\d+)?)?(?:@\d+(?:\.\d+)?:\d+(?:\.\d+)?)?(?:;s=[ab])?$',
    );
    for (final part in range) {
      final paths = part.split('!');
      if (paths.length > 2 || paths.any((p) => !pathPattern.hasMatch(p))) {
        invalid('CFI path');
      }
      for (final match in RegExp(r'\d+(?:\.\d+)?').allMatches(part)) {
        if ((num.tryParse(match[0]!) ?? 1000000001) > 1000000000) {
          invalid('CFI coordinate');
        }
      }
    }
    if (value['index'] != null &&
        (value['index'] is! int ||
            value['index'] < 0 ||
            value['index'] > 1000000)) {
      invalid('EPUB index');
    }
  } else if (format == 'pdf') {
    if (value['kind'] != null && value['kind'] != 'pdf') {
      invalid('PDF anchor kind');
    }
    if (value['page'] is! int ||
        value['page'] < 0 ||
        value['page'] > 1000000 ||
        value.containsKey('cfi')) {
      invalid('PDF page');
    }
    if (value['y'] != null) {
      finiteNumber(value['y'], 'PDF fraction', min: 0, max: 1);
    }
    if (value['point'] != null) {
      if (value['point'] is! List || (value['point'] as List).length != 2) {
        invalid('PDF point');
      }
      for (final n in value['point']) {
        finiteNumber(n, 'PDF coordinate');
      }
    }
    if (value['rect'] != null) {
      final rect = value['rect'];
      if (rect is! List || rect.length != 4) {
        invalid('PDF destination rectangle');
      }
      for (final coordinate in rect) {
        finiteNumber(coordinate, 'PDF rectangle coordinate');
      }
      if (rect[0] >= rect[2] || rect[1] >= rect[3]) {
        invalid('PDF destination rectangle');
      }
    }
    for (final key in ['textOffset', 'textLength']) {
      if (value[key] != null &&
          (value[key] is! int || value[key] < 0 || value[key] > 100000000)) {
        invalid('PDF text range');
      }
    }
    if (value['segments'] != null) {
      if (value['segments'] is! List ||
          (value['segments'] as List).length > 10000) {
        invalid('PDF segments');
      }
      for (final segment in value['segments']) {
        if (segment is! Map ||
            segment['start'] is! int ||
            segment['start'] < 0 ||
            segment['start'] > 100000000) {
          invalid('PDF segment');
        }
        if (segment['page'] != null &&
            (segment['page'] is! int ||
                segment['page'] < 0 ||
                segment['page'] > 1000000)) {
          invalid('PDF segment page');
        }
        boundedText(segment['text'], 'PDF passage', limit: 1000000);
        if (segment['boxes'] is! List ||
            (segment['boxes'] as List).length > 10000) {
          invalid('PDF boxes');
        }
        for (final box in segment['boxes']) {
          if (box is! List || box.length != 4) invalid('PDF box');
          for (final n in box) {
            finiteNumber(n, 'PDF box coordinate');
          }
        }
      }
    }
  } else {
    invalid('publication format');
  }
}

void validateTimestamp(dynamic value, String field) {
  if (value is! int || value < 0 || value > 8640000000000000) invalid(field);
}

void validateBookAppearance(dynamic appearance) {
  if (appearance is! Map) invalid('book appearance');
  if (appearance['font'] != null &&
      FontChoice.parse(appearance['font']) == null) {
    invalid('appearance font');
  }
  for (final field in ['publisher', 'hyphenate', 'spread']) {
    if (appearance[field] != null && appearance[field] is! bool) {
      invalid('appearance $field');
    }
  }
  for (final entry in {
    'size': (12.0, 40.0),
    'weight': (300.0, 700.0),
    'line': (1.0, 2.2),
    'paragraph': (0.0, 2.0),
    'margin': (0.0, 80.0),
    'width': (400.0, 1200.0),
  }.entries) {
    if (appearance[entry.key] != null) {
      finiteNumber(
        appearance[entry.key],
        'appearance ${entry.key}',
        min: entry.value.$1,
        max: entry.value.$2,
      );
    }
  }
  for (final entry in {
    'align': ['start', 'justify', 'center'],
    'color': ['system', 'light', 'dark', 'sepia'],
    'flow': ['paginated', 'scrolled'],
    'zoom': [
      'fit-page',
      'fit-width',
      '.5',
      '.75',
      '1',
      '1.25',
      '1.5',
      '2',
      '3',
    ],
  }.entries) {
    if (appearance[entry.key] != null &&
        !entry.value.contains(appearance[entry.key])) {
      invalid('appearance ${entry.key}');
    }
  }
  if (appearance['rotation'] != null &&
      ![0, 90, 180, 270].contains(appearance['rotation'])) {
    invalid('appearance rotation');
  }
}

void validateBook(Map value) {
  if (value['id'] is! String ||
      !bookIdentity.hasMatch(value['id']) ||
      !['epub', 'pdf'].contains(value['format'])) {
    invalid('book identity');
  }
  for (final field in ['read', 'added', 'membershipOrder']) {
    if (value[field] != null) validateTimestamp(value[field], field);
  }
  if (value['cover'] != null) validateLibraryCover(value['cover']);
  if (value['appearance'] != null) validateBookAppearance(value['appearance']);
  for (final field in ['path', 'referencePath']) {
    if (value[field] != null) {
      boundedText(value[field], field, limit: 32768);
      if (value[field] != '') validatePath(value[field]);
    }
  }
  if (value['status'] != null &&
      ![
        'available',
        'unverified',
        'missing',
        'denied',
        'changed',
      ].contains(value['status'])) {
    invalid('book status');
  }
  for (final field in ['title', 'author']) {
    boundedText(value[field], field);
  }
  for (final field in ['series', 'language', 'reference']) {
    if (value[field] != null) boundedText(value[field], field);
  }
  if (!['unread', 'reading', 'finished'].contains(value['state'])) {
    invalid('reading state');
  }
  finiteNumber(value['progress'] ?? 0, 'progress', min: 0, max: 1);
  finiteNumber(value['seriesOrder'] ?? 0, 'series order');
  if (value['paths'] is! List || (value['paths'] as List).length > 10000) {
    invalid('paths');
  }
  for (final path in value['paths']) {
    validatePath(path);
  }
  if (value['anchor'] != null) validateAnchor(value['anchor'], value['format']);
  for (final key in ['metadataEdited', 'engineValidated', 'coverEdited']) {
    if (value[key] != null && value[key] is! bool) invalid(key);
  }
  if (value['pages'] != null &&
      (value['pages'] is! int ||
          value['pages'] < 0 ||
          value['pages'] > 1000000)) {
    invalid('page count');
  }
  if (value['pageLabels'] != null) {
    if (value['pageLabels'] is! List ||
        (value['pageLabels'] as List).length > 1000000) {
      invalid('page labels');
    }
    for (final label in value['pageLabels']) {
      boundedText(label, 'page label', limit: 1024);
    }
  }
  if (value['outline'] != null) {
    if (value['outline'] is! List ||
        (value['outline'] as List).length > 100000) {
      invalid('outline');
    }
    final outlineIds = <String>{};
    for (final entry in value['outline']) {
      if (entry is! Map) invalid('outline entry');
      boundedText(entry['label'] ?? '', 'outline label');
      if (entry['id'] != null) {
        boundedText(entry['id'], 'outline identity', limit: 160, empty: false);
        if (!outlineIds.add(entry['id'] as String)) {
          invalid('duplicate outline identity');
        }
      }
      if (entry['depth'] != null &&
          (entry['depth'] is! int ||
              entry['depth'] < 0 ||
              entry['depth'] > 100000)) {
        invalid('outline depth');
      }
      if (entry['href'] != null) {
        boundedText(entry['href'], 'outline destination', limit: 32768);
      }
      if (entry['pageLabel'] != null) {
        boundedText(entry['pageLabel'], 'outline page label', limit: 1024);
      }
      if (entry['anchor'] != null) {
        validateAnchor(entry['anchor'], value['format']);
      }
    }
  }
}

void validatePath(dynamic path) {
  boundedText(path, 'book path', limit: 32768, empty: false);
  if (!isAbsoluteReference(path)) invalid('absolute book path');
}

void validateAnnotation(Map value, Map book) {
  if (value['id'] is! String ||
      !annotationIdentity.hasMatch(value['id']) ||
      value['bookId'] != book['id'] ||
      !['highlight', 'bookmark'].contains(value['annotationKind'])) {
    invalid('annotation identity/type');
  }
  validateAnchor(value['anchor'], book['format']);
  for (final field in ['text', 'note']) {
    boundedText(value[field], field, limit: maxAnnotationTextLength);
  }
  boundedText(value['reference'] ?? '', 'reference');
  if (!annotationColors.contains(value['color'])) invalid('highlight color');
  if (value['created'] is! int || value['created'] < 0) {
    invalid('annotation time');
  }
}
