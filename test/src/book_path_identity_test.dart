import 'dart:ffi';
import 'dart:io';
import 'package:busybooks/src/core/atomic_file_writer.dart';
import 'package:busybooks/src/library/data/book_move.dart';
import 'package:busybooks/src/library/data/book_paths.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/workspace/workspace_model.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> directoryAlias(String alias, String target) async {
  if (Platform.isWindows) {
    // Directory junctions work without the symbolic-link privilege on CI.
    final result = await Process.run('cmd', [
      '/c',
      'mklink',
      '/J',
      alias,
      target,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  } else {
    await Link(alias).create(target);
  }
}

String windowsPath(String path, String function) {
  final query = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Utf16>, Pointer<Utf16>, int)
      >(function);
  final input = path.toNativeUtf16(),
      output = calloc<Uint16>(32768).cast<Utf16>();
  try {
    final length = query(input, output, 32768);
    if (length == 0 || length >= 32768) {
      throw FileSystemException(
        'Cannot create Windows path fixture: $function',
        path,
      );
    }
    return output.toDartString(length: length);
  } finally {
    malloc.free(input);
    calloc.free(output);
  }
}

Future<void> exerciseAliases(String real, String alias, String profile) async {
  ReadingDataStore? store;
  final original = await File(
    'test/fixtures/reflowable.epub',
  ).copy(p.join(real, 'Original Book.epub'));
  final selectedName = Platform.isWindows
      ? 'ORIGINAL BOOK.EPUB'
      : 'Original Book.epub';
  final selected = p.join(alias, selectedName);
  final bytes = await original.readAsBytes();
  try {
    store = await ReadingDataStore.open(profile);
    final first = await store.call('openPath', {'path': original.path}) as Map;
    final id = first['id'] as String;
    expect(id, await contentHash(original.path));
    final anchor = {'kind': 'epub', 'cfi': 'epubcfi(/6/2!/4/2/1:4)'};
    await store.call('updateBook', {
      'id': id,
      'changes': {'anchor': anchor, 'progress': .4, 'state': 'reading'},
    });
    await store.call('putAnnotation', {
      'id': 'annotation-alias-note',
      'bookId': id,
      'annotationKind': 'bookmark',
      'anchor': anchor,
      'text': '',
      'note': 'Preserved across aliases',
      'reference': 'Chapter 1',
      'color': 'yellow',
      'created': 1,
    });
    final collection =
        await store.call('createCollection', {'name': 'Aliases'}) as Map;
    final collectionId = collection['id'];
    await store.call('addBooks', {
      'collectionId': collectionId,
      'paths': [original.path, selected],
    });
    final reopened = await store.call('openPath', {'path': selected}) as Map;
    final saved = (reopened['books'] as List).single as Map;
    expect(reopened['id'], id);
    expect(saved['anchor'], anchor);
    expect(saved['progress'], .4);
    expect(
      await FileSystemEntity.identical(saved['path'] as String, original.path),
      isTrue,
    );
    expect(
      ((await store.call('openCollection', {'id': collectionId})
              as Map)['books']
          as List),
      hasLength(1),
    );
    await original.writeAsBytes([...bytes, 0]);
    await expectLater(
      store.call('openPath', {'path': selected}),
      throwsA(
        isA<WorkspaceException>()
            .having((e) => e.code, 'code', 'changed')
            .having((e) => e.bookId, 'bookId', id),
      ),
    );
    expect(
      (await store.call('annotations', id) as List).single['note'],
      'Preserved across aliases',
    );
    await original.writeAsBytes(bytes);
    await store.call('openPath', {'path': selected});
    final relocated = await original.rename(p.join(real, 'Relocated.epub'));
    await expectLater(
      store.call('openPath', {'path': selected}),
      throwsA(
        isA<WorkspaceException>()
            .having((e) => e.code, 'code', 'missing')
            .having((e) => e.bookId, 'bookId', id),
      ),
    );
    await store.call('relocate', {
      'id': id,
      'path': p.join(alias, 'Relocated.epub'),
    });
    // Both the missing historical location and the relocated original are owned.
    for (final target in [
      original.path,
      selected,
      relocated.path,
      p.join(alias, 'Relocated.epub'),
    ]) {
      for (final operation in ['backup', 'exportMarkdown', 'exportOriginal']) {
        await expectLater(
          store.call(operation, {
            'id': id,
            'path': target,
            'preferences': {},
            'overwrite': true,
          }),
          throwsA(
            isA<StateError>().having(
              (e) => e.toString(),
              'reason',
              contains('saved original book location'),
            ),
          ),
          reason: '$operation must protect $target',
        );
      }
    }
    expect(await original.exists(), isFalse);
    expect(await relocated.readAsBytes(), bytes);
    if (Platform.isWindows) {
      for (final suffix in ['.', ' ']) {
        final ambiguous = '$selected$suffix';
        await expectLater(
          store.call('backup', {
            'path': ambiguous,
            'preferences': {},
            'overwrite': true,
          }),
          throwsA(isA<StateError>()),
        );
        expect(await original.exists(), isFalse);
      }
    }
    final backup = p.join(alias, 'Original Book.epub.backup');
    await store.call('backup', {
      'path': backup,
      'preferences': {},
      'overwrite': false,
    });
    expect(await File(backup).exists(), isTrue);
    if (Platform.isLinux) {
      final distinct = p.join(alias, 'ORIGINAL BOOK.EPUB');
      await store.call('exportMarkdown', {
        'id': id,
        'path': distinct,
        'overwrite': false,
      });
      expect(
        await File(distinct).readAsString(),
        contains('Preserved across aliases'),
      );
    }
    final target = p.join(alias, 'Moved.epub');
    final moved =
        await store.call('moveBook', {
              'id': id,
              'source': p.join(alias, 'Relocated.epub'),
              'destination': target,
            })
            as Map;
    expect(moved['status'], 'moved');
    expect(await relocated.exists(), isFalse);
    expect(await contentHash(target), id);
    // A distinct physical copy with the same contents is not a selected location.
    final unrelated = await File(
      target,
    ).copy(p.join(real, 'Unregistered.epub'));
    await expectLater(
      store.call('moveBook', {
        'id': id,
        'source': unrelated.path,
        'destination': p.join(real, 'Other.epub'),
      }),
      throwsA(
        isA<StateError>().having(
          (e) => e.toString(),
          'reason',
          contains('Unknown selected book location'),
        ),
      ),
    );
    expect(await unrelated.exists(), isTrue);
    await store.close();
    store = await ReadingDataStore.open(profile);
    final book = await store.call('book', id) as Map;
    expect(book['anchor'], anchor);
    expect(book['progress'], .4);
    expect(
      await FileSystemEntity.identical(book['path'] as String, target),
      isTrue,
    );
    expect(
      (await store.call('annotations', id) as List).single['note'],
      'Preserved across aliases',
    );
    final member =
        ((await store.call('openCollection', {'id': collectionId})
                        as Map)['books']
                    as List)
                .single
            as Map;
    expect(member['id'], id);
    expect(
      await FileSystemEntity.identical(member['path'] as String, target),
      isTrue,
    );
    expect((await store.call('snapshot') as Map)['moves'], isEmpty);
  } finally {
    await store?.close();
  }
}

