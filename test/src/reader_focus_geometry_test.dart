import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/book_workspace/application/book_presentation.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/notebook/application/notebook_controller.dart';
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
  Future<void> save(Map<String, dynamic> json) async {}
}

/// Models native acknowledgements around the production controller and store.
/// Native rendering/focus itself is verified separately in the desktop app.
class _FocusGeometryFixture {
  late Directory directory;
  late ReadingDataStore store;
  late ProviderContainer container;
  late String bookId;
  String session = '';
  bool nativeFocused = true;
  bool rejectCapture = false;
  String? captureNote;
  Completer<bool>? focusReply;
  Completer<void>? focusCommandReply;
  Completer<void>? boundsReply;
  Completer<void>? pauseReply;
  Completer<void>? resumeReply;
  final calls = <MethodCall>[];
  ReaderController get reader =>
      container.read(readerControllerProvider.notifier);

  Future<void> initialize({String fixture = 'reflowable.epub'}) async {
    directory = await Directory.systemTemp.createTemp('busybooks-pane-owner-');
    store = await ReadingDataStore.open(p.join(directory.path, 'profile'));
    container = ProviderContainer(
      overrides: [
        readingDataStoreProvider.overrideWithValue(store),
        startupAppSettingsProvider.overrideWithValue(
          StartupAppSettings(AppSettings(), _Settings()),
        ),
      ],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(readerChannel, (call) async {
          calls.add(call);
          if (call.method == 'open') {
            session = (call.arguments as Map)['session'] as String;
          }
          if (call.method == 'bounds') await boundsReply?.future;
          if (call.method == 'hasFocus') {
            return focusReply?.future ?? nativeFocused;
          }
          if (call.method == 'focus') await focusCommandReply?.future;
          if (call.method == 'focusChrome') nativeFocused = false;
          if (call.method == 'capturePopover') {
            if (rejectCapture) {
              throw PlatformException(code: 'unconfirmed-input');
            }
            if (captureNote != null) {
              return {
                ...call.arguments as Map,
                'note': captureNote,
                'revision': 3,
                'color': 'yellow',
              };
            }
          }
          if (call.method == 'dispatch') {
            final command = jsonDecode(call.arguments as String) as Map;
            if (command['action'] == 'layoutVisibility') {
              if (command['visible'] == false) await pauseReply?.future;
              if (command['visible'] == true) await resumeReply?.future;
              scheduleMicrotask(
                () => event('layoutVisibility', {
                  'request': command['request'],
                  'revision': command['revision'],
                  'visible': command['visible'],
                }),
              );
            } else if (command['action'] == 'flush') {
              scheduleMicrotask(
                () => event('flushed', {'request': command['request']}),
              );
            } else if (command['action'] == 'appearance' &&
                command['request'] != null) {
              scheduleMicrotask(
                () =>
                    event('appearanceResult', {'request': command['request']}),
              );
            }
          }
          return null;
        });
    final opened = await container
        .read(workspaceControllerProvider.notifier)
        .openPath(p.absolute('test/fixtures/$fixture'));
    bookId = opened.books.single.id;
    container
        .read(bookPresentationProvider.notifier)
        .enterBook(bookId, BookView.split);
    await reader.open(bookId);
    await event('ready');
    await reader.updateViewport(
      const Rect.fromLTWH(300, 48, 900, 650),
      bookId: bookId,
    );
    await event('opened');
    await reader.show(true);
    expect(reader.interactive, isTrue);
  }

  Future<void> event(
    String type, [
    Map<String, dynamic> fields = const {},
  ]) async {
    final reply = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      readerChannel.name,
      readerChannel.codec.encodeMethodCall(
        MethodCall(
          'event',
          jsonEncode({'type': type, 'session': session, ...fields}),
        ),
      ),
      (_) => reply.complete(),
    );
    await reply.future;
  }

