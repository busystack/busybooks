import 'dart:convert';
import 'dart:typed_data';

const readingBackupSchema = 3;
const maximumBackupRecords = 100000;
const maximumBackupManifestBytes = 128 * 1024 * 1024;

void validateBackupResources({int? recordCount, int? encodedBytes}) {
  if (recordCount != null && recordCount > maximumBackupRecords) {
    throw const FormatException(
      'Reading-data backup exceeds 100,000 combined records',
    );
  }
  if (encodedBytes != null && encodedBytes > maximumBackupManifestBytes) {
    throw const FormatException(
      'Reading-data backup exceeds 128 MiB of encoded data',
    );
  }
}

// Stop encoding at the same bound used before restore decompression. A large
// valid database must fail export without building an unbounded JSON buffer.
Uint8List encodeReadingBackup(
  List<Map<String, dynamic>> records,
  Map<String, dynamic> preferences,
) {
  validateBackupResources(recordCount: records.length);
  final sink = _ManifestSink();
  final encoder = JsonUtf8Encoder().startChunkedConversion(sink);
  encoder.add({
    'type': 'busybooks-reading-data',
    'schema': readingBackupSchema,
    'records': records,
    'preferences': preferences,
  });
  encoder.close();
  return sink.bytes.takeBytes();
}

class _ManifestSink implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  int length = 0;
  @override
  void add(List<int> data) {
    length += data.length;
    validateBackupResources(encodedBytes: length);
    bytes.add(data);
  }

  @override
  void close() {}
}
