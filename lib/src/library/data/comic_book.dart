import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../../import_export/data/archive_guard.dart';
import 'book_xml.dart';
import 'cover_image.dart';
import 'comic_image.dart';
import 'image_header.dart';

const comicEntryBytes = 64 * 1024 * 1024;
const comicTotalBytes = 4 * 1024 * 1024 * 1024;
const comicPixels = 32 * 1024 * 1024;

// ASCII numeric runs, then Unicode scalar values; no OS or locale collation.
// Case distinctions and leading zeros have a final exact-name tie breaker.
int compareComicPaths(String a, String b) {
  final left = RegExp(r'\d+|\D+').allMatches(a).map((m) => m[0]!).toList();
  final right = RegExp(r'\d+|\D+').allMatches(b).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = left[i], y = right[i];
    int result;
    if (RegExp(r'^\d').hasMatch(x) && RegExp(r'^\d').hasMatch(y)) {
      final nx = x.replaceFirst(RegExp(r'^0+'), ''),
          ny = y.replaceFirst(RegExp(r'^0+'), '');
      result = nx.length.compareTo(ny.length);
      if (result == 0) result = nx.compareTo(ny);
    } else {
      final rx = x.toLowerCase().runes.toList(),
          ry = y.toLowerCase().runes.toList();
      result = 0;
      for (var n = 0; n < rx.length && n < ry.length; n++) {
        result = rx[n].compareTo(ry[n]);
        if (result != 0) break;
      }
      if (result == 0) result = rx.length.compareTo(ry.length);
    }
    if (result != 0) return result;
  }
  final length = left.length.compareTo(right.length);
  return length != 0 ? length : a.compareTo(b);
}

Future<List<Map<String, dynamic>>> _rarResources(
  String source,
  Directory stage,
  bool Function() cancelled,
) async {
  final suffix = Platform.isWindows ? '.exe' : '';
  final executable =
      Platform.environment['BUSYBOOKS_COMIC_DECODER'] ??
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'busybooks_comic_archive$suffix',
      );
  if (!await File(executable).exists()) {
    throw const FileSystemException(
      'The bundled CBR decoder is missing. Repair the BusyBooks installation.',
    );
  }
  final process = await Process.start(executable, [
    source,
    stage.path,
  ], runInShell: false);
  var outputSize = 0, errorSize = 0;
  String? protocolError;
  final entries = <Map<String, dynamic>>[], errors = StringBuffer();
  final stdoutDone = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach((line) {
        if (cancelled()) return;
        outputSize += line.length;
        if (outputSize > 8 * 1024 * 1024 || entries.length >= 20000) {
          process.kill(ProcessSignal.sigkill);
          return;
        }
        try {
          final entry = (jsonDecode(line) as Map).cast<String, dynamic>();
          entries.add(entry);
        } catch (_) {
          protocolError = 'Damaged CBR decoder response';
          process.kill(ProcessSignal.sigkill);
        }
      })
      .catchError((Object error) {
        protocolError = 'CBR decoder output failed: $error';
        process.kill(ProcessSignal.sigkill);
      });
  final stderrDone = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .forEach((value) {
        errorSize += value.length;
        if (errorSize <= 8192) errors.write(value);
      })
      .catchError((Object error) {
        protocolError = 'CBR decoder error output failed: $error';
        process.kill(ProcessSignal.sigkill);
      });
  final timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
    if (cancelled()) process.kill(ProcessSignal.sigkill);
  });
  final deadline = Timer(
    const Duration(minutes: 3),
    () => process.kill(ProcessSignal.sigkill),
  );
  try {
    final code = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    if (cancelled()) throw const FormatException('CBR preparation cancelled');
    if (code != 0 || protocolError != null || outputSize > 8 * 1024 * 1024) {
      throw FormatException(
        protocolError ??
            (errors.isEmpty
                ? 'CBR decoding failed or exceeded its resource/time limit'
                : errors.toString().trim()),
      );
    }
    return entries;
  } finally {
    timer.cancel();
    deadline.cancel();
    process.kill();
  }
}

