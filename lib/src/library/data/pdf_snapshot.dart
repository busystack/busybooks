import 'dart:io';
import 'package:path/path.dart' as p;
import '../../import_export/data/archive_guard.dart';
import 'file_identity.dart';

/// The renderer receives only this content-addressed, application-owned copy.
/// Reopening the user's pathname later cannot change its publication identity.
Future<String> preparePdfSnapshot(
  String root,
  String id,
  String sourcePath, {
  required bool force,
  required bool Function() cancelled,
}) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
    throw const FormatException('Invalid book identity');
  }
  final parent = Directory(p.join(root, 'cache', 'pdf-v1'));
  final target = Directory(p.join(parent.path, id));
  final publication = File(p.join(target.path, 'publication.pdf'));
  for (final path in [
    p.join(root, 'cache'),
    parent.path,
    target.path,
    publication.path,
  ]) {
    if (await FileSystemEntity.isLink(path)) {
      throw const FileSystemException(
        'PDF snapshots must not be symbolic links',
      );
    }
  }
  await parent.create(recursive: true);
  final original = File(sourcePath), before = await File(sourcePath).stat();
  final instance = fileInstance(sourcePath);
  if (before.type != FileSystemEntityType.file ||
      before.size < 5 ||
      before.size > 256 * 1024 * 1024) {
    throw const FileSystemException(
      'Missing original or PDF resource limit exceeded',
    );
  }
  if (!force &&
      await publication.exists() &&
      await publication.length() <= 256 * 1024 * 1024 &&
      await fileSha256(publication, cancelled) == id) {
    if (await fileSha256(original, cancelled) != id) {
      throw const FileSystemException(
        'Original PDF changed during preparation',
      );
    }
    final after = await original.stat();
    if (before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed ||
        instance != fileInstance(sourcePath)) {
      throw const FileSystemException(
        'Original PDF changed during preparation',
      );
    }
    return target.path;
  }
  final stage = await parent.createTemp('.busybooks-pdf-');
  final output = await File(
    p.join(stage.path, 'publication.pdf'),
  ).open(mode: FileMode.write);
  var size = 0;
  var closed = false;
  try {
    await for (final chunk in original.openRead()) {
      if (cancelled()) throw const FormatException('PDF preparation cancelled');
      size += chunk.length;
      if (size > 256 * 1024 * 1024) {
        throw const FormatException('PDF exceeds resource limit');
      }
      await output.writeFrom(chunk);
    }
    await output.flush();
    await output.close();
    closed = true;
    final after = await original.stat();
    if (before.type != FileSystemEntityType.file ||
        after.type != FileSystemEntityType.file ||
        before.size != size ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed ||
        instance != fileInstance(sourcePath) ||
        await fileSha256(
              File(p.join(stage.path, 'publication.pdf')),
              cancelled,
            ) !=
            id) {
      throw const FileSystemException(
        'Original PDF changed during snapshot preparation',
      );
    }
    if (await target.exists()) await target.delete(recursive: true);
    await stage.rename(target.path);
    return target.path;
  } finally {
    if (!closed) await output.close();
    if (await stage.exists()) await stage.delete(recursive: true);
  }
}
