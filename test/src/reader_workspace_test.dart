import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:busybooks/src/annotations/domain/annotation_filter.dart';
import 'package:busybooks/src/app/app_router.dart';
import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/busybooks_app.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/app/busybooks_dialogs.dart';
import 'package:busybooks/src/app/busybooks_glyphs.dart';
import 'package:busybooks/src/app/busybooks_main_menu.dart';
import 'package:busybooks/src/app/busybooks_search_field.dart';
import 'package:busybooks/src/app/command_focus.dart';
import 'package:busybooks/src/app/command_registry.dart';
import 'package:busybooks/src/app/keymap_controller.dart';
import 'package:busybooks/src/app/linux/linux_header_style.dart';
import 'package:busybooks/src/app/linux/linux_page_frame.dart';
import 'package:busybooks/src/app/settings_screen.dart';
import 'package:busybooks/src/app/shortcut_binding.dart';
import 'package:busybooks/src/app/system_accent.dart';
import 'package:busybooks/src/app/window_control_service.dart';
import 'package:busybooks/src/book_workspace/application/book_sidebar_controller.dart';
import 'package:busybooks/src/book_workspace/presentation/book_header.dart';
import 'package:busybooks/src/book_workspace/presentation/book_workspace_screen.dart';
import 'package:busybooks/src/book_workspace/application/book_presentation.dart';
import 'package:busybooks/src/core/typography.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/application/collection_view_controller.dart';
import 'package:busybooks/src/library/data/record_validation.dart';
import 'package:busybooks/src/library/domain/annotation_limits.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/library/presentation/collection_screen.dart';
import 'package:busybooks/src/notebook/application/notebook_controller.dart';
import 'package:busybooks/src/notebook/application/notebook_view.dart';
import 'package:busybooks/src/notebook/presentation/book_view_selector.dart';
import 'package:busybooks/src/notebook/presentation/notebook_item.dart';
import 'package:busybooks/src/notebook/presentation/region_preview.dart';
import 'package:busybooks/src/notebook/presentation/notebook_screen.dart';
import 'package:busybooks/src/platform/gtk_header_icon_service.dart';
import 'package:busybooks/src/platform/native_menu_service.dart';
import 'package:busybooks/src/platform/speech_service.dart';
import 'package:busybooks/src/reading/application/dictionary_service.dart';
import 'package:busybooks/src/reading/application/narration_controller.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';
import 'package:busybooks/src/reading/domain/reader_action.dart';
import 'package:busybooks/src/reading/domain/publication_outline.dart';
import 'package:busybooks/src/reading/presentation/reader_popover.dart';
import 'package:busybooks/src/reading/presentation/reader_screen.dart';
import 'package:busybooks/src/reading/presentation/reader_sidebar.dart';
import 'package:busybooks/src/search/book_search_session.dart';
import 'package:busybooks/src/search/book_search_widgets.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../support/annotation_store_gate.dart';

Future<void> _until(bool Function() done) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      fail('Expected note transition did not complete');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _popupUpdate(WidgetTester tester, Map payload) async {
  final reply = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    readerPopoverChannel.name,
    readerPopoverChannel.codec.encodeMethodCall(
      MethodCall('update', {'locale': 'en', ...payload}),
    ),
    (_) => reply.complete(),
  );
  await tester.pump();
  await reply.future;
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  bool settle = true,
}) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > const Duration(seconds: 30)) {
      fail('Expected widget transition did not complete');
    }
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  if (settle) {
    await tester.pumpAndSettle();
  }
}

void _connectPopover(
  _ReaderFixture f, {
  List<Map>? delivered,
  List<Map>? completed,
  List<Map>? rejected,
  List<Map>? rejectionReplies,
  Completer<void>? rejectionEntered,
  Completer<void>? rejectionProceed,
  Set<String>? rejectActions,
  Set<String>? loseAcknowledgement,
  int actionByteLimit = maxReaderPopoverActionBytes,
  int forwardedByteLimit = maxReaderPopoverActionBytes,
  _PresentationGate? presentation,
}) {
  f.onNativeCall = (call) async {
    if (call.method == 'popover' && presentation != null) {
      return presentation.show((call.arguments as Map).cast<String, dynamic>());
    }
    if (call.method == 'dismissPopover') presentation?.hide();
    if (call.method == 'capturePopover') {
      final result = Completer<dynamic>();
      ServicesBinding.instance.channelBuffers.push(
        readerPopoverChannel.name,
        readerPopoverChannel.codec.encodeMethodCall(
          MethodCall('capture', call.arguments),
        ),
        (reply) {
          try {
            result.complete(readerPopoverChannel.codec.decodeEnvelope(reply!));
          } catch (error, trace) {
            result.completeError(error, trace);
          }
        },
      );
      return result.future;
    }
    if (call.method == 'popoverResult') {
      ServicesBinding.instance.channelBuffers.push(
        readerPopoverChannel.name,
        readerPopoverChannel.codec.encodeMethodCall(
          MethodCall('result', call.arguments),
        ),
        (_) {},
      );
    }
  };
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(readerPopoverChannel, (call) async {
        if (call.method == 'ready') presentation?.ready();
        if (call.method == 'presented') {
          presentation?.painted(call.arguments as Map);
        }
        if (call.method == 'failed') presentation?.fail(call.arguments as Map);
        if (call.method == 'action') {
          final event = (jsonDecode(call.arguments as String) as Map)
              .cast<String, dynamic>();
          // Native rejects before event_ is called. This is deliberately
          // different from a repository failure or a lost acknowledgement.
          if (utf8.encode(call.arguments as String).length > actionByteLimit ||
              rejectActions?.contains(event['action']) == true) {
            rejected?.add(event);
            if (rejectionProceed != null &&
                ['annotationNote', 'highlight'].contains(event['action'])) {
              rejectionEntered?.complete();
              await rejectionProceed.future;
            }
            rejectionReplies?.add(event);
            throw PlatformException(
              code: 'reader-action-size',
              message: 'Reader action exceeds its UTF-8 byte limit',
            );
          }
          // ReaderHost has a distinct publication-event bound; only its
          // trusted popover callback opts in to the note delivery budget.
          if (utf8.encode(call.arguments as String).length >
              forwardedByteLimit) {
            return null;
          }
          delivered?.add(event);
          final forwarding = f.event('popoverAction', event);
          if (loseAcknowledgement?.contains(event['action']) == true) {
            unawaited(forwarding.then((_) => completed?.add(event)));
            throw PlatformException(
              code: 'reader-channel-interrupted',
              message: 'Delivery outcome is unknown',
            );
          }
          await forwarding;
          completed?.add(event);
        }
        return null;
      });
}

// Models the native ownership contract without opening windows or sockets.
// A ready channel and a painted Flutter subtree are independent of native raster readiness.
class _PresentationGate {
  bool allowReady = true, channelReady = false;
  Map<String, dynamic>? payload;
  Completer<void>? pending;
  Completer<void> frame = Completer<void>();
  final visible = <Object?>[];
  Map<String, dynamic> overrides = {};
  Future<void> show(Map<String, dynamic> value) {
    hide();
    payload = value;
    pending = Completer<void>();
    if (channelReady && allowReady) _deliver();
    return pending!.future;
  }

  void ready() {
    channelReady = true;
    if (allowReady && payload != null) _deliver();
  }

  void _deliver() {
    ServicesBinding.instance.channelBuffers.push(
      readerPopoverChannel.name,
      readerPopoverChannel.codec.encodeMethodCall(
        MethodCall('update', {...payload!, ...overrides}),
      ),
      (_) {},
    );
  }

  bool matches(Map value) =>
      payload != null &&
      value['session'] == payload!['session'] &&
      value['presentation'] == payload!['presentation'];
  void painted(Map value) {
    final owner = payload, wait = pending;
    if (!matches(value)) return;
    frame.future.then((_) {
      if (!identical(owner, payload) || wait == null || wait.isCompleted) {
        return;
      }
      visible.add(value['presentation']);
      wait.complete();
    });
  }

  void fail(Map value) {
    if (!matches(value)) return;
    final wait = pending;
    pending = null;
    payload = null;
    if (wait != null && !wait.isCompleted) {
      wait.completeError(PlatformException(code: 'popover-content'));
    }
  }

  void hide() {
    final wait = pending;
    pending = null;
    payload = null;
    if (wait != null && !wait.isCompleted) {
      wait.completeError(PlatformException(code: 'popover-cancelled'));
    }
  }
}

// Same bridge as desktop_actions_test: reader operations can await callbacks
// queued on the widget clock while the real storage worker is running.
Future<void> _readerAction(
  WidgetTester tester,
  Future<void> Function() action, {
  bool settle = true,
  bool widgetClock = false,
}) async {
  var done = false;
  Object? failure;
  StackTrace? trace;
  void start() {
    action().then<void>(
      (_) {
        done = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        done = true;
      },
    );
  }

  if (widgetClock) {
    start();
  } else {
    await tester.runAsync(() async => start());
  }
  await _pumpUntil(tester, () => done, settle: settle);
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

class _Settings implements LocalSettingsStore {
  @override
  Future<Map<String, dynamic>> load() async => {};
  @override
  Future<void> save(Map<String, dynamic> json) async {}
}

// The opt-in allocation probe talks only to this test's authenticated loopback
// VM service, rather than the widget binding's deliberately mocked HTTP client.
class _VmDiagnosticsHttpOverrides extends HttpOverrides {}

class _CachedSearchSnapshot extends BookSearchController {
  _CachedSearchSnapshot();
  // Model a cached/asynchronously delivered snapshot independently of its
  // record's lifetime. The presentation must still consult the data owners.
  void deliver(BookSearchState snapshot) => state = snapshot;
}

class _Speech extends SpeechService {
  final calls = <({String action, Map<String, dynamic> args})>[];
  Object? stopError;
  @override
  Future<dynamic> call(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    calls.add((action: action, args: args));
    if (action == 'stop' && stopError != null) throw stopError!;
    return action == 'voices' ? ['Fixture Voice', 'Fixture Voice 2'] : null;
  }

  @override
  Future<void> dispose() async {
    await events.close();
  }
}

class _ReaderFixture {
  _ReaderFixture(this.directory, this.store, this.container);
  final Directory directory;
  final ReadingDataStore store;
  final ProviderContainer container;
  String session = '';
  Future<void> Function(Map)? onDispatch;
  Future<dynamic> Function(MethodCall)? onNativeCall;
  final calls = <MethodCall>[];
  final acceptedDispatches = <Map>[];
  final rejectedDispatches = <Map>[];
  int dispatchFailures = 0;
  bool acknowledgeFlush = true;
  bool nativeFocused = true;
  int _verification = 0;
  ReaderController get reader =>
      container.read(readerControllerProvider.notifier);
  ReaderState get state => container.read(readerControllerProvider);
  BookSidebarState get sidebar =>
      container.read(bookSidebarProvider(state.bookId!));
  BookSidebarController get sidebarController =>
      container.read(bookSidebarProvider(state.bookId!).notifier);
  BookSearchState get search => container.read(bookSearchSessionProvider);
  BookSearchController get searchController =>
      container.read(bookSearchSessionProvider.notifier);
  static Future<_ReaderFixture> create(
    String fixture, {
    SpeechService? speech,
    Duration? startupTimeout,
    ReadingDataStore Function(ReadingDataStore)? wrapStore,
    bool ownedOriginal = false,
    Directory? profileDirectory,
    bool initialize = true,
    GtkHeaderIconService? headerIcons,
    WindowControlService? windowControls,
    DictionaryService? dictionary,
    BookSearchController Function()? searchController,
  }) async {
    final directory =
        profileDirectory ??
        await Directory.systemTemp.createTemp('busybooks-reading-controls-');
    final store = await ReadingDataStore.open(
      p.join(directory.path, 'profile'),
    );
    final container = ProviderContainer(
      overrides: [
        if (searchController != null)
          bookSearchSessionProvider.overrideWith(searchController),
        if (dictionary != null)
          dictionaryServiceProvider.overrideWithValue(dictionary),
        if (windowControls != null)
          linuxAccentPlatformProvider.overrideWithValue(false),
        if (headerIcons != null)
          gtkHeaderIconServiceProvider.overrideWithValue(headerIcons),
        if (windowControls != null)
          windowControlServiceProvider.overrideWith((ref) => windowControls),
        if (speech != null) speechServiceProvider.overrideWithValue(speech),
        if (startupTimeout != null)
          readerStartupTimeoutProvider.overrideWithValue(startupTimeout),
        readingDataStoreProvider.overrideWithValue(
          wrapStore?.call(store) ?? store,
        ),
        startupAppSettingsProvider.overrideWithValue(
          StartupAppSettings(AppSettings(), _Settings()),
        ),
      ],
    );
    final test = _ReaderFixture(directory, store, container);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(readerChannel, (call) async {
          test.calls.add(call);
          if (call.method == 'dispatch' &&
              utf8.encode(call.arguments as String).length > 1048576) {
            test.dispatchFailures++;
            test.rejectedDispatches.add({
              'action': jsonDecode(call.arguments as String)['action'],
              'bytes': utf8.encode(call.arguments as String).length,
            });
            throw PlatformException(
              code: 'reader-message',
              message: 'Invalid renderer message',
            );
          }
          final nativeResult = await test.onNativeCall?.call(call);
          if (call.method == 'focusChrome') test.nativeFocused = false;
          if (call.method == 'focus') test.nativeFocused = true;
          if (call.method == 'hasFocus') {
            return nativeResult ?? test.nativeFocused;
          }
          if (call.method == 'capturePopover' || call.method == 'popover') {
            return nativeResult;
          }
          if (call.method == 'open') {
            test.session = (call.arguments as Map)['session'] as String;
          }
          if (call.method == 'dispatch') {
            final command = jsonDecode(call.arguments as String) as Map;
            if (command['action'] == 'layoutVisibility') {
              scheduleMicrotask(
                () => test.event('layoutVisibility', {
                  'request': command['request'],
                  'revision': command['revision'],
                  'visible': command['visible'],
                }),
              );
            }
          }
          if (test.acknowledgeFlush &&
              call.method == 'dispatch' &&
              jsonDecode(call.arguments as String)['action'] == 'flush') {
            final request = jsonDecode(call.arguments as String)['request'];
            scheduleMicrotask(
              () => test.event('flushed', {'request': request}),
            );
          }
          if (call.method == 'dispatch' && test.onDispatch == null) {
            final command = jsonDecode(call.arguments as String) as Map;
            if (command['action'] == 'appearance' &&
                command['request'] != null) {
              scheduleMicrotask(
                () => test.event('appearanceResult', {
                  'request': command['request'],
                }),
              );
            }
          }
          if (call.method == 'dispatch' && test.onDispatch != null) {
            await test.onDispatch!(jsonDecode(call.arguments as String) as Map);
          }
          if (call.method == 'dispatch') {
            test.acceptedDispatches.add(
              jsonDecode(call.arguments as String) as Map,
            );
          }
          return null;
        });
    final original = ownedOriginal
        ? (await File(
            'test/fixtures/$fixture',
          ).copy(p.join(directory.path, fixture))).path
        : p.absolute('test/fixtures/$fixture');
    final book = await container
        .read(workspaceControllerProvider.notifier)
        .openPath(original);
    container.read(appRouterProvider).go('/read/${book.books.single.id}');
    container.read(bookSearchSessionProvider);
    await test.reader.open(book.books.single.id);
    if (initialize) {
      await test.event('ready');
      await test.event('opened', {
        'typography': fixture == 'reflowable.epub' || fixture == 'long.epub'
            ? TypographyCapabilities.reflowable.toJson()
            : TypographyCapabilities.none.toJson(),
      });
      await test.reader.show(true);
    }
    return test;
  }

  Future<void> event(
    String type, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (type == 'opened' &&
        (args['session'] ?? session) == reader.sessionId &&
        state.bookId != null) {
      await reader.updateViewport(
        const Rect.fromLTWH(0, 0, 900, 650),
        bookId: state.bookId!,
      );
    }
    final reply = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      readerChannel.name,
      readerChannel.codec.encodeMethodCall(
        MethodCall(
          'event',
          jsonEncode({'type': type, 'session': session, ...args}),
        ),
      ),
      (_) => reply.complete(),
    );
    await reply.future;
  }

  // A reply alone does not mean success: native dispatch rejection comes back
  // in an error envelope. Cold-open tests must not inject opened after that.
  Future<void> checkedEvent(
    String type, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (type == 'opened' &&
        (args['session'] ?? session) == reader.sessionId &&
        state.bookId != null) {
      await reader.updateViewport(
        const Rect.fromLTWH(0, 0, 900, 650),
        bookId: state.bookId!,
      );
    }
    final reply = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      readerChannel.name,
      readerChannel.codec.encodeMethodCall(
        MethodCall(
          'event',
          jsonEncode({'type': type, 'session': session, ...args}),
        ),
      ),
      (bytes) {
        try {
          readerChannel.codec.decodeEnvelope(bytes!);
          reply.complete();
        } catch (error, trace) {
          reply.completeError(error, trace);
        }
      },
    );
    return reply.future;
  }

  Future<void> finishColdOpen() async {
    expectSync(state.ready, isFalse);
    expectSync(state.phase, 'initializing');
    Object? deliveryError;
    try {
      await checkedEvent('ready');
    } catch (error) {
      deliveryError = error;
    }
    final opens = acceptedDispatches.where(
      (m) => m['action'] == 'open' && m['session'] == session,
    );
    expectSync(
      {
        'deliveryError': deliveryError?.toString(),
        'rejectedDispatches': rejectedDispatches,
        'acceptedOpenCommands': opens.length,
      },
      {
        'deliveryError': null,
        'rejectedDispatches': [],
        'acceptedOpenCommands': 1,
      },
    );
    expectSync(
      utf8.encode(jsonEncode(opens.single)).length,
      lessThanOrEqualTo(1048576),
    );
    expectSync(state.ready, isFalse);
    expectSync(state.phase, 'opening');
    // Only a successfully delivered open command may produce this simulated
    // first-passage response. Actual native rendering is a separate gate.
    await checkedEvent('opened');
    await reader.show(true);
    expectSync(state.ready, isTrue);
    expectSync(state.phase, 'usable');
    expectSync(state.error, isNull);
    expectSync(state.warning, isNull);
  }

  List<Map> get dispatches => calls
      .where((c) => c.method == 'dispatch')
      .map((c) => jsonDecode(c.arguments as String) as Map)
      .toList();
  NotebookController get notes =>
      container.read(notebookControllerProvider.notifier);
  NotebookState get drafts => container.read(notebookControllerProvider);
  Map get popup =>
      calls.lastWhere((c) => c.method == 'popover').arguments as Map;
  Future<ReaderSelectionMenuOwner> selectionMenuOwner(
    Map<String, dynamic> passage, {
    String type = 'selection',
  }) async {
    final request = reader.events.stream.firstWhere(
      (e) => e['type'] == 'selectionMenu',
    );
    await event(type, {'settled': true, ...passage});
    final target = (await request)['target'] as ReaderSelectionTarget;
    return (await reader.prepareSelectionMenu(target, dismiss: () async {}))!;
  }

  // These fixtures exercise the retained secondary channel's draft protocol.
  // Automatic publication selection is tested through the primary native menu.
  Future<void> openAnnotationPopover(
    ReadingAnnotation annotation, {
    Object? rect,
  }) async {
    if (annotation.bookId != state.bookId) return;
    final current = drafts.findAnnotation(
      annotation.bookId,
      annotation.id,
      reader.annotations,
    );
    if (current == null) return;
    await reader.showPopover('selection', extra: {'annotationId': current.id});
  }

  Future<void> openSelectionPopover() async {
    await event('selection', {
      'anchor': {'page': 0, 'textOffset': 1, 'textLength': 3},
      'text': 'ABC',
      'reference': 'Page 1',
      'settled': false,
    });
    await reader.showPopover('selection');
  }

  Future<void> action(String action, [Map<String, dynamic> args = const {}]) =>
      event('popoverAction', {
        'presentation': popup['presentation'],
        'action': action,
        'request': calls.length + 1,
        ...args,
      });
  Future<void> verifyNote(String id, String note) async {
    final verification = ++_verification;
    final bookId = state.bookId!;
    expectSync(
      (await store.call('annotations', bookId) as List).single['note'],
      note,
    );
    expectSync(reader.annotations.single.id, id);
    expectSync(reader.annotations.single.note, note);
    final markdown = p.join(directory.path, 'notes-$verification.md');
    await store.call('exportMarkdown', {
      'id': bookId,
      'path': markdown,
      'overwrite': true,
    });
    expectSync(await File(markdown).readAsString(), contains(note));
    final backup = p.join(directory.path, 'notes-$verification.busybooks');
    await store.call('backup', {'path': backup, 'preferences': {}});
    final restored = await ReadingDataStore.open(
      p.join(directory.path, 'restored-$verification'),
    );
    try {
      await restored.call('restore', backup);
      final records = await restored.call('annotations', bookId) as List;
      expectSync(records.single['id'], id);
      expectSync(records.single['note'], note);
    } finally {
      await restored.close();
    }
  }

  Future<void> dispose({bool deleteDirectory = true}) async {
    await reader.close();
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(readerChannel, null);
    await store.close();
    if (deleteDirectory) await directory.delete(recursive: true);
  }
}

class _PersistenceFailure implements ReadingDataStore {
  _PersistenceFailure(this.inner);
  final ReadingDataStore inner;
  bool fail = true;
  @override
  String get root => inner.root;
  @override
  Stream<Map<String, dynamic>> get progress => inner.progress;
  @override
  Stream<int> get changes => inner.changes;
  @override
  int get searchRevision => inner.searchRevision;
  @override
  Future<dynamic> call(String action, [Object? argument]) {
    if (fail &&
        action == 'updateBook' &&
        ((argument as Map)['changes'] as Map).containsKey('anchor')) {
      return Future.error(const FileSystemException('Injected database full'));
    }
    return inner.call(action, argument);
  }

  @override
  void cancel() => inner.cancel();
  @override
  Future<void> close() => inner.close();
}

String _transportNote(String encoding) => switch (encoding) {
  'ASCII' => 'A' * 70000,
  'multibyte' => '漢📘' * 30000,
  _ => '\u0001' * 180000,
};

void _expectRendererCopy(Map message, List<ReadingAnnotation> sources) {
  final value =
      message[message['action'] == 'open' ? 'annotations' : 'value'] as List;
  expectSync(value.length, sources.length);
  final byId = {for (final a in sources) a.id: a};
  for (final entry in value) {
    final a = byId[entry['id']]!;
    expectSync((entry as Map).containsKey('note'), isFalse);
    // Preserve the existing renderer contract, including CFI/PDF segments,
    // annotation kind, color, identity and saved quotation/reference.
    expectSync(entry, {...a.data}..remove('note'));
  }
}

Future<void> _verifyColdNotes(
  _ReaderFixture f,
  List<ReadingAnnotation> expected,
) async {
  final id = f.state.bookId!;
  Map byId(Iterable values) => {for (final a in values) a['id']: a};
  final records = await f.store.call('annotations', id) as List;
  expectSync(byId(records), byId(expected.map((a) => a.data)));
  expectSync(byId(f.reader.annotations.map((a) => a.data)), byId(records));
  for (final a in f.reader.annotations) {
    expectSync(f.drafts.effectiveNote(a), byId(records)[a.id]['note']);
  }
  final markdown = p.join(f.directory.path, 'cold-open.md');
  await f.store.call('exportMarkdown', {'id': id, 'path': markdown});
  final text = await File(markdown).readAsString();
  final sections = text.split('\n## ').skip(1).toList();
  expectSync(sections.length, expected.length);
  for (final a in expected) {
    final anchor = '<!-- BusyBooks anchor: ${jsonEncode(a.anchor)} -->';
    final section = sections.singleWhere((s) => s.contains(anchor));
    // Match within its own anchored section. Searching a megabyte of repeated
    // prefixes for every long note would exercise substring complexity rather
    // than the export contract, and would not establish the right association.
    expectSync(section, contains(a.note));
    if (a.text.isNotEmpty) expectSync(section, contains(a.text));
    expectSync(section, contains(a.reference));
  }
  final archive = p.join(f.directory.path, 'cold-open.busybooks');
  await f.reader.flush();
  await f.notes.flush();
  await f.store.call('backup', {'path': archive, 'preferences': {}});
  final restored = await ReadingDataStore.open(
    p.join(f.directory.path, 'cold-restored'),
  );
  try {
    await restored.call('restore', archive);
    expectSync(
      byId(await restored.call('annotations', id) as List),
      byId(records),
    );
  } finally {
    await restored.close();
  }
}

Widget _sidebarApplication(
  _ReaderFixture f, {
  bool routed = false,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
}) {
  final defaults = BusyBooksCommandCatalog.create(
    executions: {
      BusyBooksCommandIds.outline: () =>
          f.sidebarController.selectPanel(BookSidebarPanel.outline),
      BusyBooksCommandIds.annotations: () =>
          f.sidebarController.selectPanel(BookSidebarPanel.marks),
      BusyBooksCommandIds.thumbnails: () =>
          f.sidebarController.selectPanel(BookSidebarPanel.thumbnails),
      BusyBooksCommandIds.readerBooks: () =>
          f.sidebarController.selectPanel(BookSidebarPanel.books),
      BusyBooksCommandIds.search: () =>
          f.searchController.open(category: BookSearchCategory.bookText),
      BusyBooksCommandIds.previous: () => f.reader.send('previous'),
      BusyBooksCommandIds.next: () => f.reader.send('next'),
    },
  );
  final registry = effectiveCommandRegistry(defaults, {
    BusyBooksCommandIds.outline: const BusyBooksKeyBinding(
      LogicalKeyboardKey.f8,
      control: true,
      shift: true,
      alt: true,
    ),
  });
  final router = routed ? f.container.read(appRouterProvider) : null;
  if (router != null) router.go('/read/${f.state.bookId}');
  Widget builder(BuildContext c, Widget? child) =>
      BusyBooksCommandRegistryScope(
        registry: registry,
        child: Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      );
  final theme = buildBusyBooksTheme(
    brightness: Brightness.light,
    accentColor: const Color(0xff3584e4),
  );
  return UncontrolledProviderScope(
    container: f.container,
    child: router == null
        ? MaterialApp(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: builder,
            home: BookWorkspaceScreen(
              view: BookView.reading,
              id: f.state.bookId!,
            ),
          )
        : MaterialApp.router(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: builder,
            routerConfig: router,
          ),
  );
}

class _HeaderWindow implements NativeWindowController {
  final listeners = <WindowListener>[];
  bool fullScreen = false;
  @override
  void addListener(WindowListener l) => listeners.add(l);
  @override
  void removeListener(WindowListener l) => listeners.remove(l);
  @override
  Future<void> setPreventClose(bool value) async {}
  @override
  Future<bool> isFullScreen() async => fullScreen;
  @override
  Future<void> setFullScreen(bool value) async {
    fullScreen = value;
  }

  @override
  Future<void> close() async {}
}

Future<void> _mountHeaderApplication(
  WidgetTester tester,
  _ReaderFixture f,
  String route, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1200, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const input = MethodChannel('com.busybooks.app/asset_input');
  const yaru = MethodChannel('yaru_window');
  const events = EventChannel('yaru_window/events');
  messenger.setMockMethodCallHandler(input, (_) async => null);
  messenger.setMockMethodCallHandler(
    yaru,
    (c) async => c.method == 'state' ? <String, Object?>{} : null,
  );
  messenger.setMockStreamHandler(
    events,
    MockStreamHandler.inline(onListen: (_, sink) {}),
  );
  addTearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel(nativeMenuChannelName),
      null,
    );
    messenger.setMockMethodCallHandler(input, null);
    messenger.setMockMethodCallHandler(yaru, null);
    messenger.setMockStreamHandler(events, null);
  });
  f.container.read(appRouterProvider).go(route);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: f.container,
      child: const BusyBooksApp(),
    ),
  );
  await _pumpUntil(tester, () {
    final path = f.container
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path;
    if (path.startsWith('/notebook/')) {
      final search = f.container.read(bookSearchSessionProvider);
      return find.byType(NotebookContent).evaluate().isNotEmpty &&
          (!search.active ||
              search.category == BookSearchCategory.bookText ||
              !search.loading);
    }
    if (path.startsWith('/read/')) {
      return find.byType(ReadingContent).evaluate().isNotEmpty;
    }
    return true;
  }, settle: settle);
}

List<Map> _nativeLeaves(List entries) {
  final result = <Map>[];
  for (final entry in entries) {
    result.add(entry as Map);
    if (entry['children'] is List) {
      result.addAll(_nativeLeaves(entry['children'] as List));
    }
  }
  return result;
}

Future<void> _mainMenuSelect(
  WidgetTester tester,
  String? label, {
  List<List<Map>>? snapshots,
  String tooltip = 'Main Menu',
}) async {
  const channel = MethodChannel(nativeMenuChannelName);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'show') return null;
        final entries = _nativeLeaves(
          (call.arguments as Map)['entries'] as List,
        );
        snapshots?.add(entries);
        return label == null
            ? null
            : entries.indexWhere((e) => e['label'] == label);
      });
  await tester.tap(find.byTooltip(tooltip));
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _disposeHeaderApplication(
  WidgetTester tester,
  _ReaderFixture f,
) async {
  await tester.pumpWidget(const SizedBox());
  await _readerAction(tester, f.dispose);
  debugDefaultTargetPlatformOverride = null;
}

Finder _headerButton(String label) => find.byWidgetPredicate(
  (w) => w is BusyBooksHeaderIconButton && w.tooltip == label,
);
BusyBooksCommandRegistry _appCommands(WidgetTester tester) =>
    BusyBooksCommandRegistryScope.read(
      tester.element(find.byType(BusyBooksMainMenuButton)),
    )!;
Future<void> _closeActionError(WidgetTester tester) async {
  await _pumpUntil(tester, () => find.text('Error').evaluate().isNotEmpty);
  await tester.tap(find.text('Close'));
  await tester.pumpAndSettle();
}

class _ControlledDictionary implements DictionaryService {
  final terms = <String>[];
  final pending = <Completer<DictionaryResult>>[];
  final cancelled = <int>[];
  @override
  DictionaryRequest lookup(String term) {
    final index = pending.length;
    terms.add(term);
    final completion = Completer<DictionaryResult>();
    pending.add(completion);
    return DictionaryRequest(completion.future, () => cancelled.add(index));
  }

  void complete(
    int index, {
    DictionaryStatus status = DictionaryStatus.ready,
  }) => pending[index].complete(
    DictionaryResult(
      status,
      sections: const [
        DictionarySection('English', 'Noun', ['A controlled definition.']),
      ],
      entry: status == DictionaryStatus.ready
          ? WiktionaryService.entryUri(terms[index])
          : null,
    ),
  );
}

List<Map> _lookupUpdates(_ReaderFixture f) => f.calls
    .where(
      (c) =>
          c.method == 'popoverResult' && (c.arguments as Map)['lookup'] is Map,
    )
    .map((c) => c.arguments as Map)
    .toList();

Future<void> _startLookup(_ReaderFixture f, String term) async {
  await f.event('selection', {
    'anchor': {'page': 0, 'textOffset': 0, 'textLength': term.length},
    'text': term,
    'settled': true,
  });
  final target = await f.reader.prepareLookup();
  expect(target, isNotNull);
  await f.reader.lookup(target!);
}

void main() {
  _professionalWorkspaceTests();
  _nativeSelectionTests();
  for (final invalidation in ['capacity', 'book']) {
    testWidgets(
      'selector without a registry rejects a delayed $invalidation change',
      (tester) async {
        late _ReaderFixture f;
        late String first, second;
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create('text.pdf');
          first = f.state.bookId!;
          final other =
              await File(
                p.join(f.directory.path, 'other-selector-book.pdf'),
              ).writeAsBytes([
                ...await File('test/fixtures/text.pdf').readAsBytes(),
                ...'\n% separate selector publication\n'.codeUnits,
              ]);
          final workspace = f.container.read(
            workspaceControllerProvider.notifier,
          );
          second = (await workspace.openPath(other.path)).books.single.id;
          await workspace.loadBook(first, activate: true);
        });
        final entered = Completer<void>(), proceed = Completer<int?>();
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          const MethodChannel(nativeMenuChannelName),
          (call) async {
            if (call.method != 'show') return null;
            final entries = _nativeLeaves(
              (call.arguments as Map)['entries'] as List,
            );
            final split = entries.indexWhere(
              (entry) => entry['label'] == 'Split',
            );
            expect(split, greaterThanOrEqualTo(0));
            expect(entries[split]['enabled'], true);
            entered.complete();
            return proceed.future;
          },
        );
        try {
          final router = f.container.read(appRouterProvider);
          router.go('/read/$first');
          final presentation = f.container.read(
            bookPresentationProvider.notifier,
          );
          presentation.enterBook(first, BookView.reading);
          presentation.updateLayout(first, availableWidth: 1200, textScale: 1);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: f.container,
              child: MaterialApp(
                theme: buildBusyBooksTheme(
                  brightness: Brightness.light,
                  accentColor: Colors.orange,
                ),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Consumer(
                  builder: (context, ref, child) {
                    ref.watch(appLocationProvider);
                    final route = ref
                        .read(appRouterProvider)
                        .routeInformationProvider
                        .value
                        .uri
                        .path;
                    return Scaffold(
                      body: BookViewSelector(
                        id: bookIdForRoute(route)!,
                        view: bookViewForRoute(route)!,
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('View'));
          await _pumpUntil(tester, () => entered.isCompleted, settle: false);
          final closes = f.calls.where((call) => call.method == 'close').length;
          if (invalidation == 'capacity') {
            presentation.updateLayout(first, availableWidth: 700, textScale: 1);
          } else {
            await _readerAction(
              tester,
              () => f.container
                  .read(workspaceControllerProvider.notifier)
                  .loadBook(second, activate: true)
                  .then((_) {}),
              settle: false,
            );
            router.go('/read/$second');
            presentation.enterBook(second, BookView.reading);
            presentation.updateLayout(
              second,
              availableWidth: 1200,
              textScale: 1,
            );
          }
          await tester.pump();
          expect(
            tester.widget<BookViewSelector>(find.byType(BookViewSelector)).id,
            invalidation == 'book' ? second : first,
          );
          proceed.complete(2);
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            '/read/${invalidation == 'book' ? second : first}',
          );
          expect(
            f.calls.where((call) => call.method == 'close').length,
            closes,
          );
          expect(tester.takeException(), isNull);
        } finally {
          if (!proceed.isCompleted) proceed.complete(null);
          messenger.setMockMethodCallHandler(
            const MethodChannel(nativeMenuChannelName),
            null,
          );
          await _disposeHeaderApplication(tester, f);
        }
      },
    );
  }
  testWidgets(
    'native publication focus survives geometry and a retained Split view command',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        final id = f.state.bookId!;
        await _mountHeaderApplication(tester, f, '/read/$id');
        await _pumpUntil(tester, () => f.reader.interactive);
        // Model a genuine native click after Flutter chrome owned focus. The
        // event mirrors that ownership without sending focus back to native.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        f.nativeFocused = true;
        await _readerAction(
          tester,
          () => f.event('contentFocus', {'source': 'pointer'}),
        );
        expect(
          FocusManager.instance.primaryFocus,
          isA<BusyBooksPublicationFocusNode>(),
        );
        final session = f.reader.sessionId;
        final opens = f.calls.where((call) => call.method == 'open').length;
        f.acceptedDispatches.clear();
        tester.view.physicalSize = const Size(1400, 850);
        await _pumpUntil(
          tester,
          () =>
              f.reader.hasCurrentViewport &&
              f.acceptedDispatches.any(
                (command) => command['action'] == 'focus',
              ),
        );
        expect(
          FocusManager.instance.primaryFocus,
          isA<BusyBooksPublicationFocusNode>(),
        );
        f.acceptedDispatches.clear();
        await _readerAction(
          tester,
          () => _appCommands(tester).execute(BusyBooksCommandIds.viewSplit),
        );
        await _pumpUntil(
          tester,
          () =>
              f.reader.interactive &&
              f.acceptedDispatches.any(
                (command) => command['action'] == 'focus',
              ),
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/split/$id',
        );
        expect(f.reader.sessionId, session);
        expect(f.calls.where((call) => call.method == 'open').length, opens);
        expect(
          FocusManager.instance.primaryFocus,
          isA<BusyBooksPublicationFocusNode>(),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'native publication focus loss does not reactivate Flutter chrome',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        final id = f.state.bookId!;
        await _mountHeaderApplication(tester, f, '/read/$id');
        await _pumpUntil(tester, () => f.reader.interactive);
        FocusManager.instance.listenToApplicationLifecycleChangesIfSupported();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        f.nativeFocused = true;
        await _readerAction(
          tester,
          () => f.event('contentFocus', {'source': 'pointer'}),
        );
        expect(
          FocusManager.instance.primaryFocus,
          isA<BusyBooksPublicationFocusNode>(),
        );
        final chromeRequests = f.calls
            .where((call) => call.method == 'focusChrome')
            .length;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus,
          same(FocusManager.instance.rootScope),
        );
        expect(
          f.calls.where((call) => call.method == 'focusChrome').length,
          chromeRequests,
        );
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'native focus mirroring repairs confirmed loss once and rejects a later Notebook handoff',
    (tester) async {
      late _ReaderFixture f;
      final pending = Completer<bool>();
      StreamSubscription<Map<String, dynamic>>? openingEvents;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        final id = f.state.bookId!;
        // The fixture is already interactive before mounting. The retained
        // reader's asynchronous reopen can still issue its initial focusBook;
        // finish that handoff before testing a later native focus revision.
        var openingFinished = false;
        openingEvents = f.reader.events.stream.listen((event) {
          if (event['type'] == 'focusBook' &&
              event['session'] == f.reader.sessionId) {
            openingFinished = true;
          }
        });
        await _mountHeaderApplication(tester, f, '/split/$id');
        await _pumpUntil(tester, () => openingFinished && f.reader.interactive);
        await _readerAction(tester, f.reader.focusChrome);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        var queries = 0;
        f.onNativeCall = (call) async {
          if (call.method != 'hasFocus') return null;
          queries++;
          return queries == 1;
        };
        f.calls.clear();
        await _readerAction(
          tester,
          () => f.event('contentFocus', {'source': 'pointer'}),
        );
        await _pumpUntil(
          tester,
          () => f.calls.any((call) => call.method == 'focus'),
        );
        expect(queries, 2);
        expect(
          f.calls.singleWhere((call) => call.method == 'focus').arguments,
          {'session': f.reader.sessionId},
        );
        f.onNativeCall = null;
        f.calls.clear();
        await _readerAction(
          tester,
          () => f.event('contentFocus', {'source': 'focus'}),
        );
        expect(f.calls.where((call) => call.method == 'focus'), isEmpty);
        await _readerAction(tester, f.reader.focusChrome);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        queries = 0;
        f.onNativeCall = (call) async {
          if (call.method != 'hasFocus') return null;
          queries++;
          return queries == 1 ? true : pending.future;
        };
        f.calls.clear();
        await _readerAction(
          tester,
          () => f.event('contentFocus', {'source': 'pointer'}),
          settle: false,
        );
        await _pumpUntil(tester, () => queries == 2, settle: false);
        f.container
            .read(bookPresentationProvider.notifier)
            .focusPane(id, BookPane.notebook);
        await _readerAction(tester, f.reader.focusChrome, settle: false);
        pending.complete(false);
        await tester.pumpAndSettle();
        expect(f.calls.where((call) => call.method == 'focus'), isEmpty);
        expect(
          f.container.read(bookPresentationProvider).lastPane,
          BookPane.notebook,
        );
        expect(tester.takeException(), isNull);
      } finally {
        unawaited(openingEvents?.cancel());
        if (!pending.isCompleted) pending.complete(false);
        f.onNativeCall = null;
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'explicit Notebook cancels collapsed Split restoration and retains its draft and browsing state',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      late ReadingAnnotation annotation;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (store) => gate = AnnotationStoreGate(store),
        );
        annotation = ReadingAnnotation({
          'id': 'annotation-split-explicit-view',
          'bookId': f.state.bookId!,
          'annotationKind': 'highlight',
          'text': 'A retained passage.\n' * 80,
          'note': 'Saved baseline',
          'reference': 'Page 2',
          'anchor': {'page': 1},
          'color': 'yellow',
          'created': 1,
        });
        await f.container
            .read(workspaceControllerProvider.notifier)
            .saveAnnotation(annotation);
        f.notes.view(
          annotation.bookId,
          filter: AnnotationTypeFilter.highlights,
          sort: NotebookSort.bookOrder,
          withNotes: true,
          selected: annotation.id,
        );
      });
      try {
        final id = annotation.bookId;
        await _mountHeaderApplication(tester, f, '/split/$id');
        await _pumpUntil(
          tester,
          () =>
              f.reader.interactive &&
              f.container.read(bookPresentationProvider).splitAvailable,
        );
        final notebookScroll = tester
            .widget<CustomScrollView>(
              find.descendant(
                of: find.byType(NotebookContent),
                matching: find.byType(CustomScrollView),
              ),
            )
            .controller!;
        expect(notebookScroll.position.maxScrollExtent, greaterThan(120));
        notebookScroll.jumpTo(120);
        f.container
            .read(bookPresentationProvider.notifier)
            .setDividerRatio(id, .55);
        gate.fail = true;
        await _readerAction(tester, () async {
          f.notes.edit(annotation, 'Protected draft through explicit Notebook');
          try {
            await f.notes.save(annotation.id);
          } catch (_) {}
        });
        final draft = f.drafts.drafts[annotation.id]!;
        final session = f.reader.sessionId;
        final opens = f.calls.where((call) => call.method == 'open').length;
        tester.view.physicalSize = const Size(700, 850);
        await _pumpUntil(
          tester,
          () => !f.container.read(bookPresentationProvider).splitAvailable,
        );
        await _readerAction(
          tester,
          () => _appCommands(tester).execute(BusyBooksCommandIds.viewNotebook),
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/notebook/$id',
        );
        expect(f.reader.suspended, true);
        expect(f.state.surfaceVisible, false);
        expect(f.reader.sessionId, session);
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpAndSettle();
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/notebook/$id',
        );
        expect(f.reader.suspended, true);
        expect(f.state.bookId, id);
        expect(f.calls.where((call) => call.method == 'open').length, opens);
        expect(
          find.byType(ReadingContent, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byType(NotebookContent, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          tester
              .widget<CustomScrollView>(
                find.descendant(
                  of: find.byType(NotebookContent),
                  matching: find.byType(CustomScrollView),
                ),
              )
              .controller,
          same(notebookScroll),
        );
        expect(notebookScroll.offset, closeTo(120, .01));
        final view = f.drafts.view(id);
        expect(view.filter, AnnotationTypeFilter.highlights);
        expect(view.sort, NotebookSort.bookOrder);
        expect(view.withNotes, true);
        expect(view.selected, annotation.id);
        expect(f.drafts.drafts[annotation.id]!.text, draft.text);
        expect(f.drafts.drafts[annotation.id]!.revision, draft.revision);
        expect(f.container.read(bookPresentationProvider).dividerRatio, .55);
        expect(find.textContaining('Split temporarily shows'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        gate.fail = false;
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'a delayed collapsed-pane action cannot change the retained workspace behind a modal',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      final entered = Completer<void>(), proceed = Completer<void>();
      Future<void>? dialog;
      try {
        final id = f.state.bookId!;
        await _mountHeaderApplication(tester, f, '/split/$id');
        tester.view.physicalSize = const Size(700, 850);
        await _pumpUntil(
          tester,
          () => find.text('Show Notebook').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('Show Notebook'));
        await _pumpUntil(
          tester,
          () =>
              f.container.read(bookPresentationProvider).lastPane ==
                  BookPane.notebook &&
              !f.state.surfaceVisible,
        );
        f.onNativeCall = (call) async {
          if (call.method == 'dismissPopover' && !entered.isCompleted) {
            entered.complete();
            await proceed.future;
          }
          return null;
        };
        await tester.tap(find.text('Show Reading'));
        await _pumpUntil(tester, () => entered.isCompleted, settle: false);
        dialog = showBusyBooksModalDialog<void>(
          rootNavigatorKey.currentContext!,
          builder: (_) => const BusyBooksDialogShell(
            title: 'Retained modal',
            children: [Text('Another active surface')],
          ),
        );
        await tester.pumpAndSettle();
        final focusCalls = f.calls
            .where((call) => call.method == 'focus')
            .length;
        proceed.complete();
        await tester.pumpAndSettle();
        expect(
          f.container.read(bookPresentationProvider).lastPane,
          BookPane.notebook,
        );
        expect(
          f.calls.where((call) => call.method == 'focus').length,
          focusCalls,
        );
        expect(
          find.byType(BookWorkspaceScreen, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/split/$id',
        );
        rootNavigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        await dialog;
        dialog = null;
        expect(
          f.container.read(bookPresentationProvider).lastPane,
          BookPane.notebook,
        );
        expect(f.state.surfaceVisible, false);
        expect(tester.takeException(), isNull);
      } finally {
        if (!proceed.isCompleted) proceed.complete();
        f.onNativeCall = null;
        if (dialog != null) rootNavigatorKey.currentState?.pop();
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'collapsed Split keeps Notebook editing local and reveals an explicit passage after measured pane handoff',
    (tester) async {
      late _ReaderFixture f;
      late ReadingAnnotation annotation;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        annotation = ReadingAnnotation({
          'id': 'annotation-split-collapsed',
          'bookId': f.state.bookId!,
          'annotationKind': 'highlight',
          'text': 'Source beside the note',
          'note': 'Retained private text',
          'reference': 'Page 2',
          'anchor': {'page': 1},
          'color': 'yellow',
          'created': 1,
        });
        await f.container
            .read(workspaceControllerProvider.notifier)
            .saveAnnotation(annotation);
      });
      try {
        final id = annotation.bookId;
        await _mountHeaderApplication(tester, f, '/split/$id');
        await _pumpUntil(
          tester,
          () =>
              f.container.read(bookPresentationProvider).splitAvailable &&
              f.reader.interactive,
        );
        f.container
            .read(bookPresentationProvider.notifier)
            .setDividerRatio(id, .55);
        final opens = f.calls.where((call) => call.method == 'open').length;
        tester.view.physicalSize = const Size(700, 850);
        await _pumpUntil(
          tester,
          () => find.text('Show Notebook').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('Show Notebook'));
        await _pumpUntil(
          tester,
          () =>
              !f.state.surfaceVisible &&
              find
                  .byKey(ValueKey('notebook-select-${annotation.id}'))
                  .evaluate()
                  .isNotEmpty,
        );
        final jumps = f.dispatches
            .where((command) => command['action'] == 'goto')
            .length;
        await tester.tap(
          find.byKey(ValueKey('notebook-select-${annotation.id}')),
        );
        await tester.pumpAndSettle();
        final editor = find.descendant(
          of: find.byKey(ValueKey('notebook-note-${annotation.id}')),
          matching: find.byType(TextField),
        );
        expect(tester.widget<TextField>(editor).focusNode!.hasFocus, true);
        await tester.enterText(
          editor,
          'Collapsed edit survives the reader handoff',
        );
        await tester.pump();
        expect(
          f.dispatches.where((command) => command['action'] == 'goto').length,
          jumps,
        );
        expect(f.state.surfaceVisible, false);
        await _mainMenuSelect(
          tester,
          'Show in Reading',
          tooltip: 'Annotation Actions',
        );
        await _pumpUntil(
          tester,
          () =>
              f.state.surfaceVisible &&
              f.dispatches
                      .where((command) => command['action'] == 'goto')
                      .length ==
                  jumps + 1,
        );
        expect(
          f.dispatches
              .where((command) => command['action'] == 'goto')
              .last['anchor'],
          {'page': 1},
        );
        expect(
          f.container.read(bookPresentationProvider).lastPane,
          BookPane.reading,
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/split/$id',
        );
        expect(f.calls.where((call) => call.method == 'open').length, opens);
        tester.view.physicalSize = const Size(1200, 850);
        await _pumpUntil(
          tester,
          () =>
              f.container.read(bookPresentationProvider).splitAvailable &&
              find
                  .byKey(ValueKey('notebook-note-${annotation.id}'))
                  .evaluate()
                  .isNotEmpty,
        );
        expect(f.container.read(bookPresentationProvider).dividerRatio, .55);
        expect(
          tester.widget<TextField>(editor).controller!.text,
          'Collapsed edit survives the reader handoff',
        );
        expect(f.drafts.view(id).selected, annotation.id);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'Split deliberate Notebook selection reveals one passage without losing filters or editing focus',
    (tester) async {
      late _ReaderFixture f;
      late ReadingAnnotation annotation;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        annotation = ReadingAnnotation({
          'id': 'annotation-split-selection',
          'bookId': f.state.bookId!,
          'annotationKind': 'highlight',
          'text': 'Adjacent saved passage',
          'note': 'A private note',
          'reference': 'Page 2',
          'anchor': {'page': 1},
          'color': 'yellow',
          'created': 1,
        });
        await f.container
            .read(workspaceControllerProvider.notifier)
            .saveAnnotation(annotation);
        f.notes.view(
          annotation.bookId,
          filter: AnnotationTypeFilter.highlights,
          sort: NotebookSort.bookOrder,
          withNotes: true,
        );
      });
      try {
        final id = annotation.bookId;
        await _mountHeaderApplication(tester, f, '/split/$id');
        await _pumpUntil(
          tester,
          () =>
              f.reader.interactive &&
              find
                  .byKey(ValueKey('notebook-select-${annotation.id}'))
                  .evaluate()
                  .isNotEmpty,
        );
        final opens = f.calls.where((call) => call.method == 'open').length;
        final jumps = f.dispatches
            .where((command) => command['action'] == 'goto')
            .length;
        final focuses = f.dispatches
            .where((command) => command['action'] == 'focus')
            .length;
        await tester.tap(
          find.byKey(ValueKey('notebook-select-${annotation.id}')),
        );
        await _pumpUntil(
          tester,
          () =>
              f.dispatches
                  .where((command) => command['action'] == 'goto')
                  .length >
              jumps,
        );
        final editor = find.descendant(
          of: find.byKey(ValueKey('notebook-note-${annotation.id}')),
          matching: find.byType(TextField),
        );
        expect(editor, findsOneWidget);
        expect(tester.widget<TextField>(editor).focusNode!.hasFocus, true);
        expect(
          f.dispatches
              .where((command) => command['action'] == 'goto')
              .last['anchor'],
          {'page': 1},
        );
        expect(
          f.dispatches.where((command) => command['action'] == 'focus').length,
          focuses,
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/split/$id',
        );
        expect(f.drafts.view(id).filter, AnnotationTypeFilter.highlights);
        expect(f.drafts.view(id).sort, NotebookSort.bookOrder);
        expect(f.drafts.view(id).withNotes, true);
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'あ',
            selection: TextSelection.collapsed(offset: 1),
            composing: TextRange(start: 0, end: 1),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(tester.widget<TextField>(editor).focusNode!.hasFocus, true);
        expect(tester.widget<TextField>(editor).controller!.text, 'あ');
        await tester.enterText(editor, 'An unsaved Split edit');
        await tester.pump();
        f.notes.view(id, sort: NotebookSort.recentlyAdded);
        await tester.pump(const Duration(milliseconds: 800));
        await _pumpUntil(tester, () => f.drafts.drafts.isEmpty);
        expect(
          f.dispatches.where((command) => command['action'] == 'goto').length,
          jumps + 1,
        );
        expect(
          tester.widget<TextField>(editor).controller!.text,
          'An unsaved Split edit',
        );
        await _readerAction(
          tester,
          () => _appCommands(tester).execute(BusyBooksCommandIds.viewReading),
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/read/$id',
        );
        expect(f.calls.where((call) => call.method == 'open').length, opens);
        expect(f.drafts.view(id).selected, annotation.id);
        expect(f.drafts.view(id).filter, AnnotationTypeFilter.highlights);
        expect(f.drafts.view(id).withNotes, true);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  test(
    'a newer choice wins over retained-reader reconciliation and late results',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      try {
        await f.reader.setAppearance({
          'font': {'family': 'A'},
          'publisher': false,
        });
        final pending = Completer<Map>(), reconcile = Completer<Map>();
        f.onDispatch = (command) async {
          if (command['action'] != 'appearance' || command['request'] == null) {
            return;
          }
          final family = ((command['value'] as Map)['font'] as Map)['family'];
          if (family == 'B') {
            pending.complete(command);
          } else if (family == 'A') {
            reconcile.complete(command);
          } else {
            scheduleMicrotask(
              () =>
                  f.event('appearanceResult', {'request': command['request']}),
            );
          }
        };
        final b = f.reader.setAppearance({
          'font': {'family': 'B'},
        });
        await pending.future;
        await f.reader.show(false);
        await b;
        final showing = f.reader.show(true), old = await reconcile.future;
        await f.reader.setAppearance({
          'font': {'family': 'C'},
        });
        await showing;
        await f.event('appearanceResult', {
          'request': old['request'],
          'cancelled': true,
          'message': 'Late cancellation',
        });
        expect(f.reader.appearance['font'], {'family': 'C'});
        expect(
          (await f.store.call('book', f.state.bookId)
              as Map)['appearance']['font'],
          {'family': 'C'},
        );
        expect(f.state.warning, isNull);
      } finally {
        f.onDispatch = null;
        await f.dispose();
      }
    },
  );
  test(
    'failed retained reconciliation stays hidden and can retry without changing the book',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      try {
        final pending = Completer<Map>();
        f.onDispatch = (command) async {
          if (command['action'] == 'appearance' && command['request'] != null) {
            pending.complete(command);
          }
        };
        final change = f.reader.setAppearance({
          'font': {'family': 'B'},
          'publisher': false,
        });
        await pending.future;
        await f.reader.show(false);
        await change;
        f.onDispatch = (command) async {
          if (command['action'] == 'appearance' && command['request'] != null) {
            scheduleMicrotask(
              () => f.event('appearanceResult', {
                'request': command['request'],
                'message': 'Controlled rendering failure',
              }),
            );
          }
        };
        await f.reader.show(true);
        expect(
          f.calls.lastWhere((c) => c.method == 'visible').arguments,
          false,
        );
        expect(f.state.warning, isNotNull);
        expect(f.reader.appearance['font'], 'serif');
        f.onDispatch = null;
        await f.reader.show(true);
        expect(f.calls.lastWhere((c) => c.method == 'visible').arguments, true);
        expect(
          (await f.store.call('book', f.state.bookId) as Map)['appearance'],
          isNull,
        );
      } finally {
        f.onDispatch = null;
        await f.dispose();
      }
    },
  );
  test(
    'hide and return reconcile the committed appearance before revealing the retained reader',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      try {
        await f.reader.setAppearance({
          'font': {'family': 'A'},
          'publisher': false,
        });
        const anchor = {'cfi': 'epubcfi(/6/2!/4/8/1:6)', 'index': 0};
        await f.event('location', {'anchor': anchor, 'progress': .3});
        final entered = Completer<Map>(), returning = Completer<Map>();
        Object? displayed = {'family': 'A'};
        f.onDispatch = (command) async {
          if (command['action'] != 'appearance' || command['request'] == null) {
            return;
          }
          displayed = (command['value'] as Map)['font'];
          if ((displayed as Map)['family'] == 'B') {
            entered.complete(command);
          } else {
            returning.complete(command);
          }
        };
        final changing = f.reader.setAppearance({
          'font': {'family': 'B'},
        });
        final pending = await entered.future;
        await f.reader.show(false);
        await changing;
        expect(f.reader.appearance['font'], {'family': 'A'});
        final showing = f.reader.show(true);
        final reconcile = await returning.future;
        expect(
          f.calls.lastWhere((c) => c.method == 'visible').arguments,
          false,
        );
        expect(displayed, {'family': 'A'});
        await f.event('appearanceResult', {'request': reconcile['request']});
        await showing;
        await f.event('appearanceResult', {'request': pending['request']});
        expect(f.calls.lastWhere((c) => c.method == 'visible').arguments, true);
        expect(f.reader.appearance['font'], {'family': 'A'});
        expect(
          (await f.store.call('book', f.state.bookId)
              as Map)['appearance']['font'],
          {'family': 'A'},
        );
        expect(f.state.location['anchor'], anchor);
        expect(f.state.location['progress'], .3);
      } finally {
        f.onDispatch = null;
        await f.dispose();
      }
    },
  );
  test(
    'font work is cancelled by switching books, leaving Reading and closing the application',
    () async {
      for (final transition in ['book', 'hidden', 'close']) {
        final f = await _ReaderFixture.create('reflowable.epub');
        final entered = Completer<Map>();
        f.onDispatch = (command) async {
          if (command['action'] == 'appearance' &&
              command['request'] != null &&
              !entered.isCompleted) {
            entered.complete(command);
          }
        };
        try {
          final originalId = f.state.bookId;
          final update = f.reader.setAppearance({
            'font': {'family': 'Pending'},
            'publisher': false,
          });
          final old = await entered.future, oldSession = f.session;
          if (transition == 'book') {
            final workspace = await f.container
                .read(workspaceControllerProvider.notifier)
                .openPath(p.absolute('test/fixtures/text.pdf'));
            await f.reader.open(workspace.books.single.id);
          } else if (transition == 'hidden') {
            await f.reader.show(false);
          } else {
            await f.reader.close();
          }
          await update;
          await f.event('appearanceResult', {
            'session': oldSession,
            'request': old['request'],
          });
          expect(
            (await f.store.call('book', originalId) as Map)['appearance'],
            isNull,
          );
          expect(f.reader.appearance['font'], 'serif');
          if (transition == 'book') expect(f.state.bookId, isNot(originalId));
        } finally {
          f.onDispatch = null;
          await f.dispose();
        }
      }
    },
  );
  test(
    'appearance writes serialize and a failed save restores the committed renderer choice',
    () async {
      late AnnotationStoreGate gate;
      final f = await _ReaderFixture.create(
        'reflowable.epub',
        wrapStore: (store) => gate = AnnotationStoreGate(store),
      );
      try {
        gate.appearanceEntered = Completer<void>();
        gate.appearanceProceed = Completer<void>();
        final a = f.reader.setAppearance({
          'font': {'family': 'A'},
          'publisher': false,
        });
        await gate.appearanceEntered!.future;
        final b = f.reader.setAppearance({
          'font': {'family': 'B'},
          'publisher': false,
        });
        gate.appearanceProceed!.complete();
        await Future.wait([a, b]);
        expect(f.reader.appearance['font'], {'family': 'B'});
        gate.appearanceProceed = null;
        gate.failAppearance = true;
        await expectLater(
          f.reader.setAppearance({
            'font': {'family': 'C'},
            'publisher': false,
          }),
          throwsA(isA<FileSystemException>()),
        );
        expect(f.reader.appearance['font'], {'family': 'B'});
        final rendered = f.dispatches.lastWhere(
          (c) => c['action'] == 'appearance',
        );
        expect((rendered['value'] as Map)['font'], {'family': 'B'});
        expect(f.state.warning, isNotNull);
      } finally {
        gate.failAppearance = false;
        await f.dispose();
      }
    },
  );

  test(
    'typography capability is supplied by the renderer; loading, fixed and failed readers reject replacement',
    () async {
      final f = await _ReaderFixture.create(
        'reflowable.epub',
        initialize: false,
      );
      try {
        expect(f.reader.typographyCapabilities.fontFamily, false);
        await expectLater(
          f.reader.setAppearance({
            'font': {'family': 'Named'},
          }),
          throwsStateError,
        );
        await f.event('ready');
        await f.event('opened', {
          'typography': const TypographyCapabilities(fontFamily: true).toJson(),
        });
        await f.reader.show(true);
        expect(f.reader.typographyCapabilities.fontFamily, true);
        expect(f.reader.typographyCapabilities.textMetrics, false);
        await f.reader.setAppearance({
          'font': {'family': 'Named'},
        });
        expect(f.reader.appearance['font'], {'family': 'Named'});
        await expectLater(
          f.reader.setAppearance({'size': 24}),
          throwsStateError,
        );
        await f.event('metadata', {
          'typography': TypographyCapabilities.none.toJson(),
        });
        await expectLater(
          f.reader.setAppearance({'font': 'monospace'}),
          throwsStateError,
        );
        await f.event('error', {'message': 'Unavailable renderer'});
        expect(f.reader.typographyCapabilities.fontFamily, false);
        await expectLater(
          f.reader.setAppearance({'font': 'serif'}),
          throwsStateError,
        );
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'rapid font A→B→C persists only the newest revision and ignores older acknowledgements',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      final entered = Completer<Map>();
      f.onDispatch = (command) async {
        if (command['action'] != 'appearance' || command['request'] == null) {
          return;
        }
        if (!entered.isCompleted) {
          entered.complete(command);
        } else {
          scheduleMicrotask(
            () => f.event('appearanceResult', {'request': command['request']}),
          );
        }
      };
      try {
        final a = f.reader.setAppearance({
          'font': {'family': 'A'},
          'publisher': false,
        });
        final old = await entered.future;
        final b = f.reader.setAppearance({
          'font': {'family': 'B'},
          'publisher': false,
        });
        final c = f.reader.setAppearance({
          'font': {'family': 'C'},
          'publisher': false,
        });
        await Future.wait([a, b, c]);
        await f.event('appearanceResult', {'request': old['request']});
        expect(f.reader.appearance['font'], {'family': 'C'});
        final stored = await f.store.call('book', f.state.bookId) as Map;
        expect((stored['appearance'] as Map)['font'], {'family': 'C'});
        expect(f.reader.appearance['size'], 20);
        expect(
          f.acceptedDispatches
              .where((c) => c['action'] == 'appearance' && c['request'] != null)
              .length,
          2,
        );
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'reset during a font update wins, explicit defaults retain their captured revision, and publisher remembers the family',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      final entered = Completer<Map>();
      f.onDispatch = (command) async {
        if (command['action'] != 'appearance' || command['request'] == null) {
          return;
        }
        if (!entered.isCompleted) {
          entered.complete(command);
        } else {
          scheduleMicrotask(
            () => f.event('appearanceResult', {'request': command['request']}),
          );
        }
      };
      try {
        final a = f.reader.setAppearance({
          'font': {'family': 'A'},
          'publisher': false,
        });
        await entered.future;
        await f.reader.resetAppearance();
        await a;
        expect(f.reader.book!.data['appearance'], isNull);
        await f.reader.setAppearance({
          'font': {'family': 'B'},
          'publisher': false,
        });
        await f.reader.setAppearance({'publisher': true});
        expect(f.reader.appearance['font'], {'family': 'B'});
        await f.reader.setAppearance({}, defaults: true);
        expect(
          f.container.read(appSettingsControllerProvider).reading['font'],
          {'family': 'B'},
        );
        await f.reader.setAppearance({
          'font': {'family': 'C'},
          'publisher': false,
        });
        expect(
          f.container.read(appSettingsControllerProvider).reading['font'],
          {'family': 'B'},
        );
        await f.reader.resetAppearance();
        expect(f.reader.appearance['font'], {'family': 'B'});
        expect(f.reader.appearance['publisher'], true);
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'renderer failure leaves the saved choice intact and a retry is recoverable',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      var fail = true;
      f.onDispatch = (command) async {
        if (command['action'] == 'appearance' && command['request'] != null) {
          scheduleMicrotask(
            () => f.event('appearanceResult', {
              'request': command['request'],
              if (fail && (command['value'] as Map)['publisher'] == false)
                'message': 'Injected local-face failure',
            }),
          );
        }
      };
      try {
        await expectLater(
          f.reader.setAppearance({
            'font': {'family': 'A'},
            'publisher': false,
          }),
          throwsStateError,
        );
        expect(f.reader.book!.data['appearance'], isNull);
        expect(f.state.warning, isNotNull);
        fail = false;
        await f.reader.setAppearance({
          'font': {'family': 'A'},
          'publisher': false,
        });
        expect(f.reader.appearance['font'], {'family': 'A'});
      } finally {
        await f.dispose();
      }
    },
  );

  testWidgets(
    'selection search synchronizes the header without jumping or resetting IME input',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'reflowable.epub',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel(nativeMenuChannelName),
        (call) async {
          if (call.method == 'show') {
            final entries = _nativeLeaves(
              (call.arguments as Map)['entries'] as List,
            );
            return entries.indexWhere(
              (e) => e['label'] == 'Search in This Book',
            );
          }
          return null;
        },
      );
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        await _readerAction(
          tester,
          () => f.searchController.open(category: BookSearchCategory.bookText),
        );
        for (final term in [
          'word',
          'Über den Wolken — 東京',
          'footnote déjà vu',
        ]) {
          await _readerAction(tester, () async {
            await f.event('selection', {
              'anchor': {'cfi': 'epubcfi(/6/2!/4/2:0)'},
              'text': '  $term  ',
              'settled': true,
              if (term.startsWith('footnote')) 'note': true,
            });
            // Native focus and a footnote closing can collapse the live range.
            await f.event('selection', {'anchor': null, 'text': ''});
          });
          await _pumpUntil(tester, () => f.state.query == '  $term  ');
          final field = find.descendant(
            of: find.byKey(const ValueKey('book-header-search')),
            matching: find.byType(TextField),
          );
          expect(tester.widget<TextField>(field).controller!.text, '  $term  ');
          expect(f.state.query, '  $term  ');
          expect(f.search.active, isTrue);
          expect((f.sidebar.open || f.search.active), isTrue);
          expect(f.sidebar.panel, BookSidebarPanel.outline);
          expect(f.state.currentMatch, -1);
          expect(f.dispatches.where((d) => d['action'] == 'goto'), isEmpty);
          expect(
            f.dispatches.lastWhere((d) => d['action'] == 'search')['query'],
            '  $term  ',
          );
        }
        final field = find.descendant(
          of: find.byKey(const ValueKey('book-header-search')),
          matching: find.byType(TextField),
        );
        await tester.showKeyboard(field);
        const value = TextEditingValue(
          text: 'Komposition 東京',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange(start: 0, end: 11),
        );
        tester.testTextInput.updateEditingValue(value);
        await tester.pump();
        await _readerAction(
          tester,
          () => f.event('navigation', {'back': true}),
        );
        expect(tester.widget<TextField>(field).controller!.value, value);
        expect(f.state.query, value.text);
      } finally {
        messenger.setMockMethodCallHandler(
          const MethodChannel(nativeMenuChannelName),
          null,
        );
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  for (final fixture in ['reflowable.epub', 'text.pdf']) {
    test(
      'selection search $fixture repeats without navigation and retains revisions and return commands',
      () async {
        final f = await _ReaderFixture.create(fixture);
        try {
          await f.openSelectionPopover();
          await f.action('searchSelection');
          await _until(() => f.dispatches.any((d) => d['action'] == 'search'));
          final old = f.dispatches.lastWhere(
            (d) => d['action'] == 'search',
          )['queryId'];
          await f.event('match', {
            'queryId': old,
            'anchor': {'page': 1},
            'excerpt': 'ABC',
          });
          await f.event('searchDone', {'queryId': old});
          await f.openSelectionPopover();
          await f.action('searchSelection');
          await _until(
            () =>
                f.dispatches.lastWhere(
                  (d) => d['action'] == 'search',
                )['queryId'] !=
                old,
          );
          final next = f.dispatches.lastWhere(
            (d) => d['action'] == 'search',
          )['queryId'];
          expect(next, greaterThan(old as int));
          expect(f.search.active, isTrue);
          expect(f.state.matches, isEmpty);
          expect(f.dispatches.where((d) => d['action'] == 'goto'), isEmpty);
          await f.event('match', {
            'queryId': old,
            'anchor': {'page': 3},
            'excerpt': 'obsolete',
          });
          expect(f.state.matches, isEmpty);
          final anchor = fixture.endsWith('pdf')
              ? {'page': 1}
              : {'cfi': 'result'};
          await f.event('match', {
            'queryId': next,
            'anchor': anchor,
            'excerpt': 'ABC',
          });
          await f.event('searchDone', {'queryId': next});
          await f.reader.selectMatch(0);
          expect(f.dispatches.last['anchor'], anchor);
          await f.reader.send('back');
          expect(f.dispatches.last['action'], 'back');
          await f.reader.send('forward');
          expect(f.dispatches.last['action'], 'forward');
          await f.reader.cancelSearch();
          await f.event('match', {
            'queryId': next,
            'anchor': anchor,
            'excerpt': 'cancelled',
          });
          expect(f.state.matches, hasLength(1));
          expect(f.state.searchStatus, 'cancelled');
        } finally {
          await f.dispose();
        }
      },
    );
  }

  testWidgets(
    'dictionary selection and Main Menu share consent and the complete captured term',
    (tester) async {
      final service = _ControlledDictionary();
      late _ReaderFixture f;
      final launched = <String>[];
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(launcher, (call) async {
            launched.add((call.arguments as Map)['url'] as String);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(launcher, null),
      );
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          dictionary: service,
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Completer<int?>? choice;
      Map? selectionMenu;
      messenger.setMockMethodCallHandler(
        const MethodChannel(nativeMenuChannelName),
        (call) async {
          if (call.method == 'show') {
            selectionMenu = call.arguments as Map;
            choice = Completer<int?>();
            return choice!.future;
          }
          if (call.method == 'dismiss' && choice?.isCompleted == false) {
            choice!.complete(null);
          }
          return null;
        },
      );
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        await _readerAction(
          tester,
          () => f.searchController.open(category: BookSearchCategory.bookText),
        );
        for (final selectionAction in [true, false]) {
          selectionMenu = null;
          await _readerAction(
            tester,
            () => f.event('selection', {
              'anchor': {'page': 0, 'textOffset': 0, 'textLength': 9},
              'text': '  ice cream  ',
              'settled': true,
            }),
          );
          await _pumpUntil(tester, () => selectionMenu != null);
          expect(service.terms, hasLength(selectionAction ? 0 : 1));
          if (selectionAction) {
            final entries = _nativeLeaves(selectionMenu!['entries'] as List);
            choice!.complete(
              entries.indexWhere((e) => e['label'] == 'Look Up'),
            );
          } else {
            unawaited(
              _appCommands(tester).execute(BusyBooksCommandIds.dictionary),
            );
          }
          await _pumpUntil(
            tester,
            () => find
                .widgetWithText(ElevatedButton, 'Look Up')
                .evaluate()
                .isNotEmpty,
          );
          expect(service.terms, hasLength(selectionAction ? 0 : 1));
          await tester.tap(find.widgetWithText(ElevatedButton, 'Look Up'));
          await _pumpUntil(
            tester,
            () => service.terms.length == (selectionAction ? 1 : 2),
          );
          expect(f.popup['kind'], 'lookup');
          expect(f.popup['lookupTerm'], 'ice cream');
          final index = service.terms.length - 1;
          service.complete(index);
          await _pumpUntil(
            tester,
            () => _lookupUpdates(f).last['lookup']['status'] == 'ready',
          );
          expect(launched, hasLength(index));
          await _readerAction(tester, () => f.action('lookupFullEntry'));
          await _pumpUntil(tester, () => launched.length == index + 1);
          expect(Uri.parse(launched.last).pathSegments, ['wiki', 'ice cream']);
          await _readerAction(
            tester,
            () => selectionAction
                ? f.event('popoverHidden', {
                    'presentation': f.popup['presentation'],
                    'keyboard': true,
                  })
                : f.reader.dismissPopover(),
          );
          await _pumpUntil(
            tester,
            () =>
                FocusManager.instance.primaryFocus
                    is BusyBooksPublicationFocusNode,
          );
          expect(
            FocusManager.instance.primaryFocus,
            isA<BusyBooksPublicationFocusNode>(),
          );
        }
        expect(service.terms, ['ice cream', 'ice cream']);
        expect(f.dispatches.where((d) => d['action'] == 'goto'), isEmpty);
      } finally {
        if (choice?.isCompleted == false) choice!.complete(null);
        messenger.setMockMethodCallHandler(
          const MethodChannel(nativeMenuChannelName),
          null,
        );
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  test(
    'dictionary reverse completion only updates the newest lookup and full entry',
    () async {
      final service = _ControlledDictionary();
      final f = await _ReaderFixture.create('text.pdf', dictionary: service);
      final events = <Map>[];
      final subscription = f.reader.events.stream.listen(events.add);
      try {
        await _startLookup(f, 'first phrase');
        await _until(() => service.terms.length == 1);
        await _startLookup(f, 'café au lait');
        await _until(() => service.terms.length == 2);
        expect(service.cancelled, contains(0));
        service.complete(1);
        await _until(
          () => _lookupUpdates(f).last['lookup']['status'] == 'ready',
        );
        final count = _lookupUpdates(f).length;
        service.complete(0);
        await Future<void>.delayed(Duration.zero);
        expect(_lookupUpdates(f), hasLength(count));
        expect(_lookupUpdates(f).last['lookupTerm'], 'café au lait');
        await f.action('lookupFullEntry');
        await Future<void>.delayed(Duration.zero);
        final entry = events.singleWhere((e) => e['type'] == 'dictionaryEntry');
        expect(
          Uri.parse(entry['url'] as String).pathSegments.last,
          'café au lait',
        );
      } finally {
        await subscription.cancel();
        await f.dispose();
      }
    },
  );

  for (final transition in [
    'dismiss',
    'outside dismissal',
    'Notebook',
    'book switch',
    'different popover',
  ]) {
    test(
      'dictionary $transition invalidates pending replies without reopening or focusing',
      () async {
        final service = _ControlledDictionary();
        final f = await _ReaderFixture.create('text.pdf', dictionary: service);
        try {
          await _startLookup(f, 'ice cream');
          await _until(() => service.terms.isNotEmpty);
          switch (transition) {
            case 'dismiss':
              await f.reader.dismissPopover();
            case 'outside dismissal':
              await f.event('popoverHidden', {
                'presentation': f.popup['presentation'],
              });
            case 'Notebook':
              await f.reader.suspend();
            case 'book switch':
              final next = await f.container
                  .read(workspaceControllerProvider.notifier)
                  .openPath(p.absolute('test/fixtures/mixed-pages.pdf'));
              await f.reader.open(next.books.single.id);
            case 'different popover':
              await f.reader.showPopover('speech');
          }
          final calls = f.calls.length;
          service.complete(0);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            f.calls
                .skip(calls)
                .where(
                  (c) => [
                    'popover',
                    'popoverResult',
                    'focus',
                    'dismissPopover',
                  ].contains(c.method),
                ),
            isEmpty,
          );
          expect(service.cancelled, contains(0));
        } finally {
          await f.dispose();
        }
      },
    );
  }

  test(
    'dictionary retry handles each failure with the same term and no navigation',
    () async {
      final service = _ControlledDictionary();
      final f = await _ReaderFixture.create('text.pdf', dictionary: service);
      try {
        await _startLookup(f, 'café au lait');
        for (final status in [
          DictionaryStatus.missing,
          DictionaryStatus.offline,
          DictionaryStatus.timeout,
          DictionaryStatus.invalid,
          DictionaryStatus.unavailable,
          DictionaryStatus.ready,
        ]) {
          await _until(
            () =>
                service.pending.isNotEmpty && !service.pending.last.isCompleted,
          );
          service.complete(service.pending.length - 1, status: status);
          await _until(
            () => _lookupUpdates(f).last['lookup']['status'] == status.name,
          );
          if (status != DictionaryStatus.ready) await f.action('lookupRetry');
        }
        expect(service.terms.toSet(), {'café au lait'});
        expect(f.dispatches.where((d) => d['action'] == 'goto'), isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );

  for (final kind in ['selection', 'speech', 'goto']) {
    test(
      'native $kind dismissal releases current ownership and rejects stale hidden events',
      () async {
        final f = await _ReaderFixture.create('text.pdf');
        final events = <Map>[];
        final subscription = f.reader.events.stream.listen(events.add);
        try {
          await f.openSelectionPopover();
          if (kind != 'selection') await f.reader.showPopover(kind);
          final owner = f.popup['presentation'];
          f.calls.clear();
          await f.event('popoverHidden', {
            'presentation': owner - 1,
            'keyboard': true,
          });
          expect(f.calls.where((c) => c.method == 'capturePopover'), isEmpty);
          await f.event('key', {'key': 'F9'});
          expect(events.where((e) => e['type'] == 'key'), isEmpty);
          await f.event('popoverHidden', {
            'presentation': owner,
            'keyboard': true,
          });
          final capture = f.calls.singleWhere(
            (c) => c.method == 'capturePopover',
          );
          expect((capture.arguments as Map)['seal'], true);
          expect((capture.arguments as Map)['presentation'], owner);
          final dismiss = f.calls.singleWhere(
            (c) => c.method == 'dismissPopover',
          );
          expect((dismiss.arguments as Map)['restoreFocus'], true);
          expect(f.calls.indexOf(capture), lessThan(f.calls.indexOf(dismiss)));
          await f.event('key', {'key': 'F9'});
          await _until(() => events.any((e) => e['type'] == 'key'));
          expect(events.where((e) => e['type'] == 'key').single['key'], 'F9');
          expect(f.state.selection?['text'], 'ABC');
          expect(f.dispatches.where((d) => d['action'] == 'goto'), isEmpty);
          await f.reader.showPopover('speech');
          f.calls.clear();
          await f.event('popoverHidden', {
            'presentation': owner,
            'keyboard': true,
          });
          expect(f.calls.where((c) => c.method == 'capturePopover'), isEmpty);
          await f.event('key', {'key': 'F9'});
          expect(events.where((e) => e['type'] == 'key'), hasLength(1));
        } finally {
          await subscription.cancel();
          await f.dispose();
        }
      },
    );
  }

  test(
    'native hidden capture failure retains protected creation until a sealed retry',
    () async {
      late AnnotationStoreGate gate;
      final f = await _ReaderFixture.create(
        'text.pdf',
        wrapStore: (store) => gate = AnnotationStoreGate(store),
      );
      final events = <Map>[];
      final subscription = f.reader.events.stream.listen(events.add);
      try {
        gate.failPut = true;
        await f.openSelectionPopover();
        final anchor = jsonEncode(f.state.selection!['anchor']);
        await f.action('noteDraft', {
          'note': 'Already protected failed creation',
        });
        await _until(() => f.drafts.drafts.values.any((d) => d.error != null));
        final id = f.drafts.drafts.keys.single;
        final presentation = f.popup['presentation'];
        f.onNativeCall = (call) async {
          if (call.method == 'capturePopover') {
            throw PlatformException(code: 'capture-failed');
          }
          return null;
        };
        f.calls.clear();
        await f.event('popoverHidden', {
          'presentation': presentation,
          'keyboard': true,
        });
        await _until(() => f.state.warning?.contains('capture-failed') == true);
        expect(f.calls.where((c) => c.method == 'dismissPopover'), isEmpty);
        expect(f.drafts.drafts[id]!.text, 'Already protected failed creation');
        await f.event('key', {'key': 'F9'});
        expect(events.where((e) => e['type'] == 'key'), isEmpty);
        f.onNativeCall = (call) async {
          if (call.method == 'capturePopover') {
            return {
              ...call.arguments as Map,
              'revision': 4,
              'note': 'Latest local text after native delivery failed',
              'color': 'yellow',
            };
          }
          return null;
        };
        await f.reader.dismissPopover(restoreFocus: false);
        expect(f.drafts.drafts.keys, [id]);
        expect(
          f.drafts.drafts[id]!.text,
          'Latest local text after native delivery failed',
        );
        expect(jsonEncode(f.drafts.sources[id]!.anchor), anchor);
        expect(
          (f.calls.lastWhere((c) => c.method == 'dismissPopover').arguments
              as Map)['restoreFocus'],
          false,
        );
        gate.failPut = false;
        await f.notes.flush();
        final saved =
            (await f.store.call('annotations', f.state.bookId) as List).single
                as Map;
        expect(saved['id'], id);
        expect(saved['note'], 'Latest local text after native delivery failed');
        expect(jsonEncode(saved['anchor']), anchor);
      } finally {
        gate.failPut = false;
        f.onNativeCall = null;
        await subscription.cancel();
        await f.dispose();
      }
    },
  );

  test(
    'native keyboard dismissal cannot restore reader focus over a later Notebook handoff',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      final entered = Completer<void>(), release = Completer<void>();
      final events = <Map>[];
      final subscription = f.reader.events.stream.listen(events.add);
      Future<void>? hidden;
      try {
        await f.openSelectionPopover();
        final presentation = f.popup['presentation'];
        f.onNativeCall = (call) async {
          if (call.method == 'capturePopover') {
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          return null;
        };
        f.calls.clear();
        hidden = f.event('popoverHidden', {
          'presentation': presentation,
          'keyboard': true,
        });
        await entered.future.timeout(const Duration(seconds: 5));
        f.container.read(bookPresentationProvider.notifier)
          ..enterBook(f.state.bookId!, BookView.split)
          ..focusPane(f.state.bookId!, BookPane.notebook);
        await f.reader.focusChrome();
        f.nativeFocused = false;
        release.complete();
        await hidden;
        final dismiss = f.calls.singleWhere(
          (c) => c.method == 'dismissPopover',
        );
        expect((dismiss.arguments as Map)['restoreFocus'], false);
        expect(events.where((e) => e['type'] == 'focusBook'), isEmpty);
        expect(
          f.container.read(bookPresentationProvider).lastPane,
          BookPane.notebook,
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await hidden;
        f.onNativeCall = null;
        await subscription.cancel();
        await f.dispose();
      }
    },
  );

  for (final action in ['search', 'lookup']) {
    test(
      'selection $action handoff preserves a failed note draft and refuses failed capture',
      () async {
        late AnnotationStoreGate gate;
        final f = await _ReaderFixture.create(
          'text.pdf',
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        try {
          gate.failPut = true;
          await f.openSelectionPopover();
          await f.action('noteDraft', {'note': 'Keep this failed draft'});
          await _until(
            () => f.drafts.drafts.values.any((d) => d.error != null),
          );
          if (action == 'search') {
            await f.reader.searchSelection();
          } else {
            expect(await f.reader.prepareLookup(), isNotNull);
          }
          expect(f.drafts.drafts.values.single.text, 'Keep this failed draft');
          await f.openSelectionPopover();
          f.onNativeCall = (call) async {
            if (call.method == 'capturePopover') {
              throw PlatformException(code: 'capture-failed');
            }
            return null;
          };
          final visible = f.search.active;
          await expectLater(
            action == 'search'
                ? f.reader.searchSelection()
                : f.reader.prepareLookup(),
            throwsA(anything),
          );
          expect(f.search.active, visible);
          expect(f.drafts.drafts.values.single.text, 'Keep this failed draft');
          f.onNativeCall = null;
          gate.failPut = false;
          await f.notes.flush();
        } finally {
          gate.failPut = false;
          f.onNativeCall = null;
          await f.dispose();
        }
      },
    );
  }

  testWidgets(
    'lookup presentation retry resumes the original term after native failure',
    (tester) async {
      final service = _ControlledDictionary();
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf', dictionary: service);
      });
      try {
        await _readerAction(tester, () async {
          await f.openSelectionPopover();
          final target = await f.reader.prepareLookup();
          f.onNativeCall = (call) async {
            if (call.method == 'popover') {
              await f.event('popoverHidden', {
                'presentation': (call.arguments as Map)['presentation'],
              });
              throw PlatformException(code: 'popover-timeout');
            }
            return null;
          };
          await f.reader.lookup(target!);
        });
        expect(f.state.popoverError, isNotNull);
        expect(service.terms, isEmpty);
        f.onNativeCall = null;
        await _readerAction(tester, f.reader.retryPopover);
        await _pumpUntil(tester, () => service.terms.isNotEmpty);
        expect(service.terms, ['ABC']);
        service.complete(0);
        await _pumpUntil(
          tester,
          () => _lookupUpdates(f).last['lookup']['status'] == 'ready',
        );
      } finally {
        f.onNativeCall = null;
        await _readerAction(tester, f.dispose);
      }
    },
  );

  test(
    'no-text selections and cancelled lookup presentations never send requests',
    () async {
      final service = _ControlledDictionary();
      final f = await _ReaderFixture.create(
        'image-only.pdf',
        dictionary: service,
      );
      try {
        await f.reader.searchSelection();
        expect(f.search.active, isFalse);
        expect(await f.reader.prepareLookup(), isNull);
        expect(service.terms, isEmpty);
        await f.openSelectionPopover();
        final target = await f.reader.prepareLookup();
        f.onNativeCall = (call) async {
          if (call.method == 'popover') {
            throw PlatformException(code: 'popover-cancelled');
          }
          return null;
        };
        await f.reader.lookup(target!);
        expect(service.terms, isEmpty);
        f.onNativeCall = null;
      } finally {
        f.onNativeCall = null;
        await f.dispose();
      }
    },
  );

  testWidgets(
    'appearance header and command use checked primary native menus and reject a closed owner',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.event('metadata', {'fixed': true});
      });
      List<Map>? rows;
      Map? payload;
      Completer<int?>? delayed;
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(nativeMenuChannelName),
              (call) async {
                if (call.method == 'dismiss') return true;
                if (call.method != 'show') return null;
                payload = call.arguments as Map;
                rows = _nativeLeaves(payload!['entries'] as List);
                return delayed?.future ??
                    rows!.indexWhere((e) => e['label'] == 'Sepia');
              },
            );
        f.calls.clear();
        await tester.tap(_headerButton('View Options'));
        await _pumpUntil(tester, () => rows != null);
        await _pumpUntil(tester, () => f.reader.appearance['color'] == 'sepia');
        expect(
          rows!.singleWhere((row) => row['label'] == 'Fit width')['selected'],
          true,
        );
        expect(
          rows!.singleWhere((row) => row['label'] == 'Rotation')['children'],
          isNotEmpty,
        );
        expect((payload!['anchor'] as Map)['width'], greaterThan(1));
        expect(f.calls.where((call) => call.method == 'popover'), isEmpty);
        rows = null;
        delayed = Completer<int?>();
        var done = false;
        final opening = _appCommands(
          tester,
        ).execute(BusyBooksCommandIds.appearance).then((_) => done = true);
        await _pumpUntil(tester, () => rows != null);
        expect(
          rows!.singleWhere((row) => row['label'] == 'Sepia')['selected'],
          true,
        );
        await _readerAction(tester, () => f.reader.show(false));
        delayed.complete(rows!.indexWhere((row) => row['label'] == 'Dark'));
        await _pumpUntil(tester, () => done);
        await opening;
        expect(f.reader.appearance['color'], 'sepia');
      } finally {
        if (delayed != null && !delayed.isCompleted) delayed.complete();
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'closed appearance menu releases publication input while a preference write is pending',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (store) => gate = AnnotationStoreGate(store),
        );
        await f.event('metadata', {'fixed': true});
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        gate.appearanceEntered = Completer<void>();
        gate.appearanceProceed = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(nativeMenuChannelName),
              (call) async {
                if (call.method != 'show') return null;
                final entries = _nativeLeaves(
                  (call.arguments as Map)['entries'] as List,
                );
                return entries.indexWhere((entry) => entry['label'] == 'Sepia');
              },
            );
        await tester.tap(_headerButton('View Options'));
        await _pumpUntil(tester, () => gate.appearanceEntered!.isCompleted);
        final request = {
          'session': f.reader.sessionId,
          'presentation': f.reader.presentationId,
          'focusRevision': f.reader.focusRevision,
        };
        expect(f.reader.ownsContentFocus(request), true);
        f.calls.clear();
        await _readerAction(tester, () => f.reader.send('focus'));
        expect(f.calls.where((call) => call.method == 'focus'), hasLength(1));
        gate.appearanceProceed!.complete();
        await _pumpUntil(tester, () => f.reader.appearance['color'] == 'sepia');
      } finally {
        if (gate.appearanceProceed != null &&
            !gate.appearanceProceed!.isCompleted) {
          gate.appearanceProceed!.complete();
        }
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  test(
    'appearance menu seals draft ownership and closes with route and geometry changes',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      var dismissed = 0;
      Future<void> dismiss() async {
        dismissed++;
      }

      try {
        await f.openSelectionPopover();
        f.calls.clear();
        final owner = await f.reader.prepareAppearanceMenu(dismiss: dismiss);
        expect(owner, isNotNull);
        expect(f.reader.ownsAppearanceMenu(owner!), true);
        final capture = f.calls.singleWhere(
          (c) => c.method == 'capturePopover',
        );
        final hide = f.calls.singleWhere((c) => c.method == 'dismissPopover');
        expect((capture.arguments as Map)['seal'], true);
        expect(f.calls.indexOf(capture), lessThan(f.calls.indexOf(hide)));
        await f.reader.show(false);
        expect(dismissed, 1);
        expect(f.reader.ownsAppearanceMenu(owner), false);
        await f.reader.show(true);
        final resized = await f.reader.prepareAppearanceMenu(dismiss: dismiss);
        expect(resized, isNotNull);
        await f.reader.updateViewport(
          const Rect.fromLTWH(0, 0, 720, 500),
          bookId: f.state.bookId!,
        );
        expect(dismissed, 2);
        expect(f.reader.ownsAppearanceMenu(resized!), false);
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'appearance menu excludes queued publication focus and shortcut input until dismissal',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      final events = <Map>[];
      final subscription = f.reader.events.stream.listen(events.add);
      try {
        final owner = await f.reader.prepareAppearanceMenu(
          dismiss: () async {},
        );
        expect(owner, isNotNull);
        f.calls.clear();
        final request = {
          'session': f.reader.sessionId,
          'presentation': f.reader.presentationId,
          'focusRevision': f.reader.focusRevision,
        };
        expect(f.reader.ownsFocusRequest(request), false);
        expect(f.reader.ownsContentFocus(request), false);
        await f.reader.focusPublication(isCurrent: () => true);
        await f.reader.send('focus');
        await f.reader.focusChrome();
        await f.event('key', {'key': 'F9'});
        expect(
          f.calls.where(
            (call) => call.method == 'focus' || call.method == 'focusChrome',
          ),
          isEmpty,
        );
        expect(
          f.dispatches.where((command) => command['action'] == 'focus'),
          isEmpty,
        );
        expect(events.where((event) => event['type'] == 'key'), isEmpty);
        f.reader.finishAppearanceMenu(owner!);
        await f.event('key', {'key': 'F9'});
        await _until(() => events.any((event) => event['type'] == 'key'));
        expect(events.where((event) => event['type'] == 'key'), hasLength(1));
      } finally {
        await subscription.cancel();
        await f.dispose();
      }
    },
  );

  test(
    'appearance menu refuses failed draft handoff and never dismisses its editor',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      var dismissed = false;
      try {
        await f.openSelectionPopover();
        final presentation = f.reader.presentationId;
        f.calls.clear();
        f.onNativeCall = (call) async {
          if (call.method == 'capturePopover') {
            throw PlatformException(code: 'capture-failed');
          }
          return null;
        };
        await expectLater(
          f.reader.prepareAppearanceMenu(
            dismiss: () async {
              dismissed = true;
            },
          ),
          throwsException,
        );
        expect(dismissed, false);
        expect(f.reader.presentationId, presentation);
        expect(f.calls.where((c) => c.method == 'dismissPopover'), isEmpty);
      } finally {
        f.onNativeCall = null;
        await f.dispose();
      }
    },
  );

  test(
    'current page no-text status clears on text pages and never disables document search',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        await f.event('location', {
          'anchor': {'page': 0},
          'noText': true,
        });
        expect(f.reader.currentPageHasNoText, true);
        f.reader.search('library');
        await _until(() => f.dispatches.any((c) => c['action'] == 'search'));
        await f.event('location', {
          'anchor': {'page': 1},
          'noText': false,
        });
        expect(f.reader.currentPageHasNoText, false);
        await f.event('location', {
          'anchor': {'page': 2},
        });
        expect(f.reader.currentPageHasNoText, false);
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'lookup consent target cannot act after replacement or leaving Reading',
    () async {
      final service = _ControlledDictionary();
      final f = await _ReaderFixture.create('text.pdf', dictionary: service);
      try {
        await f.openSelectionPopover();
        final target = await f.reader.prepareLookup();
        await f.reader.showPopover('speech');
        await f.reader.lookup(target!);
        expect(f.popup['kind'], 'speech');
        await f.openSelectionPopover();
        final leaving = await f.reader.prepareLookup();
        await f.reader.suspend();
        await f.reader.lookup(leaving!);
        expect(service.terms, isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );

  testWidgets(
    'view modes stale fallback selection cannot switch a replacement book',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      final delayed = Completer<int?>();
      List<Map>? menu;
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        await _readerAction(
          tester,
          () => f.searchController.open(category: BookSearchCategory.bookText),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(nativeMenuChannelName),
              (call) async {
                if (call.method == 'show') {
                  menu = _nativeLeaves(
                    (call.arguments as Map)['entries'] as List,
                  );
                  return delayed.future;
                }
                return null;
              },
            );
        await tester.tap(find.byTooltip('Main Menu'));
        await _pumpUntil(tester, () => menu != null);
        late String replacement;
        await _readerAction(tester, () async {
          replacement =
              (await f.container
                      .read(workspaceControllerProvider.notifier)
                      .openPath(p.absolute('test/fixtures/mixed-pages.pdf')))
                  .books
                  .single
                  .id;
          f.container.read(appRouterProvider).go('/read/$replacement');
        }, settle: false);
        await _pumpUntil(
          tester,
          () => f.calls.where((c) => c.method == 'open').length == 2,
          settle: false,
        );
        await _readerAction(tester, f.finishColdOpen);
        delayed.complete(menu!.indexWhere((e) => e['label'] == 'Notebook'));
        await tester.pumpAndSettle();
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/read/$replacement',
        );
        expect(find.byType(NotebookContent), findsNothing);
        expect(f.state.ready, true);
      } finally {
        if (!delayed.isCompleted) delayed.complete();
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'view modes missing original keeps Notebook fallback, protected draft and Settings return',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      late String id;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          ownedOriginal: true,
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
        });
        await f.reader.annotation('bookmark', note: 'Saved A');
        final annotation = f.reader.annotations.single;
        id = annotation.bookId;
        final path = f.reader.book!.path;
        await f.reader.close();
        await File(path).delete();
        f.notes.edit(annotation, 'Protected missing original');
        gate.fail = true;
        try {
          await f.notes.save(annotation.id);
        } catch (_) {}
        await f.container
            .read(bookSearchSessionProvider.notifier)
            .open(category: BookSearchCategory.notebook);
      });
      try {
        final opens = f.calls.where((c) => c.method == 'open').length;
        await _mountHeaderApplication(tester, f, '/notebook/$id');
        await _mainMenuSelect(tester, 'Notebook');
        await tester.pumpAndSettle();
        expect(
          f.drafts.drafts.values.single.text,
          'Protected missing original',
        );
        await _mainMenuSelect(tester, 'Settings');
        await _pumpUntil(
          tester,
          () =>
              f.container
                  .read(appRouterProvider)
                  .routeInformationProvider
                  .value
                  .uri
                  .path ==
              '/settings',
        );
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/notebook/$id',
        );
        expect(f.search.active, false);
        expect(find.byType(BookViewSelector), findsOneWidget);
        final menus = <List<Map>>[];
        await _mainMenuSelect(tester, null, snapshots: menus, tooltip: 'View');
        expect(
          menus.single.singleWhere((e) => e['label'] == 'Notebook')['selected'],
          true,
        );
        expect(
          f.drafts.drafts.values.single.text,
          'Protected missing original',
        );
        expect(f.calls.where((c) => c.method == 'open').length, opens);
        gate.fail = false;
        await _readerAction(tester, () async {
          await f.notes.flush();
          expect(
            (await f.store.call('annotations', id) as List).single['note'],
            'Protected missing original',
          );
        });
      } finally {
        gate.fail = false;
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'view modes fallback follows the same live header visibility through resize and search',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
        });
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        Future<void> check(bool visible, String active) async {
          expect(
            find.byType(BookViewSelector),
            visible ? findsOneWidget : findsNothing,
          );
          final menus = <List<Map>>[];
          await _mainMenuSelect(tester, null, snapshots: menus);
          final modes = menus.single
              .where(
                (e) =>
                    ['Reading', 'Notebook'].contains(e['label']) ||
                    (e['label'] as String).startsWith('Split'),
              )
              .toList();
          final groups = menus.single
              .where((e) => e['label'] == 'View')
              .toList();
          if (visible) {
            expect(modes, isEmpty);
            expect(groups, isEmpty);
          } else {
            expect(groups.length, 1);
            final children = groups.single['children'] as List;
            expect(children, hasLength(3));
            expect(children.take(2).map((e) => e['label']), [
              'Reading',
              'Notebook',
            ]);
            expect(children.last['label'], startsWith('Split'));
            for (final (index, item) in children.indexed) {
              final command =
                  _appCommands(tester)[[
                    BusyBooksCommandIds.viewReading,
                    BusyBooksCommandIds.viewNotebook,
                    BusyBooksCommandIds.viewSplit,
                  ][index]]!;
              expect(
                item['icon'],
                [
                  'view-paged-symbolic',
                  'document-edit-symbolic',
                  'sidebar-show-right-symbolic',
                ][index],
              );
              expect(item['selected'], item['label'] == active);
              expect(item['mutuallyExclusive'], true);
              expect(item['enabled'], command.canExecute);
              expect(item['shortcut'], command.shortcut?.label);
              expect(item['gtkAccelerator'], command.shortcut?.gtkAccelerator);
              if (index == 2 && !command.canExecute) {
                expect(
                  item['label'],
                  contains(
                    command.disabledReason!(
                      tester.element(find.byType(BusyBooksMainMenuButton)),
                    ),
                  ),
                );
              }
            }
          }
          expect(find.byType(BusyBooksMainMenuButton), findsOneWidget);
        }

        await check(true, 'Reading');
        tester.view.physicalSize = const Size(540, 850);
        await tester.pumpAndSettle();
        await check(false, 'Reading');
        tester.view.physicalSize = const Size(1200, 850);
        await tester.pumpAndSettle();
        await check(true, 'Reading');
        await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        await check(false, 'Reading');
        await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        await check(true, 'Reading');
        await _readerAction(tester, () async {
          await _appCommands(tester).execute(BusyBooksCommandIds.viewNotebook);
        });
        await tester.pumpAndSettle();
        await check(true, 'Notebook');
        await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        await check(false, 'Notebook');
        await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        await check(true, 'Notebook');
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  for (final surface in ['Home', 'Collection', 'Settings']) {
    testWidgets(
      'view modes no View fallback without an active book surface: $surface',
      (tester) async {
        late _ReaderFixture f;
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create(
            'text.pdf',
            windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          );
          if (surface == 'Collection') {
            await f.container
                .read(workspaceControllerProvider.notifier)
                .createCollection('View context');
          }
        });
        try {
          await _mountHeaderApplication(
            tester,
            f,
            surface == 'Home'
                ? '/'
                : surface == 'Collection'
                ? '/workspace'
                : '/settings',
          );
          expect(find.byType(BookViewSelector), findsNothing);
          final menus = <List<Map>>[];
          await _mainMenuSelect(tester, null, snapshots: menus);
          expect(
            menus.single.where(
              (e) =>
                  ['Reading', 'Notebook', 'View'].contains(e['label']) ||
                  (e['label'] as String).startsWith('Split'),
            ),
            isEmpty,
          );
          expect(find.byType(BusyBooksMainMenuButton), findsOneWidget);
        } finally {
          await _disposeHeaderApplication(tester, f);
        }
      },
    );
  }
  testWidgets(
    'view modes fallback uses existing commands with protected notes, active no-op and keyboard return',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
          'progress': .3,
        });
        await f.reader.annotation('bookmark', note: 'Saved A');
        f.notes.edit(f.reader.annotations.single, 'Protected B');
        gate.fail = true;
        try {
          await f.notes.save(f.reader.annotations.single.id);
        } catch (_) {}
      });
      final id = f.state.bookId!, anchor = f.state.location;
      try {
        await _mountHeaderApplication(tester, f, '/read/$id');
        await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        await _readerAction(
          tester,
          () => f.openAnnotationPopover(f.reader.annotations.single),
        );
        f.onNativeCall = (call) async {
          if (call.method == 'capturePopover') {
            throw PlatformException(code: 'capture-failed');
          }
          return null;
        };
        await _mainMenuSelect(tester, 'Notebook');
        await _closeActionError(tester);
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/read/$id',
        );
        expect(f.drafts.drafts.values.single.text, 'Protected B');
        f.onNativeCall = null;
        await _mainMenuSelect(tester, 'Notebook');
        await _pumpUntil(
          tester,
          () => find.byType(NotebookContent).evaluate().isNotEmpty,
        );
        expect(f.drafts.drafts.values.single.text, 'Protected B');
        final opens = f.calls.where((c) => c.method == 'open').length;
        if (!f.search.active) await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        final calls = gate.calls.length;
        await _mainMenuSelect(tester, 'Notebook');
        expect(gate.calls.length, calls);
        expect(f.calls.where((c) => c.method == 'open').length, opens);
        final searchFocus = tester
            .widget<TextField>(find.byType(TextField).first)
            .focusNode!;
        searchFocus.requestFocus();
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, searchFocus);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await _pumpUntil(
          tester,
          () => find.byType(ReadingContent).evaluate().isNotEmpty,
        );
        expect(f.state.location, anchor);
        expect(f.drafts.drafts.values.single.text, 'Protected B');
        expect(f.calls.where((c) => c.method == 'open').length, opens);
      } finally {
        gate.fail = false;
        f.onNativeCall = null;
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    testWidgets(
      'view modes real Flutter fallback keeps icons, checks and keyboard dismissal on $platform',
      (tester) async {
        late _ReaderFixture f;
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create(
            'text.pdf',
            windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          );
        });
        try {
          await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
          debugDefaultTargetPlatformOverride = platform;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel(nativeMenuChannelName),
                (call) async {
                  if (call.method == 'show') {
                    throw PlatformException(code: 'unavailable');
                  }
                  return null;
                },
              );
          await tester.tap(find.byTooltip('View'));
          await _pumpUntil(
            tester,
            () => find.text('Notebook').evaluate().isNotEmpty,
          );
          expect(find.byIcon(BusyBooksGlyphs.notebookView), findsOneWidget);
          expect(find.byIcon(BusyBooksGlyphs.splitView), findsOneWidget);
          expect(find.byIcon(BusyBooksGlyphs.previewView), findsWidgets);
          expect(find.byIcon(BusyBooksGlyphs.annotations), findsNothing);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(PopupMenuItem<BookView>, 'Notebook'),
            findsNothing,
          );
          expect(FocusManager.instance.primaryFocus?.context?.mounted, true);
          await _readerAction(
            tester,
            () =>
                f.searchController.open(category: BookSearchCategory.bookText),
          );
          await tester.tap(find.byTooltip('Main Menu'));
          await tester.pumpAndSettle();
          final view = find.widgetWithText(SubmenuButton, 'View');
          await _pumpUntil(tester, () => view.evaluate().isNotEmpty);
          expect(view, findsOneWidget);
          await tester.tap(view);
          await tester.pumpAndSettle();
          final notebook = find.widgetWithText(MenuItemButton, 'Notebook');
          expect(notebook, findsOneWidget);
          expect(
            find.descendant(
              of: notebook,
              matching: find.byIcon(BusyBooksGlyphs.notebookView),
            ),
            findsOneWidget,
          );
          await tester.tap(notebook);
          await _pumpUntil(
            tester,
            () => find.byType(NotebookContent).evaluate().isNotEmpty,
          );
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = TargetPlatform.linux;
          await _disposeHeaderApplication(tester, f);
        }
      },
    );
  }
  testWidgets(
    'view modes Notebook native header catalog changes and missing resources use its dedicated fallback',
    (tester) async {
      var revision = 0;
      final icons = GtkHeaderIconService.testing(
        loadBatch: (_) async => {
          'mainMenu.ltr': {
            'bytes': image.encodePng(
              image.Image(width: 2, height: 2)..setPixelRgb(0, 0, 40, 0, 0),
            ),
            'resolvedName': 'open-menu-symbolic',
            'scale': 1,
            'pixelWidth': 2,
            'pixelHeight': 2,
          },
          if (revision != 0)
            'notebook.ltr': {
              'bytes': image.encodePng(
                image.Image(width: 2, height: 2)
                  ..setPixelRgb(0, 0, revision * 40, 0, 0),
              ),
              'resolvedName': 'document-edit-symbolic',
              'scale': 1,
              'pixelWidth': 2,
              'pixelHeight': 2,
            },
        },
      );
      await icons.initialize();
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          headerIcons: icons,
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        await _mountHeaderApplication(tester, f, '/notebook/${f.state.bookId}');
        final selector = find.byType(BookViewSelector);
        expect(
          find.descendant(
            of: selector,
            matching: find.byIcon(BusyBooksGlyphs.notebookView),
          ),
          findsOneWidget,
        );
        expect(BusyBooksLinuxHeaderIcon.notebook.gtkNames, [
          'document-edit-symbolic',
        ]);
        expect(
          BusyBooksGlyphs.nativeMenuIconName(BusyBooksGlyphs.annotations),
          'document-edit-symbolic',
        );
        revision = 1;
        await icons.initialize();
        await tester.pumpAndSettle();
        final native = find.descendant(
          of: selector,
          matching: find.byType(Image),
        );
        expect(native, findsOneWidget);
        final before = tester.widget<Image>(native).image;
        revision = 2;
        await icons.initialize();
        await tester.pumpAndSettle();
        expect(tester.widget<Image>(native).image, isNot(same(before)));
        revision = 0;
        await icons.initialize();
        await tester.pumpAndSettle();
        expect(native, findsNothing);
        expect(
          find.descendant(
            of: selector,
            matching: find.byIcon(BusyBooksGlyphs.notebookView),
          ),
          findsOneWidget,
        );
      } finally {
        await _disposeHeaderApplication(tester, f);
        icons.dispose();
      }
    },
  );
  testWidgets(
    'view modes Windows native serialization includes bounded Yaru masks at display scale',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      final snapshots = <List<Map>>[];
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(nativeMenuChannelName),
              (call) async {
                if (call.method == 'show') {
                  snapshots.add(
                    _nativeLeaves((call.arguments as Map)['entries'] as List),
                  );
                }
                return null;
              },
            );
        for (final scale in [1.0, 2.0, 6.0]) {
          tester.view.devicePixelRatio = scale;
          tester.view.physicalSize = Size(1200 * scale, 850 * scale);
          await tester.pumpAndSettle();
          final count = snapshots.length;
          await tester.tap(find.byTooltip('View'));
          await _pumpUntil(tester, () => snapshots.length > count);
          for (final item in snapshots.last) {
            final size = (BusyBooksSizes.iconSm * scale).round().clamp(16, 64);
            expect(item['iconSize'], size);
            expect(item['iconMask'], isA<Uint8List>());
            expect((item['iconMask'] as Uint8List).length, size * size);
            expect((item['iconMask'] as Uint8List).any((n) => n != 0), true);
          }
        }
      } finally {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'view modes ordinary header owns switching without Main Menu duplication',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        expect(find.byType(BookViewSelector), findsOneWidget);
        final menus = <List<Map>>[];
        await _mainMenuSelect(tester, null, snapshots: menus);
        expect(
          menus.single.where(
            (e) =>
                ['Reading', 'Notebook', 'View'].contains(e['label']) ||
                (e['label'] as String).startsWith('Split'),
          ),
          isEmpty,
        );
        expect(find.byType(BusyBooksMainMenuButton), findsOneWidget);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'view modes actual selector serializes distinct icons and updates its active trigger',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        final snapshots = <List<Map>>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(nativeMenuChannelName),
              (call) async {
                if (call.method != 'show') return null;
                final entries = _nativeLeaves(
                  (call.arguments as Map)['entries'] as List,
                );
                snapshots.add(entries);
                return entries.indexWhere((e) => e['label'] == 'Notebook');
              },
            );
        final trigger = find.byType(BusyBooksHeaderPopupMenuButton<BookView>);
        expect(
          tester.widget<BusyBooksHeaderPopupMenuButton<BookView>>(trigger).icon,
          BusyBooksGlyphs.previewView,
        );
        await tester.tap(find.byTooltip('View'));
        await _pumpUntil(
          tester,
          () => find.byType(NotebookContent).evaluate().isNotEmpty,
        );
        expect(snapshots.single.map((e) => e['label']), [
          'Reading',
          'Notebook',
          'Split',
        ]);
        expect(snapshots.single[0]['icon'], 'view-paged-symbolic');
        expect(snapshots.single[1]['icon'], 'document-edit-symbolic');
        expect(snapshots.single[2]['icon'], 'sidebar-show-right-symbolic');
        expect(snapshots.single[0]['selected'], true);
        expect(snapshots.single[1]['selected'], false);
        expect(snapshots.single[2]['selected'], false);
        expect(snapshots.single[2]['enabled'], true);
        expect(
          snapshots.single[2]['shortcut'],
          _appCommands(tester)[BusyBooksCommandIds.viewSplit]!.shortcut?.label,
        );
        expect(
          snapshots.single[1]['shortcut'],
          _appCommands(
            tester,
          )[BusyBooksCommandIds.viewNotebook]!.shortcut!.label,
        );
        expect(
          tester.widget<BusyBooksHeaderPopupMenuButton<BookView>>(trigger).icon,
          BusyBooksGlyphs.edit,
        );
        expect(BusyBooksGlyphs.edit, isNot(BusyBooksGlyphs.annotations));
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'right header stale native menu and captured commands cannot bookmark a different usable book',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
        });
      });
      final delayed = Completer<int?>();
      List<Map>? entries;
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        final originalId = f.state.bookId!;
        final originalCommands = _appCommands(tester);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(nativeMenuChannelName),
              (call) async {
                if (call.method == 'show') {
                  entries = _nativeLeaves(
                    (call.arguments as Map)['entries'] as List,
                  );
                  return delayed.future;
                }
                return true;
              },
            );
        await tester.tap(find.byTooltip('Main Menu'));
        await _pumpUntil(tester, () => entries != null);
        late String replacementId;
        await _readerAction(tester, () async {
          replacementId =
              (await f.container
                      .read(workspaceControllerProvider.notifier)
                      .openPath(p.absolute('test/fixtures/mixed-pages.pdf')))
                  .books
                  .single
                  .id;
          f.container.read(appRouterProvider).go('/read/$replacementId');
        }, settle: false);
        await _pumpUntil(
          tester,
          () => f.calls.where((c) => c.method == 'open').length == 2,
          settle: false,
        );
        await _readerAction(tester, () async {
          await f.finishColdOpen();
          await f.checkedEvent('location', {
            'anchor': {'page': 0},
          });
        });
        expect(f.state.bookId, replacementId);
        expect(
          originalCommands[BusyBooksCommandIds.bookmark]!.canExecute,
          true,
        );
        delayed.complete(entries!.indexWhere((e) => e['label'] == 'Bookmark'));
        await tester.pumpAndSettle();
        await _readerAction(tester, () async {
          await originalCommands.execute(BusyBooksCommandIds.bookmark);
          await f.container.read(workspaceControllerProvider.notifier).flush();
          expect(await f.store.call('annotations', originalId), isEmpty);
          expect(await f.store.call('annotations', replacementId), isEmpty);
        });
        expect(f.state.ready, true);
        expect(f.reader.bookmarked, false);
      } finally {
        if (!delayed.isCompleted) delayed.complete();
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'right header shared fallback menu supports keyboard selection, Escape and focus return',
    (tester) async {
      final window = WindowControlService(nativeWindow: _HeaderWindow());
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf', windowControls: window);
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        tester.view.physicalSize = const Size(540, 850);
        await tester.pumpAndSettle();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(nativeMenuChannelName),
              (c) async {
                if (c.method == 'show') {
                  throw PlatformException(code: 'unavailable');
                }
                return null;
              },
            );
        await tester.tap(find.byTooltip('Main Menu'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(MenuItemButton, 'Full Screen'),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(MenuItemButton, 'Full Screen'),
          findsNothing,
        );
        await tester.tap(find.byTooltip('Main Menu'));
        await tester.pumpAndSettle();
        String? focused() {
          final item = FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<MenuItemButton>();
          return item?.child is Text ? (item!.child as Text).data : null;
        }

        for (var i = 0; i < 45 && focused() != 'Full Screen'; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        expect(focused(), 'Full Screen');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(window.isFullScreen, true);
        expect(
          find.widgetWithText(MenuItemButton, 'Full Screen'),
          findsNothing,
        );
        expect(FocusManager.instance.primaryFocus?.context?.mounted, true);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'right header fallback, grouped checks and external Full Screen state are truthful',
    (tester) async {
      final native = _HeaderWindow();
      final window = WindowControlService(nativeWindow: native);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf', windowControls: window);
        await f.checkedEvent('metadata', {'fixed': true});
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
        });
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        final main = find.byType(BusyBooksMainMenuButton);
        expect(
          find.descendant(of: main, matching: find.byType(Image)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: main,
            matching: find.byIcon(BusyBooksGlyphs.menuVertical),
          ),
          findsOneWidget,
        );
        // Compact layout exposes mode fallback without changing the selected panel.
        tester.view.physicalSize = const Size(540, 850);
        await tester.pumpAndSettle();
        final menus = <List<Map>>[];
        await _mainMenuSelect(tester, null, snapshots: menus);
        Map item(String label) =>
            menus.last.singleWhere((e) => e['label'] == label);
        expect(item('Reading')['selected'], true);
        expect(item('Notebook')['selected'], false);
        expect(item('Reading')['mutuallyExclusive'], true);
        expect(item('Full Screen')['checkable'], true);
        expect(item('Full Screen')['mutuallyExclusive'], false);
        expect(item('Full Screen')['selected'], false);
        expect(menus.last.any((e) => e['label'] == 'Bookmark'), false);
        expect(menus.last.any((e) => e['label'] == 'View Options'), false);
        expect(menus.last.any((e) => e['label'] == 'Outline'), false);
        expect(menus.last.where((e) => e['children'] is List), isNotEmpty);
        expect(menus.last.where((e) => e['separator'] == true), isNotEmpty);
        expect(
          menus.last.any((e) => e['label'] == 'Search title, author or series'),
          false,
        );
        native.fullScreen = true;
        native.listeners.single.onWindowEnterFullScreen();
        await tester.pumpAndSettle();
        await _mainMenuSelect(tester, null, snapshots: menus);
        expect(item('Full Screen')['selected'], true);
        await _mainMenuSelect(tester, 'Full Screen');
        await tester.pumpAndSettle();
        expect(native.fullScreen, false);
        expect(window.isFullScreen, false);
        const binding = BusyBooksKeyBinding(
          LogicalKeyboardKey.f8,
          control: true,
          alt: true,
          shift: true,
        );
        await _readerAction(tester, () async {
          expect(
            await f.container
                .read(appSettingsControllerProvider.notifier)
                .saveShortcutOverrides({
                  BusyBooksCommandIds.fullScreen: binding,
                }),
            true,
          );
        });
        await tester.pumpAndSettle();
        await _mainMenuSelect(tester, null, snapshots: menus);
        expect(item('Full Screen')['shortcut'], binding.label);
        expect(item('Full Screen')['gtkAccelerator'], binding.gtkAccelerator);
        await _readerAction(
          tester,
          () => f.sidebarController.selectPanel(BookSidebarPanel.marks),
        );
        expect(f.sidebar.panel, BookSidebarPanel.marks);
        expect((f.sidebar.open || f.search.active), true);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'right header bookmark failures preserve committed selection and allow safe retries',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
        });
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        gate.failPut = true;
        await tester.tap(_headerButton('Bookmark'));
        await _pumpUntil(
          tester,
          () => find.text('Error').evaluate().isNotEmpty,
        );
        expect(f.reader.bookmarked, false);
        expect(f.reader.bookmarkPending, false);
        expect(f.state.ready, true);
        expect(f.state.error, isNull);
        await _closeActionError(tester);
        gate.failPut = false;
        await tester.tap(_headerButton('Bookmark'));
        await _pumpUntil(tester, () => f.reader.bookmarked);
        final bookmark = f.reader.annotations.single;
        gate.failDelete = true;
        await tester.tap(_headerButton('Remove Bookmark'));
        await _pumpUntil(
          tester,
          () => find.text('Error').evaluate().isNotEmpty,
        );
        expect(f.reader.bookmarked, true);
        expect(f.reader.bookmarkPending, false);
        await _closeActionError(tester);
        gate.failDelete = false;
        await tester.tap(_headerButton('Remove Bookmark'));
        await _pumpUntil(tester, () => !f.reader.bookmarked);
        await _readerAction(tester, () async {
          await f.notes.flush();
          final records =
              await f.store.call('annotations', bookmark.bookId) as List;
          expect(records.where((a) => a['id'] == bookmark.id), isEmpty);
        });
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'right header pending bookmark suppresses keyboard and menu activation and stays with its captured book',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      late String otherId;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
        });
        otherId =
            (await f.container
                    .read(workspaceControllerProvider.notifier)
                    .preparePath(p.absolute('test/fixtures/reflowable.epub')))
                .books
                .single
                .id;
      });
      final bookId = f.state.bookId!;
      gate.putEntered = Completer<void>();
      gate.putProceed = Completer<void>();
      try {
        await _mountHeaderApplication(tester, f, '/read/$bookId');
        await tester.tap(_headerButton('Bookmark'));
        await _pumpUntil(tester, () => gate.putEntered!.isCompleted);
        expect(f.reader.bookmarkPending, true);
        expect(
          tester
              .widget<BusyBooksHeaderIconButton>(_headerButton('Bookmark'))
              .onPressed,
          isNull,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        tester.view.physicalSize = const Size(540, 850);
        await tester.pumpAndSettle();
        final menus = <List<Map>>[];
        await _mainMenuSelect(
          tester,
          'Bookmark',
          snapshots: menus,
          tooltip: 'Book Actions',
        );
        expect(
          menus.single.singleWhere((e) => e['label'] == 'Bookmark')['enabled'],
          false,
        );
        f.container.read(appRouterProvider).go('/notebook/$otherId');
        await tester.pump();
        gate.putProceed!.complete();
        await _readerAction(tester, () async {
          await f.container.read(workspaceControllerProvider.notifier).flush();
          expect((await f.store.call('annotations', bookId) as List).length, 1);
          expect(await f.store.call('annotations', otherId), isEmpty);
        });
        await tester.pumpAndSettle();
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/notebook/$otherId',
        );
        expect(find.byType(NotebookContent), findsOneWidget);
        expect(find.byKey(const ValueKey('reader-bookmark')), findsNothing);
        expect(gate.calls.where((x) => x == 'putAnnotation').length, 1);
      } finally {
        if (!gate.putProceed!.isCompleted) gate.putProceed!.complete();
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'right header menu host failure recovers and stale native selections cannot act on a replacement view',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
        });
      });
      final delayed = Completer<int?>();
      List<Map>? opened;
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        tester.view.physicalSize = const Size(540, 850);
        await tester.pumpAndSettle();
        const channel = MethodChannel(nativeMenuChannelName);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (c) async {
              if (c.method == 'show') {
                throw PlatformException(
                  code: 'fixture-menu',
                  message: 'Menu host failed',
                );
              }
              return null;
            });
        await tester.tap(find.byTooltip('Main Menu'));
        await _pumpUntil(
          tester,
          () => find
              .widgetWithText(MenuItemButton, 'Full Screen')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('Error'), findsNothing);
        expect(f.state.error, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await _mainMenuSelect(tester, null);
        expect(tester.takeException(), isNull);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (c) async {
              if (c.method == 'show') {
                opened = _nativeLeaves((c.arguments as Map)['entries'] as List);
                return delayed.future;
              }
              return true;
            });
        await tester.tap(find.byTooltip('Book Actions'));
        await _pumpUntil(tester, () => opened != null);
        f.container.read(appRouterProvider).go('/notebook/${f.state.bookId}');
        await tester.pumpAndSettle();
        delayed.complete(opened!.indexWhere((e) => e['label'] == 'Bookmark'));
        await tester.pumpAndSettle();
        await _readerAction(
          tester,
          () => f.container.read(workspaceControllerProvider.notifier).flush(),
        );
        expect(f.reader.annotations, isEmpty);
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          startsWith('/notebook/'),
        );
      } finally {
        if (!delayed.isCompleted) delayed.complete();
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'right header view selector is exclusive, active view is a no-op and failed transitions retain drafts',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
        });
        await f.reader.annotation('bookmark', note: 'Saved A');
        f.notes.edit(f.reader.annotations.single, 'Protected B');
        gate.fail = true;
        try {
          await f.notes.save(f.reader.annotations.single.id);
        } catch (_) {}
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        final lists = <List<Map>>[];
        const channel = MethodChannel(nativeMenuChannelName);
        String choose = 'Reading';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (c) async {
              if (c.method != 'show') return null;
              final entries = _nativeLeaves(
                (c.arguments as Map)['entries'] as List,
              );
              lists.add(entries);
              return entries.indexWhere((e) => e['label'] == choose);
            });
        final before = gate.calls.length;
        await tester.tap(find.byTooltip('View'));
        await tester.pumpAndSettle();
        expect(
          lists.last.singleWhere((e) => e['label'] == 'Reading')['selected'],
          true,
        );
        expect(gate.calls.length, before);
        await _readerAction(
          tester,
          () => f.openAnnotationPopover(f.reader.annotations.single),
        );
        f.onNativeCall = (call) async {
          if (call.method == 'capturePopover') {
            throw PlatformException(code: 'capture-failed');
          }
          return null;
        };
        choose = 'Notebook';
        await tester.tap(find.byTooltip('View'));
        await _pumpUntil(
          tester,
          () => find.text('Error').evaluate().isNotEmpty,
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          startsWith('/read/'),
        );
        expect(f.state.ready, true);
        expect(f.notes.state.drafts.values.single.text, 'Protected B');
        await _closeActionError(tester);
        f.onNativeCall = null;
        await tester.tap(find.byTooltip('View'));
        await _pumpUntil(
          tester,
          () => find.byType(NotebookContent).evaluate().isNotEmpty,
        );
        expect(find.byType(BusyBooksMainMenuButton), findsOneWidget);
        expect(find.byTooltip('Book details'), findsNothing);
        expect(f.notes.state.drafts.values.single.text, 'Protected B');
      } finally {
        gate.fail = false;
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'right header late view-transition data cannot route over a newer screen',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
      });
      final entered = Completer<void>(), proceed = Completer<void>();
      await _readerAction(tester, f.openSelectionPopover);
      f.onNativeCall = (call) async {
        if (call.method == 'capturePopover') {
          if (!entered.isCompleted) entered.complete();
          await proceed.future;
        }
        return null;
      };
      final readsBefore = gate.calls.where((c) => c == 'book').length;
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        final command = _appCommands(tester);
        unawaited(command.execute(BusyBooksCommandIds.viewNotebook));
        await _pumpUntil(tester, () => entered.isCompleted);
        expect(gate.calls.where((c) => c == 'book').length, readsBefore);
        f.container.read(appRouterProvider).go('/');
        await tester.pumpAndSettle();
        proceed.complete();
        await _readerAction(
          tester,
          () => f.container.read(workspaceControllerProvider.notifier).flush(),
        );
        await tester.pumpAndSettle();
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/',
        );
      } finally {
        if (!proceed.isCompleted) proceed.complete();
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'right header normal order, search scope and narrow scaled menu access share the application commands',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
        });
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        final points = [
          find.byType(BookViewSelector),
          _headerButton('Bookmark'),
          _headerButton('Appearance'),
          _headerButton('Search'),
          find.byType(BusyBooksMainMenuButton),
        ].map((x) => tester.getCenter(x).dx).toList();
        expect(points, orderedEquals([...points]..sort()));
        await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        expect(find.byType(BookViewSelector), findsNothing);
        expect(
          find.byKey(const ValueKey('book-header-search')),
          findsOneWidget,
        );
        expect(find.byType(BusyBooksMainMenuButton), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await _readerAction(tester, () async {
          await _appCommands(tester).execute(BusyBooksCommandIds.viewNotebook);
        });
        await tester.pumpAndSettle();
        final notebookPoints = [
          find.byType(BookViewSelector),
          _headerButton('Search'),
          find.byType(BusyBooksMainMenuButton),
        ].map((w) => tester.getCenter(w).dx).toList();
        expect(notebookPoints, orderedEquals([...notebookPoints]..sort()));
        expect(find.byTooltip('Book details'), findsNothing);
        await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        expect(find.byType(BookViewSelector), findsNothing);
        expect(find.byType(BusyBooksMainMenuButton), findsOneWidget);
        await _readerAction(tester, () async {
          await _appCommands(tester).execute(BusyBooksCommandIds.viewReading);
        });
        await tester.pumpAndSettle();
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.view.physicalSize = const Size(540, 850);
        await tester.pumpAndSettle();
        expect(find.byType(BookViewSelector), findsNothing);
        f.searchController.close(restoreFocus: false);
        await _readerAction(tester, () => f.sidebarController.setOpen(false));
        await _pumpUntil(tester, () => f.state.surfaceVisible);
        final menuRect = tester.getRect(find.byType(BusyBooksMainMenuButton));
        expect(menuRect.right, lessThanOrEqualTo(540));
        expect(menuRect.left, greaterThan(0));
        final menus = <List<Map>>[];
        await _mainMenuSelect(
          tester,
          null,
          snapshots: menus,
          tooltip: 'Book Actions',
        );
        expect(
          menus.single.singleWhere((e) => e['label'] == 'Bookmark')['enabled'],
          true,
        );
        expect(menus.single.any((e) => e['label'] == 'Search in Book'), false);
        expect(tester.takeException(), isNull);
      } finally {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  for (final surface in ['home', 'collection', 'reading', 'missing-notebook']) {
    testWidgets(
      'right header Settings round trip preserves $surface state and the original safe return target',
      (tester) async {
        late _ReaderFixture f;
        late AnnotationStoreGate gate;
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create(
            'text.pdf',
            ownedOriginal: true,
            windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
            wrapStore: (s) => gate = AnnotationStoreGate(s),
          );
          await f.checkedEvent('location', {
            'anchor': {'page': 0},
          });
          if (surface == 'collection') {
            await f.container
                .read(workspaceControllerProvider.notifier)
                .createCollection('Fixture collection');
          }
          if (surface == 'missing-notebook') {
            await f.reader.annotation('bookmark', note: 'Saved A');
            f.notes.edit(f.reader.annotations.single, 'Protected B');
            gate.fail = true;
            try {
              await f.notes.save(f.reader.annotations.single.id);
            } catch (_) {}
            await File(f.reader.book!.path).delete();
            await f.searchController.open(
              category: BookSearchCategory.notebook,
              query: 'Protected',
            );
            f.notes.view(
              f.state.bookId!,
              filter: AnnotationTypeFilter.bookmarks,
              withNotes: true,
              scroll: 0,
            );
          }
        });
        final bookId = f.state.bookId!;
        final path = switch (surface) {
          'home' => '/',
          'collection' => '/workspace',
          'reading' => '/read/$bookId',
          _ => '/notebook/$bookId',
        };
        try {
          await _mountHeaderApplication(tester, f, path);
          expect(find.byType(BusyBooksMainMenuButton), findsOneWidget);
          await _mainMenuSelect(tester, 'Settings');
          await _pumpUntil(
            tester,
            () =>
                f.container
                    .read(appRouterProvider)
                    .routeInformationProvider
                    .value
                    .uri
                    .path ==
                '/settings',
          );
          await tester.pumpAndSettle();
          expect(find.byType(BusyBooksMainMenuButton), findsOneWidget);
          final origin = f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri;
          expect(origin.queryParameters['returnTo'], path);
          final menus = <List<Map>>[];
          await _mainMenuSelect(tester, 'Settings', snapshots: menus);
          expect(
            menus.single.singleWhere(
              (e) => e['label'] == 'Settings',
            )['enabled'],
            false,
          );
          expect(
            f.container
                .read(appRouterProvider)
                .routeInformationProvider
                .value
                .uri,
            origin,
          );
          await tester.tap(find.byTooltip('Back'));
          await _pumpUntil(
            tester,
            () =>
                find.byType(CircularProgressIndicator).evaluate().isEmpty &&
                (!f.search.active ||
                    f.search.category == BookSearchCategory.bookText ||
                    !f.search.loading),
          );
          expect(
            f.container
                .read(appRouterProvider)
                .routeInformationProvider
                .value
                .uri
                .path,
            path,
          );
          if (surface == 'missing-notebook') {
            expect(f.notes.state.drafts.values.single.text, 'Protected B');
            expect(
              f.container.read(bookSearchSessionProvider).query,
              'Protected',
            );
            final m = <List<Map>>[];
            await _mainMenuSelect(
              tester,
              null,
              snapshots: m,
              tooltip: 'Book Actions',
            );
            for (final label in [
              'Move Book',
              'Locate Book',
              'Export Annotations',
            ]) {
              expect(
                m.single.singleWhere((e) => e['label'] == label)['enabled'],
                true,
              );
            }
            expect(m.single.any((e) => e['label'] == 'Bookmark'), false);
            expect(m.single.any((e) => e['label'] == 'Appearance'), false);
          }
        } finally {
          gate.fail = false;
          await _disposeHeaderApplication(tester, f);
        }
      },
    );
  }
  for (final fixture in [
    'reflowable.epub',
    'fixed-layout.epub',
    'text.pdf',
    'image-only.pdf',
  ]) {
    testWidgets(
      'right header native Appearance first use, host recovery and live resize preserve the $fixture passage',
      (tester) async {
        late _ReaderFixture f;
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create(
            fixture,
            windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          );
          await f.checkedEvent('metadata', {
            'fixed': fixture != 'reflowable.epub',
          });
        });
        final location = Map.of(f.state.location);
        var fail = true;
        final requests = <Map>[];
        try {
          await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel(nativeMenuChannelName),
                (call) async {
                  if (call.method != 'show') return null;
                  requests.add(call.arguments as Map);
                  if (fail) {
                    throw PlatformException(
                      code: 'fixture-menu',
                      message: 'Fixture host failure',
                    );
                  }
                  return null;
                },
              );
          final label = fixture == 'reflowable.epub'
              ? 'Appearance'
              : 'View Options';
          final trigger = tester.getRect(_headerButton(label));
          f.calls.clear();
          await tester.tap(_headerButton(label));
          await _pumpUntil(
            tester,
            () => find.text('Page color').evaluate().isNotEmpty,
          );
          expect(f.state.popoverError, isNull);
          expect(f.state.ready, true);
          expect(f.state.error, isNull);
          expect(f.state.location, location);
          expect(
            (requests.single['anchor'] as Map)['x'],
            closeTo(trigger.left, .01),
          );
          expect(
            (requests.single['anchor'] as Map)['y'],
            closeTo(trigger.top, .01),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          fail = false;
          tester.view.physicalSize = const Size(1100, 850);
          await tester.pumpAndSettle();
          final relocated = tester.getRect(_headerButton(label));
          await tester.tap(_headerButton(label));
          await _pumpUntil(tester, () => requests.length == 2);
          expect(
            (requests.last['anchor'] as Map)['x'],
            closeTo(relocated.left, .01),
          );
          expect(
            (requests.last['anchor'] as Map)['y'],
            closeTo(relocated.top, .01),
          );
          final entries = _nativeLeaves(requests.last['entries'] as List);
          expect(
            entries.any((row) => row['label'] == 'Font size'),
            fixture == 'reflowable.epub',
          );
          expect(
            entries.any((row) => row['label'] == 'Rotation'),
            fixture.endsWith('.pdf'),
          );
          await _readerAction(tester, () async {
            await _appCommands(tester).execute(BusyBooksCommandIds.appearance);
          });
          expect(requests, hasLength(3));
          expect(f.calls.where((call) => call.method == 'popover'), isEmpty);
          expect(f.state.location, location);
          expect(f.state.error, isNull);
        } finally {
          await _disposeHeaderApplication(tester, f);
        }
      },
    );
  }

  testWidgets(
    'right header full application consumes and replaces the native icon catalog',
    (tester) async {
      var pixels = image.encodePng(
        image.Image(width: 2, height: 2)..setPixelRgb(0, 0, 255, 0, 0),
      );
      var revision = 1;
      final icons = GtkHeaderIconService.testing(
        loadBatch: (_) async => {
          'home.ltr': {
            'bytes': pixels,
            'resolvedName': 'go-home-symbolic',
            'scale': 1,
            'pixelWidth': 2,
            'pixelHeight': 2,
          },
          'mainMenu.ltr': {
            'bytes': pixels,
            'resolvedName': 'open-menu-symbolic-$revision',
            'scale': 1,
            'pixelWidth': 2,
            'pixelHeight': 2,
          },
        },
      );
      await icons.initialize();
      final window = WindowControlService(nativeWindow: _HeaderWindow());
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          headerIcons: icons,
          windowControls: window,
        );
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        final main = find.byType(BusyBooksMainMenuButton);
        expect(main, findsOneWidget);
        final native = find.descendant(of: main, matching: find.byType(Image));
        expect(native, findsOneWidget);
        final before = tester.widget<Image>(native).image;
        final homeIcon = find.descendant(
          of: _headerButton('Home'),
          matching: find.byType(Image),
        );
        expect(homeIcon, findsOneWidget);
        final homeBefore = tester.widget<Image>(homeIcon).image;
        revision = 2;
        pixels = image.encodePng(
          image.Image(width: 2, height: 2)..setPixelRgb(0, 0, 0, 0, 255),
        );
        await icons.initialize();
        await tester.pumpAndSettle();
        expect(
          GtkHeaderIconScope.of(
            tester.element(main),
          ).catalog.assets['mainMenu.ltr']!.resolvedName,
          'open-menu-symbolic-2',
        );
        expect(tester.widget<Image>(native).image, isNot(same(before)));
        expect(tester.widget<Image>(homeIcon).image, isNot(same(homeBefore)));
        expect(
          (tester.widget<Image>(native).image as MemoryImage).bytes,
          orderedEquals(pixels),
        );
        expect((before as MemoryImage).bytes, isNot(orderedEquals(pixels)));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
        debugDefaultTargetPlatformOverride = null;
        icons.dispose();
      }
    },
  );
  testWidgets(
    'right header real bookmark activation cannot enqueue duplicate insertion at a blocked write',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      final window = WindowControlService(nativeWindow: _HeaderWindow());
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: window,
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.checkedEvent('location', {
          'anchor': {'page': 0, 'y': .1},
          'reference': 'Page 1',
        });
      });
      gate.putEntered = Completer<void>();
      gate.putProceed = Completer<void>();
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is BusyBooksHeaderIconButton && w.tooltip == 'Bookmark',
          ),
        );
        await _pumpUntil(tester, () => gate.putEntered!.isCompleted);
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is BusyBooksHeaderIconButton && w.tooltip == 'Bookmark',
          ),
        );
        await tester.pump();
        expect(gate.calls.where((c) => c == 'putAnnotation').length, 1);
        gate.putProceed!.complete();
        await _pumpUntil(tester, () => f.reader.bookmarked);
        late List persisted;
        await _readerAction(tester, () async {
          await f.container.read(workspaceControllerProvider.notifier).flush();
          persisted = await f.store.call('annotations', f.state.bookId) as List;
        });
        expect(persisted.length, 1);
      } finally {
        if (!gate.putProceed!.isCompleted) gate.putProceed!.complete();
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  testWidgets(
    'right header actual Main Menu Settings returns to Notebook and preserves reentry target',
    (tester) async {
      final window = WindowControlService(nativeWindow: _HeaderWindow());
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf', windowControls: window);
      });
      final path = '/notebook/${f.state.bookId}';
      try {
        await _mountHeaderApplication(tester, f, path);
        await _mainMenuSelect(tester, 'Settings');
        await _pumpUntil(
          tester,
          () =>
              f.container
                  .read(appRouterProvider)
                  .routeInformationProvider
                  .value
                  .uri
                  .path ==
              '/settings',
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/settings',
        );
        await _mainMenuSelect(tester, 'Settings');
        await tester.tap(find.byTooltip('Back'));
        await _pumpUntil(
          tester,
          () => find.byType(NotebookContent).evaluate().isNotEmpty,
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          path,
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(nativeMenuChannelName),
              null,
            );
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'sidebar keyboard, scaling and saved view state preserve hierarchy without following ordinary scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      final toc = <Map<String, dynamic>>[
        {'id': 'group', 'label': 'Front matter', 'depth': 0},
        for (var i = 0; i < 60; i++)
          {
            'id': 'node-$i',
            'label': 'Section $i',
            'depth': 1,
            'href': '$i',
            'anchor': {
              'page': i,
              'point': [0, 700],
            },
          },
      ];
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
        await f.checkedEvent('metadata', {
          'pages': 60,
          'labels': List.generate(60, (i) => '${i + 1}'),
          'toc': toc,
          'fixed': true,
        });
        await f.sidebarController.selectPanel(BookSidebarPanel.outline);
        await f.checkedEvent('location', {
          'tocId': 'node-0',
          'anchor': {'page': 0},
        });
      });
      try {
        await tester.pumpWidget(_sidebarApplication(f));
        await tester.pumpAndSettle();
        final disclosure = find.byKey(
          const ValueKey('outline-disclosure-group'),
        );
        await tester.tap(disclosure);
        await tester.pumpAndSettle();
        expect(find.text('Section 0'), findsNothing);
        final before = f.dispatches.where((e) => e['action'] == 'goto').length;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.text('Section 0'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _pumpUntil(
          tester,
          () =>
              f.dispatches.where((d) => d['action'] == 'goto').length > before,
        );
        expect(f.dispatches.lastWhere((e) => e['action'] == 'goto')['anchor'], {
          'page': 0,
          'point': [0, 700],
        });
        expect(
          f.dispatches.where((e) => e['action'] == 'goto').length,
          before + 1,
        );
        await _readerAction(
          tester,
          () => f.checkedEvent('location', {
            'tocId': 'node-0',
            'anchor': {'page': 0},
          }),
        );
        final list = find.byKey(ValueKey('outline-tree-${f.state.bookId}'));
        await tester.drag(list, const Offset(0, -900));
        await tester.pumpAndSettle();
        final saved = f.container
            .read(bookSidebarProvider(f.state.bookId!))
            .scroll['outline']!;
        expect(saved, greaterThan(100));
        await _readerAction(
          tester,
          () => f.checkedEvent('location', {
            'tocId': 'node-1',
            'anchor': {'page': 1},
          }),
        );
        await tester.pumpAndSettle();
        expect(
          f.container
              .read(bookSidebarProvider(f.state.bookId!))
              .scroll['outline'],
          saved,
        );
        await _readerAction(
          tester,
          () => f.sidebarController.selectPanel(BookSidebarPanel.marks),
        );
        await _readerAction(
          tester,
          () => f.sidebarController.selectPanel(BookSidebarPanel.outline),
        );
        expect(
          f.container
              .read(bookSidebarProvider(f.state.bookId!))
              .scroll['outline'],
          saved,
        );
        await _readerAction(tester, f.sidebarController.toggleOpen);
        await _readerAction(tester, f.sidebarController.toggleOpen);
        expect(
          f.container
              .read(bookSidebarProvider(f.state.bookId!))
              .scroll['outline'],
          saved,
        );
        await tester.pumpWidget(
          _sidebarApplication(f, direction: TextDirection.rtl, scale: 2),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byKey(const ValueKey('reader-sidebar-view-menu')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<BusyBooksPopupMenuItem<BookSidebarPanel>>(
                find.byWidgetPredicate(
                  (w) =>
                      w is BusyBooksPopupMenuItem<BookSidebarPanel> &&
                      w.menuValue == BookSidebarPanel.outline,
                ),
              )
              .shortcut,
          const BusyBooksKeyBinding(
            LogicalKeyboardKey.f8,
            control: true,
            shift: true,
            alt: true,
          ).label,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
      }
    },
  );
  test(
    'sidebar metadata chunks retain identities, reject stale updates and keep the publication usable on optional failure',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        final id = f.state.bookId!;
        await f.checkedEvent('metadata', {
          'pages': 4,
          'tocOffset': 0,
          'tocComplete': false,
          'outlineRevision': 8,
          'toc': [
            {'id': 'g', 'label': 'Contents', 'depth': 0},
          ],
        });
        expect(f.state.toc, isEmpty);
        await f.checkedEvent('metadata', {
          'tocOffset': 1,
          'tocComplete': true,
          'outlineRevision': 8,
          'toc': [
            {'id': 'c', 'label': 'Same', 'depth': 1, 'href': ''},
          ],
        });
        expect(f.state.outline.roots.single.children.single.id, 'c');
        f.container.read(bookSidebarProvider(id).notifier).toggle('g');
        await f.checkedEvent('metadata', {
          'outlineRevision': 8,
          'tocUpdates': [
            {
              'id': 'c',
              'anchor': {
                'page': 2,
                'point': [12, 500],
              },
              'href': '2',
            },
          ],
          'tocResolved': true,
        });
        expect(f.state.outline.byId['c']!.destination, {
          'page': 2,
          'point': [12, 500],
        });
        expect(f.container.read(bookSidebarProvider(id)).expanded, isEmpty);
        await f.checkedEvent('metadata', {
          'outlineRevision': 7,
          'tocUpdates': [
            {
              'id': 'c',
              'anchor': {'page': 0},
            },
          ],
        });
        await f.checkedEvent('metadata', {'session': 'obsolete', 'toc': []});
        expect(f.state.outline.byId['c']!.destination!['page'], 2);
        final stored = await f.store.call('book', id) as Map;
        expect((stored['outline'] as List).last['anchor'], {
          'page': 2,
          'point': [12, 500],
        });
        final archive = p.join(f.directory.path, 'outline.busybooks');
        await f.store.call('backup', {
          'path': archive,
          'preferences': {'readerPanel': 'outline'},
        });
        final restored = await ReadingDataStore.open(
          p.join(f.directory.path, 'outline-restored'),
        );
        try {
          await restored.call('restore', archive);
          final restoredBook = Book(
            (await restored.call('book', id) as Map).cast<String, dynamic>(),
          );
          expect(restoredBook.id, id);
          expect(restoredBook.data['outline'], stored['outline']);
          expect(restoredBook.format, 'pdf');
        } finally {
          await restored.close();
        }
        await f.checkedEvent('metadata', {'outlineFailed': true});
        expect(f.state.ready, isTrue);
        expect(f.state.error, isNull);
        expect(f.state.outlineStatus, 'error');
        await f.reader.reloadOutline();
        expect(f.dispatches.last['action'], 'outline');
        await f.checkedEvent('metadata', {'toc': []});
        expect(f.state.outlineStatus, 'ready');
        expect(f.state.outline.ordered, isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );
  testWidgets(
    'sidebar PDF previews wait for usability, request a bounded window and retry failures explicitly',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('image-only.pdf', initialize: false);
        await f.checkedEvent('ready');
        await f.checkedEvent('metadata', {
          'pages': 1000,
          'labels': List.generate(1000, (i) => i == 0 ? 'iv' : '${i - 25}'),
          'fixed': true,
        });
        await f.sidebarController.selectPanel(BookSidebarPanel.thumbnails);
      });
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SizedBox(
                  width: BusyBooksSizes.sidebarWidth,
                  child: ReadingSidebarBody(bookId: f.state.bookId!),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          f.dispatches.where((d) => d['action'] == 'thumbnailWindow'),
          isEmpty,
        );
        await _readerAction(
          tester,
          () => f.checkedEvent('opened'),
          settle: false,
        );
        await _readerAction(tester, () => f.reader.show(true), settle: false);
        await _pumpUntil(
          tester,
          () => f.dispatches.any((d) => d['action'] == 'thumbnailWindow'),
          settle: false,
        );
        await tester.pump();
        final window = f.dispatches.lastWhere(
          (d) => d['action'] == 'thumbnailWindow',
        );
        final requested = (window['pages'] as List).cast<int>();
        expect(requested.length, inInclusiveRange(1, 12));
        expect(requested, contains(0));
        final png =
            'data:image/png;base64,${base64Encode(image.encodePng(image.Image(width: 4, height: 2)))}';
        await _readerAction(
          tester,
          () => f.checkedEvent('thumbnail', {
            'request': window['request'],
            'page': 0,
            'data': png,
            'width': 4,
            'height': 2,
          }),
          settle: false,
        );
        await tester.pump();
        expect(find.byType(Image), findsOneWidget);
        expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
        expect(find.text('Page iv'), findsOneWidget);
        await _readerAction(
          tester,
          () => f.checkedEvent('thumbnailError', {
            'request': window['request'],
            'page': 1,
            'message': 'injected failure',
          }),
          settle: false,
        );
        await tester.pump();
        expect(find.text('Page preview could not be loaded.'), findsOneWidget);
        final prior = f.dispatches.length;
        await tester.pump();
        await tester.pump();
        expect(f.dispatches.length, prior);
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(f.dispatches.last['action'], 'thumbnail');
        expect(f.dispatches.last['page'], 1);
        await tester.drag(find.byType(ListView), const Offset(0, -2000));
        await tester.pump();
        await tester.pump();
        final moved = f.dispatches.lastWhere(
          (d) => d['action'] == 'thumbnailWindow',
        );
        expect(moved['request'], isNot(window['request']));
        expect((moved['pages'] as List).length, lessThanOrEqualTo(12));
        await _readerAction(
          tester,
          () => f.checkedEvent('thumbnail', {
            'request': window['request'],
            'page': 1,
            'data': png,
            'width': 4,
            'height': 2,
          }),
          settle: false,
        );
        expect(f.state.thumbnails.containsKey(1), isFalse);
        expect(f.state.error, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
      }
    },
  );
  test(
    'sidebar preview eviction retains the current visible window while adding nearby pages',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        await f.checkedEvent('metadata', {'pages': 100});
        final png =
            'data:image/png;base64,${base64Encode(image.encodePng(image.Image(width: 4, height: 2)))}';
        Future<void> preview(int page) async {
          await f.checkedEvent('thumbnail', {
            'request': f.dispatches.lastWhere(
              (d) => d['action'] == 'thumbnailWindow',
            )['request'],
            'page': page,
            'data': png,
            'width': 4,
            'height': 2,
          });
        }

        for (var page = 0; page < 32; page++) {
          f.reader.requestThumbnailWindow([page]);
          await preview(page);
        }
        expect(f.state.thumbnails.length, 32);
        f.reader.requestThumbnailWindow([0, 32]);
        await preview(32);
        expect(f.state.thumbnails.keys, containsAll([0, 32]));
        expect(f.state.thumbnails.length, 32);
        expect(f.state.thumbnails.containsKey(1), isFalse);
        expect(f.state.thumbnailPending, isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );
  testWidgets(
    'sidebar annotation filters show protected drafts and deletion never resurrects them',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      late ReadingAnnotation highlight, bookmark;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Saved A');
        highlight = f.reader.annotations.single;
        await f.checkedEvent('location', {
          'anchor': {'page': 0},
          'progress': 0,
        });
        await f.reader.annotation('bookmark', note: 'Bookmark private');
        bookmark = f.reader.annotations.singleWhere(
          (a) => a.kind == 'bookmark',
        );
        gate.fail = true;
        f.notes.edit(highlight, 'Protected B\n${'long ' * 10000}');
        try {
          await f.notes.save(highlight.id);
        } catch (_) {}
        await f.sidebarController.selectPanel(BookSidebarPanel.marks);
      });
      try {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const yaru = MethodChannel('yaru_window');
        const events = EventChannel('yaru_window/events');
        messenger.setMockMethodCallHandler(
          yaru,
          (c) async => c.method == 'state' ? <String, Object?>{} : null,
        );
        messenger.setMockStreamHandler(
          events,
          MockStreamHandler.inline(onListen: (_, sink) {}),
        );
        addTearDown(() {
          messenger.setMockMethodCallHandler(yaru, null);
          messenger.setMockStreamHandler(events, null);
        });
        await tester.pumpWidget(_sidebarApplication(f));
        await tester.pumpAndSettle();
        expect(find.textContaining('Protected B'), findsOneWidget);
        expect(find.text('Saved A'), findsNothing);
        final ui = f.container.read(
          bookSidebarProvider(f.state.bookId!).notifier,
        );
        ui.filter(type: AnnotationTypeFilter.bookmarks);
        await tester.pumpAndSettle();
        expect(find.text('Bookmark private'), findsOneWidget);
        expect(find.textContaining('Protected B'), findsNothing);
        ui.filter(type: AnnotationTypeFilter.highlights, withNotes: true);
        await tester.pumpAndSettle();
        expect(find.textContaining('Protected B'), findsOneWidget);
        final row = find.byKey(ValueKey('annotation-row-${highlight.id}'));
        await tester.tap(
          find.descendant(
            of: row,
            matching: find.byType(BusyBooksHeaderPopupMenuButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        gate.fail = false;
        gate.failDelete = true;
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byType(BusyBooksDialogShell),
                matching: find.text('Delete'),
              )
              .last,
        );
        await _pumpUntil(
          tester,
          () => find.text('Error').evaluate().isNotEmpty,
        );
        expect(f.drafts.drafts.containsKey(highlight.id), isTrue);
        await _closeActionError(tester);
        gate.failDelete = false;
        gate.fail = false;
        await _readerAction(
          tester,
          () => f.container
              .read(workspaceControllerProvider.notifier)
              .deleteAnnotation(highlight.id),
        );
        await _readerAction(tester, f.notes.flush);
        await f.reader.syncAnnotations();
        await tester.pump();
        expect(f.reader.annotations.map((a) => a.id), [bookmark.id]);
        expect(f.drafts.drafts.containsKey(highlight.id), isFalse);
        final saved = await tester.runAsync(
          () => f.store.call('annotations', f.state.bookId),
        );
        expect((saved as List).map((a) => a['id']), [bookmark.id]);
        expect(tester.takeException(), isNull);
      } finally {
        gate.fail = false;
        gate.failDelete = false;
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
      }
    },
  );
  testWidgets(
    'sidebar switching captures rejected local note input before native dismissal',
    (tester) async {
      late _ReaderFixture f;
      late ReadingAnnotation annotation;
      final delivered = <Map>[], rejected = <Map>[];
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Saved A');
        annotation = f.reader.annotations.single;
        await f.openAnnotationPopover(annotation);
      });
      _connectPopover(
        f,
        delivered: delivered,
        rejected: rejected,
        rejectActions: {'noteDraft'},
      );
      try {
        await tester.pumpWidget(const ReaderPopoverApp());
        await _popupUpdate(tester, f.popup);
        await tester.enterText(find.byType(TextField), 'Accepted local B');
        await _pumpUntil(tester, () => rejected.isNotEmpty);
        expect(f.drafts.drafts[annotation.id], isNull);
        await _readerAction(
          tester,
          () => f.sidebarController.selectPanel(BookSidebarPanel.marks),
        );
        expect(f.drafts.effectiveNote(annotation), 'Accepted local B');
        expect(f.sidebar.panel.preference, 'annotations');
        await _readerAction(tester, f.notes.flush);
        expect(
          (await tester.runAsync(
                    () => f.store.call('annotations', f.state.bookId),
                  )
                  as List)
              .single['note'],
          'Accepted local B',
        );
        await _readerAction(
          tester,
          () => f.openAnnotationPopover(f.reader.annotations.single),
        );
        await _popupUpdate(tester, f.popup);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Accepted local B',
        );
        expect(tester.takeException(), isNull);
      } finally {
        f.onNativeCall = null;
        await tester.pumpWidget(const SizedBox());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(readerPopoverChannel, null);
        await _readerAction(tester, f.dispose);
      }
    },
  );
  testWidgets(
    'sidebar Edit Note reveals its selected saved item and preserves later Notebook scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf', speech: _Speech());
        final id = f.state.bookId!;
        for (var i = 0; i < 100; i++) {
          await f.store.call('putAnnotation', {
            'id': 'annotation-target-$i',
            'bookId': id,
            'annotationKind': 'highlight',
            'anchor': {'page': 0, 'y': i / 100},
            'text': 'Saved passage $i',
            'reference': 'Page 1',
            'color': 'yellow',
            'note': 'Private note $i',
            'created': i + 1,
          });
        }
        await f.container
            .read(workspaceControllerProvider.notifier)
            .loadBook(id);
        await f.sidebarController.selectPanel(BookSidebarPanel.marks);
      });
      try {
        await tester.pumpWidget(_sidebarApplication(f, routed: true));
        await tester.pumpAndSettle();
        final row = find.byKey(
          const ValueKey('annotation-row-annotation-target-90'),
        );
        final scrollable = find
            .descendant(
              of: find.byType(ReadingSidebarBody),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          row,
          500,
          scrollable: scrollable,
          maxScrolls: 30,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: row,
            matching: find.byType(BusyBooksHeaderPopupMenuButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit Note'));
        await _pumpUntil(
          tester,
          () => find.byType(NotebookContent).evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        final id = f.state.bookId!, view = f.drafts.view(id);
        expect(view.selected, 'annotation-target-90');
        expect(
          find.byKey(const ValueKey('annotation-target-90')),
          findsOneWidget,
        );
        expect(find.text('Private note 90'), findsWidgets);
        expect(view.revealAnnotation, isNull);
        final before = f.drafts.view(id).scroll;
        expect(f.drafts.view(id).scrollCenter, 'annotation-target-90');
        await tester.drag(
          find.descendant(
            of: find.byType(NotebookContent),
            matching: find.byType(CustomScrollView),
          ),
          const Offset(0, 250),
        );
        await tester.pumpAndSettle();
        final saved = f.drafts.view(id).scroll;
        expect(saved, isNot(before));
        final router = f.container.read(appRouterProvider);
        router.go('/read/$id');
        await tester.pumpAndSettle();
        router.go('/notebook/$id');
        await tester.pumpAndSettle();
        expect(f.drafts.view(id).scroll, closeTo(saved, 1));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
      }
    },
  );
  test(
    'sidebar preferences survive close/reopen while session filters and PDF capabilities do not leak to another book',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        final id = f.state.bookId!;
        await f.checkedEvent('metadata', {
          'toc': [
            {'id': 'g', 'label': 'Group', 'depth': 0},
            {
              'id': 'n',
              'label': 'Child',
              'depth': 1,
              'href': '0',
              'anchor': {'page': 0},
            },
          ],
        });
        f.container.read(bookSidebarProvider(id).notifier).toggle('g');
        await f.sidebarController.selectPanel(BookSidebarPanel.marks);
        f.container
            .read(bookSidebarProvider(id).notifier)
            .filter(type: AnnotationTypeFilter.bookmarks, withNotes: true);
        final session = f.container.read(bookSidebarProvider(id).notifier);
        final router = f.container.read(appRouterProvider);
        for (final route in ['/notebook/$id', '/read/$id']) {
          router.go(route);
          await f.container.pump();
          expect(
            f.container.read(bookSidebarProvider(id).notifier),
            same(session),
          );
          expect(f.sidebar.filter, AnnotationTypeFilter.bookmarks);
          expect(f.sidebar.withNotes, isTrue);
          expect(f.sidebar.expanded, isEmpty);
        }
        final workspace = f.container.read(
          workspaceControllerProvider.notifier,
        );
        final other = await workspace.openPath(
          p.absolute('test/fixtures/fixed-layout.epub'),
        );
        await f.reader.open(other.books.single.id);
        await f.checkedEvent('ready');
        await f.checkedEvent('opened');
        expect(
          f.sidebarController.available(BookSidebarPanel.thumbnails),
          isFalse,
        );
        await f.sidebarController.selectPanel(BookSidebarPanel.thumbnails);
        expect(f.sidebar.panel.preference, isNot('thumbnails'));
        expect(
          f.container.read(bookSidebarProvider(f.state.bookId!)).filter,
          AnnotationTypeFilter.all,
        );
        await f.reader.close();
        await workspace.loadBook(id, activate: true);
        await f.reader.open(id);
        await f.checkedEvent('ready');
        await f.checkedEvent('opened');
        expect(f.sidebar.panel.preference, 'annotations');
        // The old session was replaced and closed. Only saved application
        // preferences survive. Transient presentation state and subscriptions
        // belong to the active book session, rather than every visited book.
        expect(
          f.container.read(bookSidebarProvider(id)).filter,
          AnnotationTypeFilter.all,
        );
        expect(f.container.read(bookSidebarProvider(id)).withNotes, isFalse);
        expect(f.container.read(bookSidebarProvider(id)).expanded, {'g'});
        await workspace.createCollection('Collection context');
        await workspace.addBooks([p.absolute('test/fixtures/text.pdf')]);
        expect(f.sidebarController.available(BookSidebarPanel.books), isTrue);
      } finally {
        await f.dispose();
      }
    },
  );

  testWidgets(
    'publication sidebar uses the reference selector and expandable destination tree',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
        await f.event('metadata', {
          'pages': 3,
          'labels': ['i', '67', '68'],
          'fixed': true,
          'toc': [
            {
              'id': 'outline:0',
              'label': 'Front matter',
              'depth': 0,
              'href': '',
            },
            {
              'id': 'outline:0.0',
              'label': 'Contents',
              'depth': 1,
              'href': '1',
              'anchor': {
                'page': 1,
                'point': [0, 700],
              },
            },
            {
              'id': 'outline:0.1',
              'label': 'Contents',
              'depth': 1,
              'href': '1',
              'anchor': {
                'page': 1,
                'point': [0, 300],
              },
            },
          ],
        });
        f.sidebarController.selectPanel(BookSidebarPanel.outline);
      });
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: MaterialApp(
              theme: buildBusyBooksTheme(
                brightness: Brightness.light,
                accentColor: const Color(0xff3584e4),
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: BookWorkspaceScreen(
                view: BookView.reading,
                id: f.state.bookId!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Contents'), findsNWidgets(2));
        final tree = find.byKey(ValueKey('outline-tree-${f.state.bookId}'));
        expect(
          find.descendant(of: tree, matching: find.byIcon(BusyBooksGlyphs.tag)),
          findsNothing,
        );
        final groupTitle = find.descendant(
          of: find.byKey(const ValueKey('outline-row-outline:0')),
          matching: find.text('Front matter'),
        );
        final childTitle = find.descendant(
          of: find.byKey(const ValueKey('outline-row-outline:0.0')),
          matching: find.text('Contents'),
        );
        expect(
          tester.getRect(childTitle).left - tester.getRect(groupTitle).left,
          BusyBooksSizes.sidebarTreeDepthIndent,
        );
        final childText = tester.widget<Text>(childTitle);
        expect(childText.maxLines, 1);
        expect(childText.overflow, TextOverflow.ellipsis);
        final before = f.dispatches.where((c) => c['action'] == 'goto').length;
        final disclosure = find.byKey(
          const ValueKey('outline-disclosure-outline:0'),
        );
        expect(disclosure, findsOneWidget);
        await tester.tap(disclosure);
        await tester.pumpAndSettle();
        expect(find.text('Contents'), findsNothing);
        expect(f.dispatches.where((c) => c['action'] == 'goto').length, before);
        await _readerAction(
          tester,
          () => f.event('location', {
            'tocId': 'outline:0.1',
            'anchor': {
              'page': 1,
              'point': [0, 250],
            },
          }),
        );
        expect(find.text('Contents'), findsNothing);
        await tester.tap(disclosure);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('outline-row-outline:0.1')));
        await _pumpUntil(
          tester,
          () =>
              f.dispatches.where((d) => d['action'] == 'goto').length > before,
        );
        expect(f.dispatches.lastWhere((c) => c['action'] == 'goto')['anchor'], {
          'page': 1,
          'point': [0, 300],
        });
        final menu = find.byKey(const ValueKey('reader-sidebar-view-menu'));
        expect(menu, findsOneWidget);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Outline'), findsOneWidget);
        expect(find.text('Thumbnails'), findsOneWidget);
        expect(find.text('Books'), findsNothing);
        await tester.tap(find.text('Outline'));
        await tester.pumpAndSettle();
        expect((f.sidebar.open || f.search.active), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
      }
    },
  );
  for (final origin in [
    'individual',
    'collection-book',
    'notebook',
    'collection',
  ]) {
    testWidgets(
      'home header real application returns $origin to Home without changing reading data',
      (tester) async {
        late _ReaderFixture f;
        String? collectionId;
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create(
            'text.pdf',
            windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          );
          await f.checkedEvent('location', {
            'anchor': {'page': 0, 'y': .25},
            'progress': .25,
          });
          await f.reader.annotation(
            'bookmark',
            note: 'Preserved personal note',
          );
          await f.reader.flush();
          if (origin.startsWith('collection')) {
            final workspace = f.container.read(
              workspaceControllerProvider.notifier,
            );
            await workspace.createCollection('Home navigation fixture');
            await workspace.addBooks([f.reader.book!.path]);
            collectionId = f.container
                .read(workspaceControllerProvider)
                .workspace!
                .id;
          }
        });
        final id = f.state.bookId!;
        final annotation = f.reader.annotations.single;
        final route = origin == 'collection'
            ? '/workspace'
            : origin == 'notebook'
            ? '/notebook/$id'
            : '/read/$id';
        try {
          await _mountHeaderApplication(tester, f, route);
          final home = _headerButton('Home');
          expect(home, findsOneWidget);
          expect(
            tester.widget<BusyBooksHeaderIconButton>(home).icon,
            BusyBooksGlyphs.home,
          );
          expect(
            find.descendant(
              of: home,
              matching: find.byIcon(BusyBooksGlyphs.home),
            ),
            findsOneWidget,
          );
          expect(BusyBooksLinuxHeaderIcon.home.gtkNames, ['go-home-symbolic']);
          if (route.startsWith('/read/')) {
            final sidebar = find.byKey(const ValueKey('book-sidebar-toggle'));
            final previous = find.byKey(const ValueKey('reader-previous'));
            final next = find.byKey(const ValueKey('reader-next'));
            final location = find.byKey(const ValueKey('reader-location'));
            final order = [sidebar, home, previous, location, next];
            for (var i = 1; i < order.length; i++) {
              expect(
                tester.getRect(order[i]).left -
                    tester.getRect(order[i - 1]).right,
                BusyBooksSpacing.headerInset,
              );
            }
            expect(find.byIcon(BusyBooksGlyphs.back), findsOneWidget);
            expect(
              find.descendant(
                of: previous,
                matching: find.byIcon(BusyBooksGlyphs.back),
              ),
              findsOneWidget,
            );
            final leading = find
                .ancestor(
                  of: location,
                  matching: find.byType(BusyBooksLinuxHeaderControlGroup),
                )
                .first;
            expect(
              tester
                  .widget<BusyBooksLinuxHeaderControlGroup>(leading)
                  .children
                  .length,
              5,
            );
          } else {
            expect(find.byKey(const ValueKey('reader-previous')), findsNothing);
            expect(find.byKey(const ValueKey('reader-next')), findsNothing);
          }
          await tester.tap(home);
          final router = f.container.read(appRouterProvider);
          await _pumpUntil(
            tester,
            () => router.routeInformationProvider.value.uri.path == '/',
          );
          expect(_headerButton('Home'), findsNothing);
          for (final action in [
            'Open Book',
            'Create Collection',
            'Open Collection',
          ]) {
            expect(find.text(action), findsWidgets);
          }
          expect(find.text('Recent'), findsOneWidget);
          expect(
            f.container.read(workspaceControllerProvider).workspace,
            isNull,
          );
          await _readerAction(tester, () async {
            final book = await f.store.call('book', id) as Map;
            expect(book['anchor'], {'page': 0, 'y': .25});
            final records = await f.store.call('annotations', id) as List;
            expect(records.single['id'], annotation.id);
            expect(records.single['note'], 'Preserved personal note');
            if (collectionId != null) {
              final saved =
                  await f.store.call('openCollection', {
                        'id': collectionId,
                        'recordRecent': false,
                      })
                      as Map;
              expect((saved['books'] as List).single['id'], id);
            }
            expect(
              (await f.store.call('snapshot') as Map)['recent'],
              isNotEmpty,
            );
          });
          expect(tester.takeException(), isNull);
        } finally {
          await _disposeHeaderApplication(tester, f);
        }
      },
    );
  }
  for (final fails in [false, true]) {
    testWidgets(
      'home header pending note ${fails ? 'failure and retry' : 'success'} protects input and repeated navigation',
      (tester) async {
        late _ReaderFixture f;
        late AnnotationStoreGate gate;
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create(
            'text.pdf',
            windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
            wrapStore: (s) => gate = AnnotationStoreGate(s),
          );
          await f.checkedEvent('location', {
            'anchor': {'page': 0},
          });
          await f.reader.annotation('bookmark', note: 'Saved baseline');
        });
        final id = f.state.bookId!, annotation = f.reader.annotations.single;
        try {
          await _mountHeaderApplication(tester, f, '/read/$id');
          gate.entered = Completer<void>();
          gate.proceed = Completer<void>();
          gate.failAfterProceed = fails;
          await _readerAction(tester, () async {
            f.notes.edit(annotation, 'Protected newest note');
            unawaited(f.notes.save(annotation.id).catchError((Object _) {}));
          });
          await _pumpUntil(tester, () => gate.entered!.isCompleted);
          final closeCount = f.calls.where((c) => c.method == 'close').length;
          final action = tester
              .widget<BusyBooksHeaderIconButton>(_headerButton('Home'))
              .onPressed!;
          action();
          action();
          await tester.pump();
          final router = f.container.read(appRouterProvider);
          expect(router.routeInformationProvider.value.uri.path, '/read/$id');
          expect(f.drafts.drafts[annotation.id]!.text, 'Protected newest note');
          gate.proceed!.complete();
          if (fails) {
            await _pumpUntil(
              tester,
              () => find.text('Error').evaluate().isNotEmpty,
            );
            expect(router.routeInformationProvider.value.uri.path, '/read/$id');
            expect(
              f.drafts.drafts[annotation.id]!.text,
              'Protected newest note',
            );
            await _closeActionError(tester);
            await tester.pumpAndSettle();
            expect(find.text('Error'), findsNothing);
            gate.failAfterProceed = false;
            await tester.tap(_headerButton('Home'));
          }
          await _pumpUntil(
            tester,
            () => router.routeInformationProvider.value.uri.path == '/',
          );
          await _readerAction(
            tester,
            () => f.container
                .read(workspaceControllerProvider.notifier)
                .navigate(() async {}),
          );
          expect(
            f.calls.where((c) => c.method == 'close').length - closeCount,
            1,
          );
          await _readerAction(tester, () async {
            final records = await f.store.call('annotations', id) as List;
            expect(records.length, 1);
            expect(records.single['note'], 'Protected newest note');
          });
          expect(f.drafts.drafts, isEmpty);
        } finally {
          if (gate.proceed != null && !gate.proceed!.isCompleted) {
            gate.proceed!.complete();
          }
          gate.failAfterProceed = false;
          await _disposeHeaderApplication(tester, f);
        }
      },
    );
  }
  for (final mode in [
    'printed PDF',
    'Roman PDF',
    'unlabelled PDF',
    'empty-label PDF',
    'reflowable EPUB',
    'fixed EPUB',
  ]) {
    testWidgets(
      'home header compact location and live Go To anchor for $mode',
      (tester) async {
        late _ReaderFixture f;
        final pdf = mode.endsWith('PDF');
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create(
            pdf
                ? 'text.pdf'
                : mode.startsWith('fixed')
                ? 'fixed-layout.epub'
                : 'reflowable.epub',
            windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          );
          await f.checkedEvent('metadata', {
            'pages': mode == 'printed PDF' ? 322 : 3,
            'labels': mode == 'printed PDF'
                ? List.generate(322, (i) => '${i - 25}')
                : mode == 'Roman PDF'
                ? ['i', 'ii', '1']
                : mode == 'empty-label PDF'
                ? ['', '', '']
                : <String>[],
            'fixed': mode != 'reflowable EPUB',
          });
          await f.checkedEvent('location', {
            'anchor': pdf
                ? {'page': mode == 'printed PDF' ? 48 : 1}
                : {'cfi': 'epubcfi(/6/2!/4/2/1:0)'},
            'progress': .42,
            if (mode == 'fixed EPUB') 'printPage': '23',
          });
        });
        try {
          await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
          final location = find.byKey(const ValueKey('reader-location'));
          final label = switch (mode) {
            'printed PDF' => '23',
            'Roman PDF' => 'ii',
            'unlabelled PDF' || 'empty-label PDF' => '2',
            'fixed EPUB' => '23',
            _ => '42%',
          };
          expect(
            find.descendant(of: location, matching: find.text(label)),
            findsOneWidget,
          );
          expect(tester.getSize(location).width, lessThanOrEqualTo(132));
          if (mode == 'printed PDF') {
            expect(find.text('Page 23'), findsNothing);
            expect(
              find.bySemanticsLabel(
                RegExp(
                  RegExp.escape(
                    'Go to Location · Page 23 · Physical page 49 / 322',
                  ),
                ),
              ),
              findsOneWidget,
            );
            expect(find.byTooltip('Go to Location'), findsOneWidget);
          }
          final anchor = f.state.location;
          for (final width in [1200.0, 1000.0]) {
            tester.view.physicalSize = Size(width, 850);
            await tester.pumpAndSettle();
            final bounds = tester.getRect(location);
            await tester.tap(location);
            await _pumpUntil(
              tester,
              () =>
                  f.calls.where((c) => c.method == 'popover').isNotEmpty &&
                  f.popup['x'] == bounds.left,
            );
            expect(f.popup['kind'], 'goto');
            expect(f.popup['x'], closeTo(bounds.left, .01));
            expect(f.popup['y'], closeTo(bounds.top, .01));
            expect(f.popup['location'], anchor);
            await _readerAction(tester, f.reader.dismissPopover);
            expect(f.state.location, anchor);
          }
          await _readerAction(
            tester,
            () => f.checkedEvent('navigation', {
              'previous': false,
              'next': true,
              'back': true,
            }),
          );
          final previous = find.byKey(const ValueKey('reader-previous'));
          expect(
            tester.widget<BusyBooksLinuxHeaderIconButton>(previous).onPressed,
            isNull,
          );
          expect(
            tester
                .widget<BusyBooksLinuxHeaderIconButton>(
                  find.byKey(const ValueKey('reader-next')),
                )
                .onPressed,
            isNotNull,
          );
          expect(f.state.navigation['back'], true);
          expect(tester.takeException(), isNull);
        } finally {
          await _disposeHeaderApplication(tester, f);
        }
      },
    );
  }

  testWidgets(
    'home header places compact location between page controls independently of history',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
        await f.event('metadata', {
          'pages': 322,
          'labels': List.generate(322, (i) => '${i - 25}'),
          'fixed': true,
        });
        await f.event('navigation', {
          'previous': true,
          'next': true,
          'back': true,
        });
        await f.event('location', {
          'anchor': {'page': 280},
          'progress': .87,
        });
      });
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: MaterialApp(
              theme: buildBusyBooksTheme(
                brightness: Brightness.light,
                accentColor: const Color(0xff3584e4),
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: BusyBooksCommandRegistryScope(
                registry: BusyBooksCommandCatalog.create(
                  executions: {
                    BusyBooksCommandIds.previous: () =>
                        f.reader.send('previous'),
                    BusyBooksCommandIds.next: () => f.reader.send('next'),
                  },
                ),
                child: BookWorkspaceScreen(
                  view: BookView.reading,
                  id: f.state.bookId!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final previous = find.byKey(const ValueKey('reader-previous'));
        final next = find.byKey(const ValueKey('reader-next'));
        final location = find.byKey(const ValueKey('reader-location'));
        expect(previous, findsOneWidget);
        expect(next, findsOneWidget);
        expect(
          tester.widget<BusyBooksLinuxHeaderIconButton>(previous).nativeIcon,
          BusyBooksLinuxHeaderIcon.previous,
        );
        expect(
          tester.widget<BusyBooksLinuxHeaderIconButton>(next).nativeIcon,
          BusyBooksLinuxHeaderIcon.next,
        );
        expect(
          tester.widget<BusyBooksLinuxHeaderIconButton>(previous).icon,
          BusyBooksGlyphs.headerBackFor(TextDirection.ltr),
        );
        expect(BusyBooksLinuxHeaderIcon.previous.gtkNames, [
          'go-previous-symbolic',
        ]);
        expect(BusyBooksLinuxHeaderIcon.next.gtkNames, ['go-next-symbolic']);
        expect(BusyBooksLinuxHeaderIcon.previous.directionSensitive, isTrue);
        expect(BusyBooksLinuxHeaderIcon.next.directionSensitive, isTrue);
        expect(
          tester.getSize(previous),
          Size.square(BusyBooksSizes.iconButton),
        );
        expect(find.text('255'), findsOneWidget);
        expect(find.text('Page 255'), findsNothing);
        final home = find.byKey(const ValueKey('book-home'));
        expect(home, findsOneWidget);
        expect(
          tester.getRect(home).right,
          lessThan(tester.getRect(previous).left),
        );
        expect(f.reader.viewport.bottom, closeTo(850, 1));
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(f.dispatches.last['action'], 'next');
        await _readerAction(
          tester,
          () => f.event('navigation', {'previous': false, 'next': false}),
        );
        expect(
          tester.widget<BusyBooksLinuxHeaderIconButton>(previous).onPressed,
          isNull,
        );
        expect(
          tester.widget<BusyBooksLinuxHeaderIconButton>(next).onPressed,
          isNull,
        );

        expect(
          tester.getRect(location).left - tester.getRect(previous).right,
          BusyBooksSpacing.headerInset,
        );
        expect(
          tester.getRect(next).left - tester.getRect(location).right,
          BusyBooksSpacing.headerInset,
        );
        expect(tester.getRect(previous).top, tester.getRect(next).top);
        expect(tester.getRect(previous).top, lessThan(70));
        expect(tester.getRect(location).width, lessThanOrEqualTo(132));
        expect(find.text('281 / 322'), findsNothing);
        expect(
          find.bySemanticsLabel(
            RegExp(
              RegExp.escape(
                'Go to Location · Page 255 · Physical page 281 / 322',
              ),
            ),
          ),
          findsOneWidget,
        );
        expect(find.byTooltip('Go to Location'), findsOneWidget);
        tester.view.physicalSize = const Size(640, 850);
        await tester.pumpAndSettle();
        expect(previous, findsOneWidget);
        expect(next, findsOneWidget);
        expect(find.byKey(const ValueKey('book-home')), findsOneWidget);
        if (location.evaluate().isNotEmpty) {
          expect(
            tester.getRect(location).left - tester.getRect(previous).right,
            BusyBooksSpacing.headerInset,
          );
          expect(
            tester.getRect(next).left - tester.getRect(location).right,
            BusyBooksSpacing.headerInset,
          );
        } else {
          expect(
            tester.getRect(next).left - tester.getRect(previous).right,
            BusyBooksSpacing.headerInset,
          );
        }
        tester.view.physicalSize = const Size(480, 850);
        await tester.pumpAndSettle();
        expect(location, findsNothing);
        expect(find.byKey(const ValueKey('book-home')), findsOneWidget);
        expect(
          tester.getRect(next).left - tester.getRect(previous).right,
          BusyBooksSpacing.headerInset,
        );
        f.searchController.open(category: BookSearchCategory.bookText);
        await tester.pumpAndSettle();
        expect(previous, findsNothing);
        expect(next, findsNothing);
        expect(
          find.byKey(const ValueKey('book-header-search')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
      }
    },
  );
  testWidgets(
    'Go To native contract waits for payload paint and raster readiness and ignores replaced frames',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
        await f.event('metadata', {
          'pages': 3,
          'labels': ['i', 'ii', '1'],
          'fixed': true,
        });
      });
      final gate = _PresentationGate()..allowReady = false;
      _connectPopover(f, presentation: gate);
      await tester.pumpWidget(const ReaderPopoverApp());
      var finished = false;
      final opening = f.reader.showPopover('goto').then((_) => finished = true);
      await _pumpUntil(tester, () => gate.payload != null);
      expect(finished, isFalse);
      expect(find.byType(TextField), findsNothing);
      gate.allowReady = true;
      gate.ready();
      await tester.pumpAndSettle();
      expect(find.text('Go'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(finished, isFalse);
      expect(gate.visible, isEmpty);
      gate.frame.complete();
      await _pumpUntil(tester, () => finished);
      await opening;
      expect(gate.visible, [f.popup['presentation']]);
      final old = Map<String, dynamic>.from(f.popup);
      gate.frame = Completer<void>();
      var replaced = false;
      final next = f.reader
          .showPopover(
            'speech',
            extra: const {
              'voices': [''],
              'voice': '',
              'speed': 1,
            },
          )
          .then((_) => replaced = true);
      await _pumpUntil(tester, () => gate.payload?['kind'] == 'speech');
      gate.painted(old);
      expect(replaced, isFalse);
      gate.frame.complete();
      await _pumpUntil(tester, () => replaced);
      await next;
      expect(find.text('Voice and Speed'), findsOneWidget);
      await _readerAction(tester, f.reader.dismissPopover);
      expect(f.state.popoverError, isNull);
      await tester.pumpWidget(const SizedBox());
      await _readerAction(tester, f.dispose);
    },
  );
  testWidgets(
    'Go To reports a child build failure to the primary and retries without a fatal book error',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
        await f.event('metadata', {
          'pages': 3,
          'labels': ['i', 'ii', '1'],
          'fixed': true,
        });
      });
      final gate = _PresentationGate()..overrides = {'toc': 7};
      _connectPopover(f, presentation: gate);
      await tester.pumpWidget(const ReaderPopoverApp());
      var done = false;
      final request = f.reader.showPopover('goto').then((_) => done = true);
      await _pumpUntil(tester, () => done);
      await request;
      expect(tester.takeException(), isNotNull);
      expect(f.state.popoverError, isNotNull);
      expect(f.state.ready, isTrue);
      expect(f.state.error, isNull);
      expect(gate.visible, isEmpty);
      gate.overrides = {};
      gate.frame.complete();
      await _readerAction(tester, f.reader.retryPopover, widgetClock: true);
      expect(f.state.popoverError, isNull);
      expect(find.text('Go'), findsOneWidget);
      await _readerAction(tester, f.reader.dismissPopover, widgetClock: true);
      await tester.pumpWidget(const SizedBox());
      await _readerAction(tester, f.dispose);
    },
  );
  testWidgets(
    'Go To keeps the form on navigation failure and closes only on a successful correlated result',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
        await f.event('metadata', {
          'pages': 3,
          'labels': ['i', 'ii', '1'],
          'fixed': true,
        });
      });
      final gate = _PresentationGate();
      gate.frame.complete();
      _connectPopover(f, presentation: gate);
      await tester.pumpWidget(const ReaderPopoverApp());
      await _readerAction(
        tester,
        () => f.reader.showPopover('goto'),
        widgetClock: true,
      );
      var fail = true;
      f.onDispatch = (command) async {
        if (command['action'] == 'goto') {
          await f.checkedEvent('navigationResult', {
            'request': command['request'],
            if (fail) 'message': 'Injected page failure',
          });
        }
      };
      final prior = f.popup['presentation'];
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.text('Go'));
      await _pumpUntil(
        tester,
        () =>
            find.textContaining('Injected page failure').evaluate().isNotEmpty,
      );
      expect(f.popup['presentation'], prior);
      expect(gate.payload, isNotNull);
      fail = false;
      await tester.tap(find.text('Go'));
      await _pumpUntil(tester, () => gate.payload == null);
      expect(f.state.error, isNull);
      await _readerAction(tester, f.reader.dismissPopover, widgetClock: true);
      await tester.pumpWidget(const SizedBox());
      await _readerAction(tester, f.dispose);
    },
  );
  testWidgets(
    'Go To cancellation before ready and a late stale frame cannot reveal a replaced presentation',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
      });
      final gate = _PresentationGate()..allowReady = false;
      _connectPopover(f, presentation: gate);
      await tester.pumpWidget(const ReaderPopoverApp());
      var done = false;
      final opening = f.reader.showPopover('goto').then((_) => done = true);
      await _pumpUntil(tester, () => gate.payload != null);
      final old = Map<String, dynamic>.from(gate.payload!);
      await _readerAction(tester, f.reader.dismissPopover, widgetClock: true);
      await _pumpUntil(tester, () => done);
      await opening;
      gate.allowReady = true;
      gate.ready();
      gate.painted(old);
      gate.frame.complete();
      await tester.pumpAndSettle();
      expect(gate.visible, isEmpty);
      expect(f.state.popoverError, isNull);
      await _readerAction(
        tester,
        () => f.reader.showPopover('goto'),
        widgetClock: true,
      );
      expect(gate.visible, [f.popup['presentation']]);
      expect(f.popup['presentation'], isNot(old['presentation']));
      await _readerAction(tester, f.reader.dismissPopover, widgetClock: true);
      await tester.pumpWidget(const SizedBox());
      await _readerAction(tester, f.dispose);
    },
  );
  testWidgets(
    'Go To presentation timeout retains a primary retry and rejects the late frame',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
      });
      final gate = _PresentationGate();
      _connectPopover(f, presentation: gate);
      await tester.pumpWidget(const ReaderPopoverApp());
      var done = false;
      final opening = f.reader.showPopover('goto').then((_) => done = true);
      await _pumpUntil(tester, () => gate.payload != null);
      final old = Map<String, dynamic>.from(gate.payload!);
      await tester.pump(const Duration(seconds: 18));
      await _pumpUntil(tester, () => done);
      await opening;
      expect(f.state.popoverError, isNotNull);
      expect(f.state.ready, isTrue);
      gate.painted(old);
      gate.frame.complete();
      await tester.pumpAndSettle();
      expect(gate.visible, isEmpty);
      await _readerAction(tester, f.reader.retryPopover, widgetClock: true);
      expect(f.state.popoverError, isNull);
      expect(gate.visible, [f.popup['presentation']]);
      await _readerAction(tester, f.reader.dismissPopover, widgetClock: true);
      await tester.pumpWidget(const SizedBox());
      await _readerAction(tester, f.dispose);
    },
  );
  testWidgets(
    'Go To retry waits for error-banner geometry before asking the native host to present',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
      });
      Completer<void>? pending;
      var first = true, cancelledByBounds = false;
      f.onNativeCall = (call) async {
        if (call.method == 'popover') {
          if (first) {
            first = false;
            throw PlatformException(code: 'popover-unavailable');
          }
          pending = Completer<void>();
          return pending!.future;
        }
        // Matches both production reader hosts: geometry updates dismiss controls.
        if (call.method == 'bounds' &&
            pending != null &&
            !pending!.isCompleted) {
          cancelledByBounds = true;
          pending!.completeError(PlatformException(code: 'popover-cancelled'));
        }
        return;
      };
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: MaterialApp(
            theme: buildBusyBooksTheme(
              brightness: Brightness.light,
              accentColor: const Color(0xff3584e4),
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: BookWorkspaceScreen(
              view: BookView.reading,
              id: f.state.bookId!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _readerAction(
        tester,
        () => f.reader.showPopover('goto'),
        widgetClock: true,
      );
      expect(f.state.popoverError, isNotNull);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await _pumpUntil(tester, () => pending != null);
      await tester.pumpAndSettle();
      expect(
        cancelledByBounds,
        isFalse,
        reason: 'Banner removal must settle before the new native request',
      );
      final calls = f.calls.map((c) => c.method).toList();
      expect(
        calls.lastIndexOf('bounds'),
        lessThan(calls.lastIndexOf('popover')),
      );
      pending!.complete();
      await _readerAction(tester, f.reader.dismissPopover, widgetClock: true);
      await tester.pumpWidget(const SizedBox());
      await _readerAction(tester, f.dispose);
    },
  );
  test(
    'hundreds of annotations reopen through bounded commands after store restart',
    () async {
      var f = await _ReaderFixture.create('text.pdf', initialize: false);
      var disposed = false;
      final directory = f.directory;
      try {
        final workspace = f.container.read(
          workspaceControllerProvider.notifier,
        );
        for (var i = 0; i < 400; i++) {
          await workspace.saveAnnotation(
            ReadingAnnotation({
              'id': 'annotation-batch-$i',
              'kind': 'annotation',
              'bookId': f.state.bookId!,
              'annotationKind': 'highlight',
              'anchor': {
                'page': 0,
                'segments': [
                  {
                    'page': 0,
                    'start': i,
                    'text': 'passage $i',
                    'boxes': [
                      [10.0, 20.0, 30.0, 40.0],
                    ],
                  },
                ],
              },
              'text': 'Saved quotation $i ${'漢' * 1200}',
              'reference': 'Page 1',
              'note': 'Private $i',
              'color': 'yellow',
              'created': i,
            }),
          );
        }
        final expected = [
          for (final a in f.reader.annotations) {...a.data}..remove('note'),
        ];
        expect(utf8.encode(jsonEncode(expected)).length, greaterThan(1048576));
        await f.dispose(deleteDirectory: false);
        disposed = true;
        f = await _ReaderFixture.create(
          'text.pdf',
          profileDirectory: directory,
          initialize: false,
        );
        disposed = false;
        await f.finishColdOpen();
        final messages = f.acceptedDispatches
            .where(
              (m) => m['action'] == 'annotations' && m['session'] == f.session,
            )
            .toList();
        expect(messages.length, greaterThan(1));
        expect(messages.last['complete'], isTrue);
        expect(
          jsonDecode(messages.map((m) => m['chunk'] as String).join()),
          expected,
        );
        expect(
          f.acceptedDispatches
              .lastWhere((m) => m['action'] == 'open')
              .containsKey('annotations'),
          isFalse,
        );
        expect(f.dispatchFailures, 0);
        expect(f.reader.annotations.length, 400);
        expect(
          (await f.store.call('annotations', f.state.bookId) as List).length,
          400,
        );
        await f.reader.syncAnnotations();
        expect(f.dispatchFailures, 0);
      } finally {
        if (!disposed) {
          await f.dispose();
        } else if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );
  for (final format in ['epub', 'pdf']) {
    final fixture = format == 'pdf' ? 'text.pdf' : 'reflowable.epub';
    for (final restart in ['reader close', 'fresh controllers and store']) {
      for (final content in ['escaped', 'combined ASCII', 'multibyte']) {
        testWidgets(
          'cold open $format after $restart retains $content private notes',
          (tester) async {
            tester.view.physicalSize = const Size(1100, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            late _ReaderFixture f;
            await _readerAction(tester, () async {
              f = await _ReaderFixture.create(fixture);
              final workspace = f.container.read(
                workspaceControllerProvider.notifier,
              );
              for (var i = 0; i < (content == 'combined ASCII' ? 18 : 1); i++) {
                final note = switch (content) {
                  'combined ASCII' => '${'A' * 60000} private $i',
                  'multibyte' => _transportNote('multibyte') * 6,
                  _ => _transportNote('escaped'),
                };
                expectSync(validAnnotationText(note), isTrue);
                await workspace.saveAnnotation(
                  ReadingAnnotation({
                    'id': 'annotation-cold-$i',
                    'kind': 'annotation',
                    'bookId': f.state.bookId!,
                    'annotationKind': i.isOdd ? 'bookmark' : 'highlight',
                    'anchor': format == 'epub'
                        ? {'cfi': 'epubcfi(/6/2!/4/2/1:${i + 1})', 'index': 0}
                        : {
                            'page': 0,
                            'textOffset': i,
                            'textLength': 3,
                            'segments': [
                              {
                                'page': 0,
                                'start': i,
                                'text': 'ABC',
                                'boxes': [
                                  [10.0, 10.0, 30.0, 20.0],
                                ],
                              },
                            ],
                          },
                    'text': i.isOdd ? '' : 'Saved passage $i',
                    'reference': format == 'epub' ? 'Chapter 1' : 'Page 1',
                    'note': note,
                    'color': i.isOdd ? 'blue' : 'yellow',
                    'created': i,
                  }),
                );
              }
            });
            final expected = f.reader.annotations.toList();
            final retained = [for (final a in expected) jsonEncode(a.data)];
            // The notes alone exceed the complete ordinary dispatch budget.
            // The real native-contract mock below must accept the projected open.
            expect(
              utf8
                  .encode(
                    jsonEncode({
                      'annotations': expected.map((a) => a.data).toList(),
                    }),
                  )
                  .length,
              greaterThan(1048576),
            );
            final directory = f.directory;
            var disposed = false;
            try {
              await _readerAction(tester, () async {
                final id = f.state.bookId!;
                final oldSession = f.session;
                if (restart == 'reader close') {
                  await f.reader.close();
                  expectSync(f.state.bookId, isNull);
                  expectSync(f.calls.last.method, 'close');
                  await f.reader.open(id);
                } else {
                  await f.dispose(deleteDirectory: false);
                  disposed = true;
                  f = await _ReaderFixture.create(
                    fixture,
                    profileDirectory: directory,
                    initialize: false,
                  );
                  disposed = false;
                }
                expectSync(f.session, isNot(oldSession));
                await f.finishColdOpen();
                _expectRendererCopy(
                  f.acceptedDispatches.lastWhere((m) => m['action'] == 'open'),
                  expected,
                );
                expectSync([
                  for (final a in expected) jsonEncode(a.data),
                ], retained);
                // Exercise the renderer's actual highlight interaction route:
                // EPUB resolves its CFI, PDF sends the drawn mark's stable ID.
                final request = f.reader.events.stream.firstWhere(
                  (e) => e['type'] == 'selectionMenu',
                );
                await f.checkedEvent(
                  'annotation',
                  format == 'epub'
                      ? {'cfi': expected.first.anchor['cfi']}
                      : {'id': expected.first.id},
                );
                final target =
                    (await request)['target'] as ReaderSelectionTarget;
                expectSync(target.annotationId, expected.first.id);
                expectSync(
                  f.reader.selectionAnnotation(target)!.note,
                  expected.first.note,
                );
                expectSync(target.passage!.containsKey('note'), false);
                final owner = (await f.reader.prepareSelectionMenu(
                  target,
                  dismiss: () async {},
                ))!;
                await f.reader.selectionMenuAction(
                  owner,
                  ReaderSelectionAction.addNote,
                );
                f.notes.revealAnnotation(id, expected.first.id);
              });
              await tester.pumpWidget(
                UncontrolledProviderScope(
                  container: f.container,
                  child: MaterialApp(
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    home: Scaffold(
                      body: NotebookContent(id: f.state.bookId!, active: true),
                    ),
                  ),
                ),
              );
              await _pumpUntil(
                tester,
                () => find.byType(TextField).evaluate().isNotEmpty,
              );
              expect(
                tester
                    .widget<TextField>(find.byType(TextField))
                    .controller!
                    .text,
                expected.first.note,
              );
              final edited = '${expected.first.note}\nEdited after cold open';
              await tester.enterText(find.byType(TextField), edited);
              await _readerAction(tester, f.notes.flush);
              await _pumpUntil(
                tester,
                () =>
                    f.drafts.drafts.isEmpty &&
                    f.reader.annotations.first.note == edited,
              );
              expect(expected.first.note, isNot(edited));
              expect([for (final a in expected) jsonEncode(a.data)], retained);
              final current = [
                expected.first.copy({'note': edited}),
                ...expected.skip(1),
              ];
              await tester.pumpWidget(const SizedBox.shrink());
              f.onNativeCall = null;
              await _readerAction(tester, () async {
                await f.reader.syncAnnotations();
                final updates = f.acceptedDispatches.where(
                  (m) => m['action'] == 'annotations',
                );
                expectSync(updates, isNotEmpty);
                _expectRendererCopy(updates.last, current);
                expectSync(f.rejectedDispatches, isEmpty);
                f.notes.revealAnnotation(f.state.bookId!, expected.first.id);
              });
              await tester.pumpWidget(
                UncontrolledProviderScope(
                  container: f.container,
                  child: MaterialApp(
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    home: BookWorkspaceScreen(
                      view: BookView.notebook,
                      id: f.state.bookId!,
                    ),
                  ),
                ),
              );
              await _pumpUntil(
                tester,
                () => find.byType(TextField).evaluate().isNotEmpty,
              );
              expect(
                tester
                    .widget<TextField>(find.byType(TextField))
                    .controller!
                    .text,
                edited,
              );
              expect(find.text('Saved passage 0'), findsOneWidget);
              await _readerAction(tester, () => _verifyColdNotes(f, current));
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              f.onNativeCall = null;
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                  .setMockMethodCallHandler(readerPopoverChannel, null);
              if (!disposed) {
                await _readerAction(tester, f.dispose);
              } else {
                await tester.runAsync(() => directory.delete(recursive: true));
              }
            }
          },
        );
      }
    }
    test(
      'cold open $format keeps empty and short-note annotation behavior',
      () async {
        final f = await _ReaderFixture.create(fixture);
        try {
          final id = f.state.bookId!;
          await f.reader.close();
          await f.reader.open(id);
          await f.finishColdOpen();
          _expectRendererCopy(
            f.acceptedDispatches.lastWhere((m) => m['action'] == 'open'),
            [],
          );
          await f.checkedEvent('selection', {
            'anchor': format == 'pdf'
                ? {'page': 0}
                : {'cfi': 'epubcfi(/6/2!/4/2/1:6)', 'index': 0},
            'text': 'Saved short passage',
            'reference': format == 'pdf' ? 'Page 1' : 'Chapter 1',
          });
          await f.reader.annotation(
            'highlight',
            note: 'Ordinary short private note',
          );
          final saved = f.reader.annotations.single;
          await f.reader.close();
          await f.reader.open(id);
          await f.finishColdOpen();
          _expectRendererCopy(
            f.acceptedDispatches.lastWhere((m) => m['action'] == 'open'),
            [saved],
          );
          await f.reader.syncAnnotations();
          _expectRendererCopy(
            f.acceptedDispatches.lastWhere((m) => m['action'] == 'annotations'),
            [saved],
          );
          expect(saved.note, 'Ordinary short private note');
        } finally {
          await f.dispose();
        }
      },
    );
  }

  test(
    'note transport bounds include UTF-8, JSON escaping and envelope bytes',
    () {
      final native = File('native/reader_action_limits.h').readAsStringSync();
      expect(native, contains('6 * 1000000 + 65536'));
      for (final host in [
        'linux/runner/reader_popover.cc',
        'windows/runner/reader_popover.cpp',
      ]) {
        expect(
          File(host).readAsStringSync(),
          matches(RegExp(r'>\s*kMaxReaderPopoverActionBytes')),
        );
      }
      for (final host in [
        'linux/runner/reader_host.cc',
        'windows/runner/reader_host.cpp',
      ]) {
        expect(
          File(host).readAsStringSync(),
          contains('kMaxReaderPopoverActionBytes'),
        );
      }
      for (final note in [
        'A' * maxAnnotationTextLength,
        '漢' * maxAnnotationTextLength,
        '\u0001' * maxAnnotationTextLength,
      ]) {
        expect(validAnnotationText(note), isTrue);
        expect(
          () => validateAnnotation(
            {
              'id': 'annotation-bounded',
              'bookId': '1' * 64,
              'annotationKind': 'highlight',
              'anchor': {'page': 0},
              'text': '',
              'note': note,
              'reference': 'Page 1',
              'color': 'yellow',
              'created': 0,
            },
            {'id': '1' * 64, 'format': 'pdf'},
          ),
          returnsNormally,
        );
        final encoded = jsonEncode({
          'type': 'popoverAction',
          'session': '123456789',
          'presentation': 123,
          'request': 456,
          'action': 'annotationNote',
          'note': note,
          'color': 'yellow',
        });
        expect(validReaderPopoverAction(encoded), isTrue);
        final padded =
            encoded +
            ' ' * (maxReaderPopoverActionBytes - utf8.encode(encoded).length);
        expect(validReaderPopoverAction(padded), isTrue);
        expect(validReaderPopoverAction('$padded '), isFalse);
      }
      expect(
        validReaderPopoverAction('漢' * (maxReaderPopoverActionBytes ~/ 3 + 1)),
        isFalse,
      );
      expect(validAnnotationText('A' * (maxAnnotationTextLength + 1)), isFalse);
      expect(validAnnotationText('valid\u0000invalid'), isFalse);
    },
  );

  for (final kind in ['existing', 'creation']) {
    for (final encoding in ['ASCII', 'multibyte', 'escaped']) {
      testWidgets(
        '$kind full $encoding note crosses the native bridge and round trips',
        (tester) async {
          tester.view.physicalSize = const Size(460, 650);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final note = _transportNote(encoding);
          late _ReaderFixture f;
          final delivered = <Map>[], completed = <Map>[], rejected = <Map>[];
          await _readerAction(tester, () async {
            f = await _ReaderFixture.create('text.pdf');
            await f.openSelectionPopover();
            if (kind == 'existing') {
              await f.reader.annotation('highlight', note: 'Baseline');
              // The full supported note is authored in the shared Notebook
              // lifecycle before Reading is asked to display or save it.
              final a = f.reader.annotations.single;
              f.notes.edit(a, note);
              await f.notes.save(a.id);
              await f.openAnnotationPopover(f.reader.annotations.single);
            }
          });
          _connectPopover(
            f,
            delivered: delivered,
            completed: completed,
            rejected: rejected,
          );
          try {
            await tester.pumpWidget(const ReaderPopoverApp());
            await _popupUpdate(tester, f.popup);
            if (kind == 'creation') {
              await tester.tap(find.text('Add Note'));
              await tester.pumpAndSettle();
              await tester.enterText(find.byType(TextField), note);
              await _pumpUntil(tester, () => completed.isNotEmpty);
            }
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              note,
            );
            // Beyond-contract input is refused by the actual editor, leaving
            // the previous revision intact with explicit feedback.
            final priorEvents = delivered.length;
            tester
                .state<EditableTextState>(find.byType(EditableText))
                .updateEditingValue(
                  TextEditingValue(text: 'Z' * (maxAnnotationTextLength + 1)),
                );
            await tester.pumpAndSettle();
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              note,
            );
            expect(delivered.length, priorEvents);
            expect(
              find.textContaining('This change was not accepted'),
              findsOneWidget,
            );
            tester
                .state<EditableTextState>(find.byType(EditableText))
                .updateEditingValue(
                  const TextEditingValue(text: 'invalid\u0000note'),
                );
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              note,
            );
            await tester.tap(find.text('Save'));
            await _pumpUntil(
              tester,
              () =>
                  completed.length == delivered.length &&
                  delivered.any(
                    (e) =>
                        e['action'] ==
                        (kind == 'existing' ? 'annotationNote' : 'highlight'),
                  ),
            );
            expect(rejected, isEmpty);
            final id = f.reader.annotations.single.id;
            await _readerAction(tester, f.notes.flush);
            await _readerAction(tester, () => f.verifyNote(id, note));
            await _readerAction(
              tester,
              () => f.openAnnotationPopover(f.reader.annotations.single),
            );
            await _popupUpdate(tester, f.popup);
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              note,
            );
            expect(
              tester.widget<TextField>(find.byType(TextField)).readOnly,
              isFalse,
            );
            expect(tester.takeException(), isNull);
          } finally {
            f.onNativeCall = null;
            await tester.pumpWidget(const SizedBox.shrink());
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(readerPopoverChannel, null);
            await _readerAction(tester, f.dispose);
          }
        },
      );
    }
  }

  testWidgets(
    'rejected local input is captured before replacement, flush and close; failed handoff preserves the editor',
    (tester) async {
      tester.view.physicalSize = const Size(460, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      final rejected = <Map>[];
      final reject = {'noteDraft'};
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('text.pdf');
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Saved baseline');
        await f.openAnnotationPopover(f.reader.annotations.single);
      });
      _connectPopover(f, rejectActions: reject, rejected: rejected);
      final native = f.onNativeCall!;
      bool failCapture = true;
      final captureEntered = Completer<void>(),
          captureProceed = Completer<void>();
      bool pauseCapture = true;
      f.onNativeCall = (call) async {
        if (call.method == 'capturePopover' && failCapture) {
          throw PlatformException(
            code: 'reader-draft-unavailable',
            message: 'Note handoff failed; retry',
          );
        }
        final captured = await native(call);
        if (call.method == 'capturePopover' && pauseCapture) {
          captureEntered.complete();
          await captureProceed.future;
        }
        return captured;
      };
      try {
        await tester.pumpWidget(const ReaderPopoverApp());
        await _popupUpdate(tester, f.popup);
        await tester.enterText(
          find.byType(TextField),
          'Retained after rejection',
        );
        await _pumpUntil(tester, () => rejected.isNotEmpty);
        final owner = f.popup['presentation'];
        final bookId = f.state.bookId;
        final hidden = f.calls
            .where((c) => c.method == 'visible' && c.arguments == false)
            .length;
        final handoffErrors = <String, Object>{};
        await _readerAction(tester, () async {
          // Observe failures in the driven operation itself. Widget pumping in
          // _readerAction must not overlap expectLater's own test-API guard.
          for (final operation in <String, Future<void> Function()>{
            'replacement': () => f.reader.showPopover('speech'),
            'flush': f.reader.flush,
            'close': f.reader.close,
          }.entries) {
            try {
              await operation.value();
            } catch (error) {
              handoffErrors[operation.key] = error;
            }
          }
          final other = await f.container
              .read(workspaceControllerProvider.notifier)
              .openPath(p.absolute('test/fixtures/image-only.pdf'));
          await f.reader.open(other.books.single.id);
        });
        expect(handoffErrors.keys, ['replacement', 'flush', 'close']);
        for (final error in handoffErrors.values) {
          expect(error.toString(), contains('Note handoff failed'));
        }
        expect(f.state.bookId, bookId);
        expect(f.state.ready, isTrue);
        expect(f.state.error, isNull);
        expect(f.state.warning, contains('Note handoff failed'));
        expect(
          f.calls.where((c) => c.method == 'visible' && c.arguments == false),
          hasLength(hidden),
        );
        await _readerAction(
          tester,
          () => f.container
              .read(workspaceControllerProvider.notifier)
              .loadBook(bookId!),
        );
        expect(f.popup['presentation'], owner);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Retained after rejection',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse,
        );
        expect(f.drafts.drafts, isEmpty);
        expect(find.textContaining('Note handoff failed'), findsWidgets);
        failCapture = false;
        var replaced = false;
        await tester.runAsync(() async {
          unawaited(
            f
                .openAnnotationPopover(f.reader.annotations.single)
                .then((_) => replaced = true),
          );
        });
        await _pumpUntil(tester, () => captureEntered.isCompleted);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isTrue,
        );
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .updateEditingValue(
              const TextEditingValue(text: 'Refused during sealed handoff'),
            );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Retained after rejection',
        );
        captureProceed.complete();
        pauseCapture = false;
        await _pumpUntil(tester, () => replaced);
        await _popupUpdate(tester, f.popup);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Retained after rejection',
        );
        await _readerAction(tester, f.notes.flush);
        await _readerAction(
          tester,
          () => f.verifyNote(
            f.reader.annotations.single.id,
            'Retained after rejection',
          ),
        );
        await _readerAction(
          tester,
          () => f.openAnnotationPopover(f.reader.annotations.single),
        );
        await _popupUpdate(tester, f.popup);
        await tester.enterText(find.byType(TextField), 'Flush captures latest');
        await _pumpUntil(tester, () => rejected.length == 2);
        await _readerAction(tester, f.reader.flush);
        await _readerAction(tester, f.notes.flush);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse,
        );
        await _readerAction(
          tester,
          () => f.verifyNote(
            f.reader.annotations.single.id,
            'Flush captures latest',
          ),
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!captureProceed.isCompleted) captureProceed.complete();
        f.onNativeCall = null;
        await tester.pumpWidget(const SizedBox.shrink());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(readerPopoverChannel, null);
        await _readerAction(tester, f.dispose);
      }
    },
  );

  testWidgets(
    'uncertain native delivery keeps Save sealed until the real primary result',
    (tester) async {
      tester.view.physicalSize = const Size(460, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      final entered = Completer<void>(), proceed = Completer<void>();
      final delivered = <Map>[], completed = <Map>[];
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Baseline');
        await f.openAnnotationPopover(f.reader.annotations.single);
        gate.entered = entered;
        gate.proceed = proceed;
      });
      _connectPopover(
        f,
        delivered: delivered,
        completed: completed,
        loseAcknowledgement: {'annotationNote'},
      );
      try {
        await tester.pumpWidget(const ReaderPopoverApp());
        await _popupUpdate(tester, f.popup);
        await tester.enterText(find.byType(TextField), 'Actually forwarded');
        await _pumpUntil(tester, () => completed.isNotEmpty);
        await tester.tap(find.text('Save'));
        await _pumpUntil(tester, () => entered.isCompleted);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isTrue,
        );
        expect(find.textContaining('Saving is still pending'), findsOneWidget);
        await tester.pump(const Duration(seconds: 16));
        await tester.tap(find.text('Saving note…'));
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .updateEditingValue(
              const TextEditingValue(text: 'Must not be accepted'),
            );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Actually forwarded',
        );
        proceed.complete();
        await _pumpUntil(tester, () => completed.length == delivered.length);
        expect(
          delivered.where((e) => e['action'] == 'annotationNote'),
          hasLength(1),
        );
        await _readerAction(
          tester,
          () => f.verifyNote(
            f.reader.annotations.single.id,
            'Actually forwarded',
          ),
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!proceed.isCompleted) proceed.complete();
        f.onNativeCall = null;
        await tester.pumpWidget(const SizedBox.shrink());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(readerPopoverChannel, null);
        await _readerAction(tester, f.dispose);
      }
    },
  );

  for (final kind in ['existing', 'creation']) {
    for (final timedOut in [false, true]) {
      testWidgets(
        'native rejection ${timedOut ? 'after timeout ' : ''}releases $kind Save and transfers retained text before dismissal',
        (tester) async {
          tester.view.physicalSize = const Size(460, 650);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          late _ReaderFixture f;
          final delivered = <Map>[], completed = <Map>[], rejected = <Map>[];
          final replies = <Map>[];
          final entered = Completer<void>(), proceed = Completer<void>();
          final text = 'A' * 70000;
          await _readerAction(tester, () async {
            f = await _ReaderFixture.create('text.pdf');
            await f.openSelectionPopover();
            if (kind == 'existing') {
              await f.reader.annotation('highlight', note: 'Saved baseline');
              await f.openAnnotationPopover(f.reader.annotations.single);
            }
          });
          _connectPopover(
            f,
            delivered: delivered,
            completed: completed,
            rejected: rejected,
            rejectionReplies: replies,
            rejectionEntered: timedOut ? entered : null,
            rejectionProceed: timedOut ? proceed : null,
            // Reproduce the reviewed hosts' actual byte budget, without ever
            // calling the primary handler for rejected actions. Normal bridge
            // cases above exercise both current hosts' shared larger budget.
            actionByteLimit: 65536,
          );
          try {
            await tester.pumpWidget(const ReaderPopoverApp());
            await _popupUpdate(tester, f.popup);
            if (kind == 'creation') {
              await tester.tap(find.text('Add Note'));
              await tester.pumpAndSettle();
            }
            await tester.enterText(find.byType(TextField), text);
            await _pumpUntil(tester, () => rejected.isNotEmpty);
            expect(delivered, isEmpty);
            expect(f.drafts.drafts, isEmpty);
            await tester.tap(find.text('Save'));
            await _pumpUntil(tester, () => rejected.length == 2);
            if (timedOut) {
              expect(entered.isCompleted, isTrue);
              await tester.pump(const Duration(seconds: 16));
              await tester.pumpAndSettle();
              expect(
                tester.widget<TextField>(find.byType(TextField)).readOnly,
                isTrue,
              );
              expect(
                find.textContaining('Saving is still pending'),
                findsOneWidget,
              );
              expect(delivered, isEmpty);
              expect(f.drafts.drafts, isEmpty);
              proceed.complete();
            }
            await _pumpUntil(tester, () => replies.length == 2);
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              text,
            );
            expect(
              tester.widget<TextField>(find.byType(TextField)).readOnly,
              isFalse,
            );
            expect(
              find.textContaining('Saving is still pending'),
              findsNothing,
            );
            expect(find.textContaining('Reader action exceeds'), findsWidgets);
            final bookId = f.state.bookId!;
            if (kind == 'existing') {
              await _readerAction(tester, () async {
                await f.container
                    .read(workspaceControllerProvider.notifier)
                    .openPath(p.absolute('test/fixtures/image-only.pdf'));
              });
              expect(f.reader.annotations.single.bookId, bookId);
            }
            if (kind == 'existing') {
              await tester.tap(find.text('Close'));
            } else {
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            }
            await _pumpUntil(
              tester,
              () =>
                  completed.length == delivered.length && delivered.isNotEmpty,
            );
            await _readerAction(tester, f.notes.flush);
            await _readerAction(
              tester,
              () => f.container
                  .read(workspaceControllerProvider.notifier)
                  .loadBook(bookId),
            );
            final id = f.reader.annotations.single.id;
            expect(f.dispatchFailures, 0);
            final painted =
                f.dispatches.lastWhere(
                      (c) => c['action'] == 'annotations',
                    )['value']
                    as List;
            expect(painted.single['id'], id);
            expect((painted.single as Map).containsKey('note'), isFalse);
            await _readerAction(tester, () => f.verifyNote(id, text));
            await _readerAction(
              tester,
              () => f.openAnnotationPopover(f.reader.annotations.single),
            );
            await _popupUpdate(tester, f.popup);
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              text,
            );
            expect(tester.takeException(), isNull);
          } finally {
            if (!proceed.isCompleted) proceed.complete();
            f.onNativeCall = null;
            await tester.pumpWidget(const SizedBox.shrink());
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(readerPopoverChannel, null);
            await _readerAction(tester, f.dispose);
          }
        },
      );
    }
    TestWidgetsFlutterBinding.ensureInitialized();
  }

  for (final kind in ['existing', 'creation']) {
    testWidgets('$kind popover Save cannot close over later accepted input', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(460, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      final entered = Completer<void>(), proceed = Completer<void>();
      final delivered = <Map>[], completed = <Map>[];
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.openSelectionPopover();
        if (kind == 'existing') {
          await f.reader.annotation('highlight', note: 'Persisted baseline');
          await f.openAnnotationPopover(f.reader.annotations.single);
          gate.entered = entered;
          gate.proceed = proceed;
        } else {
          gate.putEntered = entered;
          gate.putProceed = proceed;
        }
      });
      _connectPopover(f, delivered: delivered, completed: completed);
      try {
        await tester.pumpWidget(const ReaderPopoverApp());
        await _popupUpdate(tester, f.popup);
        if (kind == 'creation') {
          await tester.tap(find.text('Add Note'));
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextField), 'Submission A');
        await _pumpUntil(
          tester,
          () => f.drafts.drafts.values.any((d) => d.text == 'Submission A'),
        );
        final id = f.drafts.sources.keys.single;
        await tester.tap(find.text('Save'));
        final saveAction = kind == 'existing' ? 'annotationNote' : 'highlight';
        await _pumpUntil(
          tester,
          () =>
              entered.isCompleted &&
              delivered.any((e) => e['action'] == saveAction),
        );
        expect(proceed.isCompleted, isFalse);
        expect(completed.where((e) => e['action'] == saveAction), isEmpty);
        final field = tester.widget<TextField>(find.byType(TextField));
        if (field.readOnly) {
          tester
              .state<EditableTextState>(find.byType(EditableText))
              .updateEditingValue(
                const TextEditingValue(
                  text: 'Accepted B',
                  selection: TextSelection.collapsed(offset: 10),
                ),
              );
        } else {
          await tester.enterText(find.byType(TextField), 'Accepted B');
        }
        await tester.pump();
        final accepted = field.controller!.text == 'Accepted B';
        if (accepted) {
          expect(
            delivered.where(
              (e) => e['action'] == 'noteDraft' && e['note'] == 'Accepted B',
            ),
            hasLength(1),
          );
          expect(
            completed.where(
              (e) => e['action'] == 'noteDraft' && e['note'] == 'Accepted B',
            ),
            isEmpty,
          );
        } else {
          expect(field.readOnly, isTrue);
          expect(field.controller!.text, 'Submission A');
          expect(delivered.where((e) => e['note'] == 'Accepted B'), isEmpty);
        }
        expect(proceed.isCompleted, isFalse);
        proceed.complete();
        await _pumpUntil(tester, () => completed.length == delivered.length);
        // A successful reply must not reopen the closing presentation to input.
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isTrue,
        );
        final closedText = tester
            .widget<TextField>(find.byType(TextField))
            .controller!
            .text;
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .updateEditingValue(
              const TextEditingValue(
                text: 'Late input after acknowledgement',
                selection: TextSelection.collapsed(offset: 0),
              ),
            );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          closedText,
        );
        final expected = accepted ? 'Accepted B' : 'Submission A';
        await _readerAction(tester, () async {
          await f.notes.flush();
          await f.verifyNote(id, expected);
        });
        if (kind == 'creation') {
          expect(gate.calls.where((c) => c == 'putAnnotation'), hasLength(1));
        }
        await _readerAction(
          tester,
          () => f.openAnnotationPopover(f.reader.annotations.single),
        );
        await _popupUpdate(tester, f.popup);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          expected,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        f.onNativeCall = null;
        await _readerAction(tester, f.reader.suspend);
        f.notes.view(f.state.bookId!, selected: id);
        tester.view.physicalSize = const Size(1100, 900);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: BookWorkspaceScreen(
                view: BookView.notebook,
                id: f.state.bookId!,
              ),
            ),
          ),
        );
        await _pumpUntil(
          tester,
          () =>
              !f.container.read(workspaceControllerProvider).loading &&
              find.byType(TextField).evaluate().isNotEmpty,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          expected,
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!proceed.isCompleted) proceed.complete();
        f.onNativeCall = null;
        await tester.pumpWidget(const SizedBox.shrink());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(readerPopoverChannel, null);
        await _readerAction(tester, f.dispose);
      }
    });
  }

  for (final kind in ['existing', 'creation']) {
    for (final timedOut in [false, true]) {
      testWidgets(
        '$kind failed Save ${timedOut ? 'after timeout ' : ''}unlocks the editor for a protected retry',
        (tester) async {
          tester.view.physicalSize = const Size(460, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          late _ReaderFixture f;
          late AnnotationStoreGate gate;
          final entered = Completer<void>(), proceed = Completer<void>();
          final delivered = <Map>[], completed = <Map>[];
          await _readerAction(tester, () async {
            f = await _ReaderFixture.create(
              'text.pdf',
              wrapStore: (s) => gate = AnnotationStoreGate(s),
            );
            await f.openSelectionPopover();
            if (kind == 'existing') {
              await f.reader.annotation('highlight', note: 'Original baseline');
              await f.openAnnotationPopover(f.reader.annotations.single);
              gate.entered = entered;
              gate.proceed = proceed;
              gate.failAfterProceed = true;
            } else {
              gate.putEntered = entered;
              gate.putProceed = proceed;
              gate.failPut = true;
            }
          });
          _connectPopover(f, delivered: delivered, completed: completed);
          try {
            await tester.pumpWidget(const ReaderPopoverApp());
            await _popupUpdate(tester, f.popup);
            if (kind == 'creation') {
              await tester.tap(find.text('Add Note'));
              await tester.pumpAndSettle();
            }
            await tester.enterText(
              find.byType(TextField),
              'Protected submission',
            );
            await _pumpUntil(tester, () => f.drafts.drafts.isNotEmpty);
            final id = f.drafts.sources.keys.single;
            await tester.tap(find.text('Save'));
            await _pumpUntil(
              tester,
              () =>
                  entered.isCompleted &&
                  delivered.any(
                    (e) =>
                        e['action'] ==
                        (kind == 'existing' ? 'annotationNote' : 'highlight'),
                  ),
            );
            expect(
              tester.widget<TextField>(find.byType(TextField)).readOnly,
              isTrue,
            );
            expect(find.text('Saving note…'), findsOneWidget);
            if (timedOut) {
              await tester.pump(const Duration(seconds: 16));
              await tester.pumpAndSettle();
              expect(
                find.textContaining('Saving is still pending'),
                findsOneWidget,
              );
              expect(
                tester.widget<TextField>(find.byType(TextField)).readOnly,
                isTrue,
              );
            }
            proceed.complete();
            await _pumpUntil(
              tester,
              () => completed.length == delivered.length,
            );
            expect(
              tester.widget<TextField>(find.byType(TextField)).readOnly,
              isFalse,
            );
            expect(
              find.textContaining('Saving is still pending'),
              findsNothing,
            );
            expect(f.drafts.drafts[id]!.text, 'Protected submission');
            expect(f.drafts.drafts[id]!.error, isNotNull);
            if (kind == 'existing') {
              expect(f.drafts.drafts[id]!.baseline, 'Original baseline');
            }
            await _readerAction(
              tester,
              () => f.openAnnotationPopover(f.drafts.sources[id]!),
            );
            await _popupUpdate(tester, f.popup);
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              'Protected submission',
            );
            gate.failAfterProceed = false;
            gate.failPut = false;
            await tester.enterText(
              find.byType(TextField),
              'Retried latest\ntext',
            );
            await tester.tap(find.text('Save'));
            await _pumpUntil(
              tester,
              () =>
                  completed.length == delivered.length &&
                  f.drafts.drafts.isEmpty,
            );
            await _readerAction(
              tester,
              () => f.verifyNote(id, 'Retried latest\ntext'),
            );
            await _readerAction(
              tester,
              () => f.openAnnotationPopover(f.reader.annotations.single),
            );
            await _popupUpdate(tester, f.popup);
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              'Retried latest\ntext',
            );
            expect(tester.takeException(), isNull);
          } finally {
            gate.failAfterProceed = false;
            gate.failPut = false;
            if (!proceed.isCompleted) proceed.complete();
            f.onNativeCall = null;
            await tester.pumpWidget(const SizedBox.shrink());
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(readerPopoverChannel, null);
            await _readerAction(tester, f.dispose);
          }
        },
      );
    }
  }

  testWidgets(
    'Save locks before the next frame and repeated Save/Close/Escape settle once',
    (tester) async {
      tester.view.physicalSize = const Size(460, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      final entered = Completer<void>(), proceed = Completer<void>();
      final delivered = <Map>[], completed = <Map>[];
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Saved baseline');
        await f.openAnnotationPopover(f.reader.annotations.single);
        gate.entered = entered;
        gate.proceed = proceed;
      });
      _connectPopover(f, delivered: delivered, completed: completed);
      try {
        await tester.pumpWidget(const ReaderPopoverApp());
        await _popupUpdate(tester, f.popup);
        await tester.enterText(
          find.byType(TextField),
          'Submission before transition',
        );
        await _pumpUntil(tester, () => f.drafts.drafts.isNotEmpty);
        final id = f.drafts.sources.keys.single;
        await tester.tap(find.text('Save'));
        // No frame has rebuilt the old TextField as read-only yet.
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse,
        );
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .updateEditingValue(
              const TextEditingValue(
                text: 'Input between frames',
                selection: TextSelection.collapsed(offset: 20),
              ),
            );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Submission before transition',
        );
        await tester.tap(find.text('Save'));
        await _pumpUntil(tester, () => entered.isCompleted);
        expect(
          delivered.where((e) => e['action'] == 'annotationNote'),
          hasLength(1),
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isTrue,
        );
        final dismissals = f.calls
            .where((c) => c.method == 'dismissPopover')
            .length;
        await tester.tap(find.text('Close'));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(proceed.isCompleted, isFalse);
        expect(delivered.where((e) => e['action'] == 'dismiss'), hasLength(2));
        expect(completed.where((e) => e['action'] == 'dismiss'), isEmpty);
        proceed.complete();
        await _pumpUntil(tester, () => completed.length == delivered.length);
        expect(
          f.calls.where((c) => c.method == 'dismissPopover').length,
          dismissals + 1,
        );
        await _readerAction(
          tester,
          () => f.verifyNote(id, 'Submission before transition'),
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!proceed.isCompleted) proceed.complete();
        f.onNativeCall = null;
        await tester.pumpWidget(const SizedBox.shrink());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(readerPopoverChannel, null);
        await _readerAction(tester, f.dispose);
      }
    },
  );

  testWidgets(
    'a timed-out Save stays read-only until acknowledgement and cannot dismiss a replacement',
    (tester) async {
      tester.view.physicalSize = const Size(460, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      final entered = Completer<void>(), proceed = Completer<void>();
      final delivered = <Map>[], completed = <Map>[];
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Replacement baseline');
        await f.reader.annotation('highlight', note: 'Original baseline');
        await f.openAnnotationPopover(f.reader.annotations.last);
        gate.entered = entered;
        gate.proceed = proceed;
      });
      _connectPopover(f, delivered: delivered, completed: completed);
      try {
        await tester.pumpWidget(const ReaderPopoverApp());
        await _popupUpdate(tester, f.popup);
        await tester.enterText(find.byType(TextField), 'Delayed original');
        await _pumpUntil(tester, () => f.drafts.drafts.isNotEmpty);
        await tester.tap(find.text('Save'));
        await _pumpUntil(tester, () => entered.isCompleted);
        await tester.pump(const Duration(seconds: 16));
        await tester.pumpAndSettle();
        expect(find.textContaining('Saving is still pending'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isTrue,
        );
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .updateEditingValue(
              const TextEditingValue(
                text: 'Not accepted after timeout',
                selection: TextSelection.collapsed(offset: 0),
              ),
            );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Delayed original',
        );
        expect(
          completed.where((e) => e['action'] == 'annotationNote'),
          isEmpty,
        );
        final staleChanged = tester
            .widget<BusyBooksGroupedTextEntry>(
              find.byType(BusyBooksGroupedTextEntry),
            )
            .onChanged!;
        await _readerAction(
          tester,
          () => f.openAnnotationPopover(f.reader.annotations.first),
        );
        await _popupUpdate(tester, f.popup);
        final replacement = Map.of(f.popup);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse,
        );
        expect(find.textContaining('Saving is still pending'), findsNothing);
        await tester.enterText(find.byType(TextField), 'Replacement latest');
        await tester.pump();
        final deliveriesBeforeStaleInput = delivered.length;
        final currentDraft = Map.of(delivered.last);
        expect(currentDraft['action'], 'noteDraft');
        expect(currentDraft['presentation'], replacement['presentation']);
        expect(currentDraft['note'], 'Replacement latest');
        // The retired field must reject an already queued callback before it
        // reaches the channel, retaining the replacement owner's latest draft.
        staleChanged('Obsolete old input');
        await tester.pump();
        expect(delivered, hasLength(deliveriesBeforeStaleInput));
        expect(delivered.last, currentDraft);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Replacement latest',
        );
        final dismissals = f.calls
            .where((c) => c.method == 'dismissPopover')
            .length;
        proceed.complete();
        await _pumpUntil(tester, () => completed.length == delivered.length);
        expect(
          f.calls.where((c) => c.method == 'dismissPopover').length,
          dismissals,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Replacement latest',
        );
        await _readerAction(tester, f.notes.flush);
        await _readerAction(tester, () async {
          final records =
              await f.store.call('annotations', f.state.bookId) as List;
          expect(
            records.map((a) => a['note']),
            unorderedEquals(['Delayed original', 'Replacement latest']),
          );
        });
        await tester.tap(find.text('Save'));
        await _pumpUntil(tester, () => completed.length == delivered.length);
        expect(
          f.calls.where((c) => c.method == 'dismissPopover').length,
          dismissals + 1,
        );
        expect(tester.takeException(), isNull);
      } finally {
        if (!proceed.isCompleted) proceed.complete();
        f.onNativeCall = null;
        await tester.pumpWidget(const SizedBox.shrink());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(readerPopoverChannel, null);
        await _readerAction(tester, f.dispose);
      }
    },
  );

  test(
    'first insertion failure protects the captured passage through dismissal, views, retry and backup',
    () async {
      late AnnotationStoreGate gate;
      final f = await _ReaderFixture.create(
        'text.pdf',
        wrapStore: (s) => gate = AnnotationStoreGate(s),
      );
      try {
        gate.failPut = true;
        gate.putEntered = Completer<void>();
        await f.openSelectionPopover();
        await f.action('noteDraft', {
          'note': 'New protected\npassage note',
          'color': 'pink',
        });
        await gate.putEntered!.future;
        await _until(() => f.drafts.drafts.values.any((d) => d.error != null));
        final source = f.drafts.sources.values.single;
        final id = source.id;
        expect(source.bookId, f.state.bookId);
        expect(source.kind, 'highlight');
        expect(source.anchor, {'page': 0, 'textOffset': 1, 'textLength': 3});
        expect(source.text, 'ABC');
        expect(source.reference, 'Page 1');
        expect(source.color, 'pink');
        await f.action('dismiss');
        await f.reader.suspend();
        expect(f.drafts.drafts[id]!.text, 'New protected\npassage note');
        await expectLater(f.notes.flush(), throwsA(isA<FileSystemException>()));
        await expectLater(
          f.reader.close(),
          throwsA(isA<FileSystemException>()),
        );
        expect(f.drafts.drafts[id]!.text, 'New protected\npassage note');
        await f.reader.open(source.bookId);
        await f.reader.show(true);
        await f.openAnnotationPopover(source);
        expect(f.popup['note'], 'New protected\npassage note');
        expect(f.popup['noteError'], isNotNull);
        gate.failPut = false;
        await f.notes.flush();
        await f.verifyNote(id, 'New protected\npassage note');
        await f.reader.close();
        await f.reader.open(source.bookId);
        expect(f.reader.annotations.single.note, 'New protected\npassage note');
      } finally {
        gate.failPut = false;
        await f.dispose();
      }
    },
  );

  for (final origin in ['Notebook', 'Reading']) {
    test(
      'failed $origin edit reopens Reading with the effective protected draft',
      () async {
        late AnnotationStoreGate gate;
        final f = await _ReaderFixture.create(
          'text.pdf',
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        try {
          await f.openSelectionPopover();
          await f.reader.annotation('highlight', note: 'Saved A');
          final a = f.reader.annotations.single;
          gate.fail = true;
          if (origin == 'Notebook') {
            await f.reader.suspend();
            f.notes.edit(a, 'Protected B');
            await expectLater(
              f.notes.save(a.id),
              throwsA(isA<FileSystemException>()),
            );
            await f.reader.open(a.bookId);
            await f.reader.show(true);
          } else {
            await f.openAnnotationPopover(a);
            await f.action('noteDraft', {'note': 'Protected B'});
            await f.action('annotationNote', {'note': 'Protected B'});
            await f.action('dismiss');
          }
          await f.openAnnotationPopover(a);
          expect(f.popup['note'], 'Protected B');
          expect(f.popup['noteError'], isNotNull);
          expect(f.drafts.drafts[a.id]!.baseline, 'Saved A');
          gate.fail = false;
          await f.action('annotationNote', {'note': f.popup['note']});
          await f.notes.flush();
          await f.verifyNote(a.id, 'Protected B');
        } finally {
          gate.fail = false;
          await f.dispose();
        }
      },
    );
  }

  for (final origin in ['Notebook', 'Reading']) {
    testWidgets(
      'the actual reopened Reading popover displays a failed $origin draft',
      (tester) async {
        tester.view.physicalSize = const Size(460, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late _ReaderFixture f;
        late AnnotationStoreGate gate;
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create(
            'text.pdf',
            wrapStore: (s) => gate = AnnotationStoreGate(s),
          );
          await f.openSelectionPopover();
          await f.reader.annotation('highlight', note: 'Saved A');
          final a = f.reader.annotations.single;
          gate.fail = true;
          if (origin == 'Notebook') {
            f.notes.edit(a, 'Protected B');
            await expectLater(
              f.notes.save(a.id),
              throwsA(isA<FileSystemException>()),
            );
          } else {
            await f.openAnnotationPopover(a);
            await f.action('noteDraft', {'note': 'Protected B'});
            await f.action('annotationNote', {'note': 'Protected B'});
            await f.action('dismiss');
          }
          await f.openAnnotationPopover(a);
        });
        try {
          _connectPopover(f);
          await tester.pumpWidget(const ReaderPopoverApp());
          await _popupUpdate(tester, f.popup);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'Protected B',
          );
          expect(find.textContaining('Your draft is retained'), findsOneWidget);
          expect(f.drafts.drafts.values.single.baseline, 'Saved A');
          await tester.enterText(find.byType(TextField), 'Newer C');
          await _pumpUntil(
            tester,
            () => f.drafts.drafts.values.single.text == 'Newer C',
          );
          await _popupUpdate(tester, {...f.popup, 'note': 'Saved A'});
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'Newer C',
          );
          gate.fail = false;
          await tester.tap(find.text('Save'));
          await _pumpUntil(tester, () => f.drafts.drafts.isEmpty);
          await _readerAction(
            tester,
            () => f.verifyNote(f.reader.annotations.single.id, 'Newer C'),
          );
          await _readerAction(
            tester,
            () => f.openAnnotationPopover(f.reader.annotations.single),
          );
          await _popupUpdate(tester, f.popup);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'Newer C',
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          f.onNativeCall = null;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(readerPopoverChannel, null);
          gate.fail = false;
          await _readerAction(tester, f.dispose);
        }
      },
    );
  }

  for (final dismissal in ['Close', 'Escape']) {
    testWidgets(
      'a failed first insertion survives real popover $dismissal/reopen and missing-original Notebook',
      (tester) async {
        tester.view.physicalSize = const Size(460, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late AnnotationStoreGate gate;
        late _ReaderFixture f;
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create(
            'text.pdf',
            ownedOriginal: true,
            wrapStore: (s) => gate = AnnotationStoreGate(s),
          );
          gate.failPut = true;
          await f.openSelectionPopover();
        });
        _connectPopover(f);
        try {
          await tester.pumpWidget(const ReaderPopoverApp());
          await _popupUpdate(tester, f.popup);
          await tester.tap(find.text('Add Note'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'Captured\nnew note');
          await _pumpUntil(
            tester,
            () => f.drafts.drafts.values.any((d) => d.error != null),
          );
          expect(find.textContaining('Your draft is retained'), findsOneWidget);
          final source = f.drafts.sources.values.single;
          final beforeDismiss = f.calls
              .where((c) => c.method == 'dismissPopover')
              .length;
          if (dismissal == 'Close') {
            await tester.tap(find.text('Close'));
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          }
          await _pumpUntil(
            tester,
            () =>
                f.calls.where((c) => c.method == 'dismissPopover').length >
                beforeDismiss,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await _readerAction(tester, f.openSelectionPopover);
          expect(f.popup['annotationId'], source.id);
          await tester.pumpWidget(const ReaderPopoverApp());
          await _popupUpdate(tester, f.popup);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'Captured\nnew note',
          );
          expect(find.textContaining('Your draft is retained'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          f.onNativeCall = null;
          await _readerAction(tester, () async {
            await f.reader.suspend();
            await File(f.reader.book!.path).delete();
            await f.container
                .read(workspaceControllerProvider.notifier)
                .loadBook(source.bookId, activate: true);
          });
          tester.view.physicalSize = const Size(1100, 900);
          f.notes.view(source.bookId, selected: source.id);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: f.container,
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: BookWorkspaceScreen(
                  view: BookView.notebook,
                  id: source.bookId,
                ),
              ),
            ),
          );
          await _pumpUntil(
            tester,
            () => find.byType(TextField).evaluate().isNotEmpty,
          );
          expect(find.text('ABC'), findsOneWidget);
          expect(
            find.textContaining('original book is unavailable'),
            findsOneWidget,
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'Captured\nnew note',
          );
          gate.failPut = false;
          await tester.tap(find.text('Retry'));
          await _pumpUntil(tester, () => f.drafts.drafts.isEmpty);
          await _readerAction(
            tester,
            () => f.verifyNote(source.id, 'Captured\nnew note'),
          );
          expect(tester.takeException(), isNull);
        } finally {
          f.onNativeCall = null;
          await tester.pumpWidget(const SizedBox.shrink());
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(readerPopoverChannel, null);
          gate.failPut = false;
          await _readerAction(tester, f.dispose);
        }
      },
    );
  }

  for (final path in ['toolbar', 'popover']) {
    test(
      '$path deletion resolves a failed Notebook draft across view changes',
      () async {
        late AnnotationStoreGate gate;
        final f = await _ReaderFixture.create(
          'text.pdf',
          wrapStore: (store) => gate = AnnotationStoreGate(store),
        );
        try {
          await f.event('location', {
            'anchor': {'page': 0},
            'reference': 'Page 1',
            'progress': 0,
          });
          await f.reader.annotation('bookmark');
          final item = f.reader.annotations.single;
          final notebook = f.container.read(
            notebookControllerProvider.notifier,
          );
          await f.reader.suspend();
          notebook.edit(item, 'Failed Notebook edit');
          gate.fail = true;
          await expectLater(
            notebook.save(item.id),
            throwsA(isA<FileSystemException>()),
          );
          await f.reader.open(item.bookId);
          await f.reader.show(true);
          gate.fail = false;
          if (path == 'toolbar') {
            await f.reader.annotation('bookmark');
          } else {
            await f.openAnnotationPopover(item);
            final popup =
                f.calls.lastWhere((c) => c.method == 'popover').arguments
                    as Map;
            await f.event('popoverAction', {
              'presentation': popup['presentation'],
              'action': 'deleteAnnotation',
            });
          }
          await notebook.flush();
          expect(f.reader.annotations, isEmpty);
          expect(
            f.container.read(workspaceControllerProvider).annotations,
            isEmpty,
          );
          expect(await f.store.call('annotations', item.bookId), isEmpty);
          final markdown = p.join(f.directory.path, 'notes.md');
          await f.store.call('exportMarkdown', {
            'id': item.bookId,
            'path': markdown,
          });
          expect(
            await File(markdown).readAsString(),
            isNot(contains('Failed Notebook edit')),
          );
          final backup = p.join(f.directory.path, 'reading.busybooks');
          await f.store.call('backup', {'path': backup, 'preferences': {}});
          final manifest =
              jsonDecode(
                    utf8.decode(
                      ZipDecoder()
                          .decodeBytes(await File(backup).readAsBytes())
                          .files
                          .single
                          .content,
                    ),
                  )
                  as Map;
          expect(
            (manifest['records'] as List).where(
              (r) => r['kind'] == 'annotation',
            ),
            isEmpty,
          );
          final reopened = await ReadingDataStore.open(
            p.join(f.directory.path, 'restored'),
          );
          try {
            await reopened.call('restore', backup);
            expect(await reopened.call('annotations', item.bookId), isEmpty);
          } finally {
            await reopened.close();
          }
          await f.reader.close();
          await f.reader.open(item.bookId);
          expect(f.reader.annotations, isEmpty);
        } finally {
          await f.dispose();
        }
      },
    );
  }
  test(
    'ready handshake followed by a stalled publication remains bounded and ignores late opened',
    () async {
      final f = await _ReaderFixture.create(
        'text.pdf',
        startupTimeout: const Duration(milliseconds: 150),
      );
      try {
        final id = f.state.bookId!;
        await f.reader.close();
        await f.reader.open(id);
        await f.event('ready');
        expect(f.state.phase, 'opening');
        expect(f.state.ready, isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(f.state.error, isNotNull);
        await f.event('opened');
        expect(f.state.ready, isFalse);
        await f.reader.close();
        await f.reader.open(id);
        await f.event('ready');
        await f.event('opened');
        expect(f.state.ready, isTrue);
        expect(f.state.error, isNull);
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'Notebook suspension rejects delayed ready/opened callbacks and resumes the same usable passage',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        await f.event('location', {
          'anchor': {
            'page': 0,
            'point': [20, 40],
          },
          'progress': .2,
        });
        final location = f.state.location;
        f.calls.clear();
        await f.reader.suspend();
        expect(
          f.calls.lastWhere((c) => c.method == 'visible').arguments,
          isFalse,
        );
        await f.event('opened');
        await f.reader.show(true);
        await f.reader.open(f.state.bookId!);
        expect(f.state.location, location);
        expect(f.dispatches.where((m) => m['action'] == 'goto'), isEmpty);
        expect(
          f.calls.lastWhere((c) => c.method == 'visible').arguments,
          isTrue,
        );
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'position persistence failures retain readable surface and pending passage for retry',
    () async {
      late _PersistenceFailure gate;
      final f = await _ReaderFixture.create(
        'text.pdf',
        wrapStore: (store) => gate = _PersistenceFailure(store),
      );
      try {
        await f.event('location', {
          'anchor': {
            'page': 0,
            'point': [20, 40],
          },
          'progress': .3,
        });
        await expectLater(
          f.reader.flush(),
          throwsA(isA<FileSystemException>()),
        );
        expect(f.state.ready, isTrue);
        expect(f.state.error, isNull);
        expect(f.state.warning, isNotNull);
        await f.reader.show(true);
        expect(
          f.calls.lastWhere((c) => c.method == 'visible').arguments,
          isTrue,
        );
        gate.fail = false;
        await f.reader.flush();
        expect(f.state.warning, isNull);
        expect(f.reader.book!.progress, .3);
      } finally {
        gate.fail = false;
        await f.dispose();
      }
    },
  );
  test(
    'a missing native ready signal reports an error instead of staying blank',
    () async {
      final f = await _ReaderFixture.create(
        'text.pdf',
        startupTimeout: const Duration(milliseconds: 150),
      );
      try {
        final id = f.state.bookId!;
        await f.reader.close();
        await f.reader.open(id);
        final opened =
            f.calls.lastWhere((call) => call.method == 'open').arguments as Map;
        expect(
          Uri.decodeQueryComponent(opened['loadingQuery'] as String),
          'Opening book',
        );
        await Future<void>.delayed(const Duration(milliseconds: 220));
        expect(f.state.ready, isFalse);
        expect(f.state.error, contains('reader did not start'));
        expect(
          f.calls.lastWhere((call) => call.method == 'visible').arguments,
          isFalse,
        );
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'reader startup failures hide the native surface and preserve the error',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        await f.event('error', {'message': 'Renderer dependency failed'});
        expect(f.state.ready, isFalse);
        expect(f.state.error, 'Renderer dependency failed');
        expect(
          f.calls.lastWhere((call) => call.method == 'visible').arguments,
          isFalse,
        );
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'reader diagnostics retain readiness and log only the owning session',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      final previousDebugPrint = debugPrint;
      final diagnostics = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        diagnostics.add(message ?? '');
      };
      try {
        await f.event('diagnostic', {
          'session': 'obsolete',
          'stage': 'resize-observer',
          'message': 'Stale observation',
        });
        expect(diagnostics, isEmpty);
        await f.event('diagnostic', {
          'stage': 'resize-observer',
          'message':
              'ResizeObserver loop completed with undelivered notifications.',
        });
        expect(f.state.ready, isTrue);
        expect(f.state.error, isNull);
        expect(diagnostics.single, contains('resize-observer'));
        expect(diagnostics.single, contains(f.reader.sessionId));
        await f.event('error', {'message': 'Real script failure'});
        expect(f.state.ready, isFalse);
        expect(f.state.error, 'Real script failure');
      } finally {
        debugPrint = previousDebugPrint;
        await f.dispose();
      }
    },
  );
  test(
    'preparing shared chrome transfers native focus without restoring the publication',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        f.calls.clear();
        expect(await f.reader.prepareChromeChange(), true);
        final dismissal = f.calls.singleWhere(
          (call) => call.method == 'dismissPopover',
        );
        expect((dismissal.arguments as Map)['restoreFocus'], false);
        expect(
          f.calls.singleWhere((call) => call.method == 'focusChrome').arguments,
          {'session': f.reader.sessionId},
        );
        expect(f.dispatches.where((d) => d['action'] == 'focus'), isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );
  test('native focus handoff only runs on the visible ready reader', () async {
    final f = await _ReaderFixture.create('fixed-layout.epub');
    try {
      f.calls.clear();
      await f.reader.send('focus');
      expect(f.calls.map((call) => call.method), ['focus', 'dispatch']);
      expect(f.dispatches.single['action'], 'focus');
      await f.reader.show(false);
      f.calls.clear();
      await f.reader.send('focus');
      expect(f.calls, isEmpty);
    } finally {
      await f.dispose();
    }
  });

  test(
    'maximum supported note persists and restores without a native surface',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Baseline');
        final a = f.reader.annotations.single;
        final note = '\u0001' * maxAnnotationTextLength;
        f.notes.edit(a, note);
        await f.notes.save(a.id);
        await f.verifyNote(a.id, note);
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'a slow creation and Save serialize newer revisions into one stable annotation',
    () async {
      late AnnotationStoreGate gate;
      final f = await _ReaderFixture.create(
        'text.pdf',
        wrapStore: (s) => gate = AnnotationStoreGate(s),
      );
      try {
        gate.putEntered = Completer<void>();
        gate.putProceed = Completer<void>();
        await f.openSelectionPopover();
        await f.action('noteDraft', {'note': 'First revision'});
        await gate.putEntered!.future;
        final id = f.drafts.sources.values.single.id;
        await f.action('noteDraft', {'note': 'Second revision'});
        await f.action('noteDraft', {'note': 'Newest\nrevision'});
        final saving = f.action('highlight', {'note': 'Newest\nrevision'});
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(f.drafts.drafts[id]!.text, 'Newest\nrevision');
        expect(f.drafts.sources.keys, [id]);
        gate.putProceed!.complete();
        await saving;
        await f.notes.flush();
        expect(gate.calls.where((c) => c == 'putAnnotation'), hasLength(1));
        await f.verifyNote(id, 'Newest\nrevision');
      } finally {
        if (gate.putProceed?.isCompleted == false) gate.putProceed!.complete();
        await f.dispose();
      }
    },
  );

  testWidgets(
    'late creation failure retains the newest revision for its inactive book and ignores the old presentation',
    (tester) async {
      await _readerAction(
        tester,
        () async {
          late AnnotationStoreGate gate;
          final f = await _ReaderFixture.create(
            'text.pdf',
            wrapStore: (s) => gate = AnnotationStoreGate(s),
          );
          try {
            final second =
                (await f.container
                        .read(workspaceControllerProvider.notifier)
                        .openPath(p.absolute('test/fixtures/reflowable.epub')))
                    .books
                    .single;
            gate.failPut = true;
            gate.putEntered = Completer<void>();
            gate.putProceed = Completer<void>();
            await f.openSelectionPopover();
            final old = Map.of(f.popup);
            await f.action('noteDraft', {'note': 'First text'});
            await gate.putEntered!.future;
            final source = f.drafts.sources.values.single;
            await f.action('noteDraft', {'note': 'Latest protected text'});
            final switching = f.reader.open(second.id);
            gate.putProceed!.complete();
            await switching;
            await f.event('ready');
            await f.event('opened');
            expectSync(
              f.drafts.drafts.values.any((d) => d.error != null),
              isTrue,
            );
            expectSync(f.state.bookId, second.id);
            expectSync(
              f.drafts.drafts[source.id]!.text,
              'Latest protected text',
            );
            await f.event('popoverAction', {
              'session': old['session'],
              'presentation': old['presentation'],
              'action': 'noteDraft',
              'note': 'Obsolete text',
            });
            expectSync(
              f.drafts.drafts[source.id]!.text,
              'Latest protected text',
            );
            gate.failPut = false;
            await f.notes.flush();
            expectSync(
              (await f.store.call('annotations', source.bookId) as List)
                  .single['note'],
              'Latest protected text',
            );
            expectSync(await f.store.call('annotations', second.id), isEmpty);
            expectSync(f.reader.annotations, isEmpty);
            expectSync(
              gate.calls.where((c) => c == 'putAnnotation'),
              hasLength(2),
            );
            await f.reader.open(source.bookId);
            await f.event('ready');
            await f.event('opened');
            await f.verifyNote(source.id, 'Latest protected text');
          } finally {
            gate.failPut = false;
            if (gate.putProceed?.isCompleted == false) {
              gate.putProceed!.complete();
            }
            await f.dispose();
          }
        },
        settle: false,
        widgetClock: true,
      );
    },
  );

  for (final outcome in ['confirm', 'cancel', 'later edit', 'failed delete']) {
    test(
      'pending creation discard: $outcome settles the insertion without touching another annotation',
      () async {
        late AnnotationStoreGate gate;
        final f = await _ReaderFixture.create(
          'text.pdf',
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        try {
          await f.event('location', {
            'anchor': {'page': 1},
          });
          await f.reader.annotation('bookmark', note: 'Unrelated saved note');
          final other = f.reader.annotations.single;
          gate.putEntered = Completer<void>();
          gate.putProceed = Completer<void>();
          await f.openSelectionPopover();
          await f.action('noteDraft', {'note': 'Pending creation'});
          await gate.putEntered!.future;
          final source = f.drafts.sources.values.single;
          final decision = Completer<bool>();
          final discarding = f.notes.discard(
            source.id,
            confirm: () => decision.future,
          );
          await Future<void>.delayed(const Duration(milliseconds: 650));
          expect(f.drafts.resolving, contains(source.id));
          if (outcome == 'later edit') {
            f.notes.edit(source, 'Later valid creation');
          }
          if (outcome == 'failed delete') gate.failDelete = true;
          gate.putProceed!.complete();
          decision.complete(outcome != 'cancel');
          if (outcome == 'failed delete') {
            await expectLater(discarding, throwsA(isA<FileSystemException>()));
            expect(f.drafts.drafts[source.id]!.creating, isTrue);
            expect(f.drafts.drafts[source.id]!.creationWritten, isTrue);
            expect(f.drafts.drafts[source.id]!.text, 'Pending creation');
            gate.failDelete = false;
            await f.notes.discard(source.id, confirm: () async => true);
          } else {
            await discarding;
          }
          await f.notes.flush();
          final records =
              await f.store.call('annotations', source.bookId) as List;
          expect(
            records.singleWhere((a) => a['id'] == other.id)['note'],
            'Unrelated saved note',
          );
          final created = records.where((a) => a['id'] == source.id);
          if (outcome == 'cancel' || outcome == 'later edit') {
            expect(
              created.single['note'],
              outcome == 'cancel' ? 'Pending creation' : 'Later valid creation',
            );
          } else {
            expect(created, isEmpty);
            await f.verifyNote(other.id, 'Unrelated saved note');
            // An old popover callback after discard cannot turn into a new note.
            await f.action('noteDraft', {'note': 'Obsolete callback'});
            await f.action('highlight', {'note': 'Obsolete callback'});
            await f.notes.flush();
            expect(
              (await f.store.call('annotations', source.bookId) as List).length,
              1,
            );
          }
        } finally {
          gate.failDelete = false;
          if (gate.putProceed?.isCompleted == false) {
            gate.putProceed!.complete();
          }
          await f.dispose();
        }
      },
    );
  }

  test(
    'failed creation discard removes only its unsaved intent and remains absent after reopening',
    () async {
      late AnnotationStoreGate gate;
      final f = await _ReaderFixture.create(
        'text.pdf',
        wrapStore: (s) => gate = AnnotationStoreGate(s),
      );
      try {
        gate.failPut = true;
        await f.openSelectionPopover();
        await f.action('noteDraft', {'note': 'Never inserted'});
        await _until(() => f.drafts.drafts.values.any((d) => d.error != null));
        final id = f.drafts.sources.keys.single;
        await f.notes.discard(id, confirm: () async => true);
        gate.failPut = false;
        await f.notes.flush();
        await f.action('noteDraft', {'note': 'Late callback'});
        await f.action('highlight', {'note': 'Late callback'});
        await f.reader.close();
        final book = f.container.read(workspaceControllerProvider).books.single;
        await f.reader.open(book.id);
        expect(await f.store.call('annotations', book.id), isEmpty);
        expect(f.drafts.drafts, isEmpty);
      } finally {
        gate.failPut = false;
        await f.dispose();
      }
    },
  );

  test(
    'older update completion cannot overwrite a reopened editor revision, and deletion rejects stale callbacks',
    () async {
      late AnnotationStoreGate gate;
      final f = await _ReaderFixture.create(
        'text.pdf',
        wrapStore: (s) => gate = AnnotationStoreGate(s),
      );
      try {
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Saved A');
        final a = f.reader.annotations.single;
        gate.entered = Completer<void>();
        gate.proceed = Completer<void>();
        f.notes.edit(a, 'Older B');
        final saving = f.notes.save(a.id);
        await gate.entered!.future;
        await f.openAnnotationPopover(a);
        expect(f.popup['note'], 'Older B');
        await f.action('noteDraft', {'note': 'Newer C'});
        gate.proceed!.complete();
        await saving;
        expect(f.drafts.drafts[a.id]!.text, 'Newer C');
        await f.notes.flush();
        await f.verifyNote(a.id, 'Newer C');
        await f.openAnnotationPopover(a);
        final obsolete = Map.of(f.popup);
        await f.container
            .read(workspaceControllerProvider.notifier)
            .deleteAnnotation(a.id);
        await f.action('noteDraft', {'note': 'Deleted text'});
        await f.action('highlight', {'note': 'Deleted text'});
        await f.action('annotationNote', {'note': 'Deleted text'});
        await f.notes.flush();
        expect(f.drafts.drafts, isEmpty);
        expect(await f.store.call('annotations', a.bookId), isEmpty);
        await f.openSelectionPopover();
        await f.event('popoverAction', {
          'presentation': obsolete['presentation'],
          'action': 'noteDraft',
          'note': 'Obsolete presentation',
        });
        expect(f.drafts.drafts, isEmpty);
      } finally {
        if (gate.proceed?.isCompleted == false) gate.proceed!.complete();
        await f.dispose();
      }
    },
  );
  test(
    'selection search preserves literal surrounding whitespace while lookup trims',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      try {
        await f.event('selection', {
          'anchor': {'cfi': 'epubcfi(/6/2!/4/2/1:6)', 'index': 0},
          'text': ' library ',
          'reference': 'Chapter 1',
        });
        expect(f.reader.captureSelection()!.text, 'library');
        expect(
          f.reader.captureSelection(preserveWhitespace: true)!.text,
          ' library ',
        );
        await f.reader.searchSelection();
        await _until(() => f.dispatches.any((d) => d['action'] == 'search'));
        expect(
          f.dispatches.lastWhere((d) => d['action'] == 'search')['query'],
          ' library ',
        );
        expect(f.search.query, ' library ');
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'reader search preserves whitespace and counts bounded publication windows',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        await f.event('location', {
          'anchor': {'page': 0},
          'progress': .1,
          'noText': true,
        });
        f.reader.search('  literal .*  ', offset: 400, limit: 200);
        await _until(() => f.dispatches.any((d) => d['action'] == 'search'));
        final command = f.dispatches.lastWhere((d) => d['action'] == 'search');
        expect(command['query'], '  literal .*  ');
        expect(command['offset'], 400);
        expect(command['limit'], 200);
        final waiting = f.reader.waitForSearch();
        await f.event('match', {
          'queryId': command['queryId'],
          'anchor': {'page': 3},
          'excerpt': '  literal .*  ',
          'index': 400,
        });
        await f.event('pageText', {'page': 0, 'noText': true, 'text': ''});
        expect(f.state.query, '  literal .*  ');
        expect(f.state.searching, isTrue);
        await f.event('searchDone', {
          'queryId': command['queryId'],
          'total': 1200,
        });
        expect(await waiting, isTrue);
        expect(f.state.searchTotal, 1200);
        expect(f.state.searchOffset, 400);
        expect(f.state.matches.single['index'], 400);
        expect(f.dispatches.where((d) => d['action'] == 'goto'), isEmpty);
        f.reader.search(' ');
        await _until(
          () =>
              f.dispatches.lastWhere((d) => d['action'] == 'search')['query'] ==
              ' ',
        );
        expect(f.state.searching, isTrue);
        final obsolete = f.reader.waitForSearch();
        f.reader.search('');
        expect(await obsolete, isFalse);
        expect(f.state.matches, isEmpty);
        expect(f.state.searchTotal, 0);
        expect(f.state.searchStatus, 'idle');
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'reader occurrence windows reject cancellation and preserve complete counts',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      try {
        f.reader.search('library');
        await _until(() => f.dispatches.any((d) => d['action'] == 'search'));
        final first = f.dispatches.lastWhere((d) => d['action'] == 'search');
        await f.event('match', {
          'queryId': first['queryId'],
          'anchor': {'cfi': 'first'},
          'excerpt': 'library',
        });
        await f.event('searchDone', {
          'queryId': first['queryId'],
          'total': 1201,
        });
        expect(await f.reader.loadSearchWindow(0), isTrue);
        final loading = f.reader.loadSearchWindow(1200);
        await _until(
          () =>
              f.dispatches.lastWhere(
                (d) => d['action'] == 'search',
              )['offset'] ==
              1200,
        );
        final last = f.dispatches.lastWhere((d) => d['action'] == 'search');
        await f.event('match', {
          'queryId': last['queryId'],
          'anchor': {'cfi': 'last'},
          'excerpt': 'library',
          'index': 1200,
        });
        await f.event('searchDone', {
          'queryId': last['queryId'],
          'total': 1201,
        });
        expect(await loading, isTrue);
        expect(f.state.searchTotal, 1201);
        expect(f.state.matches, hasLength(1));
        final cancelled = f.reader.loadSearchWindow(300);
        await f.reader.cancelSearch();
        expect(await cancelled, isFalse);
        expect(f.state.searchStatus, 'cancelled');
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'header search survives sidebar changes and rejects obsolete results before and after cancellation',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      try {
        expect(f.state.searchStatus, 'idle');
        f.searchController.open(category: BookSearchCategory.bookText);
        f.reader.search('old');
        await Future<void>.delayed(const Duration(milliseconds: 330));
        final old = f.dispatches.lastWhere(
          (m) => m['action'] == 'search',
        )['queryId'];
        f.reader.search('library');
        await Future<void>.delayed(const Duration(milliseconds: 330));
        final current = f.dispatches.lastWhere(
          (m) => m['action'] == 'search',
        )['queryId'];
        await f.event('match', {
          'queryId': old,
          'excerpt': 'obsolete',
          'anchor': {'cfi': 'old'},
        });
        expect(f.state.matches, isEmpty);
        await f.event('match', {
          'queryId': current,
          'excerpt': 'A quiet library',
          'anchor': {'cfi': 'epubcfi(/6/2!/4/2/1:6)'},
        });
        await f.event('searchDone', {'queryId': current});
        f.sidebarController.selectPanel(BookSidebarPanel.marks);
        f.searchController.open(category: BookSearchCategory.bookText);
        expect(f.state.query, 'library');
        expect(f.state.matches.single['excerpt'], 'A quiet library');
        await f.reader.selectMatch(0);
        expect(f.state.currentMatch, 0);
        expect(f.dispatches.last['anchor'], f.state.matches.single['anchor']);
        await f.reader.cancelSearch();
        await f.event('match', {'queryId': current, 'excerpt': 'late'});
        expect(f.state.matches.length, 1);
        expect(f.state.searchStatus, 'cancelled');
        f.reader.search('');
        expect(f.state.searchStatus, 'idle');
        expect(f.state.matches, isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'popover draft autosave and final Save retain one annotation and the latest color',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      try {
        await f.event('selection', {
          'anchor': {'cfi': 'epubcfi(/6/2!/4/2/1:6)', 'index': 0},
          'text': 'Quotation',
          'reference': 'Chapter 1',
          'settled': true,
        });
        await f.reader.showPopover('selection');
        final popup =
            f.calls.lastWhere((c) => c.method == 'popover').arguments as Map;
        await f.event('popoverAction', {
          'presentation': popup['presentation'],
          'action': 'noteDraft',
          'note': 'Draft',
        });
        await f.container.read(notebookControllerProvider.notifier).flush();
        await f.event('popoverAction', {
          'presentation': popup['presentation'],
          'action': 'highlightColor',
          'color': 'blue',
        });
        await f.event('popoverAction', {
          'presentation': popup['presentation'],
          'action': 'highlight',
          'note': 'Final multiline\nnote',
          'color': 'blue',
        });
        final annotations = f.container
            .read(workspaceControllerProvider)
            .annotations;
        expect(annotations, hasLength(1));
        expect(annotations.single.note, 'Final multiline\nnote');
        expect(annotations.single.color, 'blue');
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'native selection ownership keeps reader visible and saves the captured passage and color',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      try {
        f.calls.clear();
        const anchor = {'cfi': 'epubcfi(/6/2!/4/2/1:6)', 'index': 0};
        final owner = await f.selectionMenuOwner({
          'anchor': anchor,
          'text': 'A quiet library',
          'reference': 'Chapter 1',
          'rect': {'x': 30, 'y': 20, 'width': 120, 'height': 24},
        });
        expect(owner.target.session, f.session);
        expect(
          f.calls.where(
            (c) => c.method == 'popover' || c.method == 'capturePopover',
          ),
          isEmpty,
        );
        expect(
          f.calls.where((c) => c.method == 'visible' && c.arguments == false),
          isEmpty,
        );
        await f.event('selection', {'anchor': null, 'text': ''});
        await f.reader.selectionMenuAction(
          owner,
          ReaderSelectionAction.highlight,
          color: 'blue',
        );
        final a = f.reader.annotations.single;
        f.notes.edit(a, 'Keep this passage');
        await f.notes.flush();
        expect(f.reader.annotations.single.anchor, anchor);
        expect(f.reader.annotations.single.note, 'Keep this passage');
        expect(f.reader.annotations.single.color, 'blue');
        expect(f.reader.highlightColor, 'blue');
        await f.reader.selectionMenuAction(
          owner,
          ReaderSelectionAction.highlight,
          color: 'pink',
        );
        await f.event('popoverAction', {
          'presentation': owner.target.presentation,
          'action': 'highlight',
          'note': 'stale',
          'color': 'pink',
        });
        expect(f.reader.annotations, hasLength(1));
        expect(f.reader.annotations.single.note, 'Keep this passage');
        await f.verifyNote(a.id, 'Keep this passage');
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'PDF defaults and bookmark toggle remain correct through changed viewport coordinates and saved appearance',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        expect(f.reader.appearance['flow'], 'scrolled');
        expect(f.reader.appearance['zoom'], 'fit-width');
        await f.event('location', {
          'anchor': {
            'page': 1,
            'point': [0, 700],
          },
          'reference': 'Page ii',
          'progress': .3,
        });
        await f.reader.annotation('bookmark');
        expect(f.reader.bookmarked, isTrue);
        await f.event('location', {
          'anchor': {
            'page': 1,
            'point': [25, 400],
          },
          'reference': 'Page ii',
          'progress': .3,
        });
        expect(f.reader.bookmarked, isTrue);
        await f.reader.annotation('bookmark');
        expect(f.reader.bookmarked, isFalse);
        expect(
          f.container.read(workspaceControllerProvider).annotations,
          isEmpty,
        );
        await f.reader.setAppearance({'zoom': 'fit-page', 'flow': 'paginated'});
        expect(f.reader.appearance['flow'], 'paginated');
        expect(f.reader.appearance['zoom'], 'fit-page');
        await f.reader.resetAppearance();
        expect(f.reader.appearance['zoom'], 'fit-width');
      } finally {
        await f.dispose();
      }
    },
  );
  test(
    'narration retains its passage and paused state when voice/speed change, then stops when the reader closes',
    () async {
      final speech = _Speech(),
          f = await _ReaderFixture.create('reflowable.epub', speech: speech);
      try {
        final narration = f.container.read(
          narrationControllerProvider.notifier,
        );
        const passage = {
          'text': 'A quiet library',
          'anchor': {'cfi': 'epubcfi(/6/2!/4/2/1:6)', 'index': 0},
        };
        await narration.start(passage: passage);
        expect(f.container.read(narrationControllerProvider).status, 'playing');
        expect(f.dispatches.last['anchor'], passage['anchor']);
        await narration.pauseResume();
        expect(f.container.read(narrationControllerProvider).status, 'paused');
        await narration.configure(voice: 'Fixture Voice 2', speed: 1.5);
        expect(f.container.read(narrationControllerProvider).status, 'paused');
        final spoken = speech.calls.lastWhere((c) => c.action == 'speak');
        expect(spoken.args['text'], passage['text']);
        expect(spoken.args['voice'], 'Fixture Voice 2');
        expect(spoken.args['speed'], 1.5);
        await narration.pauseResume();
        expect(f.container.read(narrationControllerProvider).status, 'playing');
        await f.reader.close();
        expect(speech.calls.last.action, 'stop');
        expect(f.container.read(narrationControllerProvider).active, isFalse);
        final stopped = f.dispatches.lastIndexWhere(
          (m) => m['action'] == 'speaking' && m['anchor'] == null,
        );
        expect(stopped, greaterThanOrEqualTo(0));
        expect(
          stopped,
          lessThan(f.dispatches.lastIndexWhere((m) => m['action'] == 'flush')),
        );
      } finally {
        await f.dispose();
        await speech.dispose();
      }
    },
  );
  test(
    'read-aloud from position continues in order, stops at the end and does not turn a selection into continuous narration',
    () async {
      final speech = _Speech(),
          f = await _ReaderFixture.create('text.pdf', speech: speech);
      try {
        f.onDispatch = (message) async {
          if (message['action'] == 'passage' ||
              message['action'] == 'advanceSpeech') {
            final advanced = message['action'] == 'advanceSpeech';
            if (advanced) await f.event('navigation', {'next': false});
            await f.event('passage', {
              'request': message['request'],
              'text': advanced ? 'Second passage' : 'First passage',
              'selected': false,
              'anchor': {'page': advanced ? 1 : 0},
            });
          }
        };
        await f.event('navigation', {'next': true});
        final narration = f.container.read(
          narrationControllerProvider.notifier,
        );
        await narration.start();
        speech.events.add('stopped');
        final elapsed = Stopwatch()..start();
        while (f.container.read(narrationControllerProvider).text !=
                'Second passage' ||
            f.container.read(narrationControllerProvider).status != 'playing') {
          if (elapsed.elapsed > const Duration(seconds: 5)) {
            fail('Continuation did not reach the next passage');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        speech.events.add('stopped');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(f.container.read(narrationControllerProvider).active, isFalse);
        expect(
          speech.calls
              .where((c) => c.action == 'speak')
              .map((c) => c.args['text']),
          ['First passage', 'Second passage'],
        );
        await f.event('navigation', {'next': true});
        await narration.start(
          passage: {
            'text': 'Selected sentence',
            'anchor': {'page': 1},
          },
        );
        speech.events.add('stopped');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(speech.calls.where((c) => c.action == 'speak').length, 3);
        expect(f.container.read(narrationControllerProvider).active, isFalse);
      } finally {
        await f.dispose();
        await speech.dispose();
      }
    },
  );
  test(
    'closing an inactive speech error clears it without starting language resources',
    () async {
      final speech = _Speech(),
          f = await _ReaderFixture.create('text.pdf', speech: speech);
      try {
        final narration = f.container.read(
          narrationControllerProvider.notifier,
        );
        await narration.start(
          passage: {
            'text': '',
            'anchor': {'page': 0},
          },
        );
        expect(f.container.read(narrationControllerProvider).error, 'no-text');
        await narration.stop();
        expect(f.container.read(narrationControllerProvider).error, isNull);
        expect(speech.calls, isEmpty);
      } finally {
        await f.dispose();
        await speech.dispose();
      }
    },
  );
  test(
    'a recreated Dart controller cannot accept events from the previous native reader session',
    () async {
      final first = await _ReaderFixture.create('reflowable.epub'),
          old = first.session;
      await first.dispose();
      final second = await _ReaderFixture.create('text.pdf');
      try {
        expect(second.session, isNot(old));
        await second.event('location', {
          'session': old,
          'anchor': {'cfi': 'obsolete'},
          'progress': .8,
        });
        expect(second.state.location, isEmpty);
        expect(
          second.dispatches.every((m) => m['session'] == second.session),
          isTrue,
        );
      } finally {
        await second.dispose();
      }
    },
  );
  test(
    'thumbnail cache is bounded and stale native sessions cannot replace current content',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        await f.checkedEvent('metadata', {'pages': 100});
        final png =
            'data:image/png;base64,${base64Encode(image.encodePng(image.Image(width: 4, height: 2)))}';
        for (var i = 0; i < 40; i++) {
          f.reader.requestThumbnailWindow([i]);
          await f.checkedEvent('thumbnail', {
            'page': i,
            'request': f.dispatches.lastWhere(
              (d) => d['action'] == 'thumbnailWindow',
            )['request'],
            'data': png,
            'width': 4,
            'height': 2,
          });
        }
        expect(f.state.thumbnails.length, 32);
        expect(f.state.thumbnails.containsKey(0), isFalse);
        await f.event('thumbnail', {
          'session': 'old',
          'page': 0,
          'data': 'stale',
        });
        expect(f.state.thumbnails.containsKey(0), isFalse);
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'comic region notes retain protected drafts, independent bookmarks and private payloads',
    () async {
      late AnnotationStoreGate gate;
      final f = await _ReaderFixture.create(
        'formats/comic-deflated.cbz',
        wrapStore: (store) => gate = AnnotationStoreGate(store),
      );
      try {
        final book = f.reader.book!;
        final descriptor =
            await f.store.call('prepare', {'id': book.id, 'path': book.path})
                as Map;
        final index =
            jsonDecode(
                  await File(
                    '${descriptor['cacheDirectory']}.json',
                  ).readAsString(),
                )
                as Map;
        final page = {
          'kind': 'comic',
          'version': 1,
          'format': 'cbz',
          'page': 0,
          'pageId': index['pages'][0]['file'],
        };
        await f.event('metadata', {
          'pages': 7,
          'labels': ['1', '2', '3', '4', '5', '6', '7'],
        });
        await f.event('location', {
          'anchor': page,
          'progress': .1,
          'reference': 'Page 1',
          'noText': true,
        });
        expect(f.reader.textInteraction, isFalse);
        expect(f.reader.regionNotes, isTrue);
        expect(
          f.sidebarController.available(BookSidebarPanel.thumbnails),
          isTrue,
        );
        final query = f.state.query;
        f.reader.search('art');
        expect(f.state.query, query);
        await f.reader.addNote();
        expect(f.dispatches.last['action'], 'beginRegion');
        final region = {
          ...page,
          'region': [.1, .2, .3, .4],
        };
        final regionMenu = await f.selectionMenuOwner({
          'anchor': region,
          'text': '',
          'reference': 'Page 1',
          'rect': {'x': 10, 'y': 20, 'width': 30, 'height': 40},
        }, type: 'regionSelected');
        expect(f.calls.where((c) => c.method == 'popover'), isEmpty);
        await f.reader.selectionMenuAction(
          regionMenu,
          ReaderSelectionAction.addNote,
        );
        gate.failPut = true;
        final created = f.drafts.sources.values.single;
        f.notes.edit(created, 'Private image note');
        try {
          await f.notes.save(created.id);
        } catch (_) {}
        await _until(
          () =>
              f.drafts.drafts.isNotEmpty &&
              f.drafts.drafts.values.single.error != null,
        );
        final id = f.drafts.drafts.keys.single;
        expect(f.drafts.sources[id]!.kind, 'region');
        expect(f.drafts.sources[id]!.text, isEmpty);
        expect(f.drafts.drafts[id]!.text, 'Private image note');
        expect(await f.store.call('annotations', book.id), isEmpty);
        gate.failPut = false;
        await f.notes.save(id);
        await f.reader.syncAnnotations();
        final projected =
            (f.dispatches.lastWhere(
                          (d) => d['action'] == 'annotations',
                        )['value']
                        as List)
                    .single
                as Map;
        expect(projected['annotationKind'], 'region');
        expect(projected['anchor'], region);
        expect(projected.containsKey('note'), isFalse);
        await f.reader.annotation('bookmark');
        expect((await f.store.call('annotations', book.id) as List).length, 2);
        await f.reader.annotation('bookmark');
        expect(
          (await f.store.call('annotations', book.id) as List)
              .single['annotationKind'],
          'region',
        );
        await f.openAnnotationPopover(f.reader.annotations.single);
        await f.action('annotationNote', {'note': 'Edited region note'});
        expect(
          (await f.store.call('annotations', book.id) as List).single['note'],
          'Edited region note',
        );
        final popovers = f.calls.where((c) => c.method == 'popover').length;
        await f.event('regionSelected', {
          'session': 'obsolete',
          'anchor': region,
          'text': '',
        });
        expect(f.calls.where((c) => c.method == 'popover').length, popovers);
        await f.container
            .read(workspaceControllerProvider.notifier)
            .deleteAnnotation(id);
        expect(await f.store.call('annotations', book.id), isEmpty);
      } finally {
        await f.dispose();
      }
    },
  );
  testWidgets(
    'comic sidebar exposes page panels without publication text search',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create('formats/comic-deflated.cbz');
        await f.event('metadata', {'pages': 3, 'fixed': true});
        await f.sidebarController.selectPanel(BookSidebarPanel.outline);
      });
      try {
        await tester.pumpWidget(_sidebarApplication(f));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Search'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('reader-sidebar-view-menu')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Search Results'), findsNothing);
        expect(find.text('Thumbnails'), findsOneWidget);
        expect(find.text('Marks'), findsOneWidget);
        await tester.tap(find.text('Thumbnails'));
        await _pumpUntil(
          tester,
          () => f.dispatches.any(
            (d) =>
                d['action'] == 'thumbnailWindow' &&
                (d['pages'] as List).isNotEmpty,
          ),
          settle: false,
        );
        final request = f.dispatches.lastWhere(
          (d) =>
              d['action'] == 'thumbnailWindow' &&
              (d['pages'] as List).isNotEmpty,
        );
        await _readerAction(tester, () async {
          for (final page in request['pages'] as List) {
            await f.event('thumbnailError', {
              'request': request['request'],
              'page': page,
            });
          }
        });
        expect(f.sidebar.panel.preference, 'thumbnails');
        expect(f.search.active, isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
      }
    },
  );
}

void _professionalWorkspaceTests() {
  testWidgets(
    'search retires navigation tooltips and keeps Close Search above native content',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.sidebarController.setOpen(true);
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        final home = find.descendant(
          of: find.byKey(const ValueKey('book-home')),
          matching: find.byType(Tooltip),
        );
        tester.state<TooltipState>(home).ensureTooltipVisible();
        await tester.pump(const Duration(seconds: 1));
        final homeBounds = tester.getRect(find.text('Home'));
        final headerBounds = tester.getRect(find.byType(BookHeader));
        expect(homeBounds.top, greaterThanOrEqualTo(headerBounds.top));
        expect(homeBounds.bottom, lessThanOrEqualTo(headerBounds.bottom));
        Tooltip.dismissAllToolTips();
        await tester.pumpAndSettle();
        final selector = find.descendant(
          of: find.byKey(const ValueKey('reader-sidebar-view-menu')),
          matching: find.byType(Tooltip),
        );
        tester.state<TooltipState>(selector).ensureTooltipVisible();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Sidebar View'), findsOneWidget);
        await _readerAction(
          tester,
          () => f.searchController.open(
            category: BookSearchCategory.notebook,
            query: 'query',
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Sidebar View'), findsNothing);
        final clear = find.descendant(
          of: find.byKey(const ValueKey('book-header-search')),
          matching: find.byType(Tooltip),
        );
        final clearLabel = MaterialLocalizations.of(
          tester.element(clear),
        ).clearButtonTooltip;
        expect(tester.widget<Tooltip>(clear).message, clearLabel);
        tester.state<TooltipState>(clear).ensureTooltipVisible();
        await tester.pump(const Duration(seconds: 1));
        final clearBounds = tester.getRect(find.text(clearLabel));
        expect(clearBounds.top, greaterThanOrEqualTo(headerBounds.top));
        expect(clearBounds.bottom, lessThanOrEqualTo(headerBounds.bottom));
        Tooltip.dismissAllToolTips();
        await tester.pumpAndSettle();
        final close = find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.message == 'Close Search',
        );
        tester.state<TooltipState>(close).ensureTooltipVisible();
        await tester.pump(const Duration(seconds: 1));
        final bounds = tester.getRect(find.text('Close Search'));
        final surface = tester.getRect(find.byType(BookSearchSidebar));
        expect(bounds.left, greaterThanOrEqualTo(surface.left));
        expect(bounds.right, lessThanOrEqualTo(surface.right));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Close Search'), findsNothing);
        expect(f.sidebar.open, true);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'Notebook shows the cached image region beside the complete private note',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'formats/comic-deflated.cbz',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        final descriptor =
            f.calls.lastWhere((call) => call.method == 'open').arguments as Map;
        final index =
            jsonDecode(
                  await File(
                    '${descriptor['cacheDirectory']}.json',
                  ).readAsString(),
                )
                as Map;
        final region = {
          'kind': 'comic',
          'version': 1,
          'format': 'cbz',
          'page': 0,
          'pageId': index['pages'][0]['file'],
          'region': [.1, .1, .3, .3],
        };
        final menu = await f.selectionMenuOwner({
          'anchor': region,
          'text': '',
        }, type: 'regionSelected');
        await f.reader.selectionMenuAction(menu, ReaderSelectionAction.addNote);
        final a = f.drafts.sources.values.single;
        f.notes.edit(a, 'Private region note.\nA complete second line.');
        await f.notes.flush();
      });
      try {
        // Wait for the actual cache read before settling animations. An
        // indeterminate progress indicator cannot settle a fake test clock.
        await _mountHeaderApplication(
          tester,
          f,
          '/notebook/${f.state.bookId}',
          settle: false,
        );
        final preview = find.byType(NotebookRegionPreview);
        await _pumpUntil(
          tester,
          () => find
              .descendant(of: preview, matching: find.byType(Image))
              .evaluate()
              .isNotEmpty,
        );
        expect(f.reader.suspended, true);
        expect(find.textContaining('A complete second line.'), findsOneWidget);
        expect(find.textContaining('preview unavailable'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'Escape closes shared search from the Notebook editor without changing its draft',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Private note');
      });
      try {
        final id = f.state.bookId!, annotation = f.reader.annotations.single;
        await _mountHeaderApplication(tester, f, '/notebook/$id');
        await _readerAction(
          tester,
          () => f.searchController.open(
            category: BookSearchCategory.notebook,
            query: 'Private',
          ),
        );
        final snapshot = f.search;
        final header = tester.element(find.byType(BookHeader));
        await _readerAction(
          tester,
          () => activateBookSearchResult(
            header,
            header as WidgetRef,
            snapshot.results.single,
            snapshot.generation,
          ),
        );
        final editor = find.descendant(
          of: find.byType(NotebookContent),
          matching: find.byType(TextField),
        );
        await tester.tap(editor);
        await tester.enterText(editor, 'Private draft remains intact');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(f.search.active, false);
        expect(
          f.drafts.drafts[annotation.id]?.text,
          'Private draft remains intact',
        );
        expect(f.reader.suspended, true);
        expect(f.state.surfaceVisible, false);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'returning to an edited Notebook preserves active header search focus',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Private note');
        f.notes.revealAnnotation(
          f.state.bookId!,
          f.reader.annotations.single.id,
        );
      });
      try {
        await _mountHeaderApplication(tester, f, '/notebook/${f.state.bookId}');
        await _readerAction(
          tester,
          () => f.searchController.open(
            category: BookSearchCategory.notebook,
            query: 'Private',
          ),
        );
        final focus = FocusManager.instance.primaryFocus;
        expect(focus, isA<BusyBooksSearchFocusNode>());
        await _readerAction(
          tester,
          () => _appCommands(tester).execute(BusyBooksCommandIds.viewReading),
          settle: false,
        );
        await _pumpUntil(
          tester,
          () => f.state.surfaceVisible && !f.search.loading,
        );
        await _readerAction(
          tester,
          () => _appCommands(tester).execute(BusyBooksCommandIds.viewNotebook),
          settle: false,
        );
        await _pumpUntil(tester, () => !f.search.loading);
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(f.search.query, 'Private');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(f.search.active, false);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'book properties remain reachable from Notebook without renderer readiness',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        await _mountHeaderApplication(tester, f, '/notebook/${f.state.bookId}');
        expect(f.reader.interactive, false);
        await _mainMenuSelect(
          tester,
          'Book Properties',
          tooltip: 'Book Actions',
        );
        await _pumpUntil(
          tester,
          () => find.byType(BusyBooksDialogShell).evaluate().isNotEmpty,
        );
        expect(find.text('Book Properties'), findsOneWidget);
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .any((field) => field.controller?.text == f.reader.book!.title),
          true,
        );
        await tester.tap(find.widgetWithText(BusyBooksDialogButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'narrow Book Text search runs behind its overlay and activation restores the owned surface',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.event('metadata', {'pages': 4, 'fixed': true});
      });
      try {
        final id = f.state.bookId!;
        await _mountHeaderApplication(tester, f, '/read/$id');
        tester.view.physicalSize = const Size(540, 850);
        await tester.pumpAndSettle();
        final before = f.dispatches
            .where((d) => d['action'] == 'search')
            .length;
        await _readerAction(
          tester,
          () => f.searchController.open(
            category: BookSearchCategory.bookText,
            query: 'library',
          ),
        );
        await _pumpUntil(
          tester,
          () =>
              f.dispatches.where((d) => d['action'] == 'search').length >
              before,
        );
        expect(f.state.surfaceVisible, false);
        expect(f.reader.interactive, false);
        expect(f.reader.canSearch, true);
        final query = f.dispatches.lastWhere(
          (d) => d['action'] == 'search',
        )['queryId'];
        await _readerAction(tester, () async {
          await f.event('match', {
            'queryId': query,
            'anchor': {'page': 2},
            'excerpt': 'library location',
          });
          await f.event('searchDone', {'queryId': query});
        });
        await tester.tap(find.text('library location'));
        await _pumpUntil(
          tester,
          () => f.dispatches.any(
            (d) => d['action'] == 'goto' && d['anchor']['page'] == 2,
          ),
        );
        expect(f.search.active, false);
        expect(f.sidebar.open, false);
        expect(f.state.surfaceVisible, true);
        expect(f.reader.interactive, true);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'shared workspace retains shell, search, sidebar and renderer across both book views',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          speech: _Speech(),
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.openSelectionPopover();
        await f.reader.annotation(
          'highlight',
          note: 'Shared private note\nSecond line',
        );
        await f.sidebarController.selectPanel(BookSidebarPanel.marks);
        f.sidebarController.filter(
          type: AnnotationTypeFilter.highlights,
          withNotes: true,
        );
      });
      try {
        final id = f.state.bookId!;
        await _mountHeaderApplication(tester, f, '/read/$id');
        final shell = tester.state(find.byType(BookWorkspaceScreen));
        final header = tester.state(find.byType(BookHeader));
        final opens = f.calls.where((c) => c.method == 'open').length;
        await _readerAction(
          tester,
          () => f.searchController.open(
            category: BookSearchCategory.notebook,
            query: 'Shared',
          ),
        );
        expect(find.byType(BookSearchSidebar), findsOneWidget);
        expect(f.search.results.single, isA<AnnotationSearchResult>());
        await _readerAction(
          tester,
          () => _appCommands(tester).execute(BusyBooksCommandIds.viewNotebook),
          settle: false,
        );
        await _pumpUntil(tester, () => !f.search.loading);
        expect(
          identical(tester.state(find.byType(BookWorkspaceScreen)), shell),
          true,
        );
        expect(identical(tester.state(find.byType(BookHeader)), header), true);
        expect(f.search.active, true);
        expect(f.search.query, 'Shared');
        expect(f.sidebar.panel, BookSidebarPanel.marks);
        expect(f.sidebar.open, true);
        expect(f.sidebar.filter, AnnotationTypeFilter.highlights);
        expect(f.sidebar.withNotes, true);
        expect(f.reader.suspended, true);
        expect(f.state.surfaceVisible, false);
        final commands = f.dispatches.length;
        await _readerAction(tester, () => f.reader.send('next'));
        expect(f.dispatches.length, commands);
        await _readerAction(
          tester,
          () => _appCommands(tester).execute(BusyBooksCommandIds.viewReading),
          settle: false,
        );
        await _pumpUntil(
          tester,
          () => f.state.surfaceVisible && !f.search.loading,
        );
        expect(f.state.surfaceVisible, true);
        expect(f.reader.suspended, false);
        expect(f.calls.where((c) => c.method == 'open').length, opens);
        f.searchController.close();
        await tester.pumpAndSettle();
        expect(find.byType(BookSearchSidebar), findsNothing);
        expect(f.sidebar.panel, BookSidebarPanel.marks);
        expect(f.sidebar.open, true);
        expect(f.sidebar.filter, AnnotationTypeFilter.highlights);
        expect(f.sidebar.withNotes, true);
        expect(find.textContaining('Shared private note'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  for (final suspend in [true, false]) {
    test(
      '${suspend ? 'suspension' : 'close'} drains renderer work before hiding the native surface',
      () async {
        final f = await _ReaderFixture.create('text.pdf');
        final entered = Completer<void>(), release = Completer<void>();
        Future<void>? transition;
        try {
          final id = f.state.bookId!;
          var visible = f.state.surfaceVisible;
          f.onNativeCall = (call) async {
            if (call.method == 'visible') visible = call.arguments as bool;
            if (call.method == 'dispatch' &&
                jsonDecode(call.arguments as String)['action'] == 'flush') {
              entered.complete();
              await release.future;
              // A busy PDF navigation/render publishes its final position
              // before acknowledging flush. Hiding WebKit first can stall the
              // animation frame that completes that work indefinitely.
              await f.event('location', {
                'anchor': {'page': 2},
                'progress': .75,
              });
            }
            return null;
          };
          transition = suspend ? f.reader.suspend() : f.reader.close();
          await entered.future;
          expect(visible, isTrue);
          expect(f.reader.suspended, isFalse);
          release.complete();
          await transition;
          final stored = await f.store.call('book', id) as Map;
          expect(stored['anchor']['page'], 2);
          expect(visible, isFalse);
          if (suspend) expect(f.reader.suspended, isTrue);
        } finally {
          if (!release.isCompleted) release.complete();
          await transition;
          f.onNativeCall = null;
          await f.dispose();
        }
      },
    );
  }

  test(
    'disposed speech service rejects calls without restarting its worker',
    () async {
      final speech = SpeechService();
      await speech.dispose();
      expect(speech.events.isClosed, isTrue);
      await expectLater(
        speech.call('voices'),
        throwsA(isA<SpeechServiceFailure>()),
      );
      await speech.dispose();
    },
  );

  for (final programmingFailure in [false, true]) {
    test(
      'speech stop ${programmingFailure ? 'propagates programming errors' : 'reports service loss without trapping safe navigation'}',
      () async {
        final speech = _Speech();
        final f = await _ReaderFixture.create('text.pdf', speech: speech);
        try {
          final narration = f.container.read(
            narrationControllerProvider.notifier,
          );
          await narration.start(
            passage: {
              'text': 'A quiet library',
              'anchor': {'page': 0},
            },
          );
          speech.stopError = programmingFailure
              ? ArgumentError('unexpected stop contract')
              : const SpeechServiceFailure(
                  'injected speech service unavailable',
                );
          if (programmingFailure) {
            await expectLater(narration.stop(), throwsArgumentError);
          } else {
            await narration.stop();
            expect(
              f.container.read(narrationControllerProvider).error,
              'injected speech service unavailable',
            );
          }
          expect(f.container.read(narrationControllerProvider).active, isFalse);
          await f.reader.suspend();
          expect(f.reader.suspended, isTrue);
          await f.reader.close();
          expect(f.state.bookId, isNull);
        } finally {
          speech.stopError = null;
          await f.dispose();
          await speech.dispose();
        }
      },
    );
  }

  test(
    'stale or unowned flush replies cannot acknowledge a newer native drain',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      Future<void>? flushing;
      int? request;
      try {
        await f.reader.flush();
        final previous = f.dispatches.lastWhere(
          (d) => d['action'] == 'flush',
        )['request'];
        f.acknowledgeFlush = false;
        f.onDispatch = (command) async {
          if (command['action'] == 'flush') request = command['request'] as int;
        };
        var completed = false;
        flushing = f.reader.flush().then((_) => completed = true);
        await _until(() => request != null);
        expect(request, isNot(previous));
        for (final reply in [previous, request! + 1, null]) {
          await f.event('flushed', {'request': reply});
          await Future<void>.delayed(Duration.zero);
          expect(completed, isFalse);
        }
        await f.event('flushed', {'request': request});
        await flushing;
        expect(completed, isTrue);
      } finally {
        if (request != null) await f.event('flushed', {'request': request});
        await flushing;
        f.acknowledgeFlush = true;
        f.onDispatch = null;
        await f.dispose();
      }
    },
  );

  test(
    'concurrent flush and suspension share the renderer acknowledgement',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      final entered = Completer<void>(), release = Completer<void>();
      Future<void>? saving, suspending;
      try {
        var requests = 0;
        f.onNativeCall = (call) async {
          if (call.method == 'dispatch' &&
              jsonDecode(call.arguments as String)['action'] == 'flush') {
            requests++;
            if (!entered.isCompleted) entered.complete();
            await release.future;
          }
          return null;
        };
        saving = f.reader.flush();
        await entered.future;
        suspending = f.reader.suspend();
        await Future<void>.delayed(Duration.zero);
        expect(requests, 1);
        release.complete();
        await Future.wait([saving, suspending]);
        expect(requests, 1);
        expect(f.reader.suspended, isTrue);
        expect(f.state.surfaceVisible, isFalse);
      } finally {
        if (!release.isCompleted) release.complete();
        await saving;
        await suspending;
        f.onNativeCall = null;
        await f.dispose();
      }
    },
  );

  test(
    'suspended renderer is sealed while Notebook edits still flush before close',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        await f.event('location', {
          'anchor': {'page': 0},
        });
        await f.reader.annotation('bookmark', note: 'Saved baseline');
        final annotation = f.reader.annotations.single;
        await f.reader.suspend();
        f.notes.edit(annotation, 'Notebook edit after suspension\n日本語');
        f.onNativeCall = (call) async {
          if (call.method == 'dispatch' &&
              jsonDecode(call.arguments as String)['action'] == 'flush') {
            throw StateError('Hidden renderer must not require another frame');
          }
          return null;
        };
        await f.reader.flush();
        await f.reader.close();
        final records =
            await f.store.call('annotations', annotation.bookId) as List;
        expect(
          (records.single as Map)['note'],
          'Notebook edit after suspension\n日本語',
        );
      } finally {
        f.onNativeCall = null;
        await f.dispose();
      }
    },
  );

  test(
    'failed suspension flush keeps the reader available and can be retried',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        f.onNativeCall = (call) async {
          if (call.method == 'dispatch' &&
              jsonDecode(call.arguments as String)['action'] == 'flush') {
            throw PlatformException(code: 'fixture-flush');
          }
          return null;
        };
        await expectLater(
          f.reader.suspend(),
          throwsA(isA<PlatformException>()),
        );
        expect(f.reader.suspended, isFalse);
        expect(f.state.surfaceVisible, isTrue);
        f.onNativeCall = null;
        await f.reader.suspend();
        expect(f.reader.suspended, isTrue);
        expect(f.state.surfaceVisible, isFalse);
      } finally {
        f.onNativeCall = null;
        await f.dispose();
      }
    },
  );

  testWidgets(
    'cached annotation search membership cannot revive a deleted record',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          searchController: _CachedSearchSnapshot.new,
        );
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Deleted search needle');
      });
      try {
        final id = f.state.bookId!;
        await _mountHeaderApplication(tester, f, '/read/$id');
        await _readerAction(
          tester,
          () => f.searchController.open(
            category: BookSearchCategory.notebook,
            query: 'needle',
          ),
        );
        final snapshot = f.search;
        final annotation =
            (snapshot.results.single as AnnotationSearchResult).annotation;
        await _readerAction(
          tester,
          () => f.container
              .read(workspaceControllerProvider.notifier)
              .deleteAnnotation(annotation.id),
          settle: false,
        );
        (f.searchController as _CachedSearchSnapshot).deliver(snapshot);
        expect(f.search.results, contains(snapshot.results.single));
        final header = tester.element(find.byType(BookHeader));
        await _readerAction(
          tester,
          () => activateBookSearchResult(
            header,
            header as WidgetRef,
            snapshot.results.single,
            snapshot.generation,
          ),
          settle: false,
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/read/$id',
        );
        expect(f.drafts.view(id).selected, isNot(annotation.id));
        expect(f.search.generation, greaterThan(snapshot.generation));
        await _pumpUntil(tester, () => !f.search.loading);
        expect(f.search.results, isEmpty);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  for (final category in [
    BookSearchCategory.notebook,
    BookSearchCategory.bookmarks,
  ]) {
    for (final change in ['deleted', 'query', 'category', 'book']) {
      testWidgets(
        'annotation search ${category.name} activation rejects a queued $change change',
        (tester) async {
          late _ReaderFixture f;
          final entered = Completer<void>(), proceed = Completer<void>();
          await _readerAction(tester, () async {
            f = await _ReaderFixture.create(
              'text.pdf',
              windowControls: WindowControlService(
                nativeWindow: _HeaderWindow(),
              ),
            );
            await f.openSelectionPopover();
            await f.event('location', {
              'anchor': {'page': 0},
            });
            await f.reader.annotation(
              category == BookSearchCategory.bookmarks
                  ? 'bookmark'
                  : 'highlight',
              note: 'Search target needle',
            );
          });
          try {
            final id = f.state.bookId!,
                annotation = f.reader.annotations.single;
            await _mountHeaderApplication(tester, f, '/read/$id');
            await _readerAction(
              tester,
              () =>
                  f.searchController.open(category: category, query: 'needle'),
            );
            final snapshot = f.search;
            final header = tester.element(find.byType(BookHeader));
            final workspace = f.container.read(
              workspaceControllerProvider.notifier,
            );
            var destination = '/read/$id';
            await _readerAction(tester, () async {
              final holding = workspace.navigate(() async {
                entered.complete();
                await proceed.future;
              });
              await entered.future;
              final activation = activateBookSearchResult(
                header,
                header as WidgetRef,
                snapshot.results.single,
                snapshot.generation,
              );
              switch (change) {
                case 'deleted':
                  await workspace.deleteAnnotation(annotation.id);
                case 'query':
                  f.searchController.query('different query');
                case 'category':
                  await f.searchController.open(
                    category: category == BookSearchCategory.bookmarks
                        ? BookSearchCategory.notebook
                        : BookSearchCategory.bookmarks,
                  );
                case 'book':
                  final other = await workspace.openPath(
                    p.absolute('test/fixtures/reflowable.epub'),
                  );
                  destination = '/notebook/${other.books.single.id}';
                  f.container.read(appRouterProvider).go(destination);
              }
              proceed.complete();
              await Future.wait([holding, activation]);
            }, settle: false);
            expect(
              f.container
                  .read(appRouterProvider)
                  .routeInformationProvider
                  .value
                  .uri
                  .path,
              destination,
            );
            expect(f.drafts.view(id).selected, isNot(annotation.id));
            expect(tester.takeException(), isNull);
          } finally {
            if (!proceed.isCompleted) proceed.complete();
            await _disposeHeaderApplication(tester, f);
          }
        },
      );
    }
  }

  testWidgets(
    'annotation search opens a protected failed creation from its Notebook owner',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      late ReadingAnnotation pending;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (store) => gate = AnnotationStoreGate(store),
        );
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Saved note');
        pending = f.reader.annotations.single.copy({
          'id': 'annotation-unsaved-search',
        });
        f.notes.create(pending, 'Protected unsaved needle\nSecond line');
        gate.failPut = true;
        await expectLater(
          f.notes.save(pending.id),
          throwsA(isA<FileSystemException>()),
        );
      });
      try {
        final id = pending.bookId;
        await _mountHeaderApplication(tester, f, '/read/$id');
        await _readerAction(
          tester,
          () => f.searchController.open(
            category: BookSearchCategory.notebook,
            query: 'unsaved needle',
          ),
        );
        final snapshot = f.search;
        expect(
          (snapshot.results.single as AnnotationSearchResult).annotation.id,
          pending.id,
        );
        expect(
          f.container
              .read(workspaceControllerProvider)
              .annotations
              .any((a) => a.id == pending.id),
          false,
        );
        final header = tester.element(find.byType(BookHeader));
        await _readerAction(
          tester,
          () => activateBookSearchResult(
            header,
            header as WidgetRef,
            snapshot.results.single,
            snapshot.generation,
          ),
          settle: false,
        );
        await _pumpUntil(
          tester,
          () => find
              .byKey(ValueKey('notebook-note-${pending.id}'))
              .evaluate()
              .isNotEmpty,
          settle: false,
        );
        expect(
          f.container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/notebook/$id',
        );
        expect(f.drafts.view(id).selected, pending.id);
        expect(
          f.drafts.drafts[pending.id]!.text,
          'Protected unsaved needle\nSecond line',
        );
        expect(
          find.byKey(ValueKey('notebook-note-${pending.id}')),
          findsOneWidget,
        );
      } finally {
        gate.failPut = false;
        try {
          await _readerAction(tester, f.notes.flush, settle: false);
        } finally {
          await _disposeHeaderApplication(tester, f);
        }
      }
    },
  );

  test(
    'book session resources stabilize across sixty distinct publications',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        await f.reader.close();
        final workspace = f.container.read(
          workspaceControllerProvider.notifier,
        );
        final router = f.container.read(appRouterProvider);
        final bytes = await File('test/fixtures/text.pdf').readAsBytes();
        final measurements = <Map<String, int>>[];
        // Optional VM diagnostics are enabled by --enable-vmservice. The
        // ordinary suite requires no service and still checks exact lifetimes.
        final service = (await developer.Service.getInfo()).serverUri;
        Future<Map<String, int>> heap() async {
          if (service == null) return {};
          expect(service.host, isIn(['127.0.0.1', 'localhost', '::1']));
          final client = _VmDiagnosticsHttpOverrides().createHttpClient(null);
          try {
            final request = await client.getUrl(
              service
                  .resolve('getAllocationProfile')
                  .replace(
                    queryParameters: {
                      'isolateId': developer.Service.getIsolateId(
                        Isolate.current,
                      )!,
                      'gc': 'true',
                    },
                  ),
            );
            final response = await request.close();
            final envelope =
                jsonDecode(await utf8.decoder.bind(response).join()) as Map;
            expect(envelope['error'], isNull);
            final result = envelope['result'] as Map;
            final members = (result['members'] as List).cast<Map>();
            return {
              'heapUsedBytes':
                  (result['memoryUsage'] as Map)['heapUsage'] as int,
              for (final name in [
                'BookSearchController',
                'BookSidebarController',
              ])
                '${name}Instances': members
                    .where((m) => (m['class'] as Map)['name'] == name)
                    .fold<int>(0, (n, m) => n + (m['instancesCurrent'] as int)),
            };
          } finally {
            client.close(force: true);
          }
        }

        Map<String, int> counts() {
          return {
            'searchControllers': f.container.exists(bookSearchSessionProvider)
                ? 1
                : 0,
            'sidebarControllers': f.container
                .allProviders(family: bookSidebarProvider)
                .length,
            'rssBytes': ProcessInfo.currentRss,
          };
        }

        String? firstId;
        BookSearchController? firstSearch;
        BookSearchResult? firstResult;
        int? firstGeneration;
        BookSearchController? lastSearch;
        for (var index = 0; index < 60; index++) {
          final file = File(p.join(f.directory.path, 'session-$index.pdf'));
          await file.writeAsBytes([
            ...bytes,
            ...utf8.encode('\n% session $index\n'),
          ]);
          final id = (await workspace.openPath(file.path)).books.single.id;
          firstId ??= id;
          router.go('/notebook/$id');
          final sidebar = f.container.read(bookSidebarProvider(id).notifier);
          sidebar.publication(
            outline: PublicationOutline.fromRecords([
              for (var chapter = 0; chapter < 300; chapter++)
                {
                  'id': 'chapter:$index:$chapter',
                  'label': 'Book $index chapter $chapter',
                  'href': 'chapter-$chapter.xhtml',
                  'depth': 0,
                },
            ], pdf: false),
            status: 'ready',
            pages: 300,
            labels: List.generate(300, (page) => '$page'),
          );
          final search = f.container.read(bookSearchSessionProvider.notifier);
          firstSearch ??= search;
          lastSearch = search;
          await search.open(
            category: BookSearchCategory.chapters,
            query: 'chapter',
          );
          await _until(
            () => !f.container.read(bookSearchSessionProvider).loading,
          );
          expect(
            f.container.read(bookSearchSessionProvider).results,
            hasLength(100),
          );
          expect(f.container.read(bookSearchSessionProvider).hasMore, true);
          firstResult ??= f.container
              .read(bookSearchSessionProvider)
              .results
              .first;
          firstGeneration ??= f.container
              .read(bookSearchSessionProvider)
              .generation;
          await f.container.pump();
          if ((index + 1) % 20 == 0) {
            measurements.add({
              'books': index + 1,
              ...counts(),
              ...await heap(),
            });
          }
        }
        // RSS includes the VM, SQLite and the intentional domain book cache.
        // Exact provider counts establish whether session-owned resources grow.
        // ignore: avoid_print
        print('BOOK_SESSION_RESOURCES ${jsonEncode(measurements)}');
        expect(counts()['searchControllers'], 1);
        expect(counts()['sidebarControllers'], 1);
        expect(firstSearch!.accepts(firstResult!, firstGeneration!), false);
        lastSearch!.query('pending debounce at close');
        await workspace.closeWorkspace();
        router.go('/');
        await f.container.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(counts()['searchControllers'], 1);
        expect(f.container.read(bookSearchSessionProvider).active, false);
        expect(f.container.read(bookSearchSessionProvider).results, isEmpty);
        expect(counts()['sidebarControllers'], 0);
        // The window session has one reader event subscription, independent of
        // the number of books visited. It retains no previous renderer/results.
        expect(f.reader.events.hasListener, true);
        await workspace.loadBook(firstId!, activate: true);
        router.go('/notebook/$firstId');
        expect(
          identical(
            f.container.read(bookSearchSessionProvider.notifier),
            firstSearch,
          ),
          true,
        );
      } finally {
        await f.dispose();
      }
    },
  );

  test(
    'a delayed native search cancellation cannot cancel a newer query',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      final entered = Completer<void>(), proceed = Completer<void>();
      try {
        f.reader.search('old query');
        final cancellation = f.reader.searchRevision + 1;
        f.onDispatch = (command) async {
          if (command['action'] == 'cancelSearch' &&
              command['queryId'] == cancellation) {
            entered.complete();
            await proceed.future;
          }
        };
        final cancelling = f.reader.cancelSearch();
        await entered.future;
        f.reader.search('new query');
        proceed.complete();
        await cancelling;
        expect(f.state.query, 'new query');
        expect(f.state.searchStatus, 'searching');
        expect(f.state.searching, true);
      } finally {
        if (!proceed.isCompleted) proceed.complete();
        f.onDispatch = null;
        await f.dispose();
      }
    },
  );

  test(
    'book-scoped search cancels generations and remains data-backed after reader close',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      try {
        await f.openSelectionPopover();
        await f.reader.annotation(
          'highlight',
          note: 'A needle in the notebook',
        );
        await f.event('location', {
          'anchor': {'page': 0},
        });
        await f.reader.annotation('bookmark', note: 'A bookmark to revisit');
        final id = f.state.bookId!, search = f.searchController;
        await f.sidebarController.selectPanel(BookSidebarPanel.marks);
        await search.open(
          category: BookSearchCategory.notebook,
          query: 'needle',
        );
        await _until(
          () => !f.container.read(bookSearchSessionProvider).loading,
        );
        final previous = f.container.read(bookSearchSessionProvider);
        expect(previous.results.single, isA<AnnotationSearchResult>());
        await search.open(
          category: BookSearchCategory.bookmarks,
          query: 'revisit',
        );
        await _until(
          () => !f.container.read(bookSearchSessionProvider).loading,
        );
        expect(
          search.accepts(previous.results.single, previous.generation),
          false,
        );
        expect(
          (f.container.read(bookSearchSessionProvider).results.single
                  as AnnotationSearchResult)
              .annotation
              .kind,
          'bookmark',
        );
        await f.reader.close();
        await search.open(
          category: BookSearchCategory.notebook,
          query: 'needle',
        );
        await _until(
          () => !f.container.read(bookSearchSessionProvider).loading,
        );
        expect(
          f.container.read(bookSearchSessionProvider).results,
          hasLength(1),
        );
        search.query('obsolete');
        search.query('new query');
        search.close();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(f.container.read(bookSearchSessionProvider).results, isEmpty);
        expect(
          f.container.read(bookSidebarProvider(id)).panel,
          BookSidebarPanel.marks,
        );
        f.container.read(appRouterProvider).go('/');
        expect(
          search.accepts(previous.results.single, previous.generation),
          false,
        );
      } finally {
        await f.dispose();
      }
    },
  );

  testWidgets(
    'Notebook autosave status reports failure and Retry commits the complete note',
    (tester) async {
      late _ReaderFixture f;
      late AnnotationStoreGate gate;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: 'Saved baseline');
        f.notes.revealAnnotation(
          f.state.bookId!,
          f.reader.annotations.single.id,
        );
      });
      try {
        final id = f.state.bookId!, annotation = f.reader.annotations.single;
        await _mountHeaderApplication(tester, f, '/notebook/$id');
        final editor = find.descendant(
          of: find.byKey(ValueKey('notebook-note-${annotation.id}')),
          matching: find.byType(TextField),
        );
        const note = 'First complete line\n\nThird complete line';
        gate.fail = true;
        await tester.enterText(editor, note);
        await tester.pump();
        expect(find.text('Saving note…'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(NotebookContent),
            matching: find.text('Save'),
          ),
          findsNothing,
        );
        await tester.pump(const Duration(milliseconds: 800));
        await _pumpUntil(
          tester,
          () => f.drafts.drafts[annotation.id]?.error != null,
        );
        // The draft owns this failure. It must not become a stale Home error
        // containing a database statement and the complete private note.
        expect(f.container.read(workspaceControllerProvider).error, isNull);
        expect(tester.widget<TextField>(editor).controller!.text, note);
        gate.fail = false;
        await tester.tap(find.text('Retry'));
        await _pumpUntil(
          tester,
          () => f.drafts.drafts.isEmpty && f.drafts.saving.isEmpty,
        );
        expect(find.text('Saved'), findsOneWidget);
        expect(f.container.read(workspaceControllerProvider).error, isNull);
        await _readerAction(tester, () async {
          expect(
            (await f.store.call('annotations', id) as List).single['note'],
            note,
          );
        });
        expect(tester.takeException(), isNull);
      } finally {
        gate.fail = false;
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'Notebook long-note preview expands without modifying its complete saved text',
    (tester) async {
      late _ReaderFixture f;
      final note =
          'First line\nSecond line\n\n${'A thoughtful paragraph. ' * 100}\nFinal intact line';
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.openSelectionPopover();
        await f.reader.annotation('highlight', note: note);
      });
      try {
        await _mountHeaderApplication(tester, f, '/notebook/${f.state.bookId}');
        final card = find.byType(NotebookItem);
        expect(
          find.descendant(of: card, matching: find.text('Show Full Note')),
          findsOneWidget,
        );
        final previews = tester
            .widgetList<SelectableText>(
              find.descendant(of: card, matching: find.byType(SelectableText)),
            )
            .map((w) => w.data)
            .whereType<String>();
        expect(
          previews.any((s) => s.startsWith('First line\nSecond line\n')),
          true,
        );
        await tester.tap(find.text('Show Full Note'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<SelectableText>(
                find.descendant(
                  of: card,
                  matching: find.byType(SelectableText),
                ),
              )
              .any((w) => w.data == note),
          true,
        );
        expect(f.reader.annotations.single.note, note);
        expect(f.drafts.drafts, isEmpty);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'large variable-height Notebook reveals exact identities without building the intervening list',
    (tester) async {
      late _ReaderFixture f;
      late String id;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        id = f.state.bookId!;
      });
      try {
        // This fixture performs 1,200 durable writes. Keep disk preparation
        // outside the popover/transition helper's deadline; reveal and layout
        // retain their ordinary bounded pumps and all lazy-list assertions.
        await tester.runAsync(() async {
          for (var i = 0; i < 1200; i++) {
            await f.store.call('putAnnotation', {
              'id': 'annotation-large-$i',
              'bookId': id,
              'annotationKind': 'highlight',
              'anchor': {'page': 0},
              'text':
                  'Passage $i\n${'A variable-height saved line.\n' * (i % 36)}',
              'note': 'Private note $i',
              'reference': 'Page 1',
              'color': 'yellow',
              'created': i + 1,
            });
          }
          await f.container
              .read(workspaceControllerProvider.notifier)
              .loadBook(id);
        });
        f.notes.revealAnnotation(id, 'annotation-large-0');
        await _mountHeaderApplication(tester, f, '/notebook/$id');
        final editor = find.byKey(
          const ValueKey('notebook-note-annotation-large-0'),
        );
        expect(editor, findsOneWidget);
        expect(find.byType(NotebookItem).evaluate().length, lessThan(30));
        expect(f.drafts.view(id).revealAnnotation, isNull);
        f.notes.view(
          id,
          sort: NotebookSort.bookOrder,
          filter: AnnotationTypeFilter.highlights,
        );
        f.notes.revealAnnotation(id, 'annotation-large-1199');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('notebook-note-annotation-large-1199')),
          findsOneWidget,
        );
        final scroll = find.descendant(
          of: find.byType(NotebookContent),
          matching: find.byType(CustomScrollView),
        );
        await tester.drag(scroll, const Offset(0, 200));
        await tester.pumpAndSettle();
        final offset = f.drafts.view(id).scroll;
        await tester.pump();
        expect(f.drafts.view(id).scroll, offset);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'Settings adapts its navigation and Data uses the semantic view surface',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        await _mountHeaderApplication(tester, f, '/settings');
        expect(find.byType(SettingsScreen), findsOneWidget);
        final content = find.byKey(const ValueKey('settings-content-surface'));
        expect(
          tester.widget<ColoredBox>(content).color,
          BusyBooksSurfaceColors.of(tester.element(content)).view,
        );
        tester.view.physicalSize = const Size(540, 850);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-page-selector')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('settings-page-selector')));
        await _pumpUntil(tester, () => find.text('Data').evaluate().isNotEmpty);
        await tester.tap(find.text('Data'));
        await tester.pumpAndSettle();
        expect(find.text('Back Up Reading Data'), findsOneWidget);
        expect(find.text('Restore Backup'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'narrow Collection overlays dismiss without reserving the sidebar width',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        final workspace = f.container.read(
          workspaceControllerProvider.notifier,
        );
        await workspace.createCollection('Adaptive collection');
        await workspace.addBooks([f.reader.book!.path]);
      });
      try {
        await _mountHeaderApplication(tester, f, '/workspace');
        tester.view.physicalSize = const Size(540, 850);
        await tester.pumpAndSettle();
        final frame = find.byType(LinuxPageFrame);
        expect(tester.widget<LinuxPageFrame>(frame).sidebarOverlay, true);
        expect(tester.widget<LinuxPageFrame>(frame).sidebarExpanded, false);
        final collection = find.byType(CollectionScreen);
        expect(tester.getRect(collection).width, 540);
        await tester.tap(_headerButton('Sidebar'));
        await tester.pumpAndSettle();
        expect(tester.widget<LinuxPageFrame>(frame).sidebarExpanded, true);
        await tester.tapAt(const Offset(530, 350));
        await tester.pumpAndSettle();
        expect(tester.widget<LinuxPageFrame>(frame).sidebarExpanded, false);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'native reader geometry follows sidebar animation frames and narrow overlays hide it',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'reflowable.epub',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        Map bounds() =>
            f.calls.lastWhere((c) => c.method == 'bounds').arguments as Map;
        final initial = bounds()['x'] as double;
        await _readerAction(
          tester,
          f.sidebarController.toggleOpen,
          settle: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        final middle = bounds()['x'] as double;
        await tester.pumpAndSettle();
        expect(middle, greaterThan(initial));
        expect(bounds()['x'], greaterThanOrEqualTo(middle));
        tester.view.physicalSize = const Size(540, 850);
        await tester.pumpAndSettle();
        expect(f.state.surfaceVisible, false);
        await _readerAction(tester, f.sidebarController.toggleOpen);
        expect(f.state.surfaceVisible, true);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  testWidgets(
    'unified collection search preserves ordinary browsing and header memory',
    (tester) async {
      late _ReaderFixture f;
      late String collectionId, browsingFilter;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
        await f.container.read(appSettingsControllerProvider.notifier).update({
          'grid': false,
        });
        final workspace = f.container.read(
          workspaceControllerProvider.notifier,
        );
        await workspace.createCollection('Search collection');
        collectionId = f.container
            .read(workspaceControllerProvider)
            .workspace!
            .id;
        await workspace.addBooks([f.reader.book!.path]);
        browsingFilter = f.container
            .read(workspaceControllerProvider)
            .books
            .single
            .state;
        f.container
            .read(collectionViewProvider(collectionId).notifier)
            .update(
              filter: browsingFilter,
              sort: 'author',
              selectedBook: f.reader.book!.id,
            );
      });
      try {
        await _mountHeaderApplication(tester, f, '/workspace');
        expect(find.byType(BusyBooksSearchField), findsNothing);
        await _readerAction(
          tester,
          () => _appCommands(
            tester,
          ).execute(BusyBooksCommandIds.searchCollection),
        );
        expect(f.search.category, BookSearchCategory.books);
        expect(f.search.scope.id, collectionId);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is BusyBooksPopupSelector<BookSearchScope> &&
                w.label == 'Search collection',
          ),
          findsOneWidget,
        );

        expect(find.byType(BusyBooksSearchField), findsOneWidget);
        expect(find.text('Enter text to search.'), findsOneWidget);
        final field = find.descendant(
          of: find.byType(BusyBooksSearchField),
          matching: find.byType(TextField),
        );
        await tester.enterText(field, 'no such stored book');
        await _readerAction(tester, () async {
          await f.searchController.submit();
        });
        expect(f.search.results, isEmpty);
        f.searchController.close();
        await tester.pumpAndSettle();
        expect(find.byType(BusyBooksSearchField), findsNothing);
        final browsing = f.container.read(collectionViewProvider(collectionId));
        expect(browsing.filter, browsingFilter);
        expect(browsing.sort, 'author');
        expect(browsing.selectedBook, f.reader.book!.id);
        expect(find.byType(BookRow), findsOneWidget);
        await tester.tap(_headerButton('Search'));
        await tester.pump();
        expect(f.search.category, BookSearchCategory.books);
        expect(f.search.query, 'no such stored book');
        expect(f.search.scope.id, collectionId);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'repeated Ctrl F opens Notebook search and icon restores last category',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        await _mountHeaderApplication(tester, f, '/notebook/${f.state.bookId}');
        for (var i = 0; i < 2; i++) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await _pumpUntil(tester, () => f.search.active);
          expect(f.search.category, BookSearchCategory.notebook);
          expect(f.search.scope.id, f.state.bookId);
          expect(
            FocusManager.instance.primaryFocus,
            isA<BusyBooksSearchFocusNode>(),
          );
        }
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'あ',
            selection: TextSelection.collapsed(offset: 1),
            composing: TextRange(start: 0, end: 1),
          ),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(f.search.active, true);
        expect(f.search.query, 'あ');
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'あ',
            selection: TextSelection.collapsed(offset: 1),
          ),
        );
        await _readerAction(tester, () async {
          await f.searchController.submit();
        });
        await _readerAction(
          tester,
          () => f.searchController.open(category: BookSearchCategory.bookmarks),
        );
        expect(f.search.results, isEmpty);
        await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        expect(f.search.active, false);
        await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        expect(f.search.category, BookSearchCategory.bookmarks);
        expect(find.byType(BusyBooksSearchField), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );

  testWidgets(
    'Home exposes saved categories with a single query and Actions grouped catalog',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        await _mountHeaderApplication(tester, f, '/');
        await tester.tap(_headerButton('Search'));
        await tester.pumpAndSettle();
        expect(f.searchController.categories, [
          BookSearchCategory.notebook,
          BookSearchCategory.bookmarks,
          BookSearchCategory.books,
          BookSearchCategory.recent,
          BookSearchCategory.actions,
        ]);
        expect(f.search.results, isEmpty);
        expect(find.byType(BusyBooksSearchField), findsOneWidget);
        await _readerAction(
          tester,
          () =>
              _appCommands(tester).execute(BusyBooksCommandIds.commandPalette),
        );
        expect(f.search.results, isNotEmpty);
        expect(
          f.search.results.every((r) => r is BookActionSearchResult),
          true,
        );
        expect(find.byType(BookSearchResultList), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  for (final originView in [BookView.notebook, BookView.split]) {
    for (final narrow in [false, true]) {
      testWidgets(
        'repository note activation reveals exact missing-book annotation and retains scope (origin: ${originView.name}, narrow: $narrow)',
        (tester) async {
          late _ReaderFixture f;
          late String owner, collectionId, originId;
          await _readerAction(tester, () async {
            f = await _ReaderFixture.create(
              'text.pdf',
              windowControls: WindowControlService(
                nativeWindow: _HeaderWindow(),
              ),
            );
            originId = f.state.bookId!;
            final source = File(
              p.join(f.directory.path, 'Other publication.pdf'),
            );
            await source.writeAsBytes([
              ...await File('test/fixtures/text.pdf').readAsBytes(),
              ...'\n% different saved publication\n'.codeUnits,
            ]);
            await f.container
                .read(appSettingsControllerProvider.notifier)
                .update({'grid': false});
            final workspace = f.container.read(
              workspaceControllerProvider.notifier,
            );
            await workspace.createCollection('Origin collection');
            collectionId = f.container
                .read(workspaceControllerProvider)
                .workspace!
                .id;
            await workspace.addBooks([f.reader.book!.path, source.path]);
            owner = f.container
                .read(workspaceControllerProvider)
                .books
                .firstWhere((b) => b.id != originId)
                .id;
            await f.store.call('putAnnotation', {
              'id': 'annotation-cross-book-note',
              'bookId': owner,
              'annotationKind': 'highlight',
              'text': 'Cross-book quotation',
              'note': 'Exact missing-original needle',
              'reference': 'Page 1',
              'anchor': {'page': 0},
              'color': 'yellow',
              'created': 1,
            });
            await source.delete();
            await workspace.loadBook(originId, activate: true);
          });
          try {
            await _mountHeaderApplication(
              tester,
              f,
              originView.routeFor(originId),
            );
            tester.view.physicalSize = Size(narrow ? 540 : 1200, 850);
            await tester.pumpAndSettle();
            final scope = BookSearchScope(
              BookSearchScopeKind.currentCollection,
              id: collectionId,
              name: 'Origin collection',
            );
            await _readerAction(
              tester,
              () => f.searchController.open(
                category: BookSearchCategory.notebook,
                query: 'needle',
                scope: scope,
              ),
            );
            expect(f.search.results, hasLength(1));
            final row = find.byKey(
              ValueKey('$owner:annotation-cross-book-note'),
            );
            await tester.tap(row);
            await _pumpUntil(
              tester,
              () =>
                  f.container
                          .read(appRouterProvider)
                          .routeInformationProvider
                          .value
                          .uri
                          .path ==
                      notebookTargetRoute(
                        originView.routeFor(originId),
                        owner,
                      ) &&
                  (originView != BookView.split ||
                      f.state.bookId == owner && f.state.error != null),
            );
            await _pumpUntil(
              tester,
              () => find
                  .byKey(
                    const ValueKey('notebook-note-annotation-cross-book-note'),
                  )
                  .evaluate()
                  .isNotEmpty,
            );
            expect(f.search.scope, scope);
            expect(f.search.query, 'needle');
            expect(f.search.active, !narrow);
            expect(f.search.results, narrow ? isEmpty : isNotEmpty);
            expect(
              f.container.read(workspaceControllerProvider).workspace!.id,
              collectionId,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await _disposeHeaderApplication(tester, f);
          }
        },
      );
    }
  }
  testWidgets(
    'narrow Books activation dismisses search and ordinary sidebar before reader handoff',
    (tester) async {
      late _ReaderFixture f;
      await _readerAction(tester, () async {
        f = await _ReaderFixture.create(
          'text.pdf',
          windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
        );
      });
      try {
        final book = f.reader.book!;
        await _mountHeaderApplication(tester, f, '/');
        tester.view.physicalSize = const Size(540, 850);
        await tester.pumpAndSettle();
        await _readerAction(
          tester,
          () => f.searchController.open(
            category: BookSearchCategory.books,
            query: book.title,
          ),
        );
        expect(f.search.results, hasLength(1));
        final opens = f.calls.where((c) => c.method == 'open').length;
        await tester.tap(find.byKey(ValueKey(book.id)));
        await _pumpUntil(
          tester,
          () => f.calls.where((c) => c.method == 'open').length > opens,
          settle: false,
        );
        await _readerAction(tester, () async {
          await f.event('ready');
          await f.event('opened', {
            'typography': TypographyCapabilities.none.toJson(),
          });
        });
        await _pumpUntil(
          tester,
          () =>
              f.container
                      .read(appRouterProvider)
                      .routeInformationProvider
                      .value
                      .uri
                      .path ==
                  '/read/${book.id}' &&
              f.state.surfaceVisible &&
              f.state.ready,
        );
        expect(f.search.active, false);
        expect(f.search.results, isEmpty);
        expect(f.container.read(bookSidebarProvider(book.id)).open, false);
        expect(tester.takeException(), isNull);
      } finally {
        await _disposeHeaderApplication(tester, f);
      }
    },
  );
  for (final originView in [BookView.notebook, BookView.split]) {
    for (final narrow in [false, true]) {
      for (final removed in [false, true]) {
        testWidgets(
          'deferred cross-book bookmark validates exact annotation (origin: ${originView.name}, narrow: $narrow, removed: $removed)',
          (tester) async {
            late _ReaderFixture f;
            late String originId, targetId;
            await _readerAction(tester, () async {
              f = await _ReaderFixture.create(
                'text.pdf',
                windowControls: WindowControlService(
                  nativeWindow: _HeaderWindow(),
                ),
              );
              originId = f.state.bookId!;
              final file =
                  await File(
                    p.join(f.directory.path, 'Deferred target.pdf'),
                  ).writeAsBytes([
                    ...await File('test/fixtures/text.pdf').readAsBytes(),
                    ...'\n% deferred target publication\n'.codeUnits,
                  ]);
              final workspace = f.container.read(
                workspaceControllerProvider.notifier,
              );
              await workspace.createCollection(
                'Deferred navigation collection',
              );
              await workspace.addBooks([f.reader.book!.path, file.path]);
              targetId = f.container
                  .read(workspaceControllerProvider)
                  .books
                  .firstWhere((b) => b.id != originId)
                  .id;
              await f.store.call('putAnnotation', {
                'id': 'annotation-deferred-crossbook',
                'bookId': targetId,
                'annotationKind': 'bookmark',
                'text': '',
                'note': 'pending passage',
                'reference': 'Page 3',
                'anchor': {'page': 2},
                'color': 'yellow',
                'created': 1,
              });
              await workspace.loadBook(originId, activate: true);
            });
            try {
              await _mountHeaderApplication(
                tester,
                f,
                originView.routeFor(originId),
              );
              tester.view.physicalSize = Size(narrow ? 540 : 1200, 850);
              await tester.pumpAndSettle();
              await _readerAction(
                tester,
                () => f.searchController.open(
                  category: BookSearchCategory.bookmarks,
                  query: 'pending passage',
                  scope: const BookSearchScope.all(),
                ),
              );
              await tester.tap(
                find.byKey(ValueKey('$targetId:annotation-deferred-crossbook')),
              );
              // Initialization begins before the native open request. Deliver
              // readiness only after the mock owns the new renderer session.
              await _pumpUntil(
                tester,
                () =>
                    f.state.bookId == targetId &&
                    f.state.phase == 'initializing' &&
                    f.session == f.reader.sessionId,
                settle: false,
              );
              expect(f.dispatches.where((d) => d['action'] == 'goto'), isEmpty);
              if (removed) {
                await _readerAction(
                  tester,
                  () => f.container
                      .read(workspaceControllerProvider.notifier)
                      .deleteAnnotation('annotation-deferred-crossbook'),
                  settle: false,
                );
              }
              await _readerAction(tester, () async {
                await f.event('ready');
                await f.event('opened');
              }, settle: false);
              // A cancelled deferred activation republishes changed repository
              // rows after its debounce, using the real storage worker.
              await tester.pump(const Duration(milliseconds: 150));
              await _pumpUntil(
                tester,
                () => f.state.ready && !f.search.loading,
              );
              final jumps = f.dispatches
                  .where((d) => d['action'] == 'goto')
                  .toList();
              if (removed) {
                expect(jumps, isEmpty);
              } else {
                expect(jumps, hasLength(1));
                expect(jumps.single['anchor'], {'page': 2});
              }
              expect(
                f.container
                    .read(appRouterProvider)
                    .routeInformationProvider
                    .value
                    .uri
                    .path,
                readingTargetRoute(originView.routeFor(originId), targetId),
              );
              expect(f.search.active, !narrow);
              expect(f.search.query, 'pending passage');
              expect(f.search.scope, const BookSearchScope.all());
              expect(tester.takeException(), isNull);
            } finally {
              await _disposeHeaderApplication(tester, f);
            }
          },
        );
      }
    }
  }
}

void _nativeSelectionTests() {
  for (final action in [
    ReaderSelectionAction.search,
    ReaderSelectionAction.lookUp,
    ReaderSelectionAction.readAloud,
  ]) {
    test(
      'native selection $action uses the captured passage after blur',
      () async {
        final speech = _Speech();
        final f = await _ReaderFixture.create('text.pdf', speech: speech);
        final events = <Map>[];
        final subscription = f.reader.events.stream.listen(events.add);
        try {
          final owner = await f.selectionMenuOwner({
            'anchor': {'page': 0, 'textOffset': 3, 'textLength': 7},
            'text': '  library  ',
            'reference': 'Page 1',
          });
          await f.event('selection', {'anchor': null, 'text': ''});
          await f.reader.selectionMenuAction(owner, action);
          if (action == ReaderSelectionAction.readAloud) {
            expect(
              speech.calls.singleWhere((c) => c.action == 'speak').args['text'],
              '  library  ',
            );
            expect(
              f.dispatches.lastWhere(
                (c) => c['action'] == 'speaking',
              )['anchor'],
              owner.target.passage!['anchor'],
            );
          } else {
            final type = action == ReaderSelectionAction.search
                ? 'searchSelection'
                : 'lookup';
            await _until(() => events.any((e) => e['type'] == type));
            final event = events.singleWhere((e) => e['type'] == type);
            if (action == ReaderSelectionAction.search) {
              expect(event['text'], '  library  ');
            } else {
              final target = event['target'] as ReaderSelectionTarget;
              expect(target.text, 'library');
              expect(
                target.passage!['anchor'],
                owner.target.passage!['anchor'],
              );
            }
          }
          expect(f.calls.where((c) => c.method == 'popover'), isEmpty);
        } finally {
          await subscription.cancel();
          await f.dispose();
          await speech.dispose();
        }
      },
    );
  }
  test(
    'native selection accepted highlight is drained before closing the book',
    () async {
      late AnnotationStoreGate gate;
      final f = await _ReaderFixture.create(
        'text.pdf',
        wrapStore: (s) => gate = AnnotationStoreGate(s),
      );
      try {
        final owner = await f.selectionMenuOwner({
          'anchor': {'page': 0},
          'text': 'Save before close',
        });
        gate.putEntered = Completer<void>();
        gate.putProceed = Completer<void>();
        final saving = f.reader.selectionMenuAction(
          owner,
          ReaderSelectionAction.highlight,
        );
        await gate.putEntered!.future;
        var closed = false;
        final closing = f.reader.close().then((_) => closed = true);
        await _until(() => f.dispatches.any((c) => c['action'] == 'flush'));
        expect(closed, false);
        expect(f.calls.where((c) => c.method == 'close'), isEmpty);
        gate.putProceed!.complete();
        await saving;
        await closing;
        final annotations =
            await f.store.call('annotations', owner.target.bookId) as List;
        expect(annotations, hasLength(1));
        expect(annotations.single['text'], 'Save before close');
      } finally {
        if (gate.putProceed?.isCompleted == false) gate.putProceed!.complete();
        await f.dispose();
      }
    },
  );
  for (final fixture in ['text.pdf', 'reflowable.epub']) {
    test(
      'native selection preserves $fixture passage when visual focus collapses',
      () async {
        final f = await _ReaderFixture.create(fixture);
        final copied = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
        try {
          final anchor = fixture.endsWith('.pdf')
              ? <String, dynamic>{'page': 0, 'textOffset': 0, 'textLength': 9}
              : <String, dynamic>{'cfi': 'epubcfi(/6/2!/4/2/1:0)', 'index': 0};
          final owner = await f.selectionMenuOwner({
            'anchor': anchor,
            'text': '  library\n文字  ',
            'reference': 'Page 1',
          });
          await f.event('selection', {'anchor': null, 'text': ''});
          expect(f.reader.ownsSelectionMenu(owner), isTrue);
          expect(owner.target.passage!['anchor'], anchor);
          await f.reader.selectionMenuAction(owner, ReaderSelectionAction.copy);
          expect(copied, ['  library\n文字  ']);
          expect(
            f.calls.where(
              (c) => c.method == 'popover' || c.method == 'capturePopover',
            ),
            isEmpty,
          );
        } finally {
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
          await f.dispose();
        }
      },
    );
  }
  for (final retirement in ['replacement', 'close', 'chrome', 'geometry']) {
    test(
      'native selection rejects $retirement retirement before action delivery',
      () async {
        final f = await _ReaderFixture.create('text.pdf');
        try {
          final owner = await f.selectionMenuOwner({
            'anchor': {'page': 0},
            'text': 'Original source',
          });
          if (retirement == 'replacement') {
            await f.event('selection', {
              'anchor': {'page': 1},
              'text': 'Replacement source',
            });
          } else if (retirement == 'close') {
            await f.reader.close();
          } else if (retirement == 'chrome') {
            await f.reader.prepareChromeChange();
          } else {
            await f.reader.updateViewport(
              const Rect.fromLTWH(0, 0, 800, 600),
              bookId: f.state.bookId!,
            );
          }
          expect(f.reader.ownsSelectionMenu(owner), isFalse);
          await f.reader.selectionMenuAction(
            owner,
            ReaderSelectionAction.highlight,
          );
          expect(
            await f.store.call('annotations', owner.target.bookId),
            isEmpty,
          );
        } finally {
          await f.dispose();
        }
      },
    );
  }
  test(
    'native selection Add Note creates one protected Notebook draft without a secondary surface',
    () async {
      final f = await _ReaderFixture.create('text.pdf');
      final edits = <Map>[];
      final subscription = f.reader.events.stream.listen((e) {
        if (e['type'] == 'editAnnotationNote') edits.add(e);
      });
      try {
        final owner = await f.selectionMenuOwner({
          'anchor': {'page': 0},
          'text': 'Saved source',
          'reference': 'Page 1',
        });
        await f.event('selection', {'anchor': null, 'text': ''});
        await f.reader.selectionMenuAction(
          owner,
          ReaderSelectionAction.addNote,
        );
        await _until(() => edits.isNotEmpty);
        expect(
          f.reader.ownsNoteEditRequest(edits.single.cast<String, dynamic>()),
          isTrue,
        );
        final id = edits.single['annotationId'] as String;
        final a = f.drafts.sources[id]!;
        expect(a.text, 'Saved source');
        f.notes.edit(a, 'Primary Notebook note');
        await f.notes.flush();
        await f.verifyNote(id, 'Primary Notebook note');
        expect(f.reader.annotations, hasLength(1));
        expect(
          f.calls.where(
            (c) => c.method == 'popover' || c.method == 'capturePopover',
          ),
          isEmpty,
        );
      } finally {
        await subscription.cancel();
        await f.dispose();
      }
    },
  );
  test(
    'native selection failed highlight creation remains retryable and color changes preserve notes',
    () async {
      late AnnotationStoreGate gate;
      final f = await _ReaderFixture.create(
        'text.pdf',
        wrapStore: (s) => gate = AnnotationStoreGate(s),
      );
      try {
        final owner = await f.selectionMenuOwner({
          'anchor': {'page': 0},
          'text': 'Retained source',
        });
        gate.failPut = true;
        await expectLater(
          f.reader.selectionMenuAction(
            owner,
            ReaderSelectionAction.highlight,
            color: 'green',
          ),
          throwsA(anything),
        );
        final a = f.drafts.sources.values.single;
        f.notes.edit(a, 'Protected note');
        gate.failPut = false;
        await f.notes.flush();
        final request = f.reader.events.stream.firstWhere(
          (e) => e['type'] == 'selectionMenu',
        );
        await f.event('annotation', {'id': a.id});
        final target = (await request)['target'] as ReaderSelectionTarget;
        final menu = (await f.reader.prepareSelectionMenu(
          target,
          dismiss: () async {},
        ))!;
        await f.reader.selectionMenuAction(
          menu,
          ReaderSelectionAction.highlight,
          color: 'pink',
        );
        expect(f.reader.annotations.single.note, 'Protected note');
        expect(f.reader.annotations.single.color, 'pink');
        await f.verifyNote(a.id, 'Protected note');
      } finally {
        gate.failPut = false;
        await f.dispose();
      }
    },
  );
  for (final route in ['read', 'split', 'fallback', 'existing']) {
    testWidgets(
      'native selection menu on $route uses the primary host and opens the Notebook editor',
      (tester) async {
        late _ReaderFixture f;
        await _readerAction(tester, () async {
          f = await _ReaderFixture.create(
            'text.pdf',
            windowControls: WindowControlService(nativeWindow: _HeaderWindow()),
          );
          if (route == 'existing') {
            final owner = await f.selectionMenuOwner({
              'anchor': {'page': 0, 'textOffset': 0, 'textLength': 7},
              'text': 'library',
              'reference': 'Page 1',
            });
            await f.reader.selectionMenuAction(
              owner,
              ReaderSelectionAction.highlight,
            );
            f.notes.edit(
              f.reader.annotations.single,
              'Existing protected note',
            );
            await f.notes.flush();
          }
        });
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final chosen = Completer<int?>();
        Map? request;
        messenger.setMockMethodCallHandler(
          const MethodChannel(nativeMenuChannelName),
          (call) async {
            if (call.method == 'show') {
              request = call.arguments as Map;
              if (route == 'fallback') {
                throw PlatformException(code: 'unavailable');
              }
              return chosen.future;
            }
            return null;
          },
        );
        var initialized = false;
        final initial = f.reader.events.stream.listen((e) {
          if (e['type'] == 'focusBook') initialized = true;
        });
        try {
          final id = f.state.bookId!;
          await _mountHeaderApplication(
            tester,
            f,
            '/${route == 'split' ? 'split' : 'read'}/$id',
          );
          await _pumpUntil(tester, () => initialized && f.reader.interactive);
          f.calls.clear();
          await _readerAction(
            tester,
            () => route == 'existing'
                ? f.event('annotation', {
                    'id': f.reader.annotations.single.id,
                    'rect': {'x': 30, 'y': 20, 'width': 120, 'height': 24},
                  })
                : f.event('selection', {
                    'anchor': {'page': 0, 'textOffset': 0, 'textLength': 7},
                    'text': 'library',
                    'reference': 'Page 1',
                    'settled': true,
                    'rect': {'x': 30, 'y': 20, 'width': 120, 'height': 24},
                  }),
            settle: false,
          );
          await _pumpUntil(tester, () => request != null, settle: false);
          final entries = _nativeLeaves(request!['entries'] as List);
          expect(
            entries.map((e) => e['label']),
            containsAll([
              'Highlight',
              'Highlight Color',
              route == 'existing' ? 'Edit Note' : 'Add Note',
              'Copy',
              'Search in This Book',
              'Look Up',
              'Read Aloud',
            ]),
          );
          expect(request!['anchor'], {
            'x': f.reader.viewport.left + 30,
            'y': f.reader.viewport.top + 20,
            'width': 120.0,
            'height': 24.0,
          });
          expect(
            f.calls.where(
              (c) => c.method == 'popover' || c.method == 'capturePopover',
            ),
            isEmpty,
          );
          await _readerAction(
            tester,
            () => f.event('selection', {'anchor': null, 'text': ''}),
            settle: false,
          );
          if (route == 'fallback') {
            final item = find.widgetWithText(MenuItemButton, 'Add Note');
            await _pumpUntil(tester, () => item.evaluate().isNotEmpty);
            await tester.tap(item);
          } else {
            chosen.complete(
              entries.indexWhere(
                (e) =>
                    e['label'] ==
                    (route == 'existing' ? 'Edit Note' : 'Add Note'),
              ),
            );
          }
          await _pumpUntil(
            tester,
            () =>
                find.byType(NotebookContent).evaluate().isNotEmpty &&
                find.byType(TextField).evaluate().isNotEmpty,
          );
          final editor = find.descendant(
            of: find.byType(NotebookContent),
            matching: find.byType(TextField),
          );
          expect(editor, findsOneWidget);
          if (route == 'existing') {
            expect(
              tester.widget<TextField>(editor).controller!.text,
              'Existing protected note',
            );
          }
          await tester.enterText(editor, 'Notebook selection note');
          await _readerAction(tester, f.notes.flush);
          expect(f.reader.annotations.single.note, 'Notebook selection note');
          expect(
            f.container
                .read(appRouterProvider)
                .routeInformationProvider
                .value
                .uri
                .path,
            '/${route == 'split' ? 'split' : 'notebook'}/$id',
          );
          expect(f.calls.where((c) => c.method == 'popover'), isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          unawaited(initial.cancel());
          if (!chosen.isCompleted) chosen.complete(null);
          messenger.setMockMethodCallHandler(
            const MethodChannel(nativeMenuChannelName),
            null,
          );
          await _disposeHeaderApplication(tester, f);
        }
      },
    );
  }
}
