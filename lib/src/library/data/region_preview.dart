import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

import 'cache_resources.dart';
import 'comic_book.dart';
import 'image_header.dart';
import 'publication_cache.dart';
import 'record_validation.dart';

/// Optional artwork from the existing sealed comic cache. No original is opened,
/// no cache is regenerated and no reading record is changed by this operation.
Future<Uint8List?> cachedRegionPreview(
  String root,
  String bookId,
  String format,
  Map<String, dynamic> anchor,
) async {
  validateAnchor(anchor, format);
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(bookId) ||
      !['cbz', 'cbr'].contains(format) ||
      anchor['region'] == null) {
    return null;
  }
  final directory = publicationCachePath(root, format, bookId);
  final index = File('$directory.json');
  try {
    for (final path in [
      p.join(root, 'cache'),
      p.dirname(directory),
      directory,
      index.path,
      '${index.path}.sha256',
    ]) {
      if (await FileSystemEntity.isLink(path)) return null;
    }
    final data = await readSealedCacheIndex(index);
    if (data == null ||
        data['version'] != 3 ||
        data['id'] != bookId ||
        data['format'] != format) {
      return null;
    }
    validatePreparedResourceBudget(data);
    final pages = data['pages'], page = anchor['page'] as int;
    if (pages is! List || page < 0 || page >= pages.length) return null;
    final descriptor = pages[page];
    final pageId = anchor['pageId'] as String;
    if (descriptor is! Map || descriptor['file'] != pageId) return null;
    final resources = data['resources'] as Map;
    Map? resource;
    for (final entry in resources.entries) {
      if (entry.value is Map && entry.value['file'] == pageId) {
        if (pageId !=
            sha256.convert(utf8.encode(entry.key as String)).toString()) {
          return null;
        }
        resource = entry.value as Map;
        break;
      }
    }
    if (resource == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(pageId) ||
        resource['size'] is! int ||
        resource['size'] <= 0 ||
        resource['size'] > comicEntryBytes) {
      return null;
    }
    final file = File(p.join(directory, pageId));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final input = await file.open();
    late Uint8List bytes;
    try {
      bytes = await input.read((resource['size'] as int) + 1);
    } finally {
      await input.close();
    }
    if (bytes.length != resource['size'] ||
        sha256.convert(bytes).toString() != resource['sha256']) {
      return null;
    }
    final header = boundedImageInfo(bytes, maximumPixels: comicPixels);
    if (header == null ||
        header.info.numFrames > 1 ||
        !(header.decoder is image.JpegDecoder ||
            header.decoder is image.PngDecoder ||
            header.decoder is image.WebPDecoder)) {
      return null;
    }
    final decoded = header.decoder.decode(bytes, frame: 0);
    if (decoded == null) return null;
    final oriented = image.bakeOrientation(decoded);
    if (oriented.width != descriptor['width'] ||
        oriented.height != descriptor['height']) {
      return null;
    }
    final region = (anchor['region'] as List).cast<num>();
    final x = (region[0] * oriented.width).floor().clamp(0, oriented.width - 1);
    final y = (region[1] * oriented.height).floor().clamp(
      0,
      oriented.height - 1,
    );
    final right = ((region[0] + region[2]) * oriented.width).ceil().clamp(
      x + 1,
      oriented.width,
    );
    final bottom = ((region[1] + region[3]) * oriented.height).ceil().clamp(
      y + 1,
      oriented.height,
    );
    final width = right - x, height = bottom - y;
    final scale = math.min(1.0, math.min(640 / width, 360 / height));
    // Sample directly into a bounded preview instead of allocating a second
    // full-resolution crop. Rectification needs two samples on each axis.
    final thumbnail = image.copyRectify(
      oriented,
      topLeft: image.Point(x, y),
      topRight: image.Point(right - 1, y),
      bottomLeft: image.Point(x, bottom - 1),
      bottomRight: image.Point(right - 1, bottom - 1),
      toImage: image.Image(
        width: math.max(2, (width * scale).round()),
        height: math.max(2, (height * scale).round()),
        numChannels: 4,
      ),
      interpolation: image.Interpolation.linear,
    );
    final png = image.encodePng(thumbnail);
    return png.length <= 1024 * 1024 ? png : null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on image.ImageException {
    return null;
  }
}
