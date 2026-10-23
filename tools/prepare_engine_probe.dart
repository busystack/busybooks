import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:path/path.dart' as p;

// Opens original fixtures and retains only a disposable resource-cache profile.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 || !p.isAbsolute(arguments.single)) {
    throw ArgumentError('Supply an absolute, empty disposable profile path');
  }
  final root = Directory(arguments.single);
  if (await root.exists() && !await root.list().isEmpty) {
    throw ArgumentError('The probe profile must be empty');
  }
  final store = await ReadingDataStore.open(root.path);
  try {
    final descriptors = <Map<String, dynamic>>[];
    for (final name in ['reflowable.epub', 'fixed-layout.epub', 'text.pdf']) {
      final workspace =
          await store.call('openPath', {
                'path': p.absolute('test', 'fixtures', name),
              })
              as Map;
      final book = (workspace['books'] as List).single as Map;
      final descriptor =
          await store.call('prepare', {
                'id': book['id'],
                'path': book['path'],
                'validationToken': book['validationToken'],
              })
              as Map;
      descriptors.add({
        ...descriptor.cast<String, dynamic>(),
        'format': book['format'],
      });
    }
    stdout.writeln(jsonEncode(descriptors));
  } finally {
    await store.close();
  }
}