void main() {
  test(
    'directory aliases preserve original identity, state, move selection and publication protection',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'busybooks-path-alias-',
      );
      final real = await Directory(
        p.join(root.path, 'Original Directory'),
      ).create();
      final alias = p.join(root.path, 'Directory Alias');
      try {
        await directoryAlias(alias, real.path);
        await exerciseAliases(real.path, alias, p.join(root.path, 'profile'));
      } finally {
        if (await FileSystemEntity.type(alias, followLinks: false) !=
            FileSystemEntityType.notFound) {
          await Link(alias).delete();
        }
        await root.delete(recursive: true);
      }
    },
  );
  test('Linux resolves a symbolic link before parent traversal', () async {
    final root = await Directory.systemTemp.createTemp(
      'busybooks-parent-traversal-',
    );
    ReadingDataStore? store;
    try {
      final nested = await Directory(
        p.join(root.path, 'Target', 'Nested'),
      ).create(recursive: true);
      final original = await File(
        'test/fixtures/reflowable.epub',
      ).copy(p.join(nested.parent.path, 'Book.epub'));
      await File(
        p.join(root.path, 'Book.epub'),
      ).writeAsString('Different physical object');
      final link = p.join(root.path, 'Link');
      await Link(link).create(nested.path);
      store = await ReadingDataStore.open(p.join(root.path, 'profile'));
      final result =
          await store.call('openPath', {'path': '$link/../Book.epub'}) as Map;
      expect(result['id'], await contentHash(original.path));
      expect(
        await FileSystemEntity.identical(
          result['path'] as String,
          original.path,
        ),
        isTrue,
      );
      expect(
        await File(p.join(root.path, 'Book.epub')).readAsString(),
        'Different physical object',
      );
    } finally {
      await store?.close();
      await root.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);
  test(
    'Windows short and long paths share saved locations without string equality',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'busybooks-windows-path-',
      );
      try {
        final short = windowsPath(root.path, 'GetShortPathNameW');
        final long = windowsPath(root.path, 'GetLongPathNameW');
        expect(
          short,
          isNot(long),
          reason:
              'The Windows CI temp volume must provide the reported 8.3 alias',
        );
        await exerciseAliases(long, short, p.join(long, 'profile'));
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'missing ancestors and pending move paths remain protected through aliases',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'busybooks-missing-alias-',
      );
      final real = await Directory(p.join(root.path, 'Originals')).create();
      final alias = p.join(root.path, 'Alias');
      ReadingDataStore? store;
      try {
        await directoryAlias(alias, real.path);
        final source = await File(
          'test/fixtures/text.pdf',
        ).copy(p.join(real.path, 'Book.pdf'));
        store = await ReadingDataStore.open(p.join(root.path, 'profile'));
        final id =
            (await store.call('openPath', {'path': source.path}) as Map)['id'];
        final missing = p.join(
          real.path,
          'Missing Parent',
          'Subdirectory',
          'Moved.pdf',
        );
        await expectLater(
          store.call('moveBook', {
            'id': id,
            'source': source.path,
            'destination': missing,
          }),
          throwsA(isA<StateError>()),
        );
        final journal =
            ((await store.call('snapshot') as Map)['moves'] as List).single
                as Map;
        await Directory(p.dirname(missing)).create(recursive: true);
        for (final name in [
          p.basename(missing),
          p.basename(journal['stagePath'] as String),
        ]) {
          final target = p.join(alias, 'Missing Parent', 'Subdirectory', name);
          await expectLater(
            store.call('backup', {
              'path': target,
              'preferences': {},
              'overwrite': true,
            }),
            throwsA(
              isA<StateError>().having(
                (e) => e.toString(),
                'reason',
                contains('pending Move Book location'),
              ),
            ),
          );
          expect(await File(target).exists(), isFalse);
        }
        final historical = Directory(p.join(real.path, 'Historical', 'Nested'));
        await historical.create(recursive: true);
        final saved = await source.copy(p.join(historical.path, 'Known.pdf'));
        await store.call('openPath', {'path': saved.path});
        await Directory(
          p.join(real.path, 'Historical'),
        ).delete(recursive: true);
        final missingSaved = p.join(alias, 'Historical', 'Nested', 'Known.pdf');
        await expectLater(
          store.call('backup', {
            'path': missingSaved,
            'preferences': {},
            'overwrite': true,
          }),
          throwsA(
            isA<StateError>().having(
              (e) => e.toString(),
              'reason',
              contains('saved original book location'),
            ),
          ),
        );
        expect(await historical.exists(), isFalse);
        await source.delete();
        await real.delete(recursive: true);
        // The symlink is deliberately dangling: fail closed rather than writing.
        await expectLater(
          store.call('backup', {
            'path': p.join(alias, 'Book.pdf'),
            'preferences': {},
            'overwrite': true,
          }),
          throwsA(isA<StateError>()),
        );
      } finally {
        await store?.close();
        if (await FileSystemEntity.type(alias, followLinks: false) !=
            FileSystemEntityType.notFound) {
          await Link(alias).delete();
        }
        await root.delete(recursive: true);
      }
    },
  );
  for (final overwrite in [false, true]) {
    test(
      'publication revalidates a directory alias after staging (overwrite=$overwrite)',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'busybooks-publication-alias-',
        );
        final first = await Directory(p.join(root.path, 'First')).create();
        final second = await Directory(p.join(root.path, 'Second')).create();
        final alias = p.join(root.path, 'Saved Alias');
        final target = File(p.join(second.path, 'Book.pdf'));
        try {
          await directoryAlias(alias, first.path);
          if (overwrite) await target.writeAsString('Existing bytes');
          await expectLater(
            const AtomicFileWriter().writeGenerated(
              target.path,
              (staged) async {
                await staged.writeAsString('Export bytes');
                await Link(alias).delete();
                await directoryAlias(alias, second.path);
              },
              overwrite: overwrite,
              validateTarget: (path) {
                if (BookPathIdentity.resolve(path).sameLocation(
                  BookPathIdentity.resolve(p.join(alias, 'Book.pdf')),
                )) {
                  throw const FileSystemException(
                    'Saved original moved during staging',
                  );
                }
              },
            ),
            throwsA(isA<FileSystemException>()),
          );
          if (overwrite) {
            expect(await target.readAsString(), 'Existing bytes');
          } else {
            expect(await target.exists(), isFalse);
          }
          expect(
            await second
                .list()
                .where(
                  (entry) =>
                      p.basename(entry.path).startsWith('.busybooks-export-'),
                )
                .isEmpty,
            isTrue,
          );
        } finally {
          if (await FileSystemEntity.type(alias, followLinks: false) !=
              FileSystemEntityType.notFound) {
            await Link(alias).delete();
          }
          await root.delete(recursive: true);
        }
      },
    );
  }
}
