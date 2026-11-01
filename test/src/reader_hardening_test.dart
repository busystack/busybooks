import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/import_export/data/archive_guard.dart';
import 'package:busybooks/src/library/data/cache_resources.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';
import 'package:busybooks/src/reading/domain/reader_bridge.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
import 'package:crypto/crypto.dart';
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

class _Reader {
  _Reader(this.root, this.source, this.store, this.container);
  final Directory root;
  final File source;
  final ReadingDataStore store;
  final ProviderContainer container;
  final opened = <Map>[];
  final dispatches = <Map>[];
  String session = '', id = '';
  bool failFlush = false;
  Future<void> Function(Map)? nativeOpening;
  ReaderController get controller =>
      container.read(readerControllerProvider.notifier);
  ReaderState get state => container.read(readerControllerProvider);

  static Future<_Reader> create(String fixture) async {
    final root = await Directory.systemTemp.createTemp(
      'busybooks-reader-hardening-',
    );
    final source = await File(
      fixture,
    ).copy(p.join(root.path, p.basename(fixture)));
    final store = await ReadingDataStore.open(p.join(root.path, 'profile'));
    final container = ProviderContainer(
      overrides: [
        readingDataStoreProvider.overrideWithValue(store),
        startupAppSettingsProvider.overrideWithValue(
          await StartupAppSettings.load(_Settings()),
        ),
      ],
    );
    return _Reader(root, source, store, container);
  }

