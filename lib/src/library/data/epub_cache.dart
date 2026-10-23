import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import '../../core/atomic_file_writer.dart';
import '../../import_export/data/archive_guard.dart';

// A disposable byte-for-byte resource cache, not a converted publication.
// Foliate consumes its documented loader interface with original EPUB paths.
Future<void> prepareEpubCache(
  String root,
  String id, {
  required String sourcePath,
  bool force = false,
  Uint8List? verifiedBytes,
  required bool Function() cancelled,
}) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
    throw const FormatException('Invalid book identity');
  }
  final parent = Directory(p.join(root, 'cache', 'epub'));
  await parent.create(recursive: true);
  for (final path in [
    p.join(root, 'cache'),
    parent.path,
    p.join(parent.path, id),
  ]) {
    if (await FileSystemEntity.isLink(path)) {
      throw const FileSystemException(
        'The EPUB cache must not be a symbolic link',
      );
    }
  }
  final target = Directory(p.join(parent.path, id));
  final index = File(p.join(parent.path, '$id.json'));
  if (!force && await index.exists() && await target.exists()) {
    try {
      final metadata = jsonDecode(await index.readAsString()) as Map;
      if (metadata['version'] == 2 &&
          metadata['id'] == id &&
          metadata['resources'] is Map) {
        return;
      }
    } catch (_) {
      /* An interrupted or damaged cache is regenerated. */
    }
  }
  final file = File(sourcePath);
  if (await file.length() > 256 * 1024 * 1024) {
    throw const FormatException('EPUB exceeds resource limit');
  }
  final bytes = verifiedBytes ?? await file.readAsBytes();
  if (verifiedBytes == null && sha256.convert(bytes).toString() != id) {
    throw const FileSystemException(
      'Original EPUB changed during cache preparation',
    );
  }
  final archive = validatedArchive(bytes);
  final staging = await parent.createTemp('.busybooks-epub-');
  try {
    final resources = <String, Map<String, Object>>{};
    for (final entry in archive) {
      if (cancelled()) {
        throw const FormatException('EPUB preparation cancelled');
      }
      if (entry.isFile) {
        // EPUB names are case sensitive even on Windows. Never URI-decode
        // archive names into filesystem paths: all physical names are hashes.
        final filename = sha256.convert(utf8.encode(entry.name)).toString();
        final output = File(p.join(staging.path, filename));
        await output.writeAsBytes(entry.content);
        resources[entry.name] = {'file': filename, 'size': entry.size};
      }
    }
    if (await target.exists()) {
      await target.delete(recursive: true);
    }
    await staging.rename(target.path);
    await const AtomicFileWriter().writeBytes(
      index.path,
      utf8.encode(jsonEncode({'version': 2, 'id': id, 'resources': resources})),
      overwrite: true,
    );
  } finally {
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
  }
}