  Future<void> dispose() async {
    if (focusReply != null && !focusReply!.isCompleted) {
      focusReply!.complete(false);
    }
    if (boundsReply != null && !boundsReply!.isCompleted) {
      boundsReply!.complete();
    }
    if (pauseReply != null && !pauseReply!.isCompleted) pauseReply!.complete();
    if (resumeReply != null && !resumeReply!.isCompleted) {
      resumeReply!.complete();
    }
    if (focusCommandReply != null && !focusCommandReply!.isCompleted) {
      focusCommandReply!.complete();
    }
    await reader.close();
    container.dispose();
    await store.close();
    await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(readerChannel, null);
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Expected native request was not submitted');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('content focus accepts only its bounded renderer-owned protocol', () {
    final valid = {
      'type': 'contentFocus',
      'session': '123',
      'source': 'pointer',
    };
    expect(validReaderContentFocusEvent(valid), isTrue);
    expect(
      validReaderContentFocusEvent({...valid, 'source': 'command'}),
      isFalse,
    );
    expect(validReaderContentFocusEvent({...valid, 'session': ''}), isFalse);
    expect(
      validReaderContentFocusEvent({
        ...valid,
        'anchor': {'index': 9},
      }),
      isFalse,
    );
  });

  test(
    'changed viewport hides before bounds and waits for acknowledgement without changing search',
    () async {
      final f = _FocusGeometryFixture();
      await f.initialize();
      try {
        f.reader.search(' library ');
        final searchRevision = f.reader.searchRevision;
        f.calls.clear();
        f.boundsReply = Completer<void>();
        final updating = f.reader.updateViewport(
          const Rect.fromLTWH(300, 48, 450, 650),
          bookId: f.bookId,
        );
        await _until(() => f.calls.any((call) => call.method == 'bounds'));
        expect(f.calls.first.method, 'visible');
        expect(f.calls.first.arguments, false);
        expect(f.reader.interactive, isFalse);
        expect(
          f.calls.where(
            (call) => call.method == 'visible' && call.arguments == true,
          ),
          isEmpty,
        );
        f.boundsReply!.complete();
        expect(await updating, isTrue);
        expect(f.calls.last.method, 'visible');
        expect(f.calls.last.arguments, true);
        expect(f.reader.viewport.width, 450);
        expect(f.reader.searchRevision, searchRevision);
        expect(f.container.read(readerControllerProvider).query, ' library ');
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'late bounds acknowledgement cannot reveal a logically hidden pane',
    () async {
      final f = _FocusGeometryFixture();
      await f.initialize();
      try {
        f.boundsReply = Completer<void>();
        final updating = f.reader.updateViewport(
          const Rect.fromLTWH(300, 48, 450, 650),
          bookId: f.bookId,
        );
        await _until(() => f.calls.last.method == 'bounds');
        await f.reader.setWorkspaceVisible(false);
        f.calls.clear();
        f.boundsReply!.complete();
        expect(await updating, isFalse);
        expect(f.reader.hasCurrentViewport, isFalse);
        expect(f.reader.interactive, isFalse);
        expect(
          f.calls.where(
            (call) => call.method == 'visible' && call.arguments == true,
          ),
          isEmpty,
        );
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'publication focus revalidates its owner after the native handoff',
    () async {
      final f = _FocusGeometryFixture();
      await f.initialize();
      try {
        f.calls.clear();
        f.focusCommandReply = Completer<void>();
        var current = true;
        final focusing = f.reader.focusPublication(isCurrent: () => current);
        await _until(() => f.calls.any((call) => call.method == 'focus'));
        expect(f.calls.last.arguments, {'session': f.reader.sessionId});
        current = false;
        f.focusCommandReply!.complete();
        await focusing;
        expect(
          f.calls.where(
            (call) =>
                call.method == 'dispatch' &&
                jsonDecode(call.arguments as String)['action'] == 'focus',
          ),
          isEmpty,
        );
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'late native focus reply cannot steal a Notebook editing handoff',
    () async {
      final f = _FocusGeometryFixture();
      await f.initialize();
      try {
        f.focusReply = Completer<bool>();
        final focused = f.event('contentFocus', {'source': 'pointer'});
        await _until(() => f.calls.any((call) => call.method == 'hasFocus'));
        f.container
            .read(bookPresentationProvider.notifier)
            .focusPane(f.bookId, BookPane.notebook);
        await f.reader.focusChrome();
        f.focusReply!.complete(true);
        await focused;
        expect(
          f.container.read(bookPresentationProvider).lastPane,
          BookPane.notebook,
        );
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'native ownership updates last pane before shortcut delivery and rejects hidden focus',
    () async {
      final f = _FocusGeometryFixture();
      await f.initialize();
      final delivered = <BookPane>[];
      final subscription = f.reader.events.stream.listen((event) {
        if (event['type'] == 'key') {
          delivered.add(f.container.read(bookPresentationProvider).lastPane);
        }
      });
      try {
        f.container
            .read(bookPresentationProvider.notifier)
            .focusPane(f.bookId, BookPane.notebook);
        await f.event('key', {
          'key': 'f',
          'control': true,
          'alt': false,
          'meta': false,
          'shift': false,
        });
        await _until(() => delivered.isNotEmpty);
        expect(delivered, [BookPane.reading]);
        f.container
            .read(bookPresentationProvider.notifier)
            .focusPane(f.bookId, BookPane.notebook);
        await f.reader.setWorkspaceVisible(false);
        f.calls.clear();
        await f.event('contentFocus', {'source': 'pointer'});
        expect(
          f.container.read(bookPresentationProvider).lastPane,
          BookPane.notebook,
        );
        expect(f.calls.where((call) => call.method == 'hasFocus'), isEmpty);
      } finally {
        await subscription.cancel();
        await f.dispose();
      }
    },
  );
  test(
    'viewport transfer seals protected popup input before any native hide',
    () async {
      final f = _FocusGeometryFixture();
      await f.initialize();
      try {
        await f.event('selection', {
          'text': 'library',
          'anchor': {'cfi': 'epubcfi(/6/2!/4/4,/1:53,/1:60)', 'index': 0},
        });
        f.container
            .read(bookPresentationProvider.notifier)
            .focusPane(f.bookId, BookPane.notebook);
        await f.reader.showPopover('selection');
        final popup =
            f.calls.lastWhere((call) => call.method == 'popover').arguments
                as Map;
        expect(popup['viewportX'], 300);
        expect(popup['viewportY'], 48);
        expect(popup['viewportWidth'], 900);
        expect(popup['viewportHeight'], 650);
        expect(
          f.container.read(bookPresentationProvider).lastPane,
          BookPane.reading,
        );
        f.captureNote = 'Protected native input survives divider geometry.';
        f.calls.clear();
        expect(
          await f.reader.updateViewport(
            const Rect.fromLTWH(300, 48, 450, 650),
            bookId: f.bookId,
          ),
          isTrue,
        );
        final methods = f.calls.map((call) => call.method).toList();
        expect(
          methods.indexOf('capturePopover'),
          lessThan(methods.indexOf('visible')),
        );
        expect(
          methods.indexOf('dismissPopover'),
          lessThan(methods.indexOf('bounds')),
        );
        final notes = f.container.read(notebookControllerProvider);
        final source = notes.sources.values.singleWhere(
          (note) => note.bookId == f.bookId,
        );
        expect(notes.effectiveNote(source), f.captureNote);
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'unconfirmed popup input preserves its editor and retries geometry explicitly',
    () async {
      final f = _FocusGeometryFixture();
      await f.initialize();
      try {
        await f.reader.showPopover('selection');
        f.rejectCapture = true;
        f.calls.clear();
        expect(
          await f.reader.updateViewport(
            const Rect.fromLTWH(300, 48, 450, 650),
            bookId: f.bookId,
          ),
          isFalse,
        );
        expect(
          f.calls.where(
            (call) =>
                call.method == 'bounds' ||
                call.method == 'dismissPopover' ||
                call.method == 'visible',
          ),
          isEmpty,
        );
        expect(f.reader.viewport.width, 900);
        expect(
          f.container.read(readerControllerProvider).warning,
          contains('unconfirmed-input'),
        );
        f.rejectCapture = false;
        expect(
          await f.reader.updateViewport(
            const Rect.fromLTWH(300, 48, 450, 650),
            bookId: f.bookId,
          ),
          isTrue,
        );
        expect(f.reader.viewport.width, 450);
      } finally {
        f.rejectCapture = false;
        await f.dispose();
      }
    },
  );

  test(
    'PDF hide drains before native invisibility and hidden flush stays usable',
    () async {
      final f = _FocusGeometryFixture();
      await f.initialize(fixture: 'text.pdf');
      try {
        f.calls.clear();
        f.pauseReply = Completer<void>();
        final hide = f.reader.setWorkspaceVisible(false);
        await _until(
          () => f.calls.any(
            (call) =>
                call.method == 'dispatch' &&
                jsonDecode(call.arguments as String)['action'] ==
                    'layoutVisibility',
          ),
        );
        expect(f.reader.interactive, isFalse);
        expect(
          f.calls.where((call) => call.method == 'visible'),
          isEmpty,
          reason: 'Frame-dependent PDF work must finish before physical hide',
        );
        f.pauseReply!.complete();
        await hide;
        expect(
          f.calls.lastWhere((call) => call.method == 'visible').arguments,
          false,
        );
        await f.reader.flush();
        expect(
          f.calls
              .where((call) => call.method == 'dispatch')
              .map((call) => jsonDecode(call.arguments as String)['action']),
          contains('flush'),
        );
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'a superseded PDF pause cannot hide a newer acknowledged reader pane',
    () async {
      final f = _FocusGeometryFixture();
      await f.initialize(fixture: 'text.pdf');
      try {
        f.pauseReply = Completer<void>();
        f.calls.clear();
        final hide = f.reader.setWorkspaceVisible(false);
        await _until(
          () => f.calls.any(
            (call) =>
                call.method == 'dispatch' &&
                jsonDecode(call.arguments as String)['visible'] == false,
          ),
        );
        final show = f.reader.setWorkspaceVisible(true);
        final geometry = f.reader.updateViewport(
          const Rect.fromLTWH(300, 48, 700, 650),
          bookId: f.bookId,
        );
        f.pauseReply!.complete();
        await Future.wait([hide, show, geometry]);
        expect(f.reader.interactive, isTrue);
        final visibility = f.calls
            .where((call) => call.method == 'visible')
            .map((call) => call.arguments)
            .toList();
        expect(
          visibility,
          [false, true],
          reason:
              'Only the current geometry transaction can hide; its newer reveal wins',
        );
      } finally {
        await f.dispose();
      }
    },
  );

  test('a newer PDF hide must quiesce an in-flight resume again', () async {
    final f = _FocusGeometryFixture();
    await f.initialize(fixture: 'text.pdf');
    try {
      await f.reader.setWorkspaceVisible(false);
      await f.reader.setWorkspaceVisible(true);
      f.calls.clear();
      f.resumeReply = Completer<void>();
      final geometry = f.reader.updateViewport(
        const Rect.fromLTWH(300, 48, 700, 650),
        bookId: f.bookId,
      );
      await _until(
        () => f.calls.any(
          (call) =>
              call.method == 'dispatch' &&
              jsonDecode(call.arguments as String)['action'] ==
                  'layoutVisibility' &&
              jsonDecode(call.arguments as String)['visible'] == true,
        ),
      );
      final previous = f.calls.length;
      await f.reader.setWorkspaceVisible(false);
      expect(
        f.calls
            .skip(previous)
            .where(
              (call) =>
                  call.method == 'dispatch' &&
                  jsonDecode(call.arguments as String)['action'] ==
                      'layoutVisibility' &&
                  jsonDecode(call.arguments as String)['visible'] == false,
            ),
        hasLength(1),
      );
      f.resumeReply!.complete();
      await geometry;
      expect(f.reader.interactive, isFalse);
      expect(
        f.calls.lastWhere((call) => call.method == 'visible').arguments,
        false,
      );
    } finally {
      await f.dispose();
    }
  });

  test(
    'hidden PDF preferences render only after native reveal and layout resume',
    () async {
      final f = _FocusGeometryFixture();
      await f.initialize(fixture: 'text.pdf');
      try {
        await f.reader.setWorkspaceVisible(false);
        f.calls.clear();
        await f.reader.setAppearance({'zoom': 'fit-width'});
        await f.reader.configureChrome({'dark': true});
        List<Map> commands() => f.calls
            .where((call) => call.method == 'dispatch')
            .map((call) => jsonDecode(call.arguments as String) as Map)
            .toList();
        expect(
          commands().where((command) => command['action'] == 'appearance'),
          isEmpty,
        );
        await f.reader.flush();
        await f.reader.setWorkspaceVisible(true);
        await f.reader.updateViewport(
          const Rect.fromLTWH(300, 48, 700, 650),
          bookId: f.bookId,
        );
        final visible = f.calls.indexWhere(
          (call) => call.method == 'visible' && call.arguments == true,
        );
        final resume = f.calls.indexWhere(
          (call) =>
              call.method == 'dispatch' &&
              jsonDecode(call.arguments as String)['action'] ==
                  'layoutVisibility' &&
              jsonDecode(call.arguments as String)['visible'] == true,
        );
        final appearance = f.calls.indexWhere(
          (call) =>
              call.method == 'dispatch' &&
              jsonDecode(call.arguments as String)['action'] == 'appearance',
        );
        expect(visible, greaterThanOrEqualTo(0));
        expect(resume, greaterThan(visible));
        expect(appearance, greaterThan(resume));
        expect(
          commands().lastWhere(
            (command) => command['action'] == 'appearance',
          )['value']['zoom'],
          'fit-width',
        );
      } finally {
        await f.dispose();
      }
    },
  );
}
