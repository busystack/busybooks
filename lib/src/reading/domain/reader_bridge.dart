import 'dart:convert';
import 'dart:math';

const readerBridgeFrameBytes = 1024 * 1024;
const readerBridgeInlineBytes = 128 * 1024;
const readerBridgeChunkCharacters = 32 * 1024;
const readerBridgePayloadCharacters = 16 * 1024 * 1024;

/// Focus reports contain only an input source and their renderer owner. They
/// never carry a navigation target or an application command.
bool validReaderContentFocusEvent(Map<String, dynamic> event) =>
    event.keys.every(
      (key) => const {'type', 'session', 'source'}.contains(key),
    ) &&
    event['type'] == 'contentFocus' &&
    event['session'] is String &&
    (event['session'] as String).isNotEmpty &&
    (event['session'] as String).length <= 128 &&
    const {'pointer', 'focus'}.contains(event['source']);

/// JSON string chunks preserve arbitrary Unicode and escaped text. Each frame
/// is comfortably below the native byte limit, including JSON escaping.
Iterable<Map<String, dynamic>> readerBridgeFrames(
  Map<String, dynamic> message,
  int revision, {
  required bool command,
}) sync* {
  final encoded = jsonEncode(message);
  if (encoded.length > readerBridgePayloadCharacters) {
    throw const FormatException('Reader bridge payload limit exceeded');
  }
  if (utf8.encode(encoded).length <= readerBridgeInlineBytes) {
    yield message;
    return;
  }
  for (
    var offset = 0;
    offset < encoded.length;
    offset += readerBridgeChunkCharacters
  ) {
    final end = min(encoded.length, offset + readerBridgeChunkCharacters);
    yield {
      command ? 'action' : 'type': 'bridgeChunk',
      'session': message['session'],
      'bridgeRevision': revision,
      'offset': offset,
      'total': encoded.length,
      'chunk': encoded.substring(offset, end),
      'complete': end == encoded.length,
    };
  }
}

/// One ordered, session-owned logical transfer. Incomplete, interleaved or
/// oversized delivery fails explicitly; a later flush cannot acknowledge it.
class ReaderBridgeAssembler {
  String? _session;
  int _revision = -1, _received = 0, _total = 0;
  List<String>? _chunks;

  Map<String, dynamic>? accept(Map<String, dynamic> frame) {
    if (frame['session'] != _session) {
      _session = frame['session'] as String?;
      _revision = -1;
      _chunks = null;
    }
    if (frame['type'] != 'bridgeChunk') {
      if (_chunks != null) {
        _chunks = null;
        throw const FormatException('Incomplete reader bridge transfer');
      }
      return frame;
    }
    final revision = frame['bridgeRevision'],
        offset = frame['offset'],
        total = frame['total'],
        chunk = frame['chunk'];
    Never invalid() {
      _chunks = null;
      throw const FormatException('Invalid reader bridge transfer');
    }

    if (revision is! int ||
        revision < 0 ||
        offset is! int ||
        total is! int ||
        total < 1 ||
        total > readerBridgePayloadCharacters ||
        chunk is! String ||
        chunk.isEmpty ||
        chunk.length > readerBridgeChunkCharacters ||
        frame['complete'] is! bool) {
      invalid();
    }
    if (revision < _revision || revision == _revision && _chunks == null) {
      return null;
    }
    if (offset == 0) {
      if (revision <= _revision || _chunks != null) invalid();
      _revision = revision;
      _received = 0;
      _total = total;
      _chunks = [];
    }
    if (revision != _revision ||
        _chunks == null ||
        offset != _received ||
        total != _total ||
        _received + chunk.length > _total) {
      invalid();
    }
    _chunks!.add(chunk);
    _received += chunk.length;
    if (frame['complete'] != (_received == _total)) invalid();
    if (_received != _total) return null;
    final encoded = _chunks!.join();
    _chunks = null;
    final result = (jsonDecode(encoded) as Map).cast<String, dynamic>();
    if (result['session'] != _session || result['type'] == 'bridgeChunk') {
      invalid();
    }
    return result;
  }
}
