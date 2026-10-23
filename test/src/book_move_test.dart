import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/library/data/book_move.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'same-volume move does not overwrite or move an unrelated identical copy',
    () async {
      final dir = await Directory.systemTemp.createTemp('busybooks-move-test-');
      try {
        final source = await File(
              'test/fixtures/text.pdf',
            ).copy(p.join(dir.path, 'source.pdf')),
            copy = await source.copy(p.join(dir.path, 'other.pdf'));
        final hash = await contentHash(source.path),
            target = p.join(dir.path, 'target.pdf');
        final move = BookMoveService(
          record: (_) {},
          completed: (_, _, _) {},
          cancelled: () => false,
        );
        await File(target).writeAsString('collision');
        await expectLater(
          move.move(hash, source.path, target),
          throwsA(isA<FileSystemException>()),
        );
        expect(await File(target).readAsString(), 'collision');
        expect(await source.exists(), isTrue);
        await File(target).delete();
        await move.move(hash, source.path, target);
        expect(await source.exists(), isFalse);
        expect(await contentHash(target), hash);
        expect(await contentHash(copy.path), hash);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'published destination survives failed database commit and can be recovered',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'busybooks-move-db-failure-',
      );
      try {
        final source = await File(
          'test/fixtures/text.pdf',
        ).copy(p.join(dir.path, 'source.pdf'));
        final hash = await contentHash(source.path),
            target = p.join(dir.path, 'target.pdf');
        Map<String, dynamic>? journal;
        await expectLater(
          BookMoveService(
            record: (v) => journal = jsonDecode(jsonEncode(v)),
            completed: (_, _, _) => throw StateError('database full'),
            cancelled: () => false,
          ).move(hash, source.path, target),
          throwsStateError,
        );
        expect(await contentHash(target), hash);
        expect(journal!['stage'], 'published');
        await BookMoveService(
          record: (_) {},
          completed: (_, _, _) {},
          cancelled: () => false,
        ).move(hash, source.path, target, recovery: journal);
        expect(await source.exists(), isFalse);
        expect(await contentHash(target), hash);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('no-clobber race preserves both files', () async {
    final dir = await Directory.systemTemp.createTemp('busybooks-move-race-');
    try {
      final source = await File(
        'test/fixtures/text.pdf',
      ).copy(p.join(dir.path, 'source.pdf'));
      final hash = await contentHash(source.path),
          target = p.join(dir.path, 'target.pdf');
      final move = BookMoveService(
        record: (v) {
          if (v['stage'] == 'intent') {
            File(target).writeAsStringSync('racing destination');
          }
        },
        completed: (_, _, _) {},
        cancelled: () => false,
      );
      await expectLater(
        move.move(hash, source.path, target),
        throwsA(isA<FileSystemException>()),
      );
      expect(await contentHash(source.path), hash);
      expect(await File(target).readAsString(), 'racing destination');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
