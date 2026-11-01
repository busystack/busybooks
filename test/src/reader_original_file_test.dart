import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('replaced native initialization cannot close the next book', () async {
    final owned = await Directory.systemTemp.createTemp(
      'busybooks-replaced-reader-',
    );
    final epub = await File(
      p.absolute('test/fixtures/reflowable.epub'),
    ).copy(p.join(owned.path, 'original.epub'));
    final pdf = await File(
      p.absolute('test/fixtures/text.pdf'),
    ).copy(p.join(owned.path, 'original.pdf'));
    final store = await ReadingDataStore.open(p.join(owned.path, 'profile'));
    final container = ProviderContainer(
      overrides: [
        readingDataStoreProvider.overrideWithValue(store),
        startupAppSettingsProvider.overrideWithValue(
          await StartupAppSettings.load(_Settings()),
        ),
      ],
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final firstEntered = Completer<void>();
    final firstNativeOpen = Completer<void>();
    var opens = 0, closes = 0;
    messenger.setMockMethodCallHandler(readerChannel, (call) async {
      if (call.method == 'open' && ++opens == 1) {
        firstEntered.complete();
        await firstNativeOpen.future;
      }
      if (call.method == 'close') closes++;
      return null;
    });
    try {
      final workspace = container.read(workspaceControllerProvider.notifier);
      final first = await workspace.openPath(epub.path);
      final reader = container.read(readerControllerProvider.notifier);
      final openingFirst = reader.open(first.books.single.id);
      await firstEntered.future;
      final second = await workspace.openPath(pdf.path);
      await reader.open(second.books.single.id);
      // WebView2 returns this error to the original pending MethodResult when
      // a subsequent opening replaces initialization of its native surface.
      firstNativeOpen.completeError(
        PlatformException(code: 'reader-replaced', message: 'Reader replaced'),
      );
      await openingFirst;
      expect(
        container.read(readerControllerProvider).bookId,
        second.books.single.id,
      );
      expect(container.read(readerControllerProvider).error, isNull);
      expect(closes, 0);
      await reader.close();
    } finally {
      container.dispose();
      messenger.setMockMethodCallHandler(readerChannel, null);
      await store.close();
      await owned.delete(recursive: true);
    }
  });
  test(
    'reader opens originals, restores collection state and rejects stale surface events',
    () async {
      final owned = await Directory.systemTemp.createTemp(
        'busybooks-reader-boundary-',
      );
      final profile = p.join(owned.path, 'profile');
      final original = await File(
        p.absolute('test/fixtures/reflowable.epub'),
      ).copy(p.join(owned.path, 'original.epub'));
      final pdf = await File(
        p.absolute('test/fixtures/text.pdf'),
      ).copy(p.join(owned.path, 'original.pdf'));
      final store = await ReadingDataStore.open(profile);
      final settings = await StartupAppSettings.load(_Settings());
      final container = ProviderContainer(
        overrides: [
          readingDataStoreProvider.overrideWithValue(store),
          startupAppSettingsProvider.overrideWithValue(settings),
        ],
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      String session = '';
      Future<void> event(String type, Map<String, dynamic> data) async {
        final reply = Completer<void>();
        ServicesBinding.instance.channelBuffers.push(
          readerChannel.name,
          readerChannel.codec.encodeMethodCall(
            MethodCall('event', jsonEncode({'type': type, ...data})),
          ),
          (_) => reply.complete(),
        );
        await reply.future;
      }

      messenger.setMockMethodCallHandler(readerChannel, (call) async {
        calls.add(call);
        if (call.method == 'open') {
          session = (call.arguments as Map)['session'] as String;
        }
        if (call.method == 'dispatch') {
          final command = jsonDecode(call.arguments as String) as Map;
          if (command['action'] == 'layoutVisibility') {
            scheduleMicrotask(
              () => event('layoutVisibility', {
                'session': session,
                'request': command['request'],
                'revision': command['revision'],
                'visible': command['visible'],
              }),
            );
          }
        }
        if (call.method == 'dispatch' &&
            jsonDecode(call.arguments as String)['action'] == 'flush') {
          final request = jsonDecode(call.arguments as String)['request'];
          scheduleMicrotask(
            () => event('flushed', {'session': session, 'request': request}),
          );
        }
        return null;
      });
      try {
        final workspace = container.read(workspaceControllerProvider.notifier);
        final first = await workspace.openPath(original.path);
        final id = first.books.single.id;
        final reader = container.read(readerControllerProvider.notifier);
        await reader.open(id);
        final descriptor =
            calls.lastWhere((c) => c.method == 'open').arguments as Map;
        expect(
          await FileSystemEntity.identical(
            descriptor['path'] as String,
            original.path,
          ),
          isTrue,
        );
        expect(descriptor['cacheDirectory'], startsWith(profile));
        expect(await Directory(p.join(profile, 'books')).exists(), isFalse);
        await event('ready', {'session': session});
        await event('opened', {'session': session});
        final anchor = {'kind': 'epub', 'cfi': 'epubcfi(/6/2!/4/2/1:4)'};
        await event('location', {
          'session': session,
          'anchor': anchor,
          'progress': .3,
          'reference': 'Chapter One',
        });
        await reader.annotation('bookmark', note: 'Shared bookmark');
        await reader.flush();
        await expectLater(
          workspace.preparePath(p.join(owned.path, 'missing.epub')),
          throwsException,
        );
        expect(container.read(readerControllerProvider).ready, isTrue);
        expect(
          await FileSystemEntity.identical(
            container.read(workspaceControllerProvider).workspace!.path,
            original.path,
          ),
          isTrue,
        );
        final oldSession = session;
        await reader.close();
        final second = await workspace.openPath(pdf.path);
        await reader.open(second.books.single.id);
        expect(session, isNot(oldSession));
        await event('location', {
          'session': oldSession,
          'anchor': anchor,
          'progress': .9,
        });
        await reader.flush();
        expect(container.read(readerControllerProvider).location, isEmpty);
        expect(
          container
              .read(workspaceControllerProvider)
              .bookById(second.books.single.id)!
              .anchor,
          isNull,
        );
        await reader.close();
        await workspace.createCollection('Book workspace');
        await workspace.addBooks([original.path]);
        await workspace.openBook(
          container.read(workspaceControllerProvider).books.single,
        );
        await reader.open(id);
        await event('ready', {'session': session});
        final openConfig = calls
            .where((c) => c.method == 'dispatch')
            .map((c) => jsonDecode(c.arguments as String) as Map)
            .lastWhere((m) => m['action'] == 'open');
        expect(openConfig['anchor'], anchor);
        final rendered = (openConfig['annotations'] as List).single as Map;
        expect(rendered.containsKey('note'), isFalse);
        final saved = reader.annotations.single;
        expect(rendered['id'], saved.id);
        expect(rendered['anchor'], anchor);
        // Reopening preserves the full private note in its data owners; the
        // publication renderer only receives annotation drawing/location data.
        expect(saved.note, 'Shared bookmark');
        expect(
          (await store.call('annotations', id) as List).single['note'],
          'Shared bookmark',
        );
        expect(
          container.read(workspaceControllerProvider).workspace!.name,
          'Book workspace',
        );
        await reader.close();
      } finally {
        container.dispose();
        messenger.setMockMethodCallHandler(readerChannel, null);
        await store.close();
        await owned.delete(recursive: true);
      }
    },
  );
}
