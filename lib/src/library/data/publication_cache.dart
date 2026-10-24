import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../../core/atomic_file_writer.dart';
import '../domain/book_format.dart';
import 'comic_book.dart';
import 'epub_cache.dart';
import 'fb2_book.dart';
import 'cache_resources.dart';

String publicationCachePath(String root, String format, String id) => p.join(
  root,
  'cache',
  format == 'epub'
      ? 'epub'
      : format == 'fb2'
      ? 'fb2-v2'
      : 'comic-v2',
  id,
);

Future<String> preparePublicationCache(
  String root,
  String id,
  String format, {
  required String sourcePath,
  Uint8List? verifiedBytes,
  Map<String, dynamic>? verifiedComic,
  bool force = false,
  required bool Function() cancelled,
}) async {
  if (format == 'pdf') return publicationCachePath(root, format, id);
  if (format == 'epub') {
    await prepareEpubCache(
      root,
      id,
      sourcePath: sourcePath,
      verifiedBytes: verifiedBytes,
      force: force,
      cancelled: cancelled,
    );
    return publicationCachePath(root, format, id);
  }
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
      (format != 'fb2' && !isComicFormat(format))) {
    throw const FormatException('Invalid preparation descriptor');
  }
  final original = File(sourcePath), before = await original.stat();
  Future<void> checkOriginal() async {
    final after = await original.stat();
    if (after.type != FileSystemEntityType.file ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed) {
      throw const FileSystemException(
        'Original changed during cache preparation',
      );
    }
  }

  if (before.type != FileSystemEntityType.file ||
      before.size > maximumBookBytes(format)) {
    throw const FileSystemException(
      'Missing original or book resource limit exceeded',
    );
  }
  if (verifiedBytes == null &&
      verifiedComic == null &&
      (await sha256.bind(original.openRead()).first).toString() != id) {
    throw const FileSystemException('Original book changed during preparation');
  }
  final target = Directory(publicationCachePath(root, format, id));
  final parent = target.parent, index = File('${target.path}.json');
  for (final path in [
    p.join(root, 'cache'),
    parent.path,
    target.path,
    index.path,
  ]) {
    if (await FileSystemEntity.isLink(path)) {
      throw const FileSystemException(
        'Publication caches must not be symbolic links',
      );
    }
  }
  await parent.create(recursive: true);
  if (!force && await index.exists() && await target.exists()) {
    try {
      if (await index.length() > 16 * 1024 * 1024) {
        throw const FormatException(
          'Publication resource index limit exceeded',
        );
      }
      final data = jsonDecode(await index.readAsString()) as Map;
      if (data['version'] == 1 &&
          data['id'] == id &&
          data['format'] == format &&
          await completeCachedResources(
            target,
            data['resources'],
            cancelled: cancelled,
          )) {
        await checkOriginal();
        if (verifiedComic?['directory'] case final String path) {
          final old = Directory(path);
          if (await old.exists()) await old.delete(recursive: true);
        }
        return target.path;
      }
    } catch (_) {
      /* Regenerate interrupted or damaged disposable resources. */
    }
  }
  final staging = verifiedComic != null
      ? Directory(verifiedComic['directory'] as String)
      : await parent.createTemp('.busybooks-publication-');
  try {
    Map<String, dynamic> descriptor;
    if (format == 'fb2') {
      final bytes = verifiedBytes ?? await original.readAsBytes();
      final book = prepareFb2(
        unwrapFb2(bytes, originalBookSuffix(sourcePath)!),
      );
      final resources = <String, Map<String, dynamic>>{};
      for (final entry in book.resources.entries) {
        if (cancelled()) {
          throw const FormatException('FB2 preparation cancelled');
        }
        final filename = sha256.convert(utf8.encode(entry.key)).toString();
        await File(p.join(staging.path, filename)).writeAsBytes(entry.value);
        resources[entry.key] = {'file': filename, 'size': entry.value.length};
      }
      descriptor = {
        'sections': book.sections,
        'toc': book.toc,
        'metadata': book.metadata,
        'resources': resources,
      };
    } else {
      descriptor =
          verifiedComic ??
          await extractComic(sourcePath, format, staging, cancelled);
      descriptor = Map<String, dynamic>.of(descriptor)..remove('directory');
    }
    await checkOriginal();
    if (cancelled()) throw const FormatException('Book preparation cancelled');
    final encoded = utf8.encode(
      jsonEncode({...descriptor, 'version': 1, 'id': id, 'format': format}),
    );
    if (encoded.length > 16 * 1024 * 1024) {
      throw const FormatException('Publication resource index limit exceeded');
    }
    if (await target.exists()) await target.delete(recursive: true);
    await staging.rename(target.path);
    await const AtomicFileWriter().writeBytes(
      index.path,
      encoded,
      overwrite: true,
    );
    return target.path;
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
