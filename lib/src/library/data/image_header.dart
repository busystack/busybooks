import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'jpeg_markers.dart';

// JPEG startDecode allocates coefficient planes. Inspect its frame header
// directly; preparation only needs geometry, never those planes or pixels.
image.JpegInfo? _jpegInfo(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  image.JpegInfo? info;
  for (final marker in jpegMarkers(bytes)) {
    if (marker.code == 0xda) return info;
    if (marker.code == 0xc0 || marker.code == 0xc1 || marker.code == 0xc2) {
      final offset = marker.offset;
      if (marker.length < 6 || bytes[offset] != 8) return null;
      final components = bytes[offset + 5];
      if (components < 1 ||
          components > 4 ||
          marker.length != 6 + 3 * components) {
        return null;
      }
      final ids = <int>{};
      for (var i = 0; i < components; i++) {
        final at = offset + 6 + 3 * i, sampling = bytes[at + 1];
        if (!ids.add(bytes[at]) ||
            (sampling >> 4) < 1 ||
            (sampling >> 4) > 4 ||
            (sampling & 15) < 1 ||
            (sampling & 15) > 4 ||
            bytes[at + 2] > 3) {
          return null;
        }
      }
      if (info != null) return null;
      info = image.JpegInfo()
        ..height = data.getUint16(offset + 1)
        ..width = data.getUint16(offset + 3)
        ..numComponents = components;
    }
  }
  return null;
}

/// Inspect supported publication images without initializing a JPEG decoder.
/// Callers must keep the compressed byte limit as well as these geometry limits.
({image.Decoder decoder, image.DecodeInfo info})? boundedImageInfo(
  Uint8List bytes, {
  int maximumDimension = 16000,
  int maximumPixels = 32 * 1024 * 1024,
}) {
  try {
    if (bytes.length < 12) return null;
    final image.Decoder decoder;
    final image.DecodeInfo? info;
    if (bytes[0] == 0xff && bytes[1] == 0xd8) {
      decoder = image.JpegDecoder();
      info = _jpegInfo(bytes);
    } else {
      // These decoders inspect headers/frame directories without allocating
      // full-resolution pixels. Do not probe unrelated decoder implementations.
      decoder = bytes[0] == 0x89 && bytes[1] == 0x50
          ? image.PngDecoder()
          : bytes[0] == 0x47 && bytes[1] == 0x49
          ? image.GifDecoder()
          : image.WebPDecoder();
      if (!decoder.isValidFile(bytes)) return null;
      info = decoder.startDecode(bytes);
    }
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > maximumDimension ||
        info.height > maximumDimension ||
        info.width * info.height > maximumPixels) {
      return null;
    }
    // JPEG structure was checked by the shared marker scanner. The package's
    // separate validator treats standalone markers as length-bearing segments.
    // Initializing it here would also reintroduce inconsistent header parsing.
    return (decoder: decoder, info: info);
  } catch (_) {
    // Decoder libraries can throw RangeError as well as format exceptions for
    // truncated metadata. An invalid optional image remains unusable data.
    return null;
  }
}
