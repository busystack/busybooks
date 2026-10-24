import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:busybooks/src/app/system_accent.dart';
import 'package:busybooks/src/app/busybooks_app.dart';
import 'package:busybooks/src/app/busybooks_main_menu.dart';
import 'package:busybooks/src/app/window_control_service.dart';
import 'package:busybooks/src/notebook/presentation/book_view_selector.dart';
import 'package:busybooks/src/platform/native_menu_service.dart';
import 'package:window_manager/window_manager.dart';
import 'package:busybooks/src/reading/presentation/reader_screen.dart';
import 'package:busybooks/src/app/app_theme.dart';
import 'package:busybooks/src/app/app_router.dart';
import 'package:busybooks/src/app/keymap_controller.dart';
import 'package:busybooks/src/app/shortcut_binding.dart';
import 'package:busybooks/src/reading/presentation/reader_sidebar.dart';
import 'package:busybooks/src/reading/application/reader_sidebar_state.dart';
import 'package:image/image.dart' as image;
import 'package:busybooks/src/app/command_registry.dart';
import 'package:busybooks/src/app/command_focus.dart';
import 'package:busybooks/src/app/linux/linux_header_style.dart';
import 'package:busybooks/src/platform/gtk_header_icon_service.dart';
import 'package:busybooks/src/app/busybooks_glyphs.dart';
import 'package:busybooks/src/app/app_settings.dart';
import 'package:busybooks/src/core/typography.dart';
import 'package:busybooks/src/app/busybooks_design.dart';
import 'package:busybooks/src/library/data/library_store.dart';
import 'package:busybooks/src/library/domain/book.dart';
import 'package:busybooks/src/reading/presentation/reader_popover.dart';
import 'package:busybooks/src/reading/domain/reader_action.dart';
import 'package:busybooks/src/library/domain/annotation_limits.dart';
import 'package:busybooks/src/library/data/record_validation.dart';
import 'package:busybooks/src/notebook/presentation/notebook_screen.dart';
import 'package:busybooks/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:busybooks/src/reading/application/reader_controller.dart';
import 'package:busybooks/src/reading/application/dictionary_service.dart';
import 'package:busybooks/src/reading/application/narration_controller.dart';
import 'package:busybooks/src/platform/speech_service.dart';
import 'package:busybooks/src/workspace/workspace_controller.dart';
import 'package:busybooks/src/notebook/application/notebook_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
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
      fail('Popover transition did not complete');
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

