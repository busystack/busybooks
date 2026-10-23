import 'typography.dart';

const _commonReadingAppearance = <String, dynamic>{
  'publisher': true,
  'font': 'serif',
  'size': 20.0,
  'weight': 400,
  'line': 1.5,
  'paragraph': .6,
  'margin': 32.0,
  'width': 720.0,
  'align': 'start',
  'hyphenate': true,
  'color': 'system',
  'spread': false,
  'rotation': 0,
};
const defaultReadingAppearance = <String, dynamic>{
  ..._commonReadingAppearance,
  'flow': 'paginated',
  'zoom': 'fit-page',
};
const defaultPdfAppearance = <String, dynamic>{
  ..._commonReadingAppearance,
  'flow': 'scrolled',
  'zoom': 'fit-width',
};
const busyBooksSettingsDefaults = <String, dynamic>{
  'schema': 1,
  'theme': 'system',
  'locale': null,
  'grid': true,
  'sort': 'added',
  'sidebar': true,
  'reading': defaultReadingAppearance,
  'pdfReading': defaultPdfAppearance,
  'readerSidebar': false,
  'readerPanel': 'outline',
  'highlightColor': 'yellow',
  'shortcuts': <String, dynamic>{},
  'voice': '',
  'speed': 1.0,
};
Map<String, dynamic> normalizeReadingAppearance(Object? value) {
  final result = {...defaultReadingAppearance};
  if (value is! Map) return result;
  result['font'] = (FontChoice.parse(value['font']) ?? FontChoice.serif)
      .toJson();
  for (final key in ['publisher', 'hyphenate', 'spread']) {
    if (value[key] is bool) result[key] = value[key];
  }
  for (final field in {
    'size': (12.0, 40.0),
    'weight': (300.0, 700.0),
    'line': (1.0, 2.2),
    'paragraph': (0.0, 2.0),
    'margin': (0.0, 80.0),
    'width': (400.0, 1200.0),
  }.entries) {
    final n = value[field.key];
    if (n is num && n.isFinite) {
      result[field.key] = n.clamp(field.value.$1, field.value.$2);
    }
  }
  for (final field in {
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
    if (field.value.contains(value[field.key])) {
      result[field.key] = value[field.key];
    }
  }
  if ([0, 90, 180, 270].contains(value['rotation'])) {
    result['rotation'] = value['rotation'];
  }
  return result;
}

Map<String, dynamic> normalizeAppPreferences(Map<String, dynamic> value) {
  final result = {...busyBooksSettingsDefaults};
  if (['system', 'light', 'dark'].contains(value['theme'])) {
    result['theme'] = value['theme'];
  }
  if (['en', 'de'].contains(value['locale'])) {
    result['locale'] = value['locale'];
  }
  for (final key in ['grid', 'sidebar', 'readerSidebar']) {
    if (value[key] is bool) result[key] = value[key];
  }
  if (['title', 'author', 'series', 'read', 'added'].contains(value['sort'])) {
    result['sort'] = value['sort'];
  }
  result['reading'] = normalizeReadingAppearance(value['reading']);
  result['pdfReading'] = value['pdfReading'] is Map
      ? normalizeReadingAppearance(value['pdfReading'])
      : {...defaultPdfAppearance};
  if ([
    'outline',
    'books',
    'search',
    'annotations',
    'thumbnails',
  ].contains(value['readerPanel'])) {
    result['readerPanel'] = value['readerPanel'];
  }
  if (['yellow', 'green', 'blue', 'pink'].contains(value['highlightColor'])) {
    result['highlightColor'] = value['highlightColor'];
  }
  if (value['shortcuts'] is Map) {
    result['shortcuts'] = (value['shortcuts'] as Map).cast<String, dynamic>();
  }
  if (value['voice'] is String && (value['voice'] as String).length <= 256) {
    result['voice'] = value['voice'];
  }
  final speed = value['speed'];
  if (speed is num && speed.isFinite) result['speed'] = speed.clamp(.5, 2.0);
  return result;
}
