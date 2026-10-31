import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/import_export/data/archive_guard.dart';
import 'package:busybooks/src/library/data/book_inspection.dart';
import 'package:busybooks/src/library/data/publication_cache.dart';
import 'package:path/path.dart' as p;

// Run the compiled probe to exclude JIT compiler storage from RSS measurements.
Future<void> main(List<String> args) async {
  final fixtures = p.absolute(
    args.isEmpty ? 'test/fixtures/resource-budgets' : args.single,
  );
  final root = await Directory.systemTemp.createTemp(
    'busybooks-resource-pressure-',
  );
  try {
    final warm = await inspectBook(
      'test/fixtures/reflowable.epub',
      () => false,
    );
    await preparePublicationCache(
      root.path,
      warm['id'] as String,
      'epub',
      sourcePath: 'test/fixtures/reflowable.epub',
      cancelled: () => false,
    );
    final baseline = ProcessInfo.currentRss;
    var peak = baseline;
    final sample = Timer.periodic(const Duration(milliseconds: 5), (_) {
      if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
    });
    final results = <Map<String, dynamic>>[];
    try {
      final path = p.join(fixtures, 'epub-spine-256m.epub');
      final book = await inspectBook(path, () => false);
      var rejected = false;
      try {
        await preparePublicationCache(
          root.path,
          book['id'] as String,
          'epub',
          sourcePath: path,
          cancelled: () => false,
        );
      } on FormatException catch (error) {
        rejected = error.message.contains('media limit');
      }
      if (!rejected) throw StateError('Oversized spine was not rejected');
      results.add({
        'format': 'epub',
        'result': 'rejected before cache publication',
        'expandedSpineBytes': 268435456,
        'sourceBytes': await File(path).length(),
      });
      for (final format in ['cbz', 'cbr']) {
        final source = p.join(fixtures, 'comic-irrelevant-128m.$format');
        final original = await fileSha256(File(source), () => false);
        final cache = await preparePublicationCache(
          root.path,
          original,
          format,
          sourcePath: source,
          cancelled: () => false,
        );
        final descriptor =
            jsonDecode(await File('$cache.json').readAsString()) as Map;
        final resources = descriptor['resources'] as Map;
        var bytes = 0;
        await for (final file in Directory(cache).list()) {
          bytes += await (file as File).length();
        }
        if (resources.length != 1 ||
            !resources.containsKey('page.png') ||
            bytes > 1024) {
          throw StateError('Irrelevant resources survived preparation');
        }
        results.add({
          'format': format,
          'discardedBytes': 134217728,
          'retainedFiles': resources.length,
          'retainedBytes': bytes,
          'result': 'passed',
        });
      }
      if (peak - baseline > 128 * 1024 * 1024) {
        throw StateError('Resource preparation RSS grew excessively');
      }
      stdout.writeln(
        jsonEncode({
          'status': 'passed',
          'results': results,
          'baselineRss': baseline,
          'peakRss': peak,
          'osMaxRss': ProcessInfo.maxRss,
        }),
      );
    } finally {
      sample.cancel();
    }
  } finally {
    await root.delete(recursive: true);
  }
}
