import 'package:path/path.dart' as p;

const epubTextBytes = 4 * 1024 * 1024;
const epubNavigationBytes = 1024 * 1024;
const epubImageBytes = 64 * 1024 * 1024;
const epubFontBytes = 32 * 1024 * 1024;
const epubOtherBytes = 8 * 1024 * 1024;

// Apply both the declared type and the filename limit; relabelling a text
// document as an image must not evade its whole-materialization budget.
int epubResourceLimit(
  String name, {
  String mediaType = '',
  bool navigation = false,
}) {
  int typeLimit(String type) {
    final mime = type.toLowerCase().split(';').first.trim();
    if (mime == 'text/css' || mime == 'application/x-dtbncx+xml') {
      return epubNavigationBytes;
    }
    if (mime == 'image/svg+xml' ||
        mime.startsWith('text/') ||
        mime.contains('xml') ||
        mime.contains('json')) {
      return epubTextBytes;
    }
    if (mime.startsWith('image/')) return epubImageBytes;
    if (mime.startsWith('font/') ||
        mime.contains('font') ||
        mime.contains('opentype')) {
      return epubFontBytes;
    }
    return epubOtherBytes;
  }

  final extension = p.posix.extension(name).toLowerCase();
  final byName = switch (extension) {
    '.css' || '.ncx' => epubNavigationBytes,
    '.xhtml' ||
    '.html' ||
    '.htm' ||
    '.xml' ||
    '.opf' ||
    '.svg' => epubTextBytes,
    '.jpg' ||
    '.jpeg' ||
    '.png' ||
    '.webp' ||
    '.gif' ||
    '.avif' => epubImageBytes,
    '.woff' || '.woff2' || '.ttf' || '.otf' => epubFontBytes,
    _ => null,
  };
  var limit = mediaType.isEmpty
      ? byName ?? epubOtherBytes
      : typeLimit(mediaType);
  if (byName != null && byName < limit) limit = byName;
  if (navigation && limit > epubNavigationBytes) limit = epubNavigationBytes;
  if (name == 'mimetype') return 128;
  if (name == 'META-INF/container.xml' || name == 'META-INF/encryption.xml') {
    return epubNavigationBytes;
  }
  return limit;
}
