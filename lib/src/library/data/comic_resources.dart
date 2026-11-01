import 'package:path/path.dart' as p;
import '../../import_export/data/archive_guard.dart';

const comicEntryBytes = 64 * 1024 * 1024;
const comicTotalBytes = 4 * 1024 * 1024 * 1024;
const comicDiscardBytes = 128 * 1024 * 1024;
const comicInfoBytes = 1024 * 1024;
const comicPageExtensions = ['.jpg', '.jpeg', '.jpe', '.jfif', '.png', '.webp'];
const unsupportedComicImages = [
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

enum ComicResource { page, info, discard }

ComicResource comicResource(String name) {
  if (isArchiveMetadata(name)) return ComicResource.discard;
  final extension = p.posix.extension(name).toLowerCase();
  if (comicPageExtensions.contains(extension)) return ComicResource.page;
  if (unsupportedComicImages.contains(extension)) {
    throw FormatException(
      'Unsupported comic page image: $name. Pages cannot be omitted or renumbered.',
    );
  }
  if (p.posix.basename(name).toLowerCase() == 'comicinfo.xml') {
    return ComicResource.info;
  }
  return ComicResource.discard;
}

class ComicResourceBudget {
  int retainedBytes = 0, discardedBytes = 0, metadataFiles = 0, pages = 0;
  ComicResource add(String name, int size) {
    final kind = comicResource(name);
    if (kind == ComicResource.page && ++pages > 10000) {
      throw const FormatException(
        'A comic must contain 1 to 10000 supported pages',
      );
    }
    if (size < 0 || size > comicEntryBytes) {
      throw const FormatException('Comic entry resource limit exceeded');
    }
    if (kind == ComicResource.discard) {
      discardedBytes += size;
      if (discardedBytes > comicDiscardBytes) {
        throw const FormatException(
          'Discarded comic resources exceed the 128 MiB verification budget',
        );
      }
    } else {
      if (kind == ComicResource.info &&
          (size > comicInfoBytes || ++metadataFiles > 1)) {
        throw const FormatException(
          'ComicInfo.xml must be unique and at most 1 MiB',
        );
      }
      retainedBytes += size;
      if (retainedBytes > comicTotalBytes) {
        throw const FormatException('Comic page resource limit exceeded');
      }
    }
    return kind;
  }
}
