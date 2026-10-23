import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

class _BoundedSink implements Sink<List<int>> {
  _BoundedSink(this.limit);
  final int limit;
  final builder = BytesBuilder(copy: false);
  int count = 0;
  @override
  void add(List<int> value) {
    count += value.length;
    if (count > limit) {
      throw const FormatException('Decompressed resource limit exceeded');
    }
    builder.add(value);
  }

  @override
  void close() {}
}

// Check the count before the ZIP library allocates its central directory.
void checkZipEntryCount(InputStream input) {
  final size = input.length;
  final length = size.clamp(0, 65557);
  final tail = input
      .subset(position: size - length, length: length)
      .toUint8List();
  final data = ByteData.sublistView(tail);
  for (var offset = tail.length - 22; offset >= 0; offset--) {
    if (data.getUint32(offset, Endian.little) == 0x06054b50 &&
        offset + 22 + data.getUint16(offset + 20, Endian.little) ==
            tail.length) {
      if (data.getUint16(offset + 4, Endian.little) != 0 ||
          data.getUint16(offset + 6, Endian.little) != 0) {
        throw const FormatException('Multipart ZIP archives are unsupported');
      }
      if (data.getUint16(offset + 10, Endian.little) > 20000) {
        throw const FormatException('Archive has too many entries');
      }
      return;
    }
  }
  throw const FormatException('Missing or damaged ZIP directory');
}

void validateZipDirectory(
  ZipDirectory directory, {
  int maximumTotal = 1024 * 1024 * 1024,
  int maximumEntry = 256 * 1024 * 1024,
}) {
  if (directory.fileHeaders.length > 20000) {
    throw const FormatException('Archive has too many entries');
  }
  final names = <String>{};
  var total = 0;
  for (final header in directory.fileHeaders) {
    final name = header.filename;
    if (name.isEmpty ||
        name.contains('\\') ||
        name.contains(':') ||
        name.contains('\u0000') ||
        name.startsWith('/') ||
        name.split('/').contains('..') ||
        p.posix.normalize(name) != name.replaceAll(RegExp(r'/$'), '') ||
        ![
          0,
          0x8000,
          0x4000,
        ].contains((header.externalFileAttributes >> 16) & 0xf000) ||
        !names.add(name)) {
      throw const FormatException('Unsafe or duplicate archive path');
    }
    if (header.generalPurposeBitFlag & 1 != 0) {
      throw const FormatException('Encrypted archives are unsupported');
    }
    if (![0, 8].contains(header.compressionMethod)) {
      throw const FormatException('Unsupported archive compression');
    }
    if (name.endsWith('/') && header.uncompressedSize != 0) {
      throw const FormatException('Archive directory entries must be empty');
    }
    total += header.uncompressedSize;
    if (header.uncompressedSize > maximumEntry || total > maximumTotal) {
      throw const FormatException('Archive resource limit exceeded');
    }
  }
}

Uint8List readZipEntry(ZipFileHeader header) {
  final source = header.file;
  if (source == null || source.filename != header.filename) {
    throw const FormatException('Inconsistent archive directory');
  }
  final input = source.getStream(decompress: false);
  final sink = _BoundedSink(header.uncompressedSize);
  if (header.compressionMethod == 8) {
    final decoder = ZLibCodec(raw: true).decoder.startChunkedConversion(sink);
    while (!input.isEOS) {
      decoder.add(input.readBytes(input.length.clamp(0, 4096)).toUint8List());
    }
    decoder.close();
  } else {
    while (!input.isEOS) {
      sink.add(input.readBytes(input.length.clamp(0, 65536)).toUint8List());
    }
  }
  final bytes = sink.builder.takeBytes();
  if (bytes.length != header.uncompressedSize ||
      getCrc32(bytes) != header.crc32) {
    throw const FormatException('Damaged archive resource');
  }
  return bytes;
}

Archive validatedArchive(
  Uint8List bytes, {
  int maximumTotal = 1024 * 1024 * 1024,
}) {
  final input = InputMemoryStream(bytes);
  checkZipEntryCount(input);
  final directory = ZipDirectory()..read(input);
  validateZipDirectory(directory, maximumTotal: maximumTotal);
  final archive = Archive();
  for (final header in directory.fileHeaders) {
    final data = readZipEntry(header);
    archive.addFile(
      header.filename.endsWith('/')
          ? ArchiveFile.directory(header.filename)
          : ArchiveFile(header.filename, data.length, data),
    );
  }
  return archive;
}
