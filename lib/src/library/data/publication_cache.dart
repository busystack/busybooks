import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'file_identity.dart';
import 'pdf_snapshot.dart';
import '../domain/book_format.dart';
import 'comic_book.dart';
import 'epub_cache.dart';
import 'fb2_book.dart';
import 'cache_resources.dart';

String publicationCachePath(String root, String format, String id) => p.join(
  root,
  'cache',
  format == 'pdf'
      ? 'pdf-v1'
      : format == 'epub'
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
  PreparedFb2? verifiedFb2,
  Map<String, dynamic>? verifiedComic,
  bool force = false,
  required bool Function() cancelled,
}) async {
  if (format == 'pdf') {
    return preparePdfSnapshot(
      root,
      id,
      sourcePath,
      force: force,
      cancelled: cancelled,
    );
  }
  if (format == 'epub') {
    await prepareEpubCache(
      root,
      id,
      sourcePath: sourcePath,
      force: force,
      cancelled: cancelled,
    );
    return publicationCachePath(root, format, id);
  }
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
      (format != 'fb2' && !isComicFormat(format))) {
    throw const FormatException('Invalid preparation descriptor');
  }
  final original = File(sourcePath), before = await File(sourcePath).stat();
  final instance = fileInstance(sourcePath);
  Future<void> checkOriginal() async {
    final after = await original.stat();
    if (after.type != FileSystemEntityType.file ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed ||
        fileInstance(sourcePath) != instance) {
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
  if (verifiedFb2 == null &&
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
    '${index.path}.sha256',
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
      final data = await readSealedCacheIndex(index);
      if (data?['version'] == 3 &&
          data?['id'] == id &&
          data?['format'] == format) {
        validatePreparedResourceBudget(data!);
        if (!await completeCachedResources(
          target,
          data['resources'],
          cancelled: cancelled,
        )) {
          throw const FormatException('Incomplete publication cache');
        }
        await validatePreparedClosure(data, target);
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
      final book =
          verifiedFb2 ??
          await prepareFb2File(
            sourcePath,
            originalBookSuffix(sourcePath)!,
            cancelled,
          );
      final resources = <String, Map<String, dynamic>>{};
      for (final entry in book.resources.entries) {
        if (cancelled()) {
          throw const FormatException('FB2 preparation cancelled');
        }
        final filename = sha256.convert(utf8.encode(entry.key)).toString();
        await File(p.join(staging.path, filename)).writeAsBytes(entry.value);
        resources[entry.key] = {
          'file': filename,
          'size': entry.value.length,
          'sha256': sha256.convert(entry.value).toString(),
        };
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
    descriptor = {...descriptor, 'version': 3, 'id': id, 'format': format};
    await validatePreparedClosure(descriptor, staging);
    if (await target.exists()) await target.delete(recursive: true);
    await staging.rename(target.path);
    await writeSealedCacheIndex(index, descriptor);
    return target.path;
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
