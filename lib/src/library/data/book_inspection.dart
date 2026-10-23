import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../../import_export/data/archive_guard.dart';
import 'cover_image.dart';

// Inspects the original file in the owned I/O worker. Never copies publications.
Future<Map<String, dynamic>> inspectBook(
  String source,
  bool Function() cancelled, {
  void Function(Uint8List)? retainEpub,
  void Function(FileStat)? validatedStat,
}) async {
  final extension = p.extension(source).toLowerCase();
  if (!['.epub', '.pdf'].contains(extension)) {
    throw const FormatException('Only DRM-free EPUB 3 and PDF are supported');
  }
  final input = File(source);
  final before = await input.stat();
  if (before.type != FileSystemEntityType.file ||
      before.size < 5 ||
      before.size > 256 * 1024 * 1024) {
    throw const FormatException(
      'Book must be a regular file between 5 bytes and 256 MiB',
    );
  }
  final builder = extension == '.epub' ? BytesBuilder(copy: false) : null;
  final digest = _DigestSink();
  // Stream SHA-256 and retain only the PDF header/trailer, not a whole PDF buffer.
  final hasher = sha256.startChunkedConversion(digest);
  var count = 0;
  var trailer = Uint8List(0);
  final header = <int>[];
  await for (final chunk in input.openRead()) {
    if (cancelled()) throw const FormatException('Opening cancelled');
    count += chunk.length;
    if (count > 256 * 1024 * 1024) {
      throw const FormatException('Book exceeds resource limit');
    }
    hasher.add(chunk);
    builder?.add(chunk);
    if (extension == '.pdf') {
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
  final book = <String, dynamic>{
    'id': id,
    'kind': 'book',
    'format': extension.substring(1),
    'title': p.basenameWithoutExtension(source),
    'author': '',
    'language': '',
    'series': '',
    'seriesOrder': 0,
    'state': 'unread',
    'progress': 0.0,
    'added': DateTime.now().millisecondsSinceEpoch,
  };
  if (extension == '.epub') {
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
    final xml = XmlDocument.parse(utf8.decode(container.content));
    final path = xml.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'rootfile')
        .firstOrNull
        ?.getAttribute('full-path');
    final packageFile = archive.findFile(path ?? '');
    if (packageFile == null || packageFile.size > 4 * 1024 * 1024) {
      throw const FormatException('Missing EPUB package');
    }
    final package = XmlDocument.parse(utf8.decode(packageFile.content));
    if (package.rootElement.getAttribute('version')?.startsWith('3.') != true) {
      throw const FormatException('Only EPUB 3 is supported');
    }
    final encryption = archive.findFile('META-INF/encryption.xml');
    if (encryption != null) {
      final encrypted = XmlDocument.parse(utf8.decode(encryption.content));
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
    }
    final coverItem = package.descendants
        .whereType<XmlElement>()
        .where(
          (element) =>
              element.name.local == 'item' &&
              (element.getAttribute('properties') ?? '')
                  .split(' ')
                  .contains('cover-image'),
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
        book['cover'] = libraryCover(
          cover.content,
          coverItem.getAttribute('media-type') ?? '',
        );
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
  if (extension == '.epub' && bytes != null) retainEpub?.call(bytes);
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
