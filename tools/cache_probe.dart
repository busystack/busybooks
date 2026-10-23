import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:busybooks/src/library/data/epub_cache.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('busybooks-cache-proof-');
  try {
    final archive = Archive();
    final names = ['EPUB/A.xhtml', 'EPUB/a.xhtml', '%2e%2e/outside', 'a%2Fb'];
    for (final name in names) {
      final bytes = utf8.encode('Content of $name');
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    final bytes = ZipEncoder().encode(archive);
    final id = sha256.convert(bytes).toString();
    final source = File(p.join(root.path, 'original-location', 'source.epub'));
    await source.parent.create();
    await source.writeAsBytes(bytes);
    await prepareEpubCache(
      root.path,
      id,
      sourcePath: source.path,
      cancelled: () => false,
    );
    final index =
        jsonDecode(
              await File(
                p.join(root.path, 'cache', 'epub', '$id.json'),
              ).readAsString(),
            )
            as Map;
    final resources = index['resources'] as Map;
    final files = <String>{};
    for (final name in names) {
      final filename = resources[name]['file'] as String;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(filename) ||
          !files.add(filename)) {
        throw StateError(
          'Distinct logical paths must have safe distinct physical names',
        );
      }
      final content = await File(
        p.join(root.path, 'cache', 'epub', id, filename),
      ).readAsString();
      if (content != 'Content of $name') throw StateError('Resource changed');
    }
    if (await File(p.join(root.path, 'outside')).exists()) {
      throw StateError('Encoded resource path escaped the cache');
    }
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'resources': names.length,
        'scope': 'Case-sensitive logical names and encoded path isolation',
      }),
    );
  } finally {
    await root.delete(recursive: true);
  }
}