  Future<void> frame(Map message) async {
    final done = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      readerChannel.name,
      readerChannel.codec.encodeMethodCall(
        MethodCall('event', jsonEncode(message)),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  Future<void> event(
    String type, [
    Map<String, dynamic> data = const {},
  ]) async {
    for (final message in readerBridgeFrames(
      {'type': type, 'session': session, ...data},
      1,
      command: false,
    )) {
      await frame(message);
    }
  }

  Future<void> open() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(readerChannel, (call) async {
      if (call.method == 'open') {
        final descriptor = call.arguments as Map;
        opened.add(descriptor);
        session = descriptor['session'] as String;
        await nativeOpening?.call(descriptor);
      }
      if (call.method == 'dispatch') {
        final command = jsonDecode(call.arguments as String) as Map;
        expect(
          utf8.encode(call.arguments as String).length,
          lessThanOrEqualTo(readerBridgeFrameBytes),
        );
        dispatches.add(command);
        if (command['action'] == 'layoutVisibility') {
          scheduleMicrotask(
            () => event('layoutVisibility', {
              'request': command['request'],
              'revision': command['revision'],
              'visible': command['visible'],
            }),
          );
        }
        if (command['action'] == 'flush') {
          scheduleMicrotask(() async {
            if (failFlush) {
              final first = readerBridgeFrames(
                {
                  'type': 'location',
                  'session': session,
                  'anchor': {'page': 0},
                  'reference': 'x' * 200000,
                },
                50,
                command: false,
              ).first;
              await frame(first);
              await event('bridgeError', {
                'message': 'Reader bridge frame limit exceeded',
              });
            }
            await event('flushed', {'request': command['request']});
          });
        }
      }
      return null;
    });
    final workspace = await container
        .read(workspaceControllerProvider.notifier)
        .openPath(source.path);
    id = workspace.books.single.id;
    await controller.open(id);
  }

  Future<void> usable() async {
    await event('ready');
    // This standalone native fixture owns a visible, acknowledged reader pane.
    await controller.updateViewport(
      const Rect.fromLTWH(300, 48, 900, 650),
      bookId: id,
    );
    await event('opened');
    await controller.show(true);
    expect(controller.interactive, isTrue);
  }

  Future<void> dispose() async {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(readerChannel, null);
    await store.close();
    await root.delete(recursive: true);
  }
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Reader operation did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('oversized first spine is rejected before native opening', () async {
    final reader = await _Reader.create(
      'test/fixtures/resource-budgets/epub-spine-256m.epub',
    );
    try {
      await reader.open();
      expect(reader.opened, isEmpty);
      expect(reader.state.ready, isFalse);
      expect(reader.state.error, contains('media limit'));
    } finally {
      await reader.dispose();
    }
  });
  test(
    'source watch starts before native opening and rendering stays pinned',
    () async {
      final reader = await _Reader.create('test/fixtures/text.pdf');
      var pinned = false;
      try {
        reader.nativeOpening = (descriptor) async {
          final original = await reader.source.readAsBytes();
          final modified = await reader.source.lastModified();
          final replacement = File(p.join(reader.root.path, 'replacement.pdf'));
          final changed = Uint8List.fromList(original);
          changed[20] ^= 1;
          await replacement.writeAsBytes(changed);
          await replacement.setLastModified(modified);
          await reader.source.delete();
          await replacement.rename(reader.source.path);
          pinned =
              await fileSha256(
                File(descriptor['publicationPath'] as String),
                () => false,
              ) ==
              descriptor['cacheDirectory'].toString().split(p.separator).last;
        };
        await reader.open();
        expect(pinned, isTrue);
        await until(() => reader.state.error != null);
        expect(reader.state.ready, isFalse);
      } finally {
        await reader.dispose();
      }
    },
  );

  test(
    'real controller delivers large selection and chunks a valid legacy PDF goto',
    () async {
      final reader = await _Reader.create('test/fixtures/text.pdf');
      try {
        await reader.open();
        await reader.usable();
        final text = '📚' * 400000;
        final anchor = {
          'page': 0,
          'segments': [
            {
              'page': 0,
              'start': 0,
              'text': text,
              'boxes': [
                [0, 0, 10, 10],
              ],
            },
          ],
        };
        await reader.event('selection', {
          'text': text,
          'anchor': anchor,
          'order': 0,
        });
        expect(reader.state.selection?['text'], text);
        final nextAnchor = {
          ...anchor,
          'page': 1,
          'segments': [
            {...(anchor['segments'] as List).single as Map, 'page': 1},
          ],
        };
        await Future.wait([
          reader.controller.send('goto', {'anchor': anchor}),
          reader.controller.send('passage', {'request': 99}),
          reader.controller.send('goto', {'anchor': nextAnchor}),
        ]);
        final frames = reader.dispatches
            .where((m) => m['action'] == 'bridgeChunk')
            .toList();
        final revisions = frames
            .map((m) => m['bridgeRevision'])
            .toSet()
            .toList();
        expect(revisions.length, 2);
        for (var i = 0; i < revisions.length; i++) {
          final transfer = frames
              .where((m) => m['bridgeRevision'] == revisions[i])
              .toList();
          expect(transfer.length, greaterThan(1));
          final first = reader.dispatches.indexOf(transfer.first),
              last = reader.dispatches.indexOf(transfer.last);
          expect(
            last - first + 1,
            transfer.length,
            reason: 'Commands cannot interleave a transfer',
          );
          expect(
            jsonDecode(
              transfer.map((m) => m['chunk'] as String).join(),
            )['anchor'],
            i == 0 ? anchor : nextAnchor,
          );
        }
        await reader.controller.close();
      } finally {
        await reader.dispose();
      }
    },
  );

  test(
    'bridge failure followed by flushed cannot save stale progress',
    () async {
      final reader = await _Reader.create('test/fixtures/text.pdf');
      try {
        await reader.open();
        await reader.usable();
        reader.failFlush = true;
        await expectLater(reader.controller.flush(), throwsStateError);
        expect(reader.state.warning, contains('bridge'));
        reader.failFlush = false;
        await reader.event('location', {
          'anchor': {'page': 0, 'y': 0},
          'progress': 0.1,
        });
        await reader.controller.close();
      } finally {
        await reader.dispose();
      }
    },
  );

  test(
    'cache parsing failure forces one regeneration and manual Retry forces another',
    () async {
      final reader = await _Reader.create('test/fixtures/reflowable.epub');
      try {
        await reader.open();
        final cache = reader.opened.single['cacheDirectory'] as String;
        final index = File('$cache.json');
        var descriptor = (await readSealedCacheIndex(index))!;
        final resources = descriptor['resources'] as Map;
        final resource =
            resources.entries
                    .firstWhere((e) => (e.key as String).endsWith('.xhtml'))
                    .value
                as Map;
        final file = File(p.join(cache, resource['file'] as String));
        final original = await file.readAsBytes();
        Future<void> damage() async {
          descriptor = (await readSealedCacheIndex(index))!;
          final data = Uint8List.fromList(original);
          data[0] ^= 1;
          await file.writeAsBytes(data);
          ((descriptor['resources'] as Map).values.firstWhere(
                (r) => r['file'] == resource['file'],
              )
              as Map)['sha256'] = sha256
              .convert(data)
              .toString();
          await writeSealedCacheIndex(index, descriptor);
        }

        await damage();
        await reader.event('ready');
        await reader.event('error', {
          'message': 'Invalid publication XHTML',
          'cacheFailure': true,
        });
        await until(() => reader.opened.length == 2);
        expect(await file.readAsBytes(), original);
        await reader.event('ready');
        await reader.event('error', {
          'message': 'Still invalid',
          'cacheFailure': true,
        });
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(reader.opened.length, 2);
        expect(reader.state.error, 'Still invalid');
        await damage();
        await reader.controller.retry(reader.id);
        expect(reader.opened.length, 3);
        expect(await file.readAsBytes(), original);
        await reader.controller.close();
      } finally {
        await reader.dispose();
      }
    },
  );
}
