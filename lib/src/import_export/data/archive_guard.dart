import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

bool isArchiveMetadata(String name) => name
    .split('/')
    .any(
      (part) =>
          part == '__MACOSX' || part == '.DS_Store' || part.startsWith('._'),
    );

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
void checkZipEntryCount(
  InputStream input, {
  int maximumMetadataBytes = 16 * 1024 * 1024,
  int maximumNameBytes = 4 * 1024 * 1024,
}) {
  final size = input.length;
  final length = size.clamp(0, 65557);
  final tail = input
      .subset(position: size - length, length: length)
      .toUint8List();
  final data = ByteData.sublistView(tail);
  int? lastSignature;
  for (var offset = tail.length - 22; offset >= 0; offset--) {
    if (data.getUint32(offset, Endian.little) == 0x06054b50) {
      lastSignature ??= offset;
    }
    if (data.getUint32(offset, Endian.little) == 0x06054b50 &&
        offset + 22 + data.getUint16(offset + 20, Endian.little) ==
            tail.length) {
      // The pinned library chooses the last candidate, including signatures in
      // comments. Never validate one directory and let it allocate another.
      if (lastSignature != offset) {
        throw const FormatException('Ambiguous ZIP directory signature');
      }
      if (data.getUint16(offset + 4, Endian.little) != 0 ||
          data.getUint16(offset + 6, Endian.little) != 0) {
        throw const FormatException('Multipart ZIP archives are unsupported');
      }
      _boundZipMetadata(
        input,
        size - length + offset,
        data,
        offset,
        maximumMetadataBytes,
        maximumNameBytes,
      );
      return;
    }
  }
  throw const FormatException('Missing or damaged ZIP directory');
}

// The library retains central and local
// extra fields/filenames, so bounding only the EOCD count is insufficient.
// Inspect fixed headers and bounded directory bytes before it allocates objects.
void _boundZipMetadata(
  InputStream input,
  int eocd,
  ByteData tail,
  int at,
  int maximumMetadata,
  int maximumNames,
) {
  Never damaged() => throw const FormatException('Damaged ZIP metadata');
  Never limit() =>
      throw const FormatException('ZIP metadata resource limit exceeded');
  ByteData read(int offset, int length) {
    if (offset < 0 || length < 0 || offset > eocd - length) damaged();
    return ByteData.sublistView(
      input.subset(position: offset, length: length).toUint8List(),
    );
  }

  int u16(ByteData data, int offset) => data.getUint16(offset, Endian.little);
  int u32(ByteData data, int offset) => data.getUint32(offset, Endian.little);
  int u64(ByteData data, int offset) {
    final value = data.getUint64(offset, Endian.little);
    if (value < 0) damaged();
    return value;
  }

  var count = u16(tail, at + 10),
      diskCount = u16(tail, at + 8),
      bytes = u32(tail, at + 12),
      start = u32(tail, at + 16),
      directoryEnd = eocd;
  if (eocd >= 20) {
    final locator = read(eocd - 20, 20);
    if (u32(locator, 0) == 0x07064b50) {
      if (u32(locator, 4) != 0 || u32(locator, 16) != 1) damaged();
      final location = u64(locator, 8), record = read(location, 56);
      final recordSize = u64(record, 4);
      if (u32(record, 0) != 0x06064b50 ||
          recordSize < 44 ||
          recordSize > eocd - 32 - location ||
          u32(record, 16) != 0 ||
          u32(record, 20) != 0) {
        damaged();
      }
      count = u64(record, 32);
      diskCount = u64(record, 24);
      bytes = u64(record, 40);
      start = u64(record, 48);
      directoryEnd = location;
    }
  }
  if (count > 20000 || bytes > maximumMetadata) limit();
  if (count != diskCount || start < 0 || start > directoryEnd - bytes) {
    damaged();
  }
  final directory = read(start, bytes);
  var cursor = 0, actual = 0, names = 0, localMetadata = 0;
  while (cursor < bytes) {
    if (cursor + 6 <= bytes &&
        u32(directory, cursor) == 0x05054b50 &&
        cursor + 6 + u16(directory, cursor + 4) == bytes) {
      break; // ZIP signature.
    }
    if (cursor + 46 > bytes || u32(directory, cursor) != 0x02014b50) damaged();
    if (++actual > 20000) limit();
    if (actual > count) damaged();
    final name = u16(directory, cursor + 28),
        extra = u16(directory, cursor + 30),
        comment = u16(directory, cursor + 32),
        end = cursor + 46 + name + extra + comment;
    names += name;
    if (names > maximumNames || name > 32768) limit();
    if (end > bytes || name == 0) damaged();
    var local = u32(directory, cursor + 42),
        disk = u16(directory, cursor + 34),
        packed = u32(directory, cursor + 20),
        unpacked = u32(directory, cursor + 24);
    if (local == 0xffffffff ||
        disk == 0xffff ||
        packed == 0xffffffff ||
        unpacked == 0xffffffff) {
      var extraAt = cursor + 46 + name, found = false;
      while (extraAt + 4 <= end - comment) {
        final size = u16(directory, extraAt + 2), next = extraAt + 4 + size;
        if (next > end - comment) damaged();
        if (u16(directory, extraAt) == 1) {
          var value = extraAt + 4;
          if (unpacked == 0xffffffff) {
            if (value + 8 > next) damaged();
            unpacked = u64(directory, value);
            value += 8;
          }
          if (packed == 0xffffffff) {
            if (value + 8 > next) damaged();
            packed = u64(directory, value);
            value += 8;
          }
          if (local == 0xffffffff) {
            if (value + 8 > next) damaged();
            local = u64(directory, value);
            value += 8;
          }
          if (disk == 0xffff) {
            if (value + 4 > next) damaged();
            disk = u32(directory, value);
          }
          found = true;
          break;
        }
        extraAt = next;
      }
      if (!found) damaged();
    }
    if (disk != 0) {
      throw const FormatException('Multipart ZIP archives are unsupported');
    }
    final header = read(local, 30);
    if (u32(header, 0) != 0x04034b50) damaged();
    final localName = u16(header, 26), localExtra = u16(header, 28);
    localMetadata += 30 + localName + localExtra;
    if (localMetadata > maximumMetadata || localName > 32768) limit();
    if (localName != name || local > start - 30 - localName - localExtra) {
      damaged();
    }
    if (packed > start - local - 30 - localName - localExtra) damaged();
    final localBytes = read(local + 30, localName);
    for (var i = 0; i < name; i++) {
      if (localBytes.getUint8(i) != directory.getUint8(cursor + 46 + i)) {
        damaged();
      }
    }
    cursor = end;
  }
  if (actual != count) damaged();
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
