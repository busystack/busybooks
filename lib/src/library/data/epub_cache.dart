import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import '../../import_export/data/archive_guard.dart';
import 'cache_resources.dart';
import 'file_identity.dart';

// Original EPUB resources, streamed to disposable files without retaining the
// compressed publication or its expanded resources in memory.
Future<void> prepareEpubCache(
  String root,
  String id, {
  required String sourcePath,
  bool force = false,
  required bool Function() cancelled,
}) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
    throw const FormatException('Invalid book identity');
  }
  final parent = Directory(p.join(root, 'cache', 'epub'));
  final target = Directory(p.join(parent.path, id));
  final index = File('${target.path}.json');
  for (final path in [
    p.join(root, 'cache'),
    parent.path,
    target.path,
    index.path,
    '${index.path}.sha256',
  ]) {
    if (await FileSystemEntity.isLink(path)) {
      throw const FileSystemException(
        'The EPUB cache must not be a symbolic link',
      );
    }
  }
  await parent.create(recursive: true);
  final file = File(sourcePath), before = await File(sourcePath).stat();
  final instance = fileInstance(sourcePath);
  Future<void> checkOriginal() async {
    final after = await file.stat();
    if (before.type != FileSystemEntityType.file ||
        after.type != FileSystemEntityType.file ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed ||
        fileInstance(sourcePath) != instance) {
      throw const FileSystemException(
        'Original EPUB changed during cache preparation',
      );
    }
  }

  if (before.size > 256 * 1024 * 1024) {
    throw const FormatException('EPUB exceeds resource limit');
  }
  if (await fileSha256(file, cancelled) != id) {
    throw const FileSystemException(
      'Original EPUB changed during cache preparation',
    );
  }
  Future<Uint8List?> readCached(String name, int maximum) async {
    final resourceFile = File(
      p.join(target.path, sha256.convert(utf8.encode(name)).toString()),
    );
    if (!await resourceFile.exists() || await resourceFile.length() > maximum) {
      return null;
    }
    return resourceFile.readAsBytes();
  }

  if (!force && await index.exists() && await target.exists()) {
    try {
      final metadata = await readSealedCacheIndex(index);
      if (metadata?['version'] == 3 &&
          metadata?['id'] == id &&
          await completeCachedResources(
            target,
            metadata?['resources'],
            cancelled: cancelled,
          )) {
        await validateEpubClosure(metadata!['resources'] as Map, readCached);
        await checkOriginal();
        return;
      }
    } catch (_) {
      /* Regenerate a damaged disposable representation. */
    }
  }
  final archive = await FileBackedZip.open(sourcePath);
  final staging = await parent.createTemp('.busybooks-epub-');
  try {
    await validateEpubClosure(
      archive.entries,
      (name, maximum) async => archive.read(name, maximumBytes: maximum),
    );
    final resources = <String, Map<String, Object>>{};
    for (final entry in archive.entries.values) {
      if (cancelled()) {
        throw const FormatException('EPUB preparation cancelled');
      }
      if (entry.filename.endsWith('/')) continue;
      // Case-sensitive logical paths never become filesystem paths.
      final filename = sha256.convert(utf8.encode(entry.filename)).toString();
      final digest = await streamZipEntry(
        entry,
        File(p.join(staging.path, filename)),
        cancelled,
      );
      resources[entry.filename] = {
        'file': filename,
        'size': entry.uncompressedSize,
        'sha256': digest,
      };
    }
    await checkOriginal();
    if (cancelled()) throw const FormatException('EPUB preparation cancelled');
    if (await target.exists()) await target.delete(recursive: true);
    await staging.rename(target.path);
    await writeSealedCacheIndex(index, {
      'version': 3,
      'id': id,
      'resources': resources,
    });
  } finally {
    await archive.close();
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