class _Speech extends SpeechService {
  final calls = <({String action, Map<String, dynamic> args})>[];
  @override
  Future<dynamic> call(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    calls.add((action: action, args: args));
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
  int _verification = 0;
  ReaderController get reader =>
      container.read(readerControllerProvider.notifier);
  ReaderState get state => container.read(readerControllerProvider);
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
  }) async {
    final directory =
        profileDirectory ??
        await Directory.systemTemp.createTemp('busybooks-reading-controls-');
    final store = await ReadingDataStore.open(
      p.join(directory.path, 'profile'),
    );
    final container = ProviderContainer(
      overrides: [
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
          if (call.method == 'capturePopover' || call.method == 'popover') {
            return nativeResult;
          }
          if (call.method == 'open') {
            test.session = (call.arguments as Map)['session'] as String;
          }
          if (call.method == 'dispatch' &&
              jsonDecode(call.arguments as String)['action'] == 'flush') {
            scheduleMicrotask(() => test.event('flushed'));
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
  ]) {
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
  Future<void> select() => event('selection', {
    'anchor': {'page': 0, 'textOffset': 1, 'textLength': 3},
    'text': 'ABC',
    'reference': 'Page 1',
    'settled': true,
  });
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
      BusyBooksCommandIds.outline: () => f.reader.panel('outline'),
      BusyBooksCommandIds.annotations: () => f.reader.panel('annotations'),
      BusyBooksCommandIds.thumbnails: () => f.reader.panel('thumbnails'),
      BusyBooksCommandIds.readerBooks: () => f.reader.panel('books'),
      BusyBooksCommandIds.search: () => f.reader.toggleSearch(visible: true),
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
            home: ReaderScreen(id: f.state.bookId!),
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
  String route,
) async {
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
  await tester.pumpAndSettle();
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
  await tester.tap(find.byTooltip('Main Menu'));
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
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        await _readerAction(tester, () => f.reader.toggleSearch(visible: true));
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
            await f.action('searchSelection');
          });
          final field = find.descendant(
            of: find.byKey(const ValueKey('book-header-search')),
            matching: find.byType(TextField),
          );
          expect(tester.widget<TextField>(field).controller!.text, term);
          expect(f.state.query, term);
          expect(f.state.searchVisible, isTrue);
          expect(f.state.panelOpen, isTrue);
          expect(f.state.panel, 'search');
          expect(f.state.currentMatch, -1);
          expect(f.dispatches.where((d) => d['action'] == 'goto'), isEmpty);
          expect(
            f.dispatches.lastWhere((d) => d['action'] == 'search')['query'],
            term,
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
          await f.select();
          await f.action('searchSelection');
          final old = f.dispatches.lastWhere(
            (d) => d['action'] == 'search',
          )['queryId'];
          await f.event('match', {
            'queryId': old,
            'anchor': {'page': 1},
            'excerpt': 'ABC',
          });
          await f.event('searchDone', {'queryId': old});
          await f.select();
          await f.action('searchSelection');
          final next = f.dispatches.lastWhere(
            (d) => d['action'] == 'search',
          )['queryId'];
          expect(next, greaterThan(old as int));
          expect(f.state.searchVisible, isTrue);
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
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        await _readerAction(tester, () => f.reader.toggleSearch(visible: true));
        for (final selectionAction in [true, false]) {
          await _readerAction(
            tester,
            () => f.event('selection', {
              'anchor': {'page': 0, 'textOffset': 0, 'textLength': 9},
              'text': '  ice cream  ',
              'settled': true,
            }),
          );
          expect(service.terms, hasLength(selectionAction ? 0 : 1));
          if (selectionAction) {
            await _readerAction(
              tester,
              () => f.action('dictionary'),
              settle: false,
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
              await f.reader.showPopover('appearance');
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
          await f.select();
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
          await f.select();
          f.onNativeCall = (call) async {
            if (call.method == 'capturePopover') {
              throw PlatformException(code: 'capture-failed');
            }
            return null;
          };
          final visible = f.state.searchVisible;
          await expectLater(
            action == 'search'
                ? f.reader.searchSelection()
                : f.reader.prepareLookup(),
            throwsA(anything),
          );
          expect(f.state.searchVisible, visible);
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
          await f.select();
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
        expect(f.state.searchVisible, isFalse);
        expect(await f.reader.prepareLookup(), isNull);
        expect(service.terms, isEmpty);
        await f.select();
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

  test(
    'lookup consent target cannot act after replacement or leaving Reading',
    () async {
      final service = _ControlledDictionary();
      final f = await _ReaderFixture.create('text.pdf', dictionary: service);
      try {
        await f.select();
        final target = await f.reader.prepareLookup();
        await f.reader.showPopover('appearance');
        await f.reader.lookup(target!);
        expect(f.popup['kind'], 'appearance');
        await f.select();
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
        await _readerAction(tester, () => f.reader.toggleSearch(visible: true));
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
        expect(find.byType(NotebookScreen), findsNothing);
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
        f.notes.view(id, searchVisible: true);
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
        expect(find.byType(BookViewSelector), findsNothing);
        final menus = <List<Map>>[];
        await _mainMenuSelect(tester, null, snapshots: menus);
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
              .where((e) => ['Reading', 'Notebook'].contains(e['label']))
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
            expect(children.map((e) => e['label']), ['Reading', 'Notebook']);
            for (final item in children) {
              final reading = item['label'] == 'Reading';
              final command =
                  _appCommands(tester)[reading
                      ? BusyBooksCommandIds.viewReading
                      : BusyBooksCommandIds.viewNotebook]!;
              expect(
                item['icon'],
                reading ? 'view-paged-symbolic' : 'document-edit-symbolic',
              );
              expect(item['selected'], item['label'] == active);
              expect(item['mutuallyExclusive'], true);
              expect(item['shortcut'], command.shortcut!.label);
              expect(item['gtkAccelerator'], command.shortcut!.gtkAccelerator);
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
        await tester.tap(_headerButton('Search in Book'));
        await tester.pumpAndSettle();
        await check(false, 'Reading');
        await tester.tap(_headerButton('Search in Book'));
        await tester.pumpAndSettle();
        await check(true, 'Reading');
        await _readerAction(tester, () async {
          await _appCommands(tester).execute(BusyBooksCommandIds.viewNotebook);
        });
        await tester.pumpAndSettle();
        await check(true, 'Notebook');
        await tester.tap(_headerButton('Search in Notebook'));
        await tester.pumpAndSettle();
        await check(false, 'Notebook');
        await tester.tap(_headerButton('Search in Notebook'));
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
              (e) => ['Reading', 'Notebook', 'View'].contains(e['label']),
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
        await tester.tap(_headerButton('Search in Book'));
        await tester.pumpAndSettle();
        gate.failBook = true;
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
        gate.failBook = false;
        await _mainMenuSelect(tester, 'Notebook');
        await _pumpUntil(
          tester,
          () => find.byType(NotebookScreen).evaluate().isNotEmpty,
        );
        expect(f.drafts.drafts.values.single.text, 'Protected B');
        final opens = f.calls.where((c) => c.method == 'open').length;
        await tester.tap(_headerButton('Search in Notebook'));
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
          () => find.byType(ReaderScreen).evaluate().isNotEmpty,
        );
        expect(f.state.location, anchor);
        expect(f.drafts.drafts.values.single.text, 'Protected B');
        expect(f.calls.where((c) => c.method == 'open').length, opens);
      } finally {
        gate.fail = false;
        gate.failBook = false;
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
            () => f.reader.toggleSearch(visible: true),
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
            () => find.byType(NotebookScreen).evaluate().isNotEmpty,
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
          'accessories-notes-symbolic',
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
            (e) => ['Reading', 'Notebook', 'View'].contains(e['label']),
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
          () => find.byType(NotebookScreen).evaluate().isNotEmpty,
        );
        expect(snapshots.single.map((e) => e['label']), [
          'Reading',
          'Notebook',
        ]);
        expect(snapshots.single[0]['icon'], 'view-paged-symbolic');
        expect(snapshots.single[1]['icon'], 'document-edit-symbolic');
        expect(snapshots.single[0]['selected'], true);
        expect(snapshots.single[1]['selected'], false);
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
        expect(item('Bookmark')['enabled'], true);
        expect(item('Bookmark')['icon'], 'bookmark-new-symbolic');
        expect(item('View Options')['enabled'], true);
        expect(item('Outline')['selected'], true);
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
        await _readerAction(tester, () => f.reader.panel('annotations'));
        await _mainMenuSelect(tester, null, snapshots: menus);
        expect(item('Annotations')['selected'], true);
        expect(item('Outline')['selected'], false);
        await _mainMenuSelect(tester, 'Annotations');
        expect(f.state.panelOpen, true);
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
        final menus = <List<Map>>[];
        await _mainMenuSelect(tester, 'Bookmark', snapshots: menus);
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
        expect(find.byType(NotebookScreen), findsOneWidget);
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
          () => find.text('Error').evaluate().isNotEmpty,
        );
        expect(find.textContaining('Could not open the menu'), findsOneWidget);
        expect(f.state.error, isNull);
        await _closeActionError(tester);
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
        await tester.tap(find.byTooltip('Main Menu'));
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
        gate.failBook = true;
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
        gate.failBook = false;
        await tester.tap(find.byTooltip('View'));
        await _pumpUntil(
          tester,
          () => find.byType(NotebookScreen).evaluate().isNotEmpty,
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
      gate.bookEntered = Completer<void>();
      gate.bookProceed = Completer<void>();
      try {
        await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
        final command = _appCommands(tester);
        unawaited(command.execute(BusyBooksCommandIds.viewNotebook));
        await _pumpUntil(tester, () => gate.bookEntered!.isCompleted);
        f.container.read(appRouterProvider).go('/');
        await tester.pumpAndSettle();
        gate.bookProceed!.complete();
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
        if (!gate.bookProceed!.isCompleted) gate.bookProceed!.complete();
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
          _headerButton('Search in Book'),
          find.byType(BusyBooksMainMenuButton),
        ].map((x) => tester.getCenter(x).dx).toList();
        expect(points, orderedEquals([...points]..sort()));
        await tester.tap(_headerButton('Search in Book'));
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
          _headerButton('Search in Notebook'),
          find.byType(BusyBooksMainMenuButton),
        ].map((w) => tester.getCenter(w).dx).toList();
        expect(notebookPoints, orderedEquals([...notebookPoints]..sort()));
        expect(find.byTooltip('Book details'), findsNothing);
        await tester.tap(_headerButton('Search in Notebook'));
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
        final menuRect = tester.getRect(find.byType(BusyBooksMainMenuButton));
        expect(menuRect.right, lessThanOrEqualTo(540));
        expect(menuRect.left, greaterThan(0));
        final menus = <List<Map>>[];
        await _mainMenuSelect(tester, null, snapshots: menus);
        expect(
          menus.single.singleWhere((e) => e['label'] == 'Bookmark')['enabled'],
          true,
        );
        expect(
          menus.single.singleWhere(
            (e) => e['label'] == 'Search in Book',
          )['enabled'],
          true,
        );
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
            f.notes.view(
              f.state.bookId!,
              query: 'Protected',
              filter: 'bookmark',
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
          await tester.pumpAndSettle();
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
            expect(f.notes.state.view(bookId).query, 'Protected');
            final m = <List<Map>>[];
            await _mainMenuSelect(tester, null, snapshots: m);
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
      'right header anchored Appearance first use, failure and retry preserve the $fixture passage',
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
        final anchor = Map.of(f.state.location);
        var fail = true;
        final requests = <Map>[];
        f.onNativeCall = (c) async {
          if (c.method == 'popover') {
            requests.add(c.arguments as Map);
            if (fail) {
              throw PlatformException(
                code: 'popover-initialization',
                message: 'Fixture host failure',
              );
            }
          }
          return null;
        };
        try {
          await _mountHeaderApplication(tester, f, '/read/${f.state.bookId}');
          final label = fixture == 'reflowable.epub'
              ? 'Appearance'
              : 'View Options';
          final trigger = tester.getRect(_headerButton(label));
          await tester.tap(_headerButton(label));
          await _pumpUntil(tester, () => f.state.popoverError != null);
          expect(f.state.ready, true);
          expect(f.state.error, isNull);
          expect(f.state.location, anchor);
          expect(requests.single['x'], closeTo(trigger.left, .01));
          expect(requests.single['y'], closeTo(trigger.top, .01));
          fail = false;
          tester.view.physicalSize = const Size(1100, 850);
          await tester.pumpAndSettle();
          final relocated = tester.getRect(_headerButton(label));
          await tester.tap(find.text('Retry'));
          await _pumpUntil(tester, () => requests.length == 2);
          expect(requests.last['x'], closeTo(relocated.left, .01));
          expect(requests.last['y'], closeTo(relocated.top, .01));
          expect(
            (requests.last['typography'] as Map)['fontFamily'],
            fixture == 'reflowable.epub',
          );
          expect(requests.last['pdf'], fixture.endsWith('.pdf'));
          await _readerAction(tester, f.reader.dismissPopover);
          await tester.tap(_headerButton(label));
          await _pumpUntil(tester, () => requests.length == 3);
          expect(f.state.location, anchor);
          expect(f.state.error, isNull);
        } finally {
          f.onNativeCall = null;
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
        await tester.pumpAndSettle();
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
        await f.reader.panel('outline');
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
        await tester.pumpAndSettle();
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
            .read(readerSidebarProvider(f.state.bookId!))
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
              .read(readerSidebarProvider(f.state.bookId!))
              .scroll['outline'],
          saved,
        );
        await _readerAction(tester, () => f.reader.panel('annotations'));
        await _readerAction(tester, () => f.reader.panel('outline'));
        expect(
          f.container
              .read(readerSidebarProvider(f.state.bookId!))
              .scroll['outline'],
          saved,
        );
        await _readerAction(tester, f.reader.toggleSidebar);
        await _readerAction(tester, f.reader.toggleSidebar);
        expect(
          f.container
              .read(readerSidebarProvider(f.state.bookId!))
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
              .widget<BusyBooksPopupMenuItem<String>>(
                find.byWidgetPredicate(
                  (w) =>
                      w is BusyBooksPopupMenuItem<String> &&
                      w.menuValue == 'outline',
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
        f.container.read(readerSidebarProvider(id).notifier).toggle('g');
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
        expect(f.container.read(readerSidebarProvider(id)).expanded, isEmpty);
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
        await f.reader.panel('thumbnails');
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
          wrapStore: (s) => gate = AnnotationStoreGate(s),
        );
        await f.select();
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
        await f.reader.panel('annotations');
      });
      try {
        await tester.pumpWidget(_sidebarApplication(f));
        await tester.pumpAndSettle();
        expect(find.textContaining('Protected B'), findsOneWidget);
        expect(find.text('Saved A'), findsNothing);
        final ui = f.container.read(
          readerSidebarProvider(f.state.bookId!).notifier,
        );
        ui.filter(kind: 'bookmark');
        await tester.pumpAndSettle();
        expect(find.text('Bookmark private'), findsOneWidget);
        expect(find.textContaining('Protected B'), findsNothing);
        ui.filter(kind: 'highlight', withNotes: true);
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
        gate.fail = false;
        gate.failDelete = true;
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(f.drafts.drafts.containsKey(highlight.id), isTrue);
        // Existing error dialog is actionable and leaves the protected draft.
        if (find.text('Close').evaluate().isNotEmpty) {
          await tester.tap(find.text('Close'));
        }
        if (find.text('OK').evaluate().isNotEmpty) {
          await tester.tap(find.text('OK'));
        }
        await tester.pumpAndSettle();
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
        await f.select();
        await f.reader.annotation('highlight', note: 'Saved A');
        annotation = f.reader.annotations.single;
        await f.reader.editAnnotation(annotation);
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
        await _readerAction(tester, () => f.reader.panel('annotations'));
        expect(f.drafts.effectiveNote(annotation), 'Accepted local B');
        expect(f.state.panel, 'annotations');
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
          () => f.reader.editAnnotation(f.reader.annotations.single),
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
    'sidebar Open in Notebook reveals its selected saved item and preserves later Notebook scrolling',
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
        await f.reader.panel('annotations');
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
        await tester.tap(find.text('Open in Notebook'));
        await _pumpUntil(
          tester,
          () => find.byType(NotebookScreen).evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        final id = f.state.bookId!, view = f.drafts.view(id);
        expect(view.selected, 'annotation-target-90');
        expect(
          find.byKey(const ValueKey('annotation-target-90')),
          findsOneWidget,
        );
        expect(find.text('Private note 90'), findsOneWidget);
        expect(view.revealAnnotation, isNull);
        final before = f.drafts.view(id).scroll;
        expect(before, greaterThan(1000));
        await tester.drag(find.byType(ListView), const Offset(0, 250));
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
    'sidebar capability and book-specific state survive close/reopen without leaking PDF previews to EPUB',
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
        f.container.read(readerSidebarProvider(id).notifier).toggle('g');
        await f.reader.panel('annotations');
        f.container
            .read(readerSidebarProvider(id).notifier)
            .filter(kind: 'bookmark', withNotes: true);
        final workspace = f.container.read(
          workspaceControllerProvider.notifier,
        );
        final other = await workspace.openPath(
          p.absolute('test/fixtures/fixed-layout.epub'),
        );
        await f.reader.open(other.books.single.id);
        await f.checkedEvent('ready');
        await f.checkedEvent('opened');
        expect(f.reader.panelAvailable('thumbnails'), isFalse);
        await f.reader.panel('thumbnails');
        expect(f.state.panel, isNot('thumbnails'));
        expect(
          f.container.read(readerSidebarProvider(f.state.bookId!)).filter,
          'all',
        );
        await f.reader.close();
        await workspace.loadBook(id, activate: true);
        await f.reader.open(id);
        await f.checkedEvent('ready');
        await f.checkedEvent('opened');
        expect(f.state.panel, 'annotations');
        expect(f.container.read(readerSidebarProvider(id)).filter, 'bookmark');
        expect(f.container.read(readerSidebarProvider(id)).expanded, isEmpty);
        await workspace.createCollection('Collection context');
        await workspace.addBooks([p.absolute('test/fixtures/text.pdf')]);
        expect(f.reader.panelAvailable('books'), isTrue);
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
        f.reader.panel('outline');
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
              home: ReaderScreen(id: f.state.bookId!),
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
        await tester.pumpAndSettle();
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
        expect(f.state.panelOpen, isTrue);
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
            final sidebar = find.byKey(const ValueKey('reader-sidebar-toggle'));
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
              find.byTooltip(
                'Go to Location · Page 23 · Physical page 49 / 322',
              ),
              findsOneWidget,
            );
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
                child: ReaderScreen(id: f.state.bookId!),
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
        final home = find.byKey(const ValueKey('reader-home'));
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
          find.byTooltip('Go to Location · Page 255 · Physical page 281 / 322'),
          findsOneWidget,
        );
        tester.view.physicalSize = const Size(640, 850);
        await tester.pumpAndSettle();
        expect(previous, findsOneWidget);
        expect(next, findsOneWidget);
        expect(find.byKey(const ValueKey('reader-home')), findsOneWidget);
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
        expect(find.byKey(const ValueKey('reader-home')), findsOneWidget);
        expect(
          tester.getRect(next).left - tester.getRect(previous).right,
          BusyBooksSpacing.headerInset,
        );
        f.reader.toggleSearch(visible: true);
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
          .showPopover('appearance')
          .then((_) => replaced = true);
      await _pumpUntil(tester, () => gate.payload?['kind'] == 'appearance');
      gate.painted(old);
      expect(replaced, isFalse);
      gate.frame.complete();
      await _pumpUntil(tester, () => replaced);
      await next;
      expect(find.text('Zoom'), findsOneWidget);
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
            home: ReaderScreen(id: f.state.bookId!),
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
                await f.checkedEvent(
                  'annotation',
                  format == 'epub'
                      ? {'cfi': expected.first.anchor['cfi']}
                      : {'id': expected.first.id},
                );
                expectSync(f.popup['annotationId'], expected.first.id);
                expectSync(f.popup['note'], expected.first.note);
              });
              _connectPopover(f);
              await tester.pumpWidget(const ReaderPopoverApp());
              await _popupUpdate(tester, f.popup);
              expect(
                tester
                    .widget<TextField>(find.byType(TextField))
                    .controller!
                    .text,
                expected.first.note,
              );
              final edited = '${expected.first.note}\nEdited after cold open';
              await tester.enterText(find.byType(TextField), edited);
              await tester.tap(find.text('Save'));
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
                f.notes.view(f.state.bookId!, selected: expected.first.id);
              });
              await tester.pumpWidget(
                UncontrolledProviderScope(
                  container: f.container,
                  child: MaterialApp(
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    home: NotebookScreen(id: f.state.bookId!),
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
            await f.select();
            if (kind == 'existing') {
              await f.reader.annotation('highlight', note: 'Baseline');
              // The full supported note is authored in the shared Notebook
              // lifecycle before Reading is asked to display or save it.
              final a = f.reader.annotations.single;
              f.notes.edit(a, note);
              await f.notes.save(a.id);
              await f.reader.editAnnotation(f.reader.annotations.single);
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
              () => f.reader.editAnnotation(f.reader.annotations.single),
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
        await f.select();
        await f.reader.annotation('highlight', note: 'Saved baseline');
        await f.reader.editAnnotation(f.reader.annotations.single);
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
        final handoffError = throwsA(
          predicate<Object>(
            (e) => e.toString().contains('Note handoff failed'),
          ),
        );
        await _readerAction(tester, () async {
          await expectLater(f.reader.showPopover('appearance'), handoffError);
          await expectLater(f.reader.flush(), handoffError);
          await expectLater(f.reader.close(), handoffError);
          final other = await f.container
              .read(workspaceControllerProvider.notifier)
              .openPath(p.absolute('test/fixtures/image-only.pdf'));
          await f.reader.open(other.books.single.id);
        });
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
            f.reader
                .editAnnotation(f.reader.annotations.single)
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
          () => f.reader.editAnnotation(f.reader.annotations.single),
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
        await f.select();
        await f.reader.annotation('highlight', note: 'Baseline');
        await f.reader.editAnnotation(f.reader.annotations.single);
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
            await f.select();
            if (kind == 'existing') {
              await f.reader.annotation('highlight', note: 'Saved baseline');
              await f.reader.editAnnotation(f.reader.annotations.single);
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
              () => f.reader.editAnnotation(f.reader.annotations.single),
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
        await f.select();
        if (kind == 'existing') {
          await f.reader.annotation('highlight', note: 'Persisted baseline');
          await f.reader.editAnnotation(f.reader.annotations.single);
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
          () => f.reader.editAnnotation(f.reader.annotations.single),
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
              home: NotebookScreen(id: f.state.bookId!),
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
            await f.select();
            if (kind == 'existing') {
              await f.reader.annotation('highlight', note: 'Original baseline');
              await f.reader.editAnnotation(f.reader.annotations.single);
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
              () => f.reader.editAnnotation(f.drafts.sources[id]!),
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
              () => f.reader.editAnnotation(f.reader.annotations.single),
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
        await f.select();
        await f.reader.annotation('highlight', note: 'Saved baseline');
        await f.reader.editAnnotation(f.reader.annotations.single);
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
        await f.select();
        await f.reader.annotation('highlight', note: 'Replacement baseline');
        await f.reader.annotation('highlight', note: 'Original baseline');
        await f.reader.editAnnotation(f.reader.annotations.last);
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
          () => f.reader.editAnnotation(f.reader.annotations.first),
        );
        await _popupUpdate(tester, f.popup);
        final replacement = Map.of(f.popup);
        expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly,
          isFalse,
        );
        expect(find.textContaining('Saving is still pending'), findsNothing);
        await tester.enterText(find.byType(TextField), 'Replacement latest');
        // Simulate an already queued callback from the old field. Its bound
        // presentation must remain stale even though the app has new data.
        staleChanged('Obsolete old input');
        await tester.pump();
        expect(
          delivered.last['presentation'],
          isNot(replacement['presentation']),
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
        await f.select();
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
        await f.reader.editAnnotation(source);
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
          await f.select();
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
            await f.reader.editAnnotation(a);
            await f.action('noteDraft', {'note': 'Protected B'});
            await f.action('annotationNote', {'note': 'Protected B'});
            await f.action('dismiss');
          }
          await f.reader.editAnnotation(a);
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
          await f.select();
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
            await f.reader.editAnnotation(a);
            await f.action('noteDraft', {'note': 'Protected B'});
            await f.action('annotationNote', {'note': 'Protected B'});
            await f.action('dismiss');
          }
          await f.reader.editAnnotation(a);
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
            () => f.reader.editAnnotation(f.reader.annotations.single),
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
          await f.select();
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
          await _readerAction(tester, f.select);
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
                home: NotebookScreen(id: source.bookId),
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
          await tester.tap(find.text('Save'));
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
            await f.reader.editAnnotation(item);
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
        await f.select();
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
        await f.select();
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
            await f.select();
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
          await f.select();
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
        await f.select();
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
        await f.select();
        await f.reader.annotation('highlight', note: 'Saved A');
        final a = f.reader.annotations.single;
        gate.entered = Completer<void>();
        gate.proceed = Completer<void>();
        f.notes.edit(a, 'Older B');
        final saving = f.notes.save(a.id);
        await gate.entered!.future;
        await f.reader.editAnnotation(a);
        expect(f.popup['note'], 'Older B');
        await f.action('noteDraft', {'note': 'Newer C'});
        gate.proceed!.complete();
        await saving;
        expect(f.drafts.drafts[a.id]!.text, 'Newer C');
        await f.notes.flush();
        await f.verifyNote(a.id, 'Newer C');
        await f.reader.editAnnotation(a);
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
        await f.select();
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
    'header search survives sidebar changes and rejects obsolete results before and after cancellation',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      try {
        expect(f.state.searchStatus, 'idle');
        f.reader.toggleSearch(visible: true);
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
        f.reader.panel('annotations');
        f.reader.panel('search');
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
    'selection popover keeps reader visible and writes durable passage notes and chosen color',
    () async {
      final f = await _ReaderFixture.create('reflowable.epub');
      try {
        f.calls.clear();
        const anchor = {'cfi': 'epubcfi(/6/2!/4/2/1:6)', 'index': 0};
        await f.event('selection', {
          'anchor': anchor,
          'text': 'A quiet library',
          'reference': 'Chapter 1',
          'settled': true,
          'rect': {'x': 30, 'y': 20, 'width': 120, 'height': 24},
        });
        final popup =
            f.calls.singleWhere((c) => c.method == 'popover').arguments as Map;
        expect(popup['kind'], 'selection');
        expect(popup['session'], f.session);
        expect(
          f.calls.where((c) => c.method == 'visible' && c.arguments == false),
          isEmpty,
        );
        await f.event('popoverAction', {
          'presentation': popup['presentation'],
          'action': 'highlight',
          'color': 'blue',
          'note': 'Keep this passage',
        });
        final annotations = f.container
            .read(workspaceControllerProvider)
            .annotations;
        expect(annotations.single.anchor, anchor);
        expect(annotations.single.note, 'Keep this passage');
        expect(annotations.single.color, 'blue');
        expect(f.reader.highlightColor, 'blue');
        expect(f.calls.where((c) => c.method == 'dismissPopover'), isNotEmpty);
        final stale = popup['presentation'];
        await f.event('popoverAction', {
          'presentation': stale,
          'action': 'highlight',
          'color': 'pink',
          'note': 'stale',
        });
        expect(
          f.container.read(workspaceControllerProvider).annotations.length,
          1,
        );
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
        expect(f.reader.panelAvailable('thumbnails'), isTrue);
        final query = f.state.query;
        f.reader.search('art');
        expect(f.state.query, query);
        await f.reader.addNote();
        expect(f.dispatches.last['action'], 'beginRegion');
        final region = {
          ...page,
          'region': [.1, .2, .3, .4],
        };
        await f.event('regionSelected', {
          'anchor': region,
          'text': '',
          'reference': 'Page 1',
          'rect': {'x': 10, 'y': 20, 'width': 30, 'height': 40},
        });
        expect(f.popup['annotationKind'], 'region');
        expect(f.popup['editing'], isTrue);
        gate.failPut = true;
        await f.action('highlight', {
          'note': 'Private image note',
          'color': 'blue',
        });
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
        await f.reader.editAnnotation(f.reader.annotations.single);
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
        await f.reader.panel('outline');
      });
      try {
        await tester.pumpWidget(_sidebarApplication(f));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Search in Book'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('reader-sidebar-view-menu')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Search Results'), findsNothing);
        expect(find.text('Thumbnails'), findsOneWidget);
        expect(find.text('Annotations'), findsOneWidget);
        await tester.tap(find.text('Thumbnails'));
        await tester.pumpAndSettle();
        expect(f.state.panel, 'thumbnails');
        expect(f.state.searchVisible, isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _readerAction(tester, f.dispose);
      }
    },
  );
}
