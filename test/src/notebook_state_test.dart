import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:busybooks/src/annotations/domain/annotation_filter.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/notebook/application/notebook_controller.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/annotation_store_gate.dart';

void main() {
  test(
    'a save waiting behind a failed delete retains the unsaved draft',
    () async {
      final f = await _NoteFixture.open();
      try {
        f.notebook.edit(f.item, 'Retained draft');
        f.gate.failDelete = true;
        final deleting = f.workspace.deleteAnnotation(f.item.id);
        final saving = f.notebook.save(f.item.id);
        final deletion = expectLater(
          deleting,
          throwsA(isA<FileSystemException>()),
        );
        final save = expectLater(saving, throwsA(isA<FileSystemException>()));
        await Future.wait([deletion, save]);
        expect(
          f.container.read(notebookControllerProvider).drafts[f.item.id]!.text,
          'Retained draft',
        );
        expect(
          (await f.store.call('annotations', f.id) as List).single['note'],
          'Saved baseline',
        );
        f.gate.failDelete = false;
        await f.notebook.flush();
        await f.verify('Retained draft');
      } finally {
        await f.close();
      }
    },
  );

  test(
    'Discard uses a stored baseline even with a stale widget and an inactive book',
    () async {
      final f = await _NoteFixture.open();
      try {
        await f.workspace.updateAnnotation(f.item.id, {
          'note': 'New saved baseline',
        }, bookId: f.id);
        f.container.invalidate(workspaceControllerProvider);
        await f.workspace.openPath(p.absolute('test/fixtures/reflowable.epub'));
        f.notebook.edit(f.item, 'Pending edit from stale widget');
        await f.notebook.discard(f.item.id, confirm: () async => true);
        await f.verify('New saved baseline');
      } finally {
        await f.close();
      }
    },
  );

  for (final outcome in [
    'confirm',
    'cancel',
    'later edit',
    'failed rollback',
  ]) {
    test(
      'discard lifecycle: $outcome preserves authoritative note state',
      () async {
        final f = await _NoteFixture.open();
        try {
          f.notebook.edit(f.item, 'Pending draft');
          final decision = Completer<bool>();
          final action = f.notebook.discard(
            f.item.id,
            confirm: () => decision.future,
          );
          await Future<void>.delayed(const Duration(milliseconds: 750));
          expect(f.gate.calls.where((c) => c == 'updateAnnotation'), isEmpty);
          expect(
            (await f.store.call('annotations', f.id) as List).single['note'],
            'Saved baseline',
          );
          if (outcome == 'later edit') {
            f.notebook.edit(f.item, 'Later valid edit');
          }
          if (outcome == 'failed rollback') f.gate.fail = true;
          decision.complete(outcome != 'cancel');
          if (outcome == 'failed rollback') {
            await expectLater(action, throwsA(isA<FileSystemException>()));
            expect(
              f.container
                  .read(notebookControllerProvider)
                  .drafts[f.item.id]!
                  .text,
              'Pending draft',
            );
            expect(
              f.container
                  .read(notebookControllerProvider)
                  .drafts[f.item.id]!
                  .error,
              isNotNull,
            );
            f.gate.fail = false;
            await f.notebook.discard(f.item.id, confirm: () async => true);
            await f.verify('Saved baseline');
          } else {
            await action;
            if (outcome == 'later edit') {
              expect(
                f.container
                    .read(notebookControllerProvider)
                    .drafts[f.item.id]!
                    .text,
                'Later valid edit',
              );
              expect(
                (await f.store.call('annotations', f.id) as List)
                    .single['note'],
                'Saved baseline',
              );
              await f.notebook.flush();
              await f.verify('Later valid edit');
            } else if (outcome == 'cancel') {
              expect(
                f.container
                    .read(notebookControllerProvider)
                    .drafts[f.item.id]!
                    .text,
                'Pending draft',
              );
              await Future<void>.delayed(const Duration(milliseconds: 750));
              await f.notebook.flush();
              await f.verify('Pending draft');
            } else {
              await f.notebook.flush();
              await f.verify('Saved baseline');
            }
          }
        } finally {
          await f.close();
        }
      },
    );
  }
  for (final mode in ['timer', 'in flight', 'failed delete']) {
    test(
      'coordinated deletion: $mode cannot resurrect from retry or flush',
      () async {
        final f = await _NoteFixture.open();
        try {
          f.notebook.edit(f.item, 'Pending draft');
          Future<void>? saving;
          if (mode == 'in flight') {
            f.gate.entered = Completer();
            f.gate.proceed = Completer();
            saving = f.notebook.save(f.item.id);
            await f.gate.entered!.future;
          }
          if (mode == 'failed delete') f.gate.failDelete = true;
          final deleting = f.workspace.deleteAnnotation(f.item.id);
          if (saving != null) {
            f.gate.proceed!.complete();
            await saving;
          }
          if (mode == 'failed delete') {
            await expectLater(deleting, throwsA(isA<FileSystemException>()));
            expect(
              f.container
                  .read(notebookControllerProvider)
                  .drafts[f.item.id]!
                  .text,
              'Pending draft',
            );
            expect(
              (await f.store.call('annotations', f.id) as List).single['note'],
              'Saved baseline',
            );
            f.gate.failDelete = false;
            await f.workspace.deleteAnnotation(f.item.id);
          } else {
            await deleting;
          }
          await f.notebook.flush();
          await Future<void>.delayed(const Duration(milliseconds: 750));
          await f.verify(null);
          // Even an obsolete repository update cannot insert after deletion.
          await expectLater(
            f.workspace.updateAnnotation(f.item.id, {
              'note': 'Obsolete callback',
            }, bookId: f.id),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('Unknown annotation for this book'),
              ),
            ),
          );
          expect(await f.store.call('annotations', f.id), isEmpty);
        } finally {
          await f.close();
        }
      },
    );
  }
  test(
    'inactive-book draft updates its existing row without polluting the active list',
    () async {
      final f = await _NoteFixture.open();
      try {
        f.notebook.edit(f.item, 'Inactive book note');
        f.container.invalidate(workspaceControllerProvider);
        final other = (await f.workspace.openPath(
          p.absolute('test/fixtures/reflowable.epub'),
        )).books.single.id;
        expect(other, isNot(f.id));
        expect(
          f.container.read(workspaceControllerProvider).annotations,
          isEmpty,
        );
        await f.notebook.flush();
        expect(
          f.container.read(workspaceControllerProvider).annotations,
          isEmpty,
        );
        await f.verify('Inactive book note');
        await expectLater(
          f.workspace.updateAnnotation(f.item.id, {
            'note': 'Wrong parent',
          }, bookId: other),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Unknown annotation for this book'),
            ),
          ),
        );
        await f.verify('Inactive book note');
      } finally {
        await f.close();
      }
    },
  );

  test('discard coordinates an already in-flight note write', () async {
    final f = await _NoteFixture.open();
    try {
      f.notebook.edit(f.item, 'Discarded edit');
      f.gate.entered = Completer();
      f.gate.proceed = Completer();
      final pending = f.notebook.save(f.item.id);
      await f.gate.entered!.future;
      final discarded = f.notebook.discard(
        f.item.id,
        confirm: () async => true,
      );
      f.gate.proceed!.complete();
      await pending;
      await discarded;
      await f.notebook.flush();
      await f.verify('Saved baseline');
    } finally {
      await f.close();
    }
  });
  test(
    'bookmark deletion cannot be undone by a failed Notebook draft retry',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'busybooks-delete-race-',
      );
      final store = await ReadingDataStore.open(dir.path);
      final gate = AnnotationStoreGate(store);
      final container = ProviderContainer(
        overrides: [readingDataStoreProvider.overrideWithValue(gate)],
      );
      try {
        final workspace = container.read(workspaceControllerProvider.notifier);
        final id = (await workspace.openPath(
          p.absolute('test/fixtures/text.pdf'),
        )).books.single.id;
        final item = ReadingAnnotation({
          'id': 'annotation-delete-race',
          'bookId': id,
          'annotationKind': 'bookmark',
          'anchor': {'page': 0},
          'text': '',
          'note': 'Saved baseline',
          'color': 'yellow',
          'created': 1,
        });
        await workspace.saveAnnotation(item);
        final notebook = container.read(notebookControllerProvider.notifier);
        notebook.edit(item, 'Failed draft');
        gate.fail = true;
        await expectLater(
          notebook.save(item.id),
          throwsA(isA<FileSystemException>()),
        );
        gate.fail = false;
        await workspace.deleteAnnotation(item.id);
        await notebook.flush();
        expect(await store.call('annotations', id), isEmpty);
      } finally {
        container.dispose();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'missing-original Notebook drafts survive refresh/filter/route state and retry without global reads',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'busybooks-notebook-test-',
      );
      final original = await File(
        'test/fixtures/reflowable.epub',
      ).copy(p.join(dir.path, 'book.epub'));
      final store = await ReadingDataStore.open(p.join(dir.path, 'profile')),
          gate = AnnotationStoreGate(store);
      final container = ProviderContainer(
        overrides: [readingDataStoreProvider.overrideWithValue(gate)],
      );
      try {
        final workspace = container.read(workspaceControllerProvider.notifier);
        final opened = await workspace.openPath(original.path),
            id = opened.books.single.id;
        final item = ReadingAnnotation({
          'id': 'annotation-notebook-test',
          'bookId': id,
          'annotationKind': 'bookmark',
          'anchor': {'cfi': 'epubcfi(/6/2!/4/2/1:0)'},
          'text': '',
          'note': 'Saved',
          'color': 'yellow',
          'created': 1,
        });
        await workspace.saveAnnotation(item);
        await original.delete();
        await workspace.loadBook(id, activate: true);
        expect(
          container.read(workspaceControllerProvider).bookById(id)!.available,
          isFalse,
        );
        final notebook = container.read(notebookControllerProvider.notifier);
        gate.fail = true;
        notebook.edit(item, 'Unsaved\nmultiline draft');
        await expectLater(
          notebook.save(item.id),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          container.read(notebookControllerProvider).drafts[item.id]!.text,
          'Unsaved\nmultiline draft',
        );
        expect(
          container.read(notebookControllerProvider).drafts[item.id]!.error,
          isNotNull,
        );
        notebook.view(
          id,
          filter: AnnotationTypeFilter.bookmarks,
          withNotes: true,
          scroll: 420,
          selected: item.id,
        );
        await workspace.refresh();
        await workspace.loadBook(id);
        expect(
          container.read(notebookControllerProvider).drafts[item.id]!.text,
          'Unsaved\nmultiline draft',
        );
        expect(container.read(notebookControllerProvider).view(id).scroll, 420);
        gate.fail = false;
        gate.calls.clear();
        await notebook.flush();
        expect(gate.calls, ['updateAnnotation']);
        expect(container.read(notebookControllerProvider).drafts, isEmpty);
        expect(
          (await store.call('annotations', id) as List).single['note'],
          'Unsaved\nmultiline draft',
        );
      } finally {
        container.dispose();
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('asynchronous save acknowledges only its own draft revision', () async {
    final dir = await Directory.systemTemp.createTemp(
      'busybooks-draft-revision-',
    );
    final store = await ReadingDataStore.open(dir.path),
        gate = AnnotationStoreGate(store);
    final container = ProviderContainer(
      overrides: [readingDataStoreProvider.overrideWithValue(gate)],
    );
    try {
      final workspace = container.read(workspaceControllerProvider.notifier);
      final opened = await workspace.openPath(
            p.absolute('test/fixtures/text.pdf'),
          ),
          id = opened.books.single.id;
      final item = ReadingAnnotation({
        'id': 'annotation-race',
        'bookId': id,
        'annotationKind': 'highlight',
        'anchor': {'page': 0},
        'text': 'Quote',
        'note': '',
        'color': 'blue',
        'created': 1,
      });
      await workspace.saveAnnotation(item);
      final notebook = container.read(notebookControllerProvider.notifier);
      notebook.edit(item, 'First');
      gate.entered = Completer();
      gate.proceed = Completer();
      final save = notebook.save(item.id);
      await gate.entered!.future;
      notebook.edit(item, 'Latest');
      gate.proceed!.complete();
      await save;
      expect(
        container.read(notebookControllerProvider).drafts[item.id]!.text,
        'Latest',
      );
      gate.entered = null;
      gate.proceed = null;
      await notebook.flush();
      expect(
        (await store.call('annotations', id) as List).single['note'],
        'Latest',
      );
    } finally {
      container.dispose();
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}

class _NoteFixture {
  _NoteFixture(
    this.dir,
    this.store,
    this.gate,
    this.container,
    this.id,
    this.item,
  );
  final Directory dir;
  final ReadingDataStore store;
  final AnnotationStoreGate gate;
  final ProviderContainer container;
  final String id;
  final ReadingAnnotation item;
  String? _expected;
  bool _verified = false;
  WorkspaceController get workspace =>
      container.read(workspaceControllerProvider.notifier);
  NotebookController get notebook =>
      container.read(notebookControllerProvider.notifier);
  static Future<_NoteFixture> open() async {
    final dir = await Directory.systemTemp.createTemp(
      'busybooks-note-lifecycle-',
    );
    final store = await ReadingDataStore.open(p.join(dir.path, 'profile'));
    final gate = AnnotationStoreGate(store);
    final container = ProviderContainer(
      overrides: [readingDataStoreProvider.overrideWithValue(gate)],
    );
    final workspace = container.read(workspaceControllerProvider.notifier);
    final id = (await workspace.openPath(
      p.absolute('test/fixtures/text.pdf'),
    )).books.single.id;
    final item = ReadingAnnotation({
      'id': 'annotation-lifecycle',
      'bookId': id,
      'annotationKind': 'bookmark',
      'anchor': {'page': 0},
      'text': '',
      'note': 'Saved baseline',
      'reference': 'Page 1',
      'color': 'yellow',
      'created': 1,
    });
    await workspace.saveAnnotation(item);
    gate.calls.clear();
    return _NoteFixture(dir, store, gate, container, id, item);
  }

  Future<void> verify(String? note) async {
    final records = await store.call('annotations', id) as List;
    expect(
      records.map((a) => a['note']).toList(),
      note == null ? isEmpty : equals([note]),
    );
    await workspace.loadBook(id, activate: true);
    expect(
      container
          .read(workspaceControllerProvider)
          .annotations
          .map((a) => a.note)
          .toList(),
      note == null ? isEmpty : equals([note]),
    );
    final markdown = p.join(dir.path, 'notes.md');
    await store.call('exportMarkdown', {
      'id': id,
      'path': markdown,
      'overwrite': true,
    });
    final text = await File(markdown).readAsString();
    if (note != null) {
      expect(text, contains(note));
    } else {
      expect(text, isNot(contains('Saved baseline')));
    }
    final archive = p.join(dir.path, 'backup.busybooks');
    await store.call('backup', {
      'path': archive,
      'preferences': {},
      'overwrite': true,
    });
    final manifest =
        jsonDecode(
              utf8.decode(
                ZipDecoder()
                    .decodeBytes(await File(archive).readAsBytes())
                    .files
                    .single
                    .content,
              ),
            )
            as Map;
    expect(
      (manifest['records'] as List)
          .where((a) => a['kind'] == 'annotation')
          .map((a) => a['note'])
          .toList(),
      note == null ? isEmpty : equals([note]),
    );
    final restored = await ReadingDataStore.open(p.join(dir.path, 'restored'));
    try {
      await restored.call('restore', archive);
      expect(
        (await restored.call('annotations', id) as List)
            .map((a) => a['note'])
            .toList(),
        note == null ? isEmpty : equals([note]),
      );
    } finally {
      await restored.close();
    }
    _expected = note;
    _verified = true;
  }

  Future<void> close() async {
    container.dispose();
    await store.close();
    final reopened = await ReadingDataStore.open(p.join(dir.path, 'profile'));
    try {
      if (_verified) {
        expect(
          (await reopened.call('annotations', id) as List)
              .map((a) => a['note'])
              .toList(),
          _expected == null ? isEmpty : equals([_expected]),
        );
      }
    } finally {
      await reopened.close();
      await dir.delete(recursive: true);
    }
  }
}
