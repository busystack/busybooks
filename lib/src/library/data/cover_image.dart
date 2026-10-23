import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'package:xml/xml.dart';

String? libraryCover(Uint8List bytes, String mime) {
  if (bytes.length > 4 * 1024 * 1024) return null;
  if (mime == 'image/svg+xml') {
    final doc = XmlDocument.parse(utf8.decode(bytes));
    for (final node in doc.descendants.whereType<XmlElement>().toList()) {
      if ([
        'script',
        'foreignObject',
        'iframe',
        'use',
        'image',
      ].contains(node.name.local)) {
        node.parent?.children.remove(node);
        continue;
      }
      node.attributes.removeWhere(
        (a) =>
            a.name.local.toLowerCase().startsWith('on') ||
            a.name.local == 'href' ||
            a.value.contains(
              RegExp(r'https?:|file:|javascript:', caseSensitive: false),
            ),
      );
    }
    final safe = utf8.encode(doc.toXmlString());
    if (safe.length > 128 * 1024) return null;
    return 'data:image/svg+xml;base64,${base64Encode(safe)}';
  }
  final decoder = image.findDecoderForData(bytes),
      info = decoder?.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 16 * 1024 * 1024) {
    return null;
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) return null;
  final thumbnail = image.copyResize(
    decoded,
    width: 160,
    height: 240,
    maintainAspect: true,
    interpolation: image.Interpolation.average,
  );
  return 'data:image/png;base64,${base64Encode(image.encodePng(thumbnail))}';
}

// Stored covers are the bounded data URIs emitted by libraryCover, never paths
// or remote resources. Restore rejects unsafe SVG instead of silently changing it.
void validateLibraryCover(dynamic value) {
  if (value is! String || value.length > 6 * 1024 * 1024) {
    throw const FormatException('Invalid cover type or resource size');
  }
  final match = RegExp(
    r'^data:image/(png|svg\+xml);base64,([A-Za-z0-9+/]*={0,2})$',
  ).firstMatch(value);
  if (match == null) {
    throw const FormatException('Invalid stored cover representation');
  }
  final bytes = base64Decode(match[2]!);
  if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
    throw const FormatException('Invalid cover resource size');
  }
  final mime = 'image/${match[1]}';
  if (mime == 'image/svg+xml') {
    if (bytes.length > 128 * 1024 ||
        XmlDocument.parse(utf8.decode(bytes)).rootElement.name.local != 'svg' ||
        libraryCover(bytes, mime) != value) {
      throw const FormatException('Invalid or unsanitized SVG cover');
    }
  } else {
    final info = image.PngDecoder().startDecode(bytes);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > 160 ||
        info.height > 240 ||
        libraryCover(bytes, mime) == null) {
      throw const FormatException('Invalid stored cover image');
    }
  }
}
