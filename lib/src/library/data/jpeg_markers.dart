import 'dart:typed_data';

/// Scan the bounded header region only. Entropy-coded scan data is never read.
/// JPEG permits marker fill bytes and markers without a segment length.
Iterable<({int code, int offset, int length})> jpegMarkers(
  Uint8List bytes,
) sync* {
  if (bytes.length < 2 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    throw const FormatException('Invalid JPEG signature');
  }
  final data = ByteData.sublistView(bytes);
  var at = 2;
  while (at < bytes.length) {
    if (bytes[at++] != 0xff) throw const FormatException('Invalid JPEG marker');
    while (at < bytes.length && bytes[at] == 0xff) {
      at++;
    }
    if (at == bytes.length) {
      throw const FormatException('Truncated JPEG marker');
    }
    final code = bytes[at++];
    if (code == 0 || code == 0xd8) {
      throw const FormatException('Invalid JPEG marker');
    }
    if (code == 0xd9) return;
    if (code == 0x01 || code >= 0xd0 && code <= 0xd7) continue;
    if (at + 2 > bytes.length) {
      throw const FormatException('Truncated JPEG segment');
    }
    final length = data.getUint16(at);
    if (length < 2 || length > bytes.length - at) {
      throw const FormatException('Invalid JPEG segment length');
    }
    yield (code: code, offset: at + 2, length: length - 2);
    if (code == 0xda) return;
    at += length;
  }
}
