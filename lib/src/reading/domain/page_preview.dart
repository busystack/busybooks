import 'dart:convert';
import 'dart:typed_data';

class PagePreview {
  const PagePreview(this.data, this.bytes, this.width, this.height);
  final String data;
  final Uint8List bytes;
  final double width, height;
  static PagePreview? fromEvent(Map<String, dynamic> event) {
    final data = event['data'], w = event['width'], h = event['height'];
    if (data is! String ||
        data.length > 512 * 1024 ||
        !data.startsWith('data:image/png;base64,') ||
        w is! num ||
        h is! num ||
        !w.isFinite ||
        !h.isFinite ||
        w <= 0 ||
        h <= 0 ||
        w > 320 ||
        h > 320) {
      return null;
    }
    try {
      final bytes = base64Decode(
        data.substring('data:image/png;base64,'.length),
      );
      if (bytes.length < 8 ||
          bytes[0] != 137 ||
          bytes[1] != 80 ||
          bytes[2] != 78 ||
          bytes[3] != 71) {
        return null;
      }
      return PagePreview(data, bytes, w.toDouble(), h.toDouble());
    } on FormatException {
      return null;
    }
  }
}
