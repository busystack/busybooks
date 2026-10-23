import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:busybooks/src/library/data/comic_book.dart';
import 'package:busybooks/src/library/data/library_store.dart';

Future<void> main(List<String> args) async {
  final root = await Directory.systemTemp.createTemp('busybooks-resources-');
  try {
    final stage = await Directory(p.join(root.path, 'stage')).create();
    var cancelled = false, rejected = false;
    final watch = Stopwatch()..start(), cancelWatch = Stopwatch();
    var polling = false;
    final timer = Timer.periodic(const Duration(milliseconds: 10), (_) async {
      if (polling || cancelled) return;
      polling = true;
      try {
        await for (final resource in stage.list()) {
          if (resource is File && await resource.length() >= 8 * 1024 * 1024) {
            cancelWatch.start();
            cancelled = true;
            break;
          }
        }
      } finally {
        polling = false;
      }
    });
    final deadline = Timer(const Duration(seconds: 10), () => cancelled = true);
    try {
      await extractComic(
        p.absolute('test/fixtures/formats/comic-cancellable.cbr'),
        'cbr',
        stage,
        () => cancelled,
      );
    } catch (error) {
      if (!error.toString().contains('cancelled')) rethrow;
      rejected = true;
    } finally {
      timer.cancel();
      deadline.cancel();
    }
    final files = await stage
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();
    var bytes = 0;
    for (final file in files) {
      bytes += await file.length();
    }
    if (!rejected ||
        bytes == 0 ||
        !cancelWatch.isRunning ||
        cancelWatch.elapsedMilliseconds > 2000) {
      throw StateError(
        'Cancellation did not interrupt active decoder output promptly',
      );
    }
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'operation': 'real RAR5 solid decoder cancellation',
        'elapsedMs': watch.elapsedMilliseconds,
        'cancellationMs': cancelWatch.elapsedMilliseconds,
        'interruptedOutputBytes': bytes,
        'published': false,
      }),
    );
    await stage.delete(recursive: true);
    await _workerCancellation(root.path);
    if (args.isNotEmpty) {
      final store = await ReadingDataStore.open(p.join(root.path, 'profile'));
      final clock = Stopwatch()..start();
      try {
        final workspace =
                await store.call('openPath', {'path': p.absolute(args.single)})
                    as Map,
            book = (workspace['books'] as List).single as Map;
        await store.call('prepare', {
          'id': book['id'],
          'path': book['path'],
          'validationToken': book['validationToken'],
        });
        final size = await File(args.single).length();
        if (size <= 256 * 1024 * 1024) {
          throw StateError('This stress fixture does not cross the former cap');
        }
        stdout.writeln(
          jsonEncode({
            'status': 'passed',
            'operation': 'file-backed comic above former source cap',
            'sourceBytes': size,
            'pages': book['pages'],
            'inspectionAndPreparationMs': clock.elapsedMilliseconds,
          }),
        );
      } finally {
        await store.close();
      }
    }
  } finally {
    await root.delete(recursive: true);
  }
}

Future<void> _workerCancellation(String root) async {
  final profile = p.join(root, 'worker-cancellation');
  final store = await ReadingDataStore.open(profile);
  try {
    final baseline =
            await store.call('openPath', {
                  'path': p.absolute('test/fixtures/text.pdf'),
                })
                as Map,
        book = (baseline['books'] as List).single as Map;
    await store.call('putAnnotation', {
      'id': 'annotation-cancellation-control',
      'bookId': book['id'],
      'annotationKind': 'bookmark',
      'anchor': {'page': 0},
      'text': '',
      'note': 'Retained after cancelled comic preparation',
      'reference': 'Page 1',
      'color': 'yellow',
      'created': 1,
    });
    var finished = false;
    final opening = store
        .call('openPath', {
          'path': p.absolute('test/fixtures/formats/comic-cancellable.cbr'),
        })
        .then<Object?>(
          (_) {
            finished = true;
            return null;
          },
          onError: (Object error) {
            finished = true;
            return error;
          },
        );
    final started = Stopwatch()..start(), cancellation = Stopwatch();
    final cache = Directory(p.join(profile, 'cache'));
    while (!finished && started.elapsed < const Duration(seconds: 10)) {
      var activeOutput = false;
      try {
        if (await cache.exists()) {
          await for (final file in cache.list(recursive: true)) {
            if (file is File && await file.length() >= 8 * 1024 * 1024) {
              activeOutput = true;
              break;
            }
          }
        }
      } on FileSystemException {
        // Owned staging can disappear between directory enumeration and stat.
      }
      if (activeOutput) {
        cancellation.start();
        await store.call('cancelPrepare');
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (!cancellation.isRunning) await store.call('cancelPrepare');
    final result = await opening.timeout(const Duration(seconds: 15));
    if (!cancellation.isRunning ||
        cancellation.elapsedMilliseconds > 2000 ||
        result == null ||
        !result.toString().toLowerCase().contains('cancel')) {
      throw StateError('Worker cancellation did not interrupt active CBR work');
    }
    final saved = await store.call('annotations', book['id']) as List;
    if (saved.single['note'] != 'Retained after cancelled comic preparation') {
      throw StateError('Cancellation changed existing reading data');
    }
    final interrupted = await cache
        .list(recursive: true)
        .where((e) => p.basename(e.path).startsWith('.busybooks-'))
        .toList();
    if (interrupted.isNotEmpty) {
      throw StateError('Cancelled worker retained staging resources');
    }
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'operation': 'native store worker control cancellation',
        'cancellationMs': cancellation.elapsedMilliseconds,
        'stagingRemaining': interrupted.length,
        'existingNoteRetained': true,
      }),
    );
  } finally {
    await store.close();
  }
}
