// Logical format and original representation are deliberately separate.
const supportedBookFormats = ['epub', 'pdf', 'fb2', 'cbz', 'cbr'];
const bookSuffixes = ['fb2.zip', 'epub', 'pdf', 'fb2', 'fbz', 'cbz', 'cbr'];

String? originalBookSuffix(String path) {
  final name = path.toLowerCase();
  for (final suffix in bookSuffixes) {
    if (name.endsWith('.$suffix')) return suffix;
  }
  return null;
}

String? bookFormatForPath(String path) => switch (originalBookSuffix(path)) {
  'fb2.zip' || 'fbz' || 'fb2' => 'fb2',
  final String suffix => suffix,
  _ => null,
};

bool isComicFormat(String? format) => format == 'cbz' || format == 'cbr';
bool isPageFormat(String? format) => format == 'pdf' || isComicFormat(format);

int maximumBookBytes(String format) =>
    isComicFormat(format) ? 1024 * 1024 * 1024 : 256 * 1024 * 1024;
