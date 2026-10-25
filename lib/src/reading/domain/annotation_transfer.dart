import 'dart:convert';
import 'dart:math';

const inlineAnnotationBytes = 128 * 1024;
const _chunkCharacters = 32 * 1024;

bool inlineAnnotations(List<Map<String, dynamic>> annotations) =>
    utf8.encode(jsonEncode(annotations)).length <= inlineAnnotationBytes;

// A snapshot is committed only after its final chunk arrives. JSON strings
// also bound a single large quotation/geometry record without truncating it.
// Even six-byte JSON escapes fit well below the hosts' 1 MiB command limit.
Iterable<Map<String, dynamic>> annotationTransfer(
  List<Map<String, dynamic>> annotations,
  int revision,
) sync* {
  final encoded = jsonEncode(annotations);
  if (utf8.encode(encoded).length <= inlineAnnotationBytes) {
    yield {'revision': revision, 'value': annotations};
    return;
  }
  for (var offset = 0; offset < encoded.length; offset += _chunkCharacters) {
    final end = min(encoded.length, offset + _chunkCharacters);
    yield {
      'revision': revision,
      'offset': offset,
      'chunk': encoded.substring(offset, end),
      'complete': end == encoded.length,
    };
  }
}
