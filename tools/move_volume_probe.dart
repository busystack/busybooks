// Pass two authorized directories on different filesystems. No personal files.
import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/library/data/book_move.dart';
import 'package:busybooks/src/library/data/file_identity.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: dart run tools/move_volume_probe.dart SOURCE_PARENT DESTINATION_PARENT',
    );
  }
  final sourceRoot = await Directory(
        args[0],
      ).createTemp('busybooks-volume-source-'),
      targetRoot = await Directory(
        args[1],
      ).createTemp('busybooks-volume-target-');
  var checks = 0;
  void check(bool ok) {
    if (!ok) throw StateError('Move postcondition failed');
    checks++;
  }

  try {
    final sourceMarker = await File(
          p.join(sourceRoot.path, 'device'),
        ).writeAsString('source'),
        targetMarker = await File(
          p.join(targetRoot.path, 'device'),
        ).writeAsString('destination');
    String device(String path) =>
        fileInstance(path).split(':').take(Platform.isLinux ? 2 : 1).join(':');
    if (device(sourceMarker.path) == device(targetMarker.path)) {
      throw ArgumentError('Probe requires actual different filesystems');
    }
    for (final boundary in [
      'intent',
      'copying',
      'verified',
      'published',
      'recorded',
      'removing',
      'quarantined',
    ]) {
      final source = await File(
            'test/fixtures/long.pdf',
          ).copy(p.join(sourceRoot.path, '$boundary.pdf')),
          target = p.join(targetRoot.path, '$boundary.pdf');
      final hash = await contentHash(source.path);
      Map<String, dynamic>? journal;
      var interrupted = false;
      final journalFile = File(p.join(sourceRoot.path, 'journal.json'));
      try {
        await BookMoveService(
          record: (v) {
            journal = jsonDecode(jsonEncode(v));
            journalFile.writeAsStringSync(jsonEncode(v), flush: true);
            if (v['stage'] == boundary && !interrupted) {
              interrupted = true;
              throw StateError('Injected interruption at $boundary');
            }
          },
          completed: (_, _, _) {},
          cancelled: () => false,
        ).move(hash, source.path, target);
      } catch (_) {
        check(interrupted);
      }
      check(interrupted);
      check(journal != null);
      // Read the durable journal into a fresh service, as after process restart.
      final recovered = (jsonDecode(await journalFile.readAsString()) as Map)
          .cast<String, dynamic>();
      await BookMoveService(
        record: (v) {
          journal = v;
        },
        completed: (_, _, _) {},
        cancelled: () => false,
      ).move(hash, source.path, target, recovery: recovered);
      check(!await source.exists());
      check(await contentHash(target) == hash);
      check(journal!['stage'] == 'complete');
    }
    final source = await File(
          'test/fixtures/long.pdf',
        ).copy(p.join(sourceRoot.path, 'replacement.pdf')),
        target = p.join(targetRoot.path, 'replacement.pdf');
    final hash = await contentHash(source.path);
    Map<String, dynamic>? journal;
    try {
      await BookMoveService(
        record: (v) {
          journal = jsonDecode(jsonEncode(v));
          if (v['stage'] == 'recorded') {
            throw StateError('pause before deletion');
          }
        },
        completed: (_, _, _) {},
        cancelled: () => false,
      ).move(hash, source.path, target);
    } catch (_) {}
    final preserved = await source.rename(
      p.join(sourceRoot.path, 'preserved.pdf'),
    );
    await preserved.copy(
      source.path,
    ); // Same bytes, different physical identity.
    var rejected = false;
    try {
      await BookMoveService(
        record: (_) {},
        completed: (_, _, _) {},
        cancelled: () => false,
      ).move(hash, source.path, target, recovery: journal);
    } catch (_) {
      rejected = true;
    }
    check(rejected);
    check(await contentHash(source.path) == hash);
    check(await contentHash(target) == hash);
    for (final failure in ['cancel', 'copy', 'hash', 'delete']) {
      if (failure == 'delete' && !Platform.isLinux) continue;
      final original = await File(
        'test/fixtures/long.pdf',
      ).copy(p.join(sourceRoot.path, '$failure.pdf'));
      final destination = p.join(targetRoot.path, '$failure.pdf'),
          identity = await contentHash(original.path);
      Map<String, dynamic>? intent;
      var cancel = false, failed = false;
      try {
        await BookMoveService(
          record: (entry) {
            intent = jsonDecode(jsonEncode(entry));
            if (failure == 'hash' && entry['stage'] == 'verified') {
              File(
                entry['stagePath'] as String,
              ).writeAsStringSync('injected corrupt copy', flush: true);
            }
            if (failure == 'delete' && entry['stage'] == 'quarantined') {
              final mode = Process.runSync('chmod', ['500', sourceRoot.path]);
              if (mode.exitCode != 0) {
                throw StateError('Cannot prepare permission fixture');
              }
            }
          },
          completed: (_, _, _) {},
          cancelled: () => cancel,
          report: (done, total) {
            if (failure == 'cancel') cancel = true;
            if (failure == 'copy') {
              throw const FileSystemException(
                'Injected copy write failure: no space left on device',
              );
            }
          },
        ).move(identity, original.path, destination);
      } catch (_) {
        failed = true;
      } finally {
        if (failure == 'delete') {
          Process.runSync('chmod', ['700', sourceRoot.path]);
        }
      }
      check(failed);
      check(intent != null);
      final recoverySource = failure == 'delete'
          ? intent!['quarantine'] as String
          : original.path;
      check(await contentHash(recoverySource) == identity);
      if (failure != 'hash') {
        await BookMoveService(
          record: (_) {},
          completed: (_, _, _) {},
          cancelled: () => false,
        ).move(identity, original.path, destination, recovery: intent);
        check(!await original.exists());
        check(await contentHash(destination) == identity);
      } else {
        // A conflicting/corrupt published destination is preserved for explicit
        // user review. Recovery never deletes or overwrites it automatically.
        check(
          await File(destination).readAsString() == 'injected corrupt copy',
        );
      }
    }
    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'checks': checks,
        'scope':
            'real cross-filesystem streamed move and durable journal interruption/recovery; replacement source preserved; cancellation, injected copy/hash failure, actual Linux delete denial',
        'sourceParent': args[0],
        'destinationParent': args[1],
      }),
    );
  } finally {
    await sourceRoot.delete(recursive: true);
    await targetRoot.delete(recursive: true);
  }
}
