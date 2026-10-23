import 'package:flutter/material.dart';
import '../../app/localization.dart';
import '../../library/domain/book.dart';
import '../../reading/domain/publication_outline.dart';
import '../../reading/presentation/publication_location.dart';

// Existing Reading highlight swatches, shared by its editors and saved rows.
Color annotationHighlightColor(String color) => Color(switch (color) {
  'green' => 0xff70c77d,
  'blue' => 0xff6ab7ed,
  'pink' => 0xffe997ba,
  _ => 0xfff5d547,
});
String annotationPreview(String text) {
  var end = text.length > 512 ? 512 : text.length;
  if (end > 0 &&
      end < text.length &&
      text.codeUnitAt(end - 1) >= 0xd800 &&
      text.codeUnitAt(end - 1) <= 0xdbff) {
    end--;
  }
  return '${text.substring(0, end).replaceAll(RegExp(r'\s+'), ' ').trim()}${end < text.length ? '…' : ''}';
}

String annotationReference(
  BuildContext context,
  ReadingAnnotation a, {
  Book? book,
}) {
  final page = a.anchor['page'];
  if (page is int && book?.pageBased == true) {
    return describePublicationPage(
      context.l10n,
      PublicationPageReference.pdf(
        page,
        book!.data['pages'] as int? ?? 0,
        (book.data['pageLabels'] as List? ?? []).cast<String>(),
      ),
    );
  }
  if (a.reference.isNotEmpty &&
      !a.reference.contains('epubcfi(') &&
      !a.reference.startsWith('{')) {
    return a.reference;
  }
  if (page is int) return '${context.l10n.page} ${page + 1}';
  final index = a.anchor['index'];
  return index is int
      ? '${context.l10n.section} ${index + 1}'
      : context.l10n.savedLocation;
}
