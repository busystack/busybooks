import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import '../../import_export/data/archive_guard.dart';
import 'cache_resources.dart';
import 'file_identity.dart';
import 'book_xml.dart';
import 'publication_resource_limits.dart';

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
    if (await FileSystemEntity.type(resourceFile.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await resourceFile.length() > maximum) {
      return null;
    }
    return resourceFile.readAsBytes();
  }

  if (!force && await index.exists() && await target.exists()) {
    try {
      final metadata = await readSealedCacheIndex(index);
      if (metadata?['version'] == 4 && metadata?['id'] == id) {
        final resources = metadata!['resources'] as Map;
        final limits = await validateEpubClosure({
          for (final e in resources.entries)
            e.key as String: e.value['size'] as int,
        }, readCached);
        for (final entry in resources.entries) {
          final maximum = entry.value['maximumBytes'];
          if (maximum is! int ||
              maximum < 0 ||
              maximum > limits[entry.key]! ||
              entry.value['size'] > maximum) {
            throw const FormatException('Invalid EPUB media limits');
          }
        }
        if (!await completeCachedResources(
          target,
          resources,
          cancelled: cancelled,
        )) {
          throw const FormatException('Incomplete EPUB cache');
        }
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
    final limits = await validateEpubClosure({
      for (final e in archive.entries.entries)
        if (!e.key.endsWith('/')) e.key: e.value.uncompressedSize,
    }, (name, maximum) async => archive.read(name, maximumBytes: maximum));
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
        maximumBytes: limits[entry.filename]!,
      );
      final output = File(p.join(staging.path, filename));
      var maximum = limits[entry.filename]!;
      final prefix = entry.uncompressedSize == 0
          ? Uint8List(0)
          : await output
                .openRead(0, entry.uncompressedSize.clamp(0, 512))
                .first;
      var offset = 0;
      if (prefix.length >= 3 &&
          prefix[0] == 239 &&
          prefix[1] == 187 &&
          prefix[2] == 191) {
        offset = 3;
      }
      final utf16 =
          prefix.length >= 2 &&
          (prefix[0] == 255 && prefix[1] == 254 ||
              prefix[0] == 254 && prefix[1] == 255 ||
              prefix[0] == 60 && prefix[1] == 0 ||
              prefix[0] == 0 && prefix[1] == 60);
      while (offset < prefix.length &&
          [9, 10, 13, 32].contains(prefix[offset])) {
        offset++;
      }
      final markup = utf16 || offset == prefix.length || prefix[offset] == 60;
      if (markup && maximum > epubTextBytes) maximum = epubTextBytes;
      final signature = prefix.length >= 4
          ? latin1.decode(prefix.sublist(0, 4))
          : '';
      if ([
            'OTTO',
            'ttcf',
            'true',
            'typ1',
            'wOFF',
            'wOF2',
            '\u0000\u0001\u0000\u0000',
          ].contains(signature) &&
          maximum > epubFontBytes) {
        maximum = epubFontBytes;
      }
      if (entry.uncompressedSize > maximum) {
        throw FormatException(
          'EPUB resource exceeds its media limit: ${entry.filename}',
        );
      }
      final suffix = p.posix.extension(entry.filename).toLowerCase();
      if (markup ||
          [
            '.xhtml',
            '.xml',
            '.opf',
            '.ncx',
            '.svg',
            '.html',
            '.htm',
          ].contains(suffix)) {
        final text = decodeBookXml(await output.readAsBytes());
        if (['.xhtml', '.xml', '.opf', '.ncx', '.svg'].contains(suffix)) {
          validateBookXmlStructure(text, maximumNodes: 100000);
        } else {
          validateBookMarkup(text);
        }
      }
      resources[entry.filename] = {
        'file': filename,
        'size': entry.uncompressedSize,
        'sha256': digest,
        'maximumBytes': maximum,
      };
    }
    await checkOriginal();
    if (cancelled()) throw const FormatException('EPUB preparation cancelled');
    if (await target.exists()) await target.delete(recursive: true);
    await staging.rename(target.path);
    await writeSealedCacheIndex(index, {
      'version': 4,
      'id': id,
      'resources': resources,
    });
  } finally {
    await archive.close();
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
