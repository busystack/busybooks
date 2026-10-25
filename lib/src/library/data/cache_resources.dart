import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../../core/atomic_file_writer.dart';
import '../../import_export/data/archive_guard.dart';
import 'book_xml.dart';
import 'publication_resource_limits.dart';
import 'comic_resources.dart';

const maximumCacheIndexBytes = 16 * 1024 * 1024;
final _digestPattern = RegExp(r'^[a-f0-9]{64}$');

Future<Map<String, dynamic>?> readSealedCacheIndex(File index) async {
  final seal = File('${index.path}.sha256');
  if (await FileSystemEntity.type(seal.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await seal.length() != 64 ||
      await index.length() > maximumCacheIndexBytes) {
    return null;
  }
  final bytes = await index.readAsBytes();
  if (sha256.convert(bytes).toString() != await seal.readAsString()) {
    return null;
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  return decoded is Map ? decoded.cast<String, dynamic>() : null;
}

Future<void> writeSealedCacheIndex(
  File index,
  Map<String, dynamic> value,
) async {
  final bytes = utf8.encode(jsonEncode(value));
  if (bytes.length > maximumCacheIndexBytes) {
    throw const FormatException('Publication resource index limit exceeded');
  }
  const writer = AtomicFileWriter();
  await writer.writeBytes(index.path, bytes, overwrite: true);
  await writer.writeBytes(
    '${index.path}.sha256',
    ascii.encode(sha256.convert(bytes).toString()),
    overwrite: true,
  );
}

Future<bool> completeCachedResources(
  Directory directory,
  dynamic resources, {
  required bool Function() cancelled,
}) async {
  if (resources is! Map || resources.isEmpty || resources.length > 20000) {
    return false;
  }
  final files = <String>{};
  for (final entry in resources.entries) {
    if (cancelled()) throw const FormatException('Book preparation cancelled');
    final value = entry.value;
    if (entry.key is! String ||
        value is! Map ||
        value['file'] !=
            sha256.convert(utf8.encode(entry.key as String)).toString() ||
        value['size'] is! int ||
        value['size'] < 0 ||
        value['size'] > 64 * 1024 * 1024 ||
        value['sha256'] is! String ||
        !_digestPattern.hasMatch(value['sha256'] as String) ||
        !files.add(value['file'] as String)) {
      return false;
    }
    final file = File(p.join(directory.path, value['file'] as String));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() != value['size'] ||
        await fileSha256(file, cancelled) != value['sha256']) {
      return false;
    }
  }
  await for (final file in directory.list(followLinks: false)) {
    if (file is! File || !files.remove(p.basename(file.path))) return false;
  }
  return files.isEmpty;
}

String? epubResourcePath(String base, String href) {
  final reference = Uri.parse(href);
  if (reference.hasScheme || reference.hasAuthority) return null;
  final resolved = Uri.decodeComponent(
    Uri(path: base).resolveUri(reference).path,
  );
  return resolved.startsWith('/') ? resolved.substring(1) : resolved;
}

Future<Map<String, int>> validateEpubClosure(
  Map<String, int> resources,
  Future<Uint8List?> Function(String, int) read,
) async {
  Never invalid() =>
      throw const FormatException('Incomplete EPUB resource descriptor');
  final limits = {
    for (final name in resources.keys) name: epubResourceLimit(name),
  };
  final assigned = <String>{};
  final mime = await read('mimetype', 128);
  if (mime == null || utf8.decode(mime).trim() != 'application/epub+zip') {
    invalid();
  }
  final containerBytes = await read('META-INF/container.xml', 1024 * 1024);
  if (containerBytes == null) invalid();
  final container = boundedBookXml(containerBytes, maximumBytes: 1024 * 1024);
  final paths = container.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'rootfile')
      .map((e) => e.getAttribute('full-path'))
      .whereType<String>()
      .toList();
  if (paths.isEmpty) invalid();
  for (final path in paths) {
    final bytes = await read(path, 4 * 1024 * 1024);
    if (bytes == null) invalid();
    final package = boundedBookXml(bytes, maximumBytes: 4 * 1024 * 1024);
    if (package.rootElement.name.local != 'package') invalid();
    final ids = <String>{};
    for (final item in package.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'item',
    )) {
      final href = item.getAttribute('href'), id = item.getAttribute('id');
      if (href == null || id == null || !ids.add(id)) invalid();
      final resource = epubResourcePath(path, href);
      if (resource != null) {
        if (!resources.containsKey(resource)) invalid();
        final limit = epubResourceLimit(
          resource,
          mediaType: item.getAttribute('media-type') ?? '',
          navigation: (item.getAttribute('properties') ?? '')
              .split(RegExp(r'\s+'))
              .contains('nav'),
        );
        // The manifest's declared image/font type may raise a generic extension
        // allowance; known filename limits remain authoritative.
        if (assigned.add(resource) || limit < limits[resource]!) {
          limits[resource] = limit;
        }
      }
    }
    for (final item in package.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'itemref',
    )) {
      if (!ids.contains(item.getAttribute('idref'))) invalid();
    }
  }
  for (final entry in resources.entries) {
    if (entry.value < 0 || entry.value > limits[entry.key]!) {
      throw FormatException(
        'EPUB resource exceeds its media limit: ${entry.key}',
      );
    }
  }
  return limits;
}

