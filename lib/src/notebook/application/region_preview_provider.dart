import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/domain/book.dart';
import '../../workspace/workspace_controller.dart';

typedef NotebookRegion = ({
  String bookId,
  String format,
  int page,
  String pageId,
  double x,
  double y,
  double width,
  double height,
});

NotebookRegion notebookRegion(ReadingAnnotation annotation) {
  final anchor = annotation.anchor,
      region = (annotation.anchor['region'] as List).cast<num>();
  return (
    bookId: annotation.bookId,
    format: anchor['format'] as String,
    page: anchor['page'] as int,
    pageId: anchor['pageId'] as String,
    x: region[0].toDouble(),
    y: region[1].toDouble(),
    width: region[2].toDouble(),
    height: region[3].toDouble(),
  );
}

/// A value-keyed, optional cache read shared by cards at the same image region.
/// Neither draft revisions nor renderer readiness own or invalidate the artwork.
final notebookRegionPreviewProvider = FutureProvider.autoDispose
    .family<Uint8List?, NotebookRegion>((ref, region) async {
      return await ref.watch(readingDataStoreProvider).call('regionPreview', {
            'bookId': region.bookId,
            'anchor': {
              'kind': 'comic',
              'version': 1,
              'format': region.format,
              'page': region.page,
              'pageId': region.pageId,
              'region': [region.x, region.y, region.width, region.height],
            },
          })
          as Uint8List?;
    });
