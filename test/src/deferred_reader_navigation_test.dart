import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';
import 'package:busybooks/src/reading/domain/reader_bridge.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Settings implements LocalSettingsStore {
  @override
  Future<Map<String, dynamic>> load() async => {};
  @override
  Future<void> save(Map<String, dynamic> value) async {}
}

class _GatedStore implements ReadingDataStore {
  _GatedStore(this.delegate);
  final ReadingDataStore delegate;
  Future<void> Function()? beforePrepare;
  @override
  String get root => delegate.root;
  @override
  int get searchRevision => delegate.searchRevision;
  @override
  Stream<int> get changes => delegate.changes;
  @override
  Stream<Map<String, dynamic>> get progress => delegate.progress;
  @override
  Future<dynamic> call(String action, [Object? argument]) async {
    if (action == 'prepare') await beforePrepare?.call();
    return delegate.call(action, argument);
  }

  @override
  void cancel() => delegate.cancel();
  @override
  Future<void> close() => delegate.close();
}

class _Fixture {
  _Fixture(this.root, this.store, this.container);
  final Directory root;
  final _GatedStore store;
  final ProviderContainer container;
  final dispatches = <Map>[];
  final sessions = <String>[];
  String first = '', second = '';
  bool failOpen = false;
  Future<void> Function(Map)? dispatch;
  ReaderController get reader =>
      container.read(readerControllerProvider.notifier);
  ReaderState get state => container.read(readerControllerProvider);
  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('busybooks-owned-jump-');
    final store = _GatedStore(
      await ReadingDataStore.open(p.join(root.path, 'profile')),
    );
    final container = ProviderContainer(
      overrides: [
        readingDataStoreProvider.overrideWithValue(store),
        startupAppSettingsProvider.overrideWithValue(
          await StartupAppSettings.load(_Settings()),
        ),
      ],
    );
    final f = _Fixture(root, store, container);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(readerChannel, (call) async {
          if (call.method == 'open') {
            f.sessions.add((call.arguments as Map)['session'] as String);
            if (f.failOpen) {
              throw PlatformException(code: 'fixture-open-failed');
            }
          }
          if (call.method == 'dispatch') {
            final command = jsonDecode(call.arguments as String) as Map;
            f.dispatches.add(command);
            await f.dispatch?.call(command);
            if (command['action'] == 'flush') {
              scheduleMicrotask(
                () => f.event('flushed', {'request': command['request']}),
              );
            }
          }
          return null;
        });
    final bytes = await File('test/fixtures/text.pdf').readAsBytes();
    final workspace = container.read(workspaceControllerProvider.notifier);
    for (final name in ['first', 'second']) {
      final file = await File(
        p.join(root.path, '$name.pdf'),
      ).writeAsBytes([...bytes, ...'\n% $name\n'.codeUnits]);
      final opened = await workspace.openPath(file.path);
      if (name == 'first') {
        f.first = opened.books.single.id;
      } else {
        f.second = opened.books.single.id;
      }
    }
    await f.reader.show(true);
    return f;
  }

  Future<void> event(
    String type, [
    Map<String, dynamic> data = const {},
    String? session,
  ]) async {
    final done = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      readerChannel.name,
      readerChannel.codec.encodeMethodCall(
        MethodCall(
          'event',
          jsonEncode({
            'type': type,
            'session': session ?? reader.sessionId,
            ...data,
          }),
        ),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  Future<void> ready() async {
    await event('ready');
    await event('opened');
  }

  Iterable<Map> get jumps => dispatches.where((d) => d['action'] == 'goto');
  Future<void> dispose() async {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(readerChannel, null);
    await store.close();
    await root.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed target opening cannot donate its passage to another book',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final pending = f.reader.deferJump(bookId: f.first, anchor: {'page': 2});
      f.failOpen = true;
      await f.reader.open(f.first);
      expect(f.state.error, isNotNull);
      await pending.finished;
      f.failOpen = false;
      await f.reader.open(f.second);
      await f.ready();
      expect(f.state.bookId, f.second);
      expect(f.jumps, isEmpty);
    },
  );
  test(
    'switch before readiness rejects late opened and target anchor',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final pending = f.reader.deferJump(bookId: f.first, anchor: {'page': 2});
      await f.reader.open(f.first);
      await f.event('ready');
      final old = f.reader.sessionId;
      await f.reader.open(f.second);
      await pending.finished;
      await f.event('opened', const {}, old);
      await f.ready();
      expect(f.state.bookId, f.second);
      expect(f.jumps, isEmpty);
    },
  );
  test(
    'closing and reopening the same book abandons the old activation',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final pending = f.reader.deferJump(bookId: f.first, anchor: {'page': 2});
      await f.reader.open(f.first);
      await f.event('ready');
      await f.reader.close();
      await pending.finished;
      await f.reader.open(f.first);
      await f.ready();
      expect(f.jumps, isEmpty);
    },
  );
  test(
    'superseding opening of the same book does not inherit the activation',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final pending = f.reader.deferJump(bookId: f.first, anchor: {'page': 2});
      await f.reader.open(f.first);
      await f.reader.open(f.first);
      await pending.finished;
      await f.ready();
      expect(f.jumps, isEmpty);
    },
  );
  test(
    'intentional already-loading handoff applies exactly once when visible',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.reader.setWorkspaceVisible(false);
      await f.reader.open(f.first);
      final pending = f.reader.deferJump(bookId: f.first, anchor: {'page': 2});
      await f.ready();
      expect(f.jumps, isEmpty);
      await f.reader.setWorkspaceVisible(true);
      await pending.finished;
      expect(f.jumps.single['anchor'], {'page': 2});
      await f.reader.setWorkspaceVisible(true);
      expect(f.jumps, hasLength(1));
    },
  );
  test(
    'old reader visibility cannot abandon an unclaimed target passage',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.reader.open(f.first);
      await f.ready();
      final pending = f.reader.deferJump(bookId: f.second, anchor: {'page': 2});
      await f.reader.setWorkspaceVisible(true);
      expect(f.jumps, isEmpty);
      await f.reader.open(f.second);
      await f.ready();
      await pending.finished;
      expect(f.state.bookId, f.second);
      expect(f.jumps.single['anchor'], {'page': 2});
      expect(f.jumps.single['session'], f.reader.sessionId);
    },
  );
  test(
    'same-book visibility waits for the claimed opening to pass preflight',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.reader.open(f.first);
      await f.ready();
      final entered = Completer<void>(), proceed = Completer<void>();
      f.store.beforePrepare = () async {
        entered.complete();
        await proceed.future;
      };
      var validations = 0;
      final pending = f.reader.deferJump(
        bookId: f.first,
        anchor: {'page': 2},
        validate: () async {
          validations++;
          return true;
        },
      );
      final opening = f.reader.open(f.first);
      await entered.future;
      await f.reader.setWorkspaceVisible(true);
      expect(validations, 0);
      expect(f.jumps, isEmpty);
      proceed.complete();
      await opening;
      await pending.finished;
      expect(validations, greaterThanOrEqualTo(2));
      expect(f.jumps.single['anchor'], {'page': 2});
    },
  );
  test(
    'delayed retry close cannot hide or reopen a superseding book',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.reader.open(f.first);
      await f.ready();
      final closing = Completer<void>(), proceed = Completer<void>();
      f.dispatch = (command) async {
        if (command['action'] == 'cancelAppearance' && !closing.isCompleted) {
          closing.complete();
          await proceed.future;
        }
      };
      final retry = f.reader.retry(f.first);
      await closing.future;
      await f.reader.open(f.second);
      await f.ready();
      final session = f.reader.sessionId;
      proceed.complete();
      await retry;
      expect(f.state.bookId, f.second);
      expect(f.reader.sessionId, session);
      expect(f.reader.interactive, isTrue);
      expect(f.sessions, hasLength(2));
    },
  );
  test(
    'deleted annotation is revalidated after readiness and queued native work',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.store.call('putAnnotation', {
        'id': 'annotation-deferred',
        'bookId': f.first,
        'annotationKind': 'bookmark',
        'text': '',
        'note': 'saved',
        'reference': 'Page 3',
        'anchor': {'page': 2},
        'color': 'yellow',
        'created': 1,
      });
      final validated = Completer<void>();
      var validations = 0;
      final pending = f.reader.deferJump(
        bookId: f.first,
        anchor: {'page': 2},
        validate: () async {
          validations++;
          if (!validated.isCompleted) validated.complete();
          try {
            await f.store.call('annotation', {
              'id': 'annotation-deferred',
              'bookId': f.first,
            });
            return true;
          } on Object {
            return false;
          }
        },
      );
      await f.reader.open(f.first);
      await f.event('ready');
      final transferEntered = Completer<void>(),
          transferProceed = Completer<void>();
      f.dispatch = (command) async {
        if (!transferEntered.isCompleted) {
          transferEntered.complete();
          await transferProceed.future;
        }
      };
      final transfer = f.reader.send('annotations', {
        'value': [
          {'text': 'x' * (readerBridgeFrameBytes * 2)},
        ],
      });
      await transferEntered.future;
      final opening = f.event('opened');
      await validated.future;
      await f.store.call('deleteAnnotation', 'annotation-deferred');
      transferProceed.complete();
      await transfer;
      await opening;
      await pending.finished;
      expect(validations, greaterThanOrEqualTo(2));
      expect(f.jumps, isEmpty);
    },
  );
}
