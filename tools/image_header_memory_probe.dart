import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:busybooks/src/library/data/comic_book.dart';
import 'package:busybooks/src/library/data/cover_image.dart';
import 'package:busybooks/src/library/data/fb2_book.dart';
import 'package:path/path.dart' as p;

// Compile to AOT and run each mode in a fresh process. A tiny declared-geometry
// probe must be rejected without the JPEG decoder's coefficient allocations.
Future<void> main(List<String> args) async {
  final mode = args.single;
  final bytes = Uint8List.fromList([
    0xff,
    0xd8,
    0xff,
    0xc0,
    0,
    17,
    8,
    0x17,
    0x70,
    0x17,
    0x70,
    3,
    1,
    0x11,
    0,
    2,
    0x11,
    0,
    3,
    0x11,
    0,
    0xff,
    0xda,
    0,
    2,
    0xff,
    0xd9,
  ]);
  final before = ProcessInfo.maxRss;
  var rejected = false;
  switch (mode) {
    case 'cover':
      rejected = libraryCover(bytes, 'image/jpeg') == null;
    case 'fb2':
      final book = prepareFb2(
        Uint8List.fromList(
          utf8.encode(
            '''
<FictionBook xmlns="$fb2Namespace" xmlns:l="$xlinkNamespace"><body><section><p>Readable text.</p><image l:href="#oversized"/></section></body><binary id="oversized" content-type="image/jpeg">${base64Encode(bytes)}</binary></FictionBook>''',
          ),
        ),
      );
      rejected = !book.resources.containsKey('binary/0');
    case 'comic':
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-jpeg-memory-',
      );
      try {
        final archive = Archive()
          ..addFile(ArchiveFile('page.jpg', bytes.length, bytes));
        final original = await File(
          p.join(owned.path, 'header.cbz'),
        ).writeAsBytes(ZipEncoder().encode(archive));
        final stage = await Directory(p.join(owned.path, 'stage')).create();
        try {
          await extractComic(original.path, 'cbz', stage, () => false);
        } on FormatException {
          rejected = true;
        }
      } finally {
        await owned.delete(recursive: true);
      }
    default:
      throw ArgumentError('Choose cover, fb2, or comic');
  }
  final additional = ProcessInfo.maxRss - before;
  stdout.writeln(
    jsonEncode({
      'mode': mode,
      'rejected': rejected,
      'jpegBytes': bytes.length,
      'additionalPeakRssBytes': additional,
    }),
  );
  if (!rejected || additional > 64 * 1024 * 1024) {
    throw StateError('Image limits must precede decoder allocations');
  }
}
