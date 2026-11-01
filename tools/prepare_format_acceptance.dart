import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:busybooks/src/library/data/library_store.dart';

// The shell probe supplies a newly owned, disposable profile. The second phase
// persists the *native engine's* captured range, clears caches and reopens it.
Future<void> main(List<String> args) async {
  if (args.length < 2 || !p.isAbsolute(args[0]) || !p.isAbsolute(args[1])) {
    throw ArgumentError('Supply absolute disposable profile and fixture paths');
  }
  final root = args[0];
  final preparation = Stopwatch()..start();
  var store = await ReadingDataStore.open(root);
  try {
    var workspace = await store.call('openPath', {'path': args[1]}) as Map;
    var book = (workspace['books'] as List).single as Map;
    if (args.length > 2) {
      final saved = jsonDecode(await File(args[2]).readAsString()) as Map;
      await store.call('updateBook', {
        'id': book['id'],
        'changes': {
          'anchor': saved['anchor'],
          'appearance': {'publisher': false, 'size': 28, 'margin': 40},
          if (saved['outlineProof'] is List)
            'outline': [
              for (final (index, row)
                  in (saved['outlineProof'] as List).indexed)
                {
                  ...row as Map,
                  'id': 'outline:$index',
                  'depth': index == 0 ? 0 : 1,
                },
            ],
        },
      });
      for (final annotation in saved['annotations'] as List) {
        await store.call('putAnnotation', {
          ...(annotation as Map).cast<String, dynamic>(),
          'bookId': book['id'],
          'note': 'Private native proof note',
          'created': 1,
        });
      }
      // Release owned inspection staging before deleting caches, then actually
      // reopen SQLite and revalidate the original for the next renderer process.
      await store.close();
      final cache = Directory(p.join(root, 'cache'));
      if (await cache.exists()) await cache.delete(recursive: true);
      store = await ReadingDataStore.open(root);
      workspace = await store.call('openPath', {'path': args[1]}) as Map;
      book = (workspace['books'] as List).single as Map;
      final annotations = await store.call('annotations', book['id']) as List;
      saved['anchor'] = book['anchor'];
      saved['annotations'] = [
        for (final annotation in annotations)
          {
            for (final key in [
              'id',
              'annotationKind',
              'anchor',
              'text',
              'color',
              'reference',
            ])
              key: annotation[key],
          },
      ];
      if (saved['outlineProof'] is List) {
        saved['outlineProof'] = [
          for (final row in book['outline'] as List)
            {
              for (final key in ['label', 'href', 'anchor']) key: row[key],
            },
        ];
      }
      await File(args[2]).writeAsString(jsonEncode(saved));
    }
    final descriptor =
        await store.call('prepare', {
              'id': book['id'],
              'path': book['path'],
              'validationToken': book['validationToken'],
            })
            as Map;
    stdout.writeln(
      jsonEncode({
        ...descriptor.cast<String, dynamic>(),
        'id': book['id'],
        'format': book['format'],
        'preparationMs': preparation.elapsedMilliseconds,
      }),
    );
  } finally {
    await store.close();
  }
}
