import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/core/reading_preferences.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args.first).absolute.path;
  final store = await ReadingDataStore.open('$root/reading-profile');
  try {
    final workspace =
        await store.call('openPath', {
              'path': args.length > 1
                  ? File(args[1]).absolute.path
                  : '$root/typography.epub',
            })
            as Map;
    final book = (workspace['books'] as List).single as Map;
    if (args.contains('--saved-typography')) {
      await store.call('updateBook', {
        'id': book['id'],
        'changes': {
          'appearance': {
            ...defaultReadingAppearance,
            'font': {'family': 'Noto Serif'},
            'publisher': false,
          },
        },
      });
      final saved = await store.call('book', book['id']) as Map;
      await File(
        '$root/committed-appearance.json',
      ).writeAsString(jsonEncode(saved['appearance']));
    }
    final descriptor =
        await store.call('prepare', {
              'id': book['id'],
              'path': book['path'],
              'validationToken': book['validationToken'],
            })
            as Map;
    stdout.writeln(jsonEncode(descriptor));
  } finally {
    await store.close();
  }
}