// Archives are read one entry at a time, directly to an owned staging directory.
// Full page buffers are discarded after bounded header inspection, never kept
// in a book record or passed through Flutter's reader message channel.
Future<Map<String, dynamic>> extractComic(
  String source,
  String format,
  Directory stage,
  bool Function() cancelled,
) async {
  final entries = <Map<String, dynamic>>[];
  if (format == 'cbz') {
    final input = InputFileStream(source);
    try {
      checkZipEntryCount(
        input,
        maximumMetadataBytes: 16 * 1024 * 1024,
        maximumNameBytes: 4 * 1024 * 1024,
      );
      final directory = ZipDirectory()..read(input);
      validateZipDirectory(
        directory,
        maximumTotal: comicTotalBytes,
        maximumEntry: comicEntryBytes,
      );
      for (final header in directory.fileHeaders) {
        if (header.filename.endsWith('/')) continue;
        final filename = sha256
            .convert(utf8.encode(header.filename))
            .toString();
        await streamZipEntry(
          header,
          File(p.join(stage.path, filename)),
          cancelled,
          maximumBytes: comicEntryBytes,
        );
        entries.add({
          'name': header.filename,
          'file': filename,
          'size': header.uncompressedSize,
        });
      }
    } finally {
      await input.close();
    }
  } else if (format == 'cbr') {
    entries.addAll(await _rarResources(source, stage, cancelled));
    for (final entry in entries) {
      final filename = sha256
          .convert(utf8.encode(entry['name'] as String))
          .toString();
      await File(
        p.join(stage.path, entry['file'] as String),
      ).rename(p.join(stage.path, filename));
      entry['file'] = filename;
    }
  } else {
    throw const FormatException('Unsupported comic format');
  }
  // Validate/decode archive entries first, including metadata CRCs and paths.
  // Filesystem sidecars never participate in page or ComicInfo enumeration.
  bool filesystemMetadata(Map<String, dynamic> entry) {
    return isArchiveMetadata(entry['name'] as String);
  }

  for (final entry in entries.where(filesystemMetadata)) {
    await File(p.join(stage.path, entry['file'] as String)).delete();
  }
  entries.removeWhere(filesystemMetadata);
  const unsupportedImages = [
    '.gif',
    '.bmp',
    '.tif',
    '.tiff',
    '.avif',
    '.heic',
    '.heif',
    '.jxl',
    '.jp2',
    '.j2k',
    '.jpf',
    '.svg',
    '.ico',
    '.ppm',
    '.pnm',
    '.pgm',
    '.pbm',
    '.dib',
    '.jng',
    '.apng',
    '.jxr',
    '.wdp',
    '.hdp',
    '.dds',
    '.tga',
    '.psd',
  ];
  for (final entry in entries) {
    if (unsupportedImages.contains(
      p.posix.extension(entry['name'] as String).toLowerCase(),
    )) {
      throw FormatException(
        'Unsupported comic page image: ${entry['name']}. Pages cannot be omitted or renumbered.',
      );
    }
  }
  final pages =
      entries
          .where(
            (e) => [
              '.jpg',
              '.jpeg',
              '.jpe',
              '.jfif',
              '.png',
              '.webp',
            ].contains(p.posix.extension(e['name'] as String).toLowerCase()),
          )
          .toList()
        ..sort(
          (a, b) => compareComicPaths(a['name'] as String, b['name'] as String),
        );
  if (entries.fold<int>(
        0,
        (sum, entry) => sum + (entry['name'] as String).length,
      ) >
      4 * 1024 * 1024) {
    throw const FormatException('Comic resource index limit exceeded');
  }
  if (pages.isEmpty || pages.length > 10000) {
    throw const FormatException(
      'Comic must contain between 1 and 10000 JPEG, PNG or WebP pages',
    );
  }
  final metadata = <String, dynamic>{'pages': pages.length};
  final info = entries
      .where(
        (e) =>
            p.posix.basename(e['name'] as String).toLowerCase() ==
            'comicinfo.xml',
      )
      .toList();
  final flags = <int, Map<String, dynamic>>{};
  var coverIndex = 0;
  if (info.length == 1 && (info.single['size'] as int) <= 1024 * 1024) {
    try {
      final xml = boundedBookXml(
        await File(
          p.join(stage.path, info.single['file'] as String),
        ).readAsBytes(),
        maximumBytes: 1024 * 1024,
      );
      if (xml.rootElement.name.local == 'ComicInfo') {
        String text(String name) =>
            xml.rootElement.childElements
                .where((e) => e.name.local == name)
                .firstOrNull
                ?.innerText
                .trim() ??
            '';
        final candidate = <String, dynamic>{
          'title': text('Title'),
          'author': [
            'Writer',
            'Penciller',
            'Inker',
            'Colorist',
            'Letterer',
            'CoverArtist',
            'Editor',
            'Translator',
          ].map(text).where((x) => x.isNotEmpty).toSet().join(', '),
          'series': text('Series'),
          'seriesOrder': num.tryParse(text('Number')) ?? 0,
          'language': text('LanguageISO'),
          'direction': text('Manga') == 'YesAndRightToLeft' ? 'rtl' : 'ltr',
        };
        if (candidate.values.any(
          (v) =>
              v is String && v.length > 65536 ||
              v is num && (!v.isFinite || v.abs() > 10000000),
        )) {
          throw const FormatException('Invalid ComicInfo metadata');
        }
        metadata.addAll(candidate);
        for (final page in xml.descendants.whereType<XmlElement>().where(
          (e) => e.name.local == 'Page',
        )) {
          final index = int.tryParse(page.getAttribute('Image') ?? '');
          if (index == null || index < 0 || index >= pages.length) continue;
          final type = page.getAttribute('Type') ?? '';
          final bookmark = page.getAttribute('Bookmark') ?? '';
          if (type.length > 65536 || bookmark.length > 65536) continue;
          if (type.split(',').map((s) => s.trim()).contains('FrontCover')) {
            coverIndex = index;
          }
          flags[index] = {
            'wide': page.getAttribute('DoublePage')?.toLowerCase() == 'true',
            'bookmark': bookmark,
            'type': type,
          };
        }
      }
    } catch (_) {
      /* ComicInfo is optional. Enumerated pages stay authoritative. */
    }
  }
  for (var index = 0; index < pages.length; index++) {
    if (cancelled()) throw const FormatException('Comic preparation cancelled');
    final page = pages[index];
    final bytes = await File(
      p.join(stage.path, page['file'] as String),
    ).readAsBytes();
    final header = boundedImageInfo(bytes, maximumPixels: comicPixels);
    if (header == null) {
      throw FormatException(
        'Comic page ${index + 1} is damaged or exceeds image limits (16000 per side, 32 million pixels)',
      );
    }
    final decoder = header.decoder, info = header.info;
    if (decoder is! image.JpegDecoder &&
        decoder is! image.PngDecoder &&
        decoder is! image.WebPDecoder) {
      throw FormatException(
        'Unsupported comic page image encoding: ${page['name']}',
      );
    }
    if (info.numFrames > 1) {
      throw FormatException(
        'Animated comic pages are unsupported: ${page['name']}',
      );
    }
    // Browser image-orientation:from-image defines the persisted coordinate
    // space. Dimensions are rechecked against oriented naturalWidth/Height.
    final orientation = comicOrientation(bytes);
    final swapped = orientation >= 5 && orientation <= 8;
    page.addAll({
      'width': swapped ? info.height : info.width,
      'height': swapped ? info.width : info.height,
      ...?flags[index],
    });
    if (index == coverIndex) {
      try {
        metadata['cover'] = libraryCover(bytes, '');
      } catch (_) {
        /* optional */
      }
    }
    await Future<void>.delayed(Duration.zero);
  }
  return {
    'metadata': metadata,
    'pages': pages,
    'resources': {
      for (final entry in entries)
        entry['name'] as String: {
          'file': entry['file'],
          'size': entry['size'],
          'sha256': await fileSha256(
            File(p.join(stage.path, entry['file'] as String)),
            cancelled,
          ),
        },
    },
  };
}