void validatePreparedResourceBudget(Map data) {
  final resources = data['resources'];
  if (resources is! Map || resources.isEmpty || resources.length > 20000) {
    throw const FormatException('Incomplete publication resource descriptor');
  }
  final comic = ComicResourceBudget();
  var fb2Total = 0;
  for (final entry in resources.entries) {
    if (entry.key is! String ||
        entry.value is! Map ||
        entry.value['size'] is! int ||
        entry.value['size'] < 0) {
      throw const FormatException('Invalid publication resource size');
    }
    final name = entry.key as String, size = entry.value['size'] as int;
    if (data['format'] == 'fb2') {
      final limit = name.startsWith('sections/')
          ? epubTextBytes
          : 16 * 1024 * 1024;
      fb2Total += size;
      if (size > limit || fb2Total > 64 * 1024 * 1024) {
        throw const FormatException('FB2 prepared resource limit exceeded');
      }
    } else if (comic.add(name, size) == ComicResource.discard) {
      throw const FormatException(
        'Irrelevant comic resources must not be cached',
      );
    }
  }
}

Future<void> validatePreparedClosure(Map data, Directory directory) async {
  validatePreparedResourceBudget(data);
  Never invalid() =>
      throw const FormatException('Incomplete publication resource descriptor');
  final resources = data['resources'];
  if (resources is! Map) invalid();
  if (data['format'] == 'fb2') {
    final sections = data['sections'];
    if (sections is! List ||
        sections.isEmpty ||
        sections.length > 10000 ||
        data['toc'] is! List ||
        data['metadata'] is! Map) {
      invalid();
    }
    final paths = <String>{}, ids = <String>{};
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      if (section is! Map ||
          section['path'] != 'sections/$i.xhtml' ||
          section['id'] is! String ||
          !ids.add(section['id'] as String) ||
          section['notes'] is! bool ||
          !resources.containsKey(section['path'])) {
        invalid();
      }
      paths.add(section['path'] as String);
      final resource = resources[section['path']] as Map;
      if (resource['size'] > epubTextBytes) invalid();
      final doc = boundedBookXml(
        await File(
          p.join(directory.path, resource['file'] as String),
        ).readAsBytes(),
        maximumBytes: epubTextBytes,
      );
      for (final node in doc.descendants.whereType<XmlElement>()) {
        final src = node.getAttribute('src'), href = node.getAttribute('href');
        if (src != null && !resources.containsKey(src)) invalid();
        if (href != null &&
            !Uri.parse(href).hasScheme &&
            !resources.containsKey(href.split('#').first)) {
          invalid();
        }
      }
    }
    for (final name in resources.keys) {
      if (name is! String ||
          (!paths.contains(name) && !RegExp(r'^binary/\d+$').hasMatch(name))) {
        invalid();
      }
    }
    void outline(List rows) {
      for (final row in rows) {
        if (row is! Map ||
            row['href'] is! String ||
            !paths.contains((row['href'] as String).split('#').first)) {
          invalid();
        }
        if (row['subitems'] is List) outline(row['subitems'] as List);
      }
    }

    outline(data['toc'] as List);
  } else {
    final pages = data['pages'];
    if (pages is! List ||
        pages.isEmpty ||
        pages.length > 10000 ||
        data['metadata'] is! Map) {
      invalid();
    }
    for (final entry in resources.entries) {
      final name = entry.key as String;
      final suffix = p.posix.extension(name).toLowerCase();
      if (![
            '.jpg',
            '.jpeg',
            '.jpe',
            '.jfif',
            '.png',
            '.webp',
          ].contains(suffix) &&
          !(p.posix.basename(name).toLowerCase() == 'comicinfo.xml' &&
              entry.value['size'] <= 1024 * 1024)) {
        invalid();
      }
    }
    final names = <String>{};
    for (final page in pages) {
      if (page is! Map ||
          page['name'] is! String ||
          !names.add(page['name'] as String)) {
        invalid();
      }
      final resource = resources[page['name']];
      if (resource is! Map ||
          page['file'] != resource['file'] ||
          page['size'] != resource['size'] ||
          page['width'] is! int ||
          page['height'] is! int ||
          page['width'] <= 0 ||
          page['height'] <= 0 ||
          page['width'] > 16000 ||
          page['height'] > 16000 ||
          page['width'] * page['height'] > 32 * 1024 * 1024) {
        invalid();
      }
    }
    final expected = resources.keys
        .whereType<String>()
        .where(
          (name) => [
            '.jpg',
            '.jpeg',
            '.jpe',
            '.jfif',
            '.png',
            '.webp',
          ].contains(p.posix.extension(name).toLowerCase()),
        )
        .toSet();
    if (names.length != expected.length || !names.containsAll(expected)) {
      invalid();
    }
  }
}
