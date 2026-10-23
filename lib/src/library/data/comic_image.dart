import 'dart:convert';
import 'dart:typed_data';

// Read only IFD0's orientation. Arbitrary EXIF subdirectories are never
// traversed, and geometry inspection never decodes full-resolution pixels.
int comicOrientation(Uint8List bytes) {
  int tiff(int start, int length) {
    if (length < 8 || length > 1024 * 1024 || start + length > bytes.length) {
      return 1;
    }
    final data = ByteData.sublistView(bytes, start, start + length);
    final endian = data.getUint16(0) == 0x4949 ? Endian.little : Endian.big;
    if (data.getUint16(0) != 0x4949 && data.getUint16(0) != 0x4d4d ||
        data.getUint16(2, endian) != 42) {
      return 1;
    }
    final offset = data.getUint32(4, endian);
    if (offset + 2 > length) return 1;
    final count = data.getUint16(offset, endian);
    if (count > 4096 || offset + 2 + 12 * count > length) return 1;
    for (var i = 0; i < count; i++) {
      final at = offset + 2 + i * 12;
      if (data.getUint16(at, endian) == 274 &&
          data.getUint16(at + 2, endian) == 3 &&
          data.getUint32(at + 4, endian) == 1) {
        final value = data.getUint16(at + 8, endian);
        return value >= 1 && value <= 8 ? value : 1;
      }
    }
    return 1;
  }

  final data = ByteData.sublistView(bytes);
  if (bytes.length > 2 && bytes[0] == 255 && bytes[1] == 216) {
    var at = 2;
    while (at + 4 <= bytes.length) {
      if (bytes[at] != 255) break;
      final marker = bytes[at + 1];
      if (marker == 0xda || marker == 0xd9) break;
      final length = data.getUint16(at + 2, Endian.big);
      if (length < 2 || at + 2 + length > bytes.length) break;
      if (marker == 0xe1 &&
          length > 8 &&
          latin1.decode(bytes.sublist(at + 4, at + 10)) == 'Exif\u0000\u0000') {
        return tiff(at + 10, length - 8);
      }
      at += length + 2;
    }
  } else if (bytes.length > 12) {
    final png = bytes[0] == 137 && bytes[1] == 80,
        webp =
            latin1.decode(bytes.sublist(0, 4)) == 'RIFF' &&
            latin1.decode(bytes.sublist(8, 12)) == 'WEBP';
    if (png || webp) {
      var at = png ? 8 : 12;
      for (var chunks = 0; chunks < 4096 && at + 8 <= bytes.length; chunks++) {
        final length = data.getUint32(
          png ? at : at + 4,
          png ? Endian.big : Endian.little,
        );
        if (at + 8 + length > bytes.length) break;
        final type = latin1.decode(
          bytes.sublist(png ? at + 4 : at, png ? at + 8 : at + 4),
        );
        if (type == (png ? 'eXIf' : 'EXIF')) {
          final skip =
              length > 6 &&
                  latin1.decode(bytes.sublist(at + 8, at + 14)) ==
                      'Exif\u0000\u0000'
              ? 6
              : 0;
          return tiff(at + 8 + skip, length - skip);
        }
        at += 8 + length + (png ? 4 : length % 2);
      }
    }
  }
  return 1;
}
