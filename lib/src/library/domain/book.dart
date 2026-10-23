import 'dart:convert';
import '../../core/reading_preferences.dart';
import 'book_format.dart';

class Book {
  Book(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get path => data['path'] as String? ?? '';
  String get referencePath => data['referencePath'] as String? ?? path;
  String get status => data['status'] as String? ?? 'available';
  bool get available => status == 'available';
  String get title => data['title'] as String? ?? '';
  String get author => data['author'] as String? ?? '';
  String get series => data['series'] as String? ?? '';
  num get seriesOrder => data['seriesOrder'] as num? ?? 0;
  String get language => data['language'] as String? ?? '';
  String get format => data['format'] as String;
  bool get comic => isComicFormat(format);
  bool get pageBased => isPageFormat(format);
  bool get textInteraction => !comic;
  String get originalSuffix =>
      originalBookSuffix(path) ?? data['originalSuffix'] as String? ?? format;
  String get state => data['state'] as String? ?? 'unread';
  String? get cover => data['cover'] as String?;
  double get progress => (data['progress'] as num? ?? 0).toDouble();
  int get added => data['added'] as int? ?? 0;
  int get read => data['read'] as int? ?? 0;
  Map<String, dynamic>? get anchor =>
      (data['anchor'] as Map?)?.cast<String, dynamic>();
  Map<String, dynamic>? get appearance => data['appearance'] == null
      ? null
      : normalizeReadingAppearance(data['appearance']);
  Book copy(Map<String, dynamic> changes) => Book({...data, ...changes});
  String encode() => jsonEncode(data);
}

class ReadingAnnotation {
  ReadingAnnotation(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get bookId => data['bookId'] as String;
  String get kind => data['annotationKind'] as String? ?? 'bookmark';
  String get text => data['text'] as String? ?? '';
  String get note => data['note'] as String? ?? '';
  String get color => data['color'] as String? ?? 'yellow';
  String get reference => data['reference'] as String? ?? '';
  Map<String, dynamic> get anchor =>
      (data['anchor'] as Map).cast<String, dynamic>();
  ReadingAnnotation copy(Map<String, dynamic> changes) =>
      ReadingAnnotation({...data, ...changes});
}
