import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/library/data/book_inspection.dart';
import 'package:busybooks/src/library/data/publication_cache.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Supply the generated expansion EPUB');
  }
  final root = await Directory.systemTemp.createTemp(
    'busybooks-streamed-epub-',
  );
  // Compile/warm the same inspection and extraction paths before measuring the
  // untrusted expansion; JIT compilation is not expanded publication storage.
  final warm = await inspectBook('test/fixtures/reflowable.epub', () => false);
  await preparePublicationCache(
    root.path,
    warm['id'] as String,
    'epub',
    sourcePath: 'test/fixtures/reflowable.epub',
    cancelled: () => false,
  );
  final baseline = ProcessInfo.currentRss;
  var peak = baseline, retained = false;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
    if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
  });
  try {
    final book = await inspectBook(
      args.single,
      () => false,
      retainBytes: (_) => retained = true,
    );
    final cache = await preparePublicationCache(
      root.path,
      book['id'] as String,
      'epub',
      sourcePath: args.single,
      cancelled: () => false,
    );
    final index = jsonDecode(await File('$cache.json').readAsString()) as Map;
    final expanded = (index['resources'] as Map).values.fold<int>(
      0,
      (sum, value) => sum + value['size'] as int,
    );
    final growth = peak - baseline;
    if (retained ||
        expanded < 256 * 1024 * 1024 ||
        growth >= 128 * 1024 * 1024) {
      throw StateError(
        'Streaming memory bound failed: retained=$retained, expanded=$expanded, growth=$growth',
      );
    }
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'compressedBytes': await File(args.single).length(),
        'expandedBytes': expanded,
        'baselineRss': baseline,
        'peakRss': peak,
        'growthBytes': growth,
        'osMaxRss': ProcessInfo.maxRss,
        'scope':
            'Actual inspection and cache extraction, 256 MiB expansion, sampled process RSS; no whole-book retained bytes',
      }),
    );
  } finally {
    timer.cancel();
    await root.delete(recursive: true);
  }
}
