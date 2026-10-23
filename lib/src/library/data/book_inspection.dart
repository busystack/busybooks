import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../../import_export/data/archive_guard.dart';
import 'cover_image.dart';
import '../domain/book_format.dart';
import 'book_xml.dart';
import 'fb2_book.dart';
import 'comic_book.dart';

// Inspects the original file in the owned I/O worker. Never copies publications.
Future<Map<String, dynamic>> inspectBook(
  String source,
  bool Function() cancelled, {
  void Function(Uint8List)? retainBytes,
  void Function(Map<String, dynamic>)? retainComic,
  String? comicStagingRoot,
  void Function(FileStat)? validatedStat,
  void Function(String)? identified,
}) async {
  final format = bookFormatForPath(source), suffix = originalBookSuffix(source);
  if (format == null) {
    throw const FormatException(
      'Only DRM-free EPUB 2/3, PDF, FB2, CBZ and CBR are supported',
    );
  }
  final input = File(source);
  final before = await input.stat();
  if (before.type != FileSystemEntityType.file ||
      before.size < 5 ||
      before.size > maximumBookBytes(format)) {
    throw FormatException(
      'Book must be a regular file between 5 bytes and ${isComicFormat(format) ? '1 GiB' : '256 MiB'}',
    );
  }
  final builder = format == 'epub' || format == 'fb2'
      ? BytesBuilder(copy: false)
      : null;
  final digest = _DigestSink();
  // Stream SHA-256 and retain only the PDF header/trailer, not a whole PDF buffer.
  final hasher = sha256.startChunkedConversion(digest);
  var count = 0;
  var trailer = Uint8List(0);
  final header = <int>[];
  await for (final chunk in input.openRead()) {
    if (cancelled()) throw const FormatException('Opening cancelled');
    count += chunk.length;
    if (count > maximumBookBytes(format)) {
      throw const FormatException('Book exceeds resource limit');
    }
    hasher.add(chunk);
    builder?.add(chunk);
    if (format == 'pdf') {
      if (header.length < 5) header.addAll(chunk.take(5 - header.length));
      final combined = Uint8List(trailer.length + chunk.length)
        ..setAll(0, trailer)
        ..setAll(trailer.length, chunk);
      trailer = Uint8List.fromList(
        combined.sublist((combined.length - 65536).clamp(0, combined.length)),
      );
    }
  }
  hasher.close();
  final bytes = builder?.takeBytes();
  final after = await input.stat();
  if (before.size != after.size ||
      before.modified != after.modified ||
      before.changed != after.changed ||
      count != after.size) {
    throw const FileSystemException('Book changed while it was being opened');
  }
  final id = digest.value!.toString();
  identified?.call(id);
  final book = <String, dynamic>{
    'id': id,
    'kind': 'book',
    'format': format,
    'originalSuffix': suffix,
    'title': p
        .basename(source)
        .substring(0, p.basename(source).length - suffix!.length - 1),
    'author': '',
    'language': '',
    'series': '',
    'seriesOrder': 0,
    'state': 'unread',
    'progress': 0.0,
    'added': DateTime.now().millisecondsSinceEpoch,
  };
  if (format == 'epub') {
    final archive = validatedArchive(bytes!);
    final mimetype = archive.findFile('mimetype');
    if (mimetype == null ||
        utf8.decode(mimetype.content).trim() != 'application/epub+zip') {
      throw const FormatException('Invalid EPUB mimetype');
    }
    final container = archive.findFile('META-INF/container.xml');
    if (container == null || container.size > 1024 * 1024) {
      throw const FormatException('Missing EPUB container');
    }
    final xml = boundedBookXml(container.content, maximumBytes: 1024 * 1024);
    final path = xml.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'rootfile')
        .firstOrNull
        ?.getAttribute('full-path');
    final packageFile = archive.findFile(path ?? '');
    if (packageFile == null || packageFile.size > 4 * 1024 * 1024) {
      throw const FormatException('Missing EPUB package');
    }
    final package = boundedBookXml(
      packageFile.content,
      maximumBytes: 4 * 1024 * 1024,
    );
    final version = package.rootElement.getAttribute('version') ?? '';
    if (package.rootElement.name.local != 'package' ||
        package.rootElement.namespaceUri != 'http://www.idpf.org/2007/opf' ||
        !(version == '2.0' || version.startsWith('3.'))) {
      throw const FormatException(
        'Only EPUB 2 and EPUB 3 packages are supported',
      );
    }
    final encryption = archive.findFile('META-INF/encryption.xml');
    if (encryption != null) {
      final encrypted = boundedBookXml(encryption.content);
      for (final method in encrypted.descendants.whereType<XmlElement>().where(
        (element) => element.name.local == 'EncryptionMethod',
      )) {
        if (![
          'http://www.idpf.org/2008/embedding',
          'http://ns.adobe.com/pdf/enc#RC',
        ].contains(method.getAttribute('Algorithm'))) {
          throw const FormatException('DRM-protected EPUB is unsupported');
        }
      }
    }
    String text(String name) => package.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == name)
        .map((element) => element.innerText.trim())
        .where((value) => value.isNotEmpty)
        .join(name == 'creator' ? ', ' : ' ');
    for (final entry in {
      'title': 'title',
      'author': 'creator',
      'language': 'language',
    }.entries) {
      final value = text(entry.value);
      if (value.isNotEmpty) {
        book[entry.key] = value;
      }
    }
    for (final meta in package.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'meta',
    )) {
      if (meta.getAttribute('property') == 'belongs-to-collection') {
        book['series'] = meta.innerText;
      }
      if (meta.getAttribute('property') == 'group-position') {
        book['seriesOrder'] = num.tryParse(meta.innerText) ?? 0;
      }
      if (meta.getAttribute('name') == 'calibre:series') {
        book['series'] = meta.getAttribute('content') ?? '';
      }
      if (meta.getAttribute('name') == 'calibre:series_index') {
        book['seriesOrder'] =
            num.tryParse(meta.getAttribute('content') ?? '') ?? 0;
      }
    }
    final coverId = package.descendants
        .whereType<XmlElement>()
        .where(
          (e) => e.name.local == 'meta' && e.getAttribute('name') == 'cover',
        )
        .firstOrNull
        ?.getAttribute('content');
    final coverItem = package.descendants
        .whereType<XmlElement>()
        .where(
          (element) =>
              element.name.local == 'item' &&
              ((coverId != null && element.getAttribute('id') == coverId) ||
                  (element.getAttribute('properties') ?? '')
                      .split(' ')
                      .contains('cover-image')) &&
              (element.getAttribute('media-type') ?? '').startsWith('image/'),
        )
        .firstOrNull;
    if (coverItem != null) {
      final href = coverItem.getAttribute('href') ?? '';
      final cover = archive.findFile(
        p.posix.normalize(
          p.posix.join(p.posix.dirname(path!), Uri.decodeComponent(href)),
        ),
      );
      if (cover != null) {
        try {
          book['cover'] = libraryCover(
            cover.content,
            coverItem.getAttribute('media-type') ?? '',
          );
        } catch (_) {
          /* Optional cover failure must not discard readable text. */
        }
      }
    }
    if (book['cover'] == null) {
      // OPF 2 meta/guide may identify an XHTML cover page. Resolve its image
      // relative to that document, without labeling XHTML bytes as an image.
      try {
        final pageItem = package.descendants
            .whereType<XmlElement>()
            .where(
              (e) => e.name.local == 'item' && e.getAttribute('id') == coverId,
            )
            .firstOrNull;
        final guide = package.descendants
            .whereType<XmlElement>()
            .where(
              (e) =>
                  e.name.local == 'reference' &&
                  (e.getAttribute('type') ?? '').split(' ').contains('cover'),
            )
            .firstOrNull;
        final href =
            pageItem?.getAttribute('href') ?? guide?.getAttribute('href');
        if (href != null) {
          final pagePath = p.posix.normalize(
            p.posix.join(
              p.posix.dirname(path!),
              Uri.decodeComponent(href.split('#').first),
            ),
          );
          final page = archive.findFile(pagePath);
          if (page != null && page.size <= 4 * 1024 * 1024) {
            if (pageItem?.getAttribute('media-type')?.startsWith('image/') ==
                true) {
              book['cover'] = libraryCover(
                page.content,
                pageItem?.getAttribute('media-type') ?? '',
              );
            } else {
              final coverDoc = boundedBookXml(
                page.content,
                maximumBytes: 4 * 1024 * 1024,
              );
              final src = coverDoc.descendants
                  .whereType<XmlElement>()
                  .where((e) => e.name.local == 'img')
                  .firstOrNull
                  ?.getAttribute('src');
              if (src != null) {
                final image = archive.findFile(
                  p.posix.normalize(
                    p.posix.join(
                      p.posix.dirname(pagePath),
                      Uri.decodeComponent(src),
                    ),
                  ),
                );
                if (image != null) {
                  book['cover'] = libraryCover(image.content, '');
                }
              }
            }
          }
        }
      } catch (_) {
        /* Optional cover metadata does not prevent reading. */
      }
    }
  } else if (format == 'fb2') {
    book.addAll(
      prepareFb2(unwrapFb2(bytes!, suffix)).metadata
        ..removeWhere((key, value) => value == null || value == ''),
    );
  } else if (isComicFormat(format)) {
    final parent = comicStagingRoot == null
        ? Directory.systemTemp
        : Directory(comicStagingRoot);
    if (comicStagingRoot != null) {
      for (final path in [parent.parent.path, parent.path]) {
        if (await FileSystemEntity.isLink(path)) {
          throw const FileSystemException(
            'Comic cache must not be a symbolic link',
          );
        }
      }
      await parent.create(recursive: true);
    }
    final stage = await parent.createTemp('.busybooks-comic-');
    var retained = false;
    try {
      final prepared = await extractComic(source, format, stage, cancelled);
      final stat = await input.stat();
      if (after.size != stat.size ||
          after.modified != stat.modified ||
          after.changed != stat.changed) {
        throw const FileSystemException('Comic changed during inspection');
      }
      book.addAll(
        (prepared['metadata'] as Map).cast<String, dynamic>()
          ..removeWhere((key, value) => value == null || value == ''),
      );
      if (retainComic != null) {
        retainComic({...prepared, 'directory': stage.path});
        retained = true;
      }
    } finally {
      if (!retained && await stage.exists()) {
        await stage.delete(recursive: true);
      }
    }
  } else {
    if (ascii.decode(header, allowInvalid: true) != '%PDF-') {
      throw const FormatException('Invalid PDF header');
    }
    final trailerText = latin1.decode(trailer);
    if (!trailerText.contains('%%EOF') || !trailerText.contains('startxref')) {
      throw const FormatException('Damaged PDF trailer');
    }
    // PDF.js performs structural/password validation before the UI publishes
    // the first readable page. No PDF layout/parser is duplicated here.
  }
  if (bytes != null) retainBytes?.call(bytes);
  validatedStat?.call(after);
  return book;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
