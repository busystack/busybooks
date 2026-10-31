import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show AsyncCallback;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../app/app_settings.dart';
import '../../book_workspace/application/book_sidebar_controller.dart';
import '../../book_workspace/application/book_presentation.dart';
import '../../core/reading_preferences.dart';
import '../../core/typography.dart';
import '../../library/data/file_identity.dart';
import '../../library/data/record_validation.dart'
    show validateAnchor, annotationColors;
import '../../library/domain/book.dart';
import '../../notebook/application/notebook_controller.dart';
import '../../workspace/workspace_controller.dart';
import '../../workspace/workspace_model.dart';
import '../domain/annotation_transfer.dart';
import '../domain/page_preview.dart';
import '../domain/publication_outline.dart';
import '../domain/reader_bridge.dart';
import '../domain/reading_navigation.dart';
import '../fonts/reading_font_service.dart';
import 'dictionary_service.dart';
import 'narration_controller.dart';

const readerChannel = MethodChannel('io.busystack.busybooks/reader');
final readerStartupTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 45),
);

/// One passage activation, claimed by exactly one publication opening. The
/// source validator remains live until dispatch, including across route handoff.
class ReaderJumpRequest {
  ReaderJumpRequest._(
    this.bookId,
    Map<String, dynamic> anchor,
    this._isCurrent,
    this._validate,
    this._onReleased,
  ) : _anchor = Map.unmodifiable(
        jsonDecode(jsonEncode(anchor)) as Map<String, dynamic>,
      );

  final String bookId;
  final Map<String, dynamic> _anchor;
  final bool Function()? _isCurrent;
  final Future<bool> Function()? _validate;
  final VoidCallback _onReleased;
  final _finished = Completer<void>();
  int? _openingRevision;
  String? _session;
  bool _consuming = false;
  Future<void> get finished => _finished.future;
  bool get _live => !_finished.isCompleted && (_isCurrent?.call() ?? true);
  void cancel() {
    if (_finished.isCompleted) return;
    _onReleased();
    _finished.complete();
  }
}

/// Captured before a native selection can collapse or its menu can close.
class ReaderSelectionTarget {
  const ReaderSelectionTarget(
    this.bookId,
    this.session,
    this.presentation,
    this.text,
    this.rect, {
    this.passage,
    this.selectionRevision,
    this.annotationId,
  });
  final Map<String, dynamic>? passage;
  final int? selectionRevision;
  final String? annotationId;
  final String bookId, session, text;
  final int presentation;
  final Rect? rect;
}

enum ReaderSelectionAction {
  highlight,
  addNote,
  copy,
  search,
  lookUp,
  readAloud,
}

/// The passage belongs to the selection intent, independently of native pixels.
class ReaderSelectionMenuOwner {
  ReaderSelectionMenuOwner._(this.target, this._focusRevision);
  final ReaderSelectionTarget target;
  final int _focusRevision;
}

/// Ownership of one primary-window appearance menu, after draft handoff.
class ReaderAppearanceMenuOwner {
  const ReaderAppearanceMenuOwner._(
    this.bookId,
    this.session,
    this.presentation,
  );
  final String bookId, session;
  final int presentation;
}

/// Primary-window controls retain the reader session and presentation owner.
class ReaderPanel {
  const ReaderPanel({
    required this.bookId,
    required this.session,
    required this.presentation,
    this.term = '',
    this.lookup = const {'status': 'loading'},
  });
  final String bookId, session, term;
  final int presentation;
  final Map<String, dynamic> lookup;
}

class ReaderState {
  const ReaderState({
    this.bookId,
    this.ready = false,
    this.surfaceVisible = false,
    this.modalFrame,
    this.error,
    this.warning,
    this.panel,
    this.errorCode,
    this.phase = 'idle',
    this.selection,
    this.location = const {},
    this.navigation = const {},
    this.toc = const [],
    this.outline = const PublicationOutline.empty(),
    this.outlineStatus = 'loading',
    this.matches = const [],
    this.searching = false,
    this.searchProgress = 0,
    this.query = '',
    this.searchStatus = 'idle',
    this.currentMatch = -1,
    this.searchTotal = 0,
    this.searchOffset = 0,
    this.searchLimit = 200,
    this.fixed = false,
    this.typography = TypographyCapabilities.none,
    this.pages = 0,
    this.labels = const [],
    this.thumbnails = const {},
    this.thumbnailErrors = const {},
    this.thumbnailPending = const {},
  });
  final String? bookId, error, warning, errorCode;
  final ReaderPanel? panel;
  final ui.Image? modalFrame;
  final String phase;
  final bool ready, searching, fixed, surfaceVisible;
  final TypographyCapabilities typography;
  final int pages;
  final Map<String, dynamic>? selection;
  final Map<String, dynamic> location, navigation;
  bool get canBack => ready && navigation['back'] == true;
  bool get canForward => ready && navigation['forward'] == true;
  bool get canNext => ready && navigation['next'] == true;
  bool get canSpeakNext =>
      ready &&
      (navigation['speechNext'] as bool? ?? navigation['next'] == true);
  bool get canPrevious => ready && navigation['previous'] == true;
  final List<Map<String, dynamic>> toc, matches;
  final String query, searchStatus;
  final int currentMatch, searchTotal, searchOffset, searchLimit;
  final double searchProgress;
  final List<String> labels;
  final Map<int, PagePreview> thumbnails;
  final Map<int, String> thumbnailErrors;
  final Set<int> thumbnailPending;
  final PublicationOutline outline;
  final String outlineStatus;
  ReaderState copy({
    String? bookId,
    bool? ready,
    bool? surfaceVisible,
    ui.Image? modalFrame,
    bool clearModalFrame = false,
    String? error,
    String? warning,
    String? errorCode,
    String? phase,
    bool clearWarning = false,
    ReaderPanel? panel,
    bool clearPanel = false,
    Map<String, dynamic>? selection,
    bool clearSelection = false,
    Map<String, dynamic>? location,
    Map<String, dynamic>? navigation,
    List<Map<String, dynamic>>? toc,
    List<Map<String, dynamic>>? matches,
    bool? searching,
    double? searchProgress,
    String? query,
    String? searchStatus,
    int? currentMatch,
    int? searchTotal,
    int? searchOffset,
    int? searchLimit,
    bool? fixed,
    TypographyCapabilities? typography,
    int? pages,
    List<String>? labels,
    Map<int, PagePreview>? thumbnails,
    Map<int, String>? thumbnailErrors,
    Set<int>? thumbnailPending,
    PublicationOutline? outline,
    String? outlineStatus,
  }) => ReaderState(
    bookId: bookId ?? this.bookId,
    ready: ready ?? this.ready,
    surfaceVisible: surfaceVisible ?? this.surfaceVisible,
    modalFrame: clearModalFrame ? null : modalFrame ?? this.modalFrame,
    error: error ?? this.error,
    warning: clearWarning ? null : warning ?? this.warning,
    panel: clearPanel ? null : panel ?? this.panel,
    errorCode: errorCode ?? this.errorCode,
    phase: phase ?? this.phase,
    selection: clearSelection ? null : selection ?? this.selection,
    location: location ?? this.location,
    navigation: navigation ?? this.navigation,
    toc: toc ?? this.toc,
    matches: matches ?? this.matches,
    searching: searching ?? this.searching,
    searchProgress: searchProgress ?? this.searchProgress,
    query: query ?? this.query,
    searchStatus: searchStatus ?? this.searchStatus,
    currentMatch: currentMatch ?? this.currentMatch,
    searchTotal: searchTotal ?? this.searchTotal,
    searchOffset: searchOffset ?? this.searchOffset,
    searchLimit: searchLimit ?? this.searchLimit,
    fixed: fixed ?? this.fixed,
    typography: typography ?? this.typography,
    pages: pages ?? this.pages,
    labels: labels ?? this.labels,
    thumbnails: thumbnails ?? this.thumbnails,
    thumbnailErrors: thumbnailErrors ?? this.thumbnailErrors,
    thumbnailPending: thumbnailPending ?? this.thumbnailPending,
    outline: outline ?? this.outline,
    outlineStatus: outlineStatus ?? this.outlineStatus,
  );
}

class ReaderController extends Notifier<ReaderState> {
  final events = StreamController<Map<String, dynamic>>.broadcast();
  Timer? _saveTimer, _startupTimer;
  int _searchRevision = 0, _presentation = 0;
  final _searchWaiters = <Completer<bool>>[];

  void _finishSearchWaiters(bool complete) {
    for (final waiter in _searchWaiters) {
      if (!waiter.isCompleted) waiter.complete(complete);
    }
    _searchWaiters.clear();
  }

  Rect _viewport = Rect.zero;
  Rect get viewport => _viewport;
  Map<String, dynamic> _chrome = {};
  bool get _panelActive => state.panel != null;
  int _panelRequest = 0;
  int _selectionRevision = 0;
  Map<String, dynamic>? _selectionIntent;
  ReaderSelectionMenuOwner? _selectionMenuOwner;
  Future<void> Function()? _selectionMenuDismiss;
  DictionaryRequest? _lookupRequest;
  DictionaryResult? _lookupResult;
  String? _lookupTerm;
  int _lookupRevision = 0;

  void _invalidateLookup() {
    ++_lookupRevision;
    _lookupRequest?.cancel();
    _lookupRequest = null;
    _lookupResult = null;
    _lookupTerm = null;
  }

  ReaderSelectionTarget? captureSelection({bool preserveWhitespace = false}) {
    if (!state.ready || !_routeVisible || _suspended || state.bookId == null) {
      return null;
    }
    final passage = _selectionMenuOwner?.target.passage ?? state.selection;
    final rawText = passage?['text'] as String? ?? '';
    final text = preserveWhitespace ? rawText : rawText.trim();
    if (text.isEmpty) return null;
    return ReaderSelectionTarget(
      state.bookId!,
      _session,
      _presentation,
      text,
      _selectionRect(passage?['rect']),
      passage: passage,
      selectionRevision: _selectionRevision,
    );
  }

  bool _ownsSelection(ReaderSelectionTarget target, {int? presentation}) =>
      ref.mounted &&
      state.ready &&
      _routeVisible &&
      !_suspended &&
      target.bookId == state.bookId &&
      target.session == _session &&
      (presentation ?? target.presentation) == _presentation &&
      (target.selectionRevision == null ||
          target.selectionRevision == _selectionRevision);

  Future<void> searchSelection({ReaderSelectionTarget? selection}) async {
    final target = selection ?? captureSelection(preserveWhitespace: true);
    if (target == null) {
      events.add({'type': 'feedback', 'message': _labels.selectText});
      return;
    }
    if (!_ownsSelection(target)) return;
    await dismissReaderControls(restoreFocus: false);
    if (!_ownsSelection(target, presentation: target.presentation + 1)) {
      return;
    }
    await focusChrome();
    if (!_ownsSelection(target, presentation: target.presentation + 1)) {
      return;
    }
    events.add({
      'type': 'searchSelection',
      'bookId': target.bookId,
      'session': _session,
      'presentation': _presentation,
      'text': target.text,
    });
  }

  Future<ReaderSelectionTarget?> prepareLookup({
    ReaderSelectionTarget? selection,
  }) async {
    final target = selection ?? captureSelection();
    if (target == null || !_ownsSelection(target)) return null;
    await dismissReaderControls(restoreFocus: false);
    if (!_ownsSelection(target, presentation: target.presentation + 1)) {
      return null;
    }
    return ReaderSelectionTarget(
      target.bookId,
      target.session,
      _presentation,
      target.text.trim(),
      target.rect,
      passage: target.passage,
      selectionRevision: target.selectionRevision,
      annotationId: target.annotationId,
    );
  }

  Future<void> lookup(ReaderSelectionTarget target) async {
    if (!_ownsSelection(target)) return;
    await _showLookupPanel(target.text);
    if (target.selectionRevision != null &&
            target.selectionRevision != _selectionRevision ||
        target.session != _session ||
        target.bookId != state.bookId ||
        target.presentation + 1 != _presentation ||
        !_panelActive ||
        !_routeVisible ||
        !state.ready) {
      return;
    }
    _lookupTerm = target.text;
    unawaited(_runLookup());
  }

  Future<void> _runLookup() async {
    final term = _lookupTerm;
    if (term == null || !_panelActive) {
      return;
    }
    _lookupRequest?.cancel();
    final revision = ++_lookupRevision,
        session = _session,
        presentation = _presentation,
        bookId = state.bookId;
    bool current() =>
        ref.mounted &&
        revision == _lookupRevision &&
        session == _session &&
        presentation == _presentation &&
        bookId == state.bookId &&
        _lookupTerm == term &&
        _panelActive &&
        _routeVisible &&
        !_suspended &&
        state.ready;
    Future<void> update(Map<String, dynamic> value) async {
      if (!current()) return;
      final panel = state.panel!;
      state = state.copy(
        panel: ReaderPanel(
          bookId: panel.bookId,
          session: panel.session,
          presentation: panel.presentation,
          term: term,
          lookup: value,
        ),
      );
    }

    try {
      await update({'status': 'loading'});
      if (!current()) return;
      _lookupResult = null;
      final request = ref.read(dictionaryServiceProvider).lookup(term);
      _lookupRequest = request;
      final result = await request.result;
      if (!current()) return;
      _lookupRequest = null;
      _lookupResult = result;
      await update(result.toJson());
    } catch (_) {
      if (current()) {
        await update({'status': 'unavailable'}).catchError((Object _) {});
      }
    }
  }

  String? get stateBookId => state.bookId;
  String get sessionId => _session;
  int get presentationId => _presentation;
  int get searchRevision => _searchRevision;
  bool get interactive =>
      _modalOwners.isEmpty &&
      state.ready &&
      state.surfaceVisible &&
      _hasViewport &&
      state.error == null &&
      _routeVisible &&
      _workspaceVisible &&
      !_suspended;
  ReaderJumpRequest? _pendingJump;

  ReaderJumpRequest deferJump({
    required String bookId,
    required Map<String, dynamic> anchor,
    bool useCurrentOpening = false,
    bool Function()? isCurrent,
    Future<bool> Function()? validate,
    VoidCallback? onReleased,
  }) {
    _pendingJump?.cancel();
    late final ReaderJumpRequest request;
    request = ReaderJumpRequest._(bookId, anchor, isCurrent, validate, () {
      if (identical(_pendingJump, request)) _pendingJump = null;
      onReleased?.call();
    });
    _pendingJump = request;
    // A retained ready reader can be waiting for its measured pane to become
    // visible. Bind it, and already-loading readers, to this exact opening.
    if (state.bookId == bookId &&
        !_suspended &&
        state.error == null &&
        (state.ready && useCurrentOpening ||
            const [
              'verifying',
              'initializing',
              'opening',
            ].contains(state.phase))) {
      request._openingRevision = _openRevision;
      if (state.phase != 'verifying') request._session = _session;
    }
    if (state.bookId == bookId && state.error != null && !_suspended) {
      request.cancel();
    }
    return request;
  }

  void _claimPendingJump(String id, int revision) {
    final request = _pendingJump;
    if (request == null) return;
    if (!request._live ||
        request.bookId != id ||
        request._openingRevision != null) {
      request.cancel();
    } else {
      request._openingRevision = revision;
    }
  }

  Future<void> _consumePendingJump(String id, int revision) async {
    final request = _pendingJump;
    if (request == null || request._consuming) return;
    // An old surface's visibility can finish while the target is preparing.
    // Only the opening that claimed this request may consume or abandon it.
    if (request.bookId != id ||
        request._openingRevision == null ||
        request._session == null) {
      return;
    }
    final session = _session;
    bool owned() =>
        ref.mounted &&
        identical(_pendingJump, request) &&
        request._live &&
        request.bookId == id &&
        state.bookId == id &&
        request._openingRevision == revision &&
        _openRevision == revision &&
        request._session == session &&
        _session == session &&
        state.error == null &&
        !_suspended;
    if (!owned()) {
      request.cancel();
      return;
    }
    // Visibility can settle after opened, especially after a narrow dismissal.
    // Keep the intent until the owned surface becomes interactive.
    if (!interactive) return;
    request._consuming = true;
    try {
      if (request._validate != null && !await request._validate()) return;
      if (!owned() || !interactive) return;
      await _send(
        'goto',
        {'anchor': request._anchor},
        isCurrent: () => owned() && interactive,
        validateNavigation: request._validate,
      );
    } finally {
      request.cancel();
    }
  }

  bool _suspended = false;
  bool _workspaceVisible = true;
  bool get suspended => _suspended;
  // Searching is safe while the reading surface is hidden behind a temporary
  // sidebar. Navigation/focus still require visible, interactive ownership.
  bool get canSearch =>
      state.ready && state.error == null && _routeVisible && !_suspended;
  Future<void> setWorkspaceVisible(bool value) {
    if (!value) {
      _focusRevision++;
      _panelRequest++;
      if (_panelActive) {
        unawaited(_dismissReaderControls(restoreFocus: false));
      } else {
        unawaited(_dismissSelectionMenu());
        unawaited(_dismissAppearanceMenu());
      }
      _workspaceVisible = false;
      return invalidateViewport();
    }
    _workspaceVisible = value;
    return _applyVisibility();
  }

  /// A geometry transaction hides native pixels without changing the content
  /// focus intent. Pane/chrome handoffs invalidate that intent separately.
  Future<void> invalidateViewport() {
    _viewportRevision++;
    _viewportSession = null;
    return _applyVisibility();
  }

  bool get hasCurrentViewport => _hasViewport;

  void requestViewportLayout() {
    events.add({'type': 'viewportNeeded', 'session': _session});
  }

  Completer<void>? _viewportSettled;
  int _viewportRevision = 0;
  String? _viewportSession;
  Rect? _acknowledgedViewport;
  bool get _hasViewport =>
      _viewportSession == _session &&
      _acknowledgedViewport == viewport &&
      viewport.width > 0 &&
      viewport.height > 0;

  /// Native bounds must acknowledge the current measured pane before reveal.
  /// The caller owns its widget/layout lifetime; the controller owns renderer
  /// replacement and rejects a late acknowledgement from either owner.
  Future<bool> updateViewport(
    Rect rect, {
    required String bookId,
    bool Function()? isCurrent,
  }) async {
    if (!rect.isFinite || rect.isEmpty || state.bookId != bookId) return false;
    final revision = ++_viewportRevision, session = _session;
    bool current() =>
        ref.mounted &&
        revision == _viewportRevision &&
        session == _session &&
        state.bookId == bookId &&
        (isCurrent?.call() ?? true);
    if (!current()) return false;
    final settled = Completer<void>();
    _viewportSettled = settled;
    try {
      if ((_appearanceMenuOwner != null || _selectionMenuOwner != null) &&
          rect != _viewport) {
        await dismissReaderControls(restoreFocus: false);
        if (!current()) return false;
      }
      // Hide before submitting a changed allocation. The source focus intent
      // and desired visibility survive; only this acknowledgement may reveal.
      _viewportSession = null;
      await _applyVisibility();
      if (!current()) return false;
      _viewport = rect;
      await readerChannel.invokeMethod<void>('bounds', {
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      });
      if (!current()) return false;
      _acknowledgedViewport = rect;
      _viewportSession = session;
      await _applyVisibility();
      return current();
    } catch (error) {
      if (current()) {
        state = state.copy(warning: error.toString());
        events.add({'type': 'feedback', 'message': error.toString()});
      }
      return false;
    } finally {
      settled.complete();
      if (identical(_viewportSettled, settled)) _viewportSettled = null;
    }
  }

  Future<void> suspend() async {
    _focusRevision++;
    _pendingJump?.cancel();
    if (state.bookId == null) {
      _suspended = true;
      _routeVisible = false;
      return;
    }
    final session = _session, visible = _routeVisible;
    await ref.read(narrationControllerProvider.notifier).stop();
    _invalidateAppearanceWork();
    if (state.ready) await send('cancelAppearance');
    await _eventTail;
    await dismissReaderControls();
    if (session != _session) return;
    await cancelSearch();
    // PDF navigation/layout may need a rendered frame to settle. Capture and
    // drain native input while its surface can still produce frames;
    // a suspended reader has no further user input to flush.
    await _flushRenderer();
    if (session != _session) return;
    _suspended = true;
    _routeVisible = false;
    try {
      await _applyVisibility();
    } catch (_) {
      if (session == _session) {
        _suspended = false;
        _routeVisible = visible;
      }
      rethrow;
    }
    _openRevision++;
    if (_preparationOwner != null) {
      await ref.read(readingDataStoreProvider).call('cancelPrepare');
    }
    _startupTimer?.cancel();
    if (!state.ready) {
      _invalidateLayoutVisibility();
      _session = 'suspended:${++_generation}';
      await readerChannel.invokeMethod<void>('close');
    }
    try {
      await flush();
    } catch (_) {
      /* pending positions and Notebook drafts stay protected for editing */
    }
  }

  bool get textInteraction => book?.textInteraction == true;
  bool get pageNavigation => book?.pageBased == true;
  bool get regionNotes => book?.comic == true;
  String get appearanceDefaultsKey => regionNotes
      ? 'comicReading'
      : book?.format == 'pdf'
      ? 'pdfReading'
      : 'reading';
  Future<void> addNote() async {
    if (regionNotes) {
      await dismissReaderControls();
      await send('beginRegion');
    } else {
      final target = captureSelection(preserveWhitespace: true);
      if (target == null) {
        events.add({'type': 'feedback', 'message': _labels.selectText});
        return;
      }
      await _editSelectionNote(target);
    }
  }

  String get highlightColor =>
      ref.read(appSettingsControllerProvider).data['highlightColor'] as String;
  final _pendingBookmarks = <({String bookId, Map<String, dynamic> anchor})>[];
  bool get bookmarkPending => _pendingBookmarks.any(
    (pending) =>
        pending.bookId == state.bookId &&
        sameBookmarkLocation(
          pending.anchor,
          (state.location['anchor'] as Map? ?? {}).cast<String, dynamic>(),
        ),
  );
  bool get canBookmark {
    final anchor = state.location['anchor'];
    if (!state.ready ||
        state.error != null ||
        _suspended ||
        anchor is! Map ||
        bookmarkPending) {
      return false;
    }
    return anchor['page'] is int && anchor['page'] >= 0 ||
        anchor['cfi'] is String &&
            (anchor['cfi'] as String).startsWith('epubcfi(');
  }

  bool get bookmarked => annotations.any(
    (a) =>
        a.kind == 'bookmark' &&
        sameBookmarkLocation(
          a.anchor,
          (state.location['anchor'] as Map? ?? {}).cast<String, dynamic>(),
        ),
  );
  Future<void> _eventTail = Future.value();
  Future<void>? _commandTail;
  final _bridgeAssembler = ReaderBridgeAssembler();
  int _bridgeRevision = 0;
  Object? _bridgeFailure;
  bool _cacheRecoveryAttempted = false;
  Completer<void>? _flushing;
  int _flushRequest = 0;
  Future<void>? _flushOperation;
  StreamSubscription<FileSystemEvent>? _fileWatch;
  Timer? _fileCheck, _filePoll;
  String? _sourcePath;
  int _generation = 0;
  int _openRevision = 0;
  int _annotationRevision = 0;
  int? _preparationOwner;
  int _preparationSerial = 0;
  Future<dynamic> _preparePublication(Map<String, dynamic> args) async {
    final store = ref.read(readingDataStoreProvider),
        owner = ++_preparationSerial;
    if (_preparationOwner != null) await store.call('cancelPrepare');
    _preparationOwner = owner;
    try {
      return await store.call('prepare', args);
    } finally {
      if (_preparationOwner == owner) _preparationOwner = null;
    }
  }

  bool _routeVisible = false;
  final _sessionPrefix =
      '${DateTime.now().microsecondsSinceEpoch}${Random.secure().nextInt(0x100000000)}';
  String _session = 'closed';
  final _pendingLocations = <String, Map<String, dynamic>>{};
  @override
  ReaderState build() {
    listenSelf((previous, next) {
      if (next.error != null && _pendingJump?.bookId == next.bookId) {
        _pendingJump?.cancel();
      }
      if (previous?.error != next.error) {
        _invalidateLayoutVisibility();
        unawaited(_applyVisibility());
      }
    });
    readerChannel.setMethodCallHandler((call) async {
      if (call.method == 'event' && call.arguments is String) {
        final text = call.arguments as String;
        if (text.length > readerBridgeFrameBytes ||
            utf8.encode(text).length > readerBridgeFrameBytes) {
          throw PlatformException(code: 'reader-bridge-size');
        }
        var msg = (jsonDecode(text) as Map).cast<String, dynamic>();
        if (msg['session'] != _session) return;
        try {
          final assembled = _bridgeAssembler.accept(msg);
          if (assembled == null) return;
          msg = assembled;
        } catch (error) {
          msg = {
            'type': 'bridgeError',
            'session': _session,
            'message': error.toString(),
          };
        }
        // A geometry handoff may be waiting inside an inbound selection event.
        // Its renderer drain acknowledgement must not queue behind that event.
        if (msg['type'] == 'layoutVisibility') {
          final pending = _layoutVisibilityResults[msg['request']];
          if (pending != null &&
              msg['revision'] == pending.revision &&
              msg['visible'] == pending.visible &&
              !pending.result.isCompleted) {
            if (msg['message'] is String) {
              pending.result.completeError(
                StateError(msg['message'] as String),
              );
            } else {
              pending.result.complete();
            }
          }
          return;
        }
        if (msg['type'] == 'appearanceResult') {
          final pending = _appearanceResults.remove(msg['request']);
          if (pending != null && !pending.isCompleted) {
            if (msg['message'] is String) {
              pending.completeError(StateError(msg['message'] as String));
            } else {
              pending.complete();
            }
          }
          return;
        }

        final operation = _eventTail.then((_) => _event(msg));
        _eventTail = operation.catchError((Object error) {
          if (msg['session'] == _session) {
            state = state.copy(warning: error.toString());
          }
        });
        await operation;
      }
    });
    ref.onDispose(() {
      _modalImage?.dispose();
      _modalImage = null;
      unawaited(_dismissSelectionMenu());
      unawaited(_dismissAppearanceMenu());
      _pendingJump?.cancel();
      _finishSearchWaiters(false);
      _invalidateLookup();
      for (final pending in _appearanceResults.values) {
        if (!pending.isCompleted) pending.complete();
      }
      _appearanceResults.clear();
      _invalidateLayoutVisibility();
      _session = 'disposed:${++_generation}';
      _presentation++;
      _openRevision++;
      _saveTimer?.cancel();
      _startupTimer?.cancel();
      _fileCheck?.cancel();
      _filePoll?.cancel();
      unawaited(_fileWatch?.cancel());
      readerChannel.setMethodCallHandler(null);
      unawaited(events.close());
    });
    ref.listen(workspaceControllerProvider.select((s) => s.annotations), (
      before,
      after,
    ) {
      if (state.ready && !_suspended) {
        unawaited(syncAnnotations().catchError((Object _) {}));
      }
    });
    return const ReaderState();
  }

  Book? get book =>
      ref.read(workspaceControllerProvider).bookById(state.bookId);
  List<ReadingAnnotation> get annotations => ref
      .read(workspaceControllerProvider)
      .annotations
      .where((x) => x.bookId == state.bookId)
      .toList();
  // Both cold opening and later painting use the existing annotation contract.
  // Private notes stay in primary state/Flutter editors, outside the ordinary
  // renderer message budget. Copy each record without mutating stored data.
  List<Map<String, dynamic>> get _rendererAnnotations => [
    for (final a in annotations) {...a.data}..remove('note'),
  ];
  Map<String, dynamic> get appearance =>
      book?.appearance ??
      (ref.read(appSettingsControllerProvider).data[appearanceDefaultsKey]
              as Map)
          .cast<String, dynamic>();
  AppLocalizations get _labels {
    final tag =
        ref.read(appSettingsControllerProvider).data['locale'] as String? ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return lookupAppLocalizations(Locale(tag == 'de' ? 'de' : 'en'));
  }

  Future<void> retry(String id, {bool Function()? isCurrent}) async {
    if (state.bookId != id || !(isCurrent?.call() ?? true)) return;
    final closingRevision = _openRevision + 1;
    await close();
    if (!ref.mounted ||
        _openRevision != closingRevision ||
        !(isCurrent?.call() ?? true)) {
      return;
    }
    await _open(id, force: true, isCurrent: isCurrent);
  }

  Future<void> open(String id) => _open(id);

  Future<void> _open(
    String id, {
    bool force = false,
    bool cacheRecovery = false,
    bool Function()? isCurrent,
  }) async {
    if (!cacheRecovery) _cacheRecoveryAttempted = false;
    _suspended = false;
    final current = ref.read(workspaceControllerProvider).bookById(id);
    if (current == null || !(isCurrent?.call() ?? true)) {
      _pendingJump?.cancel();
      return;
    }
    final revision = ++_openRevision;
    _claimPendingJump(id, revision);
    bool ownedOpening() =>
        ref.mounted && revision == _openRevision && (isCurrent?.call() ?? true);
    try {
      await _dismissSelectionMenu();
      await _dismissAppearanceMenu();
      if (!ownedOpening()) return;
      await dismissReaderControls(restoreFocus: false);
      if (!ownedOpening()) return;
    } catch (error) {
      if (_pendingJump?._openingRevision == revision) _pendingJump?.cancel();
      if (ownedOpening()) {
        state = state.copy(warning: error.toString());
        events.add({'type': 'feedback', 'message': error.toString()});
      }
      return;
    }
    if (state.bookId != id || !state.ready) {
      _invalidateLookup();
      _invalidateAppearanceWork();
      if (state.ready) await send('cancelAppearance');
      if (!ownedOpening()) return;
      _invalidateLayoutVisibility();
      _session = 'preparing:${++_generation}';
      _selectionIntent = null;
      state = ReaderState(bookId: id, phase: 'verifying');
    }
    final path = current.path.isNotEmpty
        ? current.path
        : (current.data['paths'] as List?)?.firstOrNull as String?;
    try {
      // Revalidate the original even when reusing a live renderer after routing.
      final descriptor = await _preparePublication({
        'id': id,
        'path': path,
        'validationToken': current.data['validationToken'],
        'force': force,
      });
      if (!ownedOpening()) return;
      if (state.bookId == id && state.ready && _sourcePath == path) {
        await _appearanceTail;
        final value = await _resolveAppearance(
          appearance,
          capabilities: typographyCapabilities,
        );
        if (!ownedOpening()) return;
        if (_pendingJump?._openingRevision == revision) {
          _pendingJump?._session = _session;
        }
        if (_canRenderAppearance) {
          await send('appearance', {'value': value});
        } else {
          _appearanceNeedsReconcile = true;
        }
        await syncAnnotations();
        await _applyVisibility();
        await _consumePendingJump(id, revision);
        if (ownedOpening() && _routeVisible && state.ready) {
          events.add(_publicationFocusEvent());
        }
        return;
      }
      await flush();
      if (!ownedOpening()) return;
      await _fileWatch?.cancel();
      if (!ownedOpening()) return;
      _fileCheck?.cancel();
      _filePoll?.cancel();
      _filePoll = null;
      await ref.read(narrationControllerProvider.notifier).stop();
      if (!ownedOpening()) return;
      _finishSearchWaiters(false);
      _searchRevision++;
      _revealOnLocation = false;
      _outlineRevision = null;
      _outlineIncoming.clear();
      _outlineIndices = {};

      _thumbnailWindow = {};
      _thumbnailRevision++;
      state = state.copy(clearPanel: true);
      _presentation++;
      state = ReaderState(bookId: id, phase: 'initializing');
      _sourcePath = path;
      _invalidateLayoutVisibility();
      _session = '$_sessionPrefix${++_generation}';
      final session = _session;
      if (_pendingJump?._openingRevision == revision) {
        _pendingJump?._session = session;
      }
      _bridgeFailure = null;
      await _watchOriginal(path!, id, revision, descriptor as Map);
      if (!ownedOpening()) return;
      _startupTimer?.cancel();
      _startupTimer = Timer(ref.read(readerStartupTimeoutProvider), () {
        if (session == _session) {
          state = state.copy(error: _labels.readerStartupTimedOut);
        }
      });
      await readerChannel.invokeMethod<void>('open', {
        ...descriptor,
        'session': _session,
        'loadingQuery': Uri.encodeQueryComponent(_labels.loadingBook),
      });
      if (!ownedOpening()) return;
      await _applyVisibility();
      if (!ownedOpening()) return;
    } catch (error) {
      if (_pendingJump?._openingRevision == revision) _pendingJump?.cancel();
      // A native initialization result can arrive after another open/close.
      // Its error belongs to the superseded surface, not the current book.
      if (!ownedOpening()) return;
      _startupTimer?.cancel();
      _fileCheck?.cancel();
      _filePoll?.cancel();
      await _fileWatch?.cancel();
      if (!ownedOpening()) return;
      _sourcePath = null;
      _invalidateLayoutVisibility();
      _session = 'closed:${++_generation}';
      await readerChannel.invokeMethod<void>('close');
      if (!ownedOpening()) return;
      state = ReaderState(
        bookId: id,
        error: error.toString(),
        errorCode: error is WorkspaceException ? error.code : 'renderer',
      );
    }
  }

  void _armOpeningWatchdog() {
    _startupTimer?.cancel();
    final session = _session;
    // Publication opening has its own bounded budget after module initialization.
    // Larger originals get additional time without an unbounded activity reset.
    final duration = ref.read(readerStartupTimeoutProvider) * 3;
    _startupTimer = Timer(duration, () {
      if (session == _session && !_suspended && !state.ready) {
        state = state.copy(
          error: _labels.readerStartupTimedOut,
          phase: 'failed',
        );
      }
    });
  }

  Future<void> _watchOriginal(
    String path,
    String id,
    int revision,
    Map descriptor,
  ) async {
    final original = File(path);
    var observed = await original.stat();
    var instance = fileInstance(path);
    if (revision != _openRevision) return;
    if (observed.type != FileSystemEntityType.file ||
        descriptor['sourceInstance'] != instance ||
        descriptor['sourceSize'] != observed.size ||
        descriptor['sourceModified'] !=
            observed.modified.microsecondsSinceEpoch ||
        descriptor['sourceChanged'] !=
            observed.changed.microsecondsSinceEpoch) {
      throw const FileSystemException(
        'Original changed before reader initialization',
      );
    }
    void changed() {
      if (revision != _openRevision || _sourcePath != path) return;
      _fileCheck?.cancel();
      _fileCheck = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(_verifyOriginal(path, id)),
      );
    }

    Future<void> check() async {
      if (_sourcePath != path ||
          state.bookId != id ||
          revision != _openRevision) {
        return;
      }
      try {
        final stat = await original.stat(), identity = fileInstance(path);
        if (_sourcePath != path || revision != _openRevision) return;
        if (stat.type != observed.type ||
            stat.size != observed.size ||
            stat.modified != observed.modified ||
            stat.changed != observed.changed ||
            identity != instance) {
          observed = stat;
          instance = identity;
          changed();
        }
      } catch (_) {
        if (revision == _openRevision && _sourcePath == path) changed();
      }
    }

    // Poll even when native watching is available: rename replacement can leave
    // a watch attached to the old inode, and some filesystems omit events.
    _filePoll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(check()),
    );
    try {
      _fileWatch = original.watch().listen(
        (_) => changed(),
        onError: (Object _) => changed(),
      );
    } catch (_) {
      /* The instance-aware poll remains active. */
    }
    // Close the setup window before handing any pathname to native code.
    final stat = await original.stat();
    if (fileInstance(path) != instance ||
        stat.size != observed.size ||
        stat.modified != observed.modified ||
        stat.changed != observed.changed) {
      throw const FileSystemException(
        'Original changed while installing its watch',
      );
    }
  }

  Future<void> _verifyOriginal(String path, String id) async {
    if (_sourcePath != path || state.bookId != id) return;
    final revision = _openRevision;
    try {
      await _preparePublication({'id': id, 'path': path});
    } catch (error) {
      if (revision != _openRevision) return;
      Object issue = error;
      try {
        await flush();
      } catch (saveError) {
        issue = '$error\n$saveError';
      }
      if (revision != _openRevision) return;
      _invalidateAppearanceWork();
      _invalidateLayoutVisibility();
      _session = 'closed:${++_generation}';
      _filePoll?.cancel();
      _filePoll = null;
      await _fileWatch?.cancel();
      if (revision != _openRevision) return;
      _fileWatch = null;
      await readerChannel.invokeMethod<void>('close');
      if (revision != _openRevision) return;
      state = state.copy(
        ready: false,
        clearSelection: true,
        error: issue.toString(),
        errorCode: error is WorkspaceException ? error.code : 'missing',
      );
    }
  }

  bool _revealOnLocation = false;
  int? _outlineRevision;
  final _outlineIncoming = <Map<String, dynamic>>[];
  Map<String, int> _outlineIndices = {};

  Future<void> _event(Map<String, dynamic> event) async {
    if (event['session'] != _session) return;
    if ([
          'match',
          'matches',
          'searchStart',
          'searchProgress',
          'searchDone',
          'searchError',
        ].contains(event['type']) &&
        event['queryId'] != _searchRevision) {
      return;
    }
    switch (event['type']) {
      case 'contentFocus':
        if (!validReaderContentFocusEvent(event) ||
            !await _acceptNativeContentFocus()) {
          return;
        }
        event = {...event, 'focusRevision': _focusRevision};
      case 'key':
        if (!await _acceptNativeContentFocus()) return;
      case 'focusChrome':
        if (!await _acceptNativeContentFocus()) return;
        event = {...event, 'focusRevision': _focusRevision};
      case 'ready':
        if (_suspended ||
            state.phase != 'initializing' ||
            state.error != null) {
          return;
        }
        state = state.copy(phase: 'opening');
        _armOpeningWatchdog();
        final labels = _labels;
        final b = book;
        if (b != null) {
          final initialAppearance = await _resolveAppearance(appearance);
          if (event['session'] != _session || _suspended) return;
          final rendererAnnotations = _rendererAnnotations;
          final inline = inlineAnnotations(rendererAnnotations);
          if (!inline && !await _sendAnnotationSnapshot(rendererAnnotations)) {
            return;
          }
          if (event['session'] != _session || _suspended) return;
          await send('open', {
            'format': b.format,
            'title': b.title,
            'generateCover': b.cover == null,
            'labels': {
              'printPage': labels.printPage,
              'page': labels.page,
              'invalidPage': labels.invalidPage,
              'navigationInterrupted': labels.navigationInterrupted,
              'footnote': labels.footnote,
              'loadingBook': labels.loadingBook,
              'regionNote': labels.regionNote,
              'regionInstructions': labels.regionInstructions,
            },
            'anchor': b.anchor,
            'appearance': initialAppearance,
            'chrome': _chrome,
            if (inline) 'annotations': rendererAnnotations,
          });
        }
      case 'opened':
        if (_suspended || state.phase != 'opening' || state.error != null) {
          return;
        }
        _startupTimer?.cancel();
        state = state.copy(
          ready: true,
          phase: 'usable',
          typography: event.containsKey('typography')
              ? TypographyCapabilities.fromJson(event['typography'])
              : state.typography,
        );
        event = {
          ...event,
          'focusRevision': _focusRevision,
          'presentation': _presentation,
        };
        final openedBook = state.bookId!,
            openedRevision = _openRevision,
            openedSession = _session;
        await _consumePendingJump(openedBook, openedRevision);
        if (!ref.mounted ||
            state.bookId != openedBook ||
            _openRevision != openedRevision ||
            _session != openedSession) {
          return;
        }
        await ref
            .read(workspaceControllerProvider.notifier)
            .updateBook(state.bookId!, {
              'read': DateTime.now().millisecondsSinceEpoch,
              'state': book?.state == 'unread' ? 'reading' : book?.state,
            });
      case 'location':
        _bridgeFailure = null;
        if (_suspended || state.error != null) return;
        if (event['anchor'] is Map) {
          state = state.copy(location: event);
          if (_revealOnLocation && state.bookId != null) {
            _revealOnLocation = false;
            ref.read(bookSidebarProvider(state.bookId!).notifier).reveal();
          }
          if (state.bookId != null) _pendingLocations[state.bookId!] = event;
          _saveTimer?.cancel();
          _saveTimer = Timer(
            const Duration(milliseconds: 350),
            () => unawaited(_save().catchError((Object _) {})),
          );
        }
      case 'navigationJump':
        await ref.read(narrationControllerProvider.notifier).stop();
      case 'navigation':
        state = state.copy(navigation: event);
      case 'pageText':
        if ((state.location['anchor'] as Map?)?['page'] == event['page']) {
          state = state.copy(
            location: {
              ...state.location,
              'text': event['text'],
              'noText': event['noText'],
            },
          );
        }
      case 'annotation':
        final a = annotations
            .where(
              (a) =>
                  a.id == event['id'] ||
                  a.anchor['cfi'] == event['cfi'] && event['cfi'] != null,
            )
            .firstOrNull;
        if (a != null) requestSelectionMenu(annotation: a, rect: event['rect']);
      case 'regionSelected':
        if (!regionNotes || book == null || event['anchor'] is! Map) return;
        validateAnchor(event['anchor'], book!.format);
        if (event['anchor']['region'] == null) return;
        _selectionRevision++;
        _selectionIntent = event;
        state = state.copy(selection: event);
        await _dismissSelectionMenu();
        requestSelectionMenu();
      case 'selection':
        final replaced =
            event['anchor'] is Map &&
            (!_sameAnchor(event['anchor'], _selectionIntent?['anchor']) ||
                event['text'] != _selectionIntent?['text']);
        if (replaced) _selectionRevision++;
        if (event['anchor'] is Map) _selectionIntent = event;
        state = state.copy(
          selection: event['anchor'] is Map ? event : null,
          clearSelection: event['anchor'] is! Map,
        );
        if (replaced) {
          if (_panelActive) {
            await dismissReaderControls(restoreFocus: false);
          } else {
            await _dismissSelectionMenu();
          }
        }
        if (event['anchor'] is Map && event['settled'] == true) {
          requestSelectionMenu();
        }
      case 'metadata':
        if (event['tocOffset'] is int) {
          final offset = event['tocOffset'] as int,
              revision = event['outlineRevision'];
          final chunk = (event['toc'] as List? ?? [])
              .map((v) => (v as Map).cast<String, dynamic>())
              .toList();
          if (offset == 0) {
            _outlineIncoming.clear();
            _outlineRevision = revision as int?;
          }
          if (revision != _outlineRevision ||
              offset != _outlineIncoming.length ||
              offset + chunk.length > 100000) {
            return;
          }
          _outlineIncoming.addAll(chunk);
          if (event['tocComplete'] != true) return;
          event = {
            ...event,
            'toc': List<Map<String, dynamic>>.of(_outlineIncoming),
          };
          _outlineIncoming.clear();
        }
        if (event['tocUpdates'] is List) {
          if (event['outlineRevision'] != _outlineRevision) return;
          final updated = List<Map<String, dynamic>>.of(state.toc);
          for (final patch in event['tocUpdates']) {
            if (patch is! Map) continue;
            final index = _outlineIndices[patch['id']];
            if (index != null) {
              updated[index] = {
                ...updated[index],
                ...patch.cast<String, dynamic>(),
              };
            }
          }
          event = {...event, 'toc': updated};
        }

        final current = book;
        if (current != null && current.format == 'pdf') {
          final changes = <String, dynamic>{'engineValidated': true};
          if (current.data['metadataEdited'] != true) {
            for (final key in ['title', 'author', 'language']) {
              final value = event[key];
              if (value is String && value.trim().isNotEmpty) {
                changes[key] = value.trim();
              }
            }
          }
          if (current.cover == null && event['cover'] is String) {
            changes['coverEdited'] = false;
            changes['cover'] = await ref
                .read(readingDataStoreProvider)
                .call('coverData', event['cover']);
          }
          await ref
              .read(workspaceControllerProvider.notifier)
              .updateBook(current.id, changes);
        }
        if (event['session'] != _session) return;
        final metadata = <String, dynamic>{
          if (event.containsKey('toc') &&
              (event['tocUpdates'] == null || event['tocResolved'] == true))
            'outline': event['toc'],
          if (event.containsKey('pages')) 'pages': event['pages'],
          if (event.containsKey('labels')) 'pageLabels': event['labels'],
        };
        if (current != null && metadata.isNotEmpty) {
          await ref
              .read(workspaceControllerProvider.notifier)
              .updateBook(current.id, metadata);
        }
        if (event['session'] != _session) return;
        final records = (event['toc'] as List? ?? state.toc)
            .map((x) => (x as Map).cast<String, dynamic>())
            .toList();
        final outline = event.containsKey('toc')
            ? PublicationOutline.fromRecords(
                records,
                pdf: current?.format == 'pdf',
              )
            : state.outline;
        if (event.containsKey('toc')) {
          _outlineIndices = {
            for (var i = 0; i < records.length; i++)
              if (records[i]['id'] is String) records[i]['id'] as String: i,
          };
        }
        state = state.copy(
          toc: records,
          outline: outline,
          outlineStatus: event['outlineFailed'] == true
              ? 'error'
              : event.containsKey('toc')
              ? 'ready'
              : state.outlineStatus,
          fixed: event['fixed'] as bool? ?? state.fixed,
          typography: event.containsKey('typography')
              ? TypographyCapabilities.fromJson(event['typography'])
              : state.typography,
          pages: event['pages'] as int? ?? state.pages,
          labels: (event['labels'] as List?)?.cast<String>() ?? state.labels,
        );
        if (state.bookId != null) {
          ref
              .read(bookSidebarProvider(state.bookId!).notifier)
              .publication(
                outline: outline,
                status: state.outlineStatus,
                pages: state.pages,
                labels: state.labels,
              );
        }
      case 'matches':
        state = state.copy(
          matches: [
            ...state.matches,
            ...(event['items'] as List).map(
              (m) => (m as Map).cast<String, dynamic>(),
            ),
          ],
        );
      case 'match':
        state = state.copy(matches: [...state.matches, event]);
      case 'searchStart':
        state = state.copy(
          searching: true,
          matches: [],
          searchProgress: 0,
          searchStatus: 'searching',
          searchTotal: 0,
          searchOffset: event['offset'] as int? ?? state.searchOffset,
          searchLimit: event['limit'] as int? ?? state.searchLimit,
        );
      case 'searchProgress':
        state = state.copy(
          searchProgress: (event['progress'] as num).toDouble(),
        );
      case 'searchDone':
        state = state.copy(
          searching: false,
          searchProgress: 1,
          searchStatus: 'done',
          searchTotal: event['total'] as int? ?? state.matches.length,
        );
        _finishSearchWaiters(true);
      case 'searchError':
        state = state.copy(searching: false, searchStatus: 'error');
        _finishSearchWaiters(false);
      case 'thumbnailError':
        final page = event['page'];
        if (event['request'] != _thumbnailRevision ||
            !_thumbnailWindow.contains(page)) {
          return;
        }

        state = state.copy(
          thumbnailErrors: {
            ...state.thumbnailErrors,
            page as int: _labels.thumbnailFailed,
          },
          thumbnailPending: {...state.thumbnailPending}..remove(page),
        );
      case 'navigationError':
        _revealOnLocation = false;
        events.add({'type': 'feedback', 'message': event['message']});
      case 'thumbnail':
        final page = event['page'];
        if (event['request'] != _thumbnailRevision ||
            !_thumbnailWindow.contains(page)) {
          return;
        }

        final preview = PagePreview.fromEvent(event);
        if (preview == null) {
          state = state.copy(
            thumbnailErrors: {
              ...state.thumbnailErrors,
              page as int: _labels.thumbnailFailed,
            },
            thumbnailPending: {...state.thumbnailPending}..remove(page),
          );
          return;
        }
        final next = {...state.thumbnails, page as int: preview};
        while (next.length > 32 ||
            next.values.fold<int>(0, (n, p) => n + p.data.length) >
                8 * 1024 * 1024) {
          // Keep the visible/nearby window resident. Evicting one of its older
          // cached images would leave a blank row without a new window request.
          // Twelve bounded previews fit below the byte cap.
          final victim = next.keys.firstWhere(
            (p) => !_thumbnailWindow.contains(p),
            orElse: () => next.keys.first,
          );
          next.remove(victim);
        }
        state = state.copy(
          thumbnails: next,
          thumbnailPending: {...state.thumbnailPending}..remove(page),
        );
      case 'bridgeError':
        final error = StateError(
          event['message']?.toString() ?? 'Reader bridge delivery failed',
        );
        _bridgeFailure = error;
        if (_flushing?.isCompleted == false) _flushing!.completeError(error);
        state = state.copy(warning: error.toString());
      case 'flushed':
        if (event['request'] == _flushRequest &&
            _flushing?.isCompleted == false) {
          if (_bridgeFailure case final Object error) {
            _flushing!.completeError(error);
          } else {
            _flushing!.complete();
          }
        }
      case 'diagnostic':
        debugPrint(
          'BusyBooks reader diagnostic [${state.bookId}/$_session/${event['stage']}]: ${event['message']}',
        );
      case 'error':
        _finishSearchWaiters(false);
        if (event['cacheFailure'] == true &&
            book?.format != 'pdf' &&
            !_cacheRecoveryAttempted) {
          _cacheRecoveryAttempted = true;
          _startupTimer?.cancel();
          state = state.copy(ready: false, phase: 'recovering');
          final session = _session,
              id = state.bookId!,
              revision = _openRevision;
          // Run after this event settles; close drains the inbound event tail.
          Timer(Duration.zero, () async {
            if (_session != session || _openRevision != revision) return;
            try {
              await close();
              await _open(id, force: true, cacheRecovery: true);
            } catch (error) {
              if (state.bookId == id) {
                state = state.copy(error: error.toString());
              }
            }
          });
          return;
        }
        _invalidateAppearanceWork();
        _startupTimer?.cancel();
        debugPrint('BusyBooks reader error: ${event['message']}');
        state = state.copy(ready: false, error: event['message']?.toString());
    }
    events.add(event);
  }

  Future<void> send(String action, [Map<String, dynamic> args = const {}]) =>
      _send(action, args);

  Future<void> focusPublication({required bool Function() isCurrent}) {
    final revision = _focusRevision, presentation = _presentation;
    final id = state.bookId;
    return _send(
      'focus',
      const {},
      isCurrent: () =>
          revision == _focusRevision &&
          presentation == _presentation &&
          state.bookId == id &&
          !_panelActive &&
          _appearanceMenuOwner == null &&
          _selectionMenuOwner == null &&
          ref.read(bookPresentationProvider).lastPane == BookPane.reading &&
          isCurrent(),
    );
  }

  Future<void> _send(
    String action,
    Map<String, dynamic> args, {
    bool Function()? isCurrent,
    Future<bool> Function()? validateNavigation,
  }) async {
    final session = _session;
    bool current() =>
        ref.mounted && session == _session && (isCurrent?.call() ?? true);
    if ([
          'goto',
          'back',
          'forward',
          'next',
          'previous',
          'focus',
        ].contains(action) &&
        !interactive) {
      return;
    }
    if (action == 'search' && !canSearch) return;
    if (['goto', 'back', 'forward', 'next', 'previous'].contains(action) &&
        ref.read(narrationControllerProvider).active) {
      await ref.read(narrationControllerProvider.notifier).stop();
    }
    if (!current()) return;
    if (action == 'focus') {
      if (!_routeVisible ||
          !state.ready ||
          (_appearanceMenuOwner != null || _selectionMenuOwner != null)) {
        return;
      }
      await readerChannel.invokeMethod<void>('focus', {'session': session});
      if (!current()) return;
    }
    final navigation = [
      'goto',
      'back',
      'forward',
      'next',
      'previous',
    ].contains(action);
    final frames = readerBridgeFrames(
      {'action': action, ...args, 'session': session},
      ++_bridgeRevision,
      command: true,
    ).toList();
    // Ordinary commands retain immediate submission. Only a multi-frame
    // transfer owns the channel until all of its frames have been submitted.
    if (frames.length == 1 && _commandTail == null) {
      if (validateNavigation != null &&
          (!await validateNavigation() || !current())) {
        return;
      }
      if (!current()) return;
      if (navigation) _revealOnLocation = true;
      await readerChannel.invokeMethod<void>(
        'dispatch',
        jsonEncode(frames.single),
      );
      return;
    }
    Future<void> deliver() async {
      if (!current()) return;
      if (validateNavigation != null &&
          (!await validateNavigation() || !current())) {
        return;
      }
      for (final frame in frames) {
        if (!current()) return;
        if (navigation) _revealOnLocation = true;
        await readerChannel.invokeMethod<void>('dispatch', jsonEncode(frame));
      }
    }

    final previous = _commandTail;
    final operation = previous == null
        ? deliver()
        : previous.catchError((Object _) {}).then((_) => deliver());
    _commandTail = operation;
    void finished() {
      if (identical(_commandTail, operation)) _commandTail = null;
    }

    unawaited(
      operation.then(
        (_) => finished(),
        onError: (Object _, StackTrace _) => finished(),
      ),
    );
    await operation;
  }

  final _modalOwners = <Object>{};
  Future<void>? _modalPreparation;
  Future<void>? _modalRelease;
  ui.Image? _modalImage;
  bool _modalFramePainted = false;
  (String, int)? _modalReturnFocus;

  Future<AsyncCallback> coverForModal() async {
    while (_modalRelease != null) {
      await _modalRelease;
    }
    final owner = Object();
    _modalOwners.add(owner);
    try {
      await (_modalPreparation ??= _prepareModalFrame());
    } catch (_) {
      await _releaseModal(owner);
      rethrow;
    }
    var released = false;
    return () async {
      if (released) return;
      released = true;
      await _releaseModal(owner);
    };
  }

  Future<void> _releaseModal(Object owner) async {
    _modalOwners.remove(owner);
    if (_modalOwners.isNotEmpty || !ref.mounted) return;
    _modalPreparation = null;
    final operation = _restoreModalSurface();
    _modalRelease = operation;
    try {
      await operation;
    } finally {
      if (identical(_modalRelease, operation)) _modalRelease = null;
    }
  }

  Future<void> _restoreModalSurface() async {
    _modalFramePainted = false;
    await _applyVisibility();
    if (!ref.mounted) return;
    final image = _modalImage;
    _modalImage = null;
    state = state.copy(clearModalFrame: true);
    final restore = _modalReturnFocus;
    _modalReturnFocus = null;
    await WidgetsBinding.instance.endOfFrame;
    image?.dispose();
    if (ref.mounted &&
        restore != null &&
        restore.$1 == _session &&
        restore.$2 == _focusRevision &&
        interactive) {
      await focusPublication(
        isCurrent: () =>
            ref.mounted &&
            restore.$1 == _session &&
            restore.$2 == _focusRevision &&
            interactive,
      );
    }
  }

  Future<void> _prepareModalFrame() async {
    final session = _session, id = state.bookId;
    if (state.ready && state.surfaceVisible && id != null) {
      final focused = await nativeContentHasFocus();
      final bytes = await readerChannel.invokeMethod<Uint8List>('capture');
      if (!ref.mounted || session != _session || id != state.bookId) return;
      if (bytes == null) {
        throw PlatformException(
          code: 'reader-capture',
          message: 'The reader could not be covered.',
        );
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!ref.mounted || session != _session || id != state.bookId) {
        frame.image.dispose();
        return;
      }
      _modalImage = frame.image;
      state = state.copy(modalFrame: frame.image);
      await focusChrome();
      if (focused == true) _modalReturnFocus = (session, _focusRevision);
      // The primary Flutter view must paint the exact captured pixels before
      // the native surface is covered. This is a frame acknowledgement, not a delay.
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!ref.mounted) return;
    _modalFramePainted = true;
    await _applyVisibility();
  }

  // Route visibility survives a native close/open on a retained reader route.
  // Page navigation owns this intent; modal coverage has separate leases.
  Future<void> show(bool value) => _showRoute(value);

  Future<void> _showRoute(bool value) async {
    _routeVisible = value;
    if (!value) {
      _panelRequest++;
      if (_panelActive) {
        await _dismissReaderControls(restoreFocus: false);
      } else {
        await _dismissSelectionMenu();
        await _dismissAppearanceMenu();
        _invalidateLookup();
      }
      _focusRevision++;
      _appearanceNeedsReconcile |=
          _appearanceIntent != null || _appearanceResults.isNotEmpty;
      _invalidateAppearanceWork();
      if (state.ready) await send('cancelAppearance');
    }
    if (value && book?.format != 'pdf') {
      final session = _session, id = state.bookId;
      bool current() =>
          ref.mounted &&
          session == _session &&
          id == state.bookId &&
          _routeVisible &&
          !_suspended &&
          state.ready;
      if (!await _reconcileVisibleAppearance(current)) return;
    }
    if (!value) requestThumbnailWindow(const []);
    if (value) requestViewportLayout();
    return _applyVisibility();
  }

  int _visibilityRevision = 0;
  bool get _surfaceVisible =>
      !(_modalOwners.isNotEmpty && _modalFramePainted) &&
      _routeVisible &&
      _workspaceVisible &&
      _hasViewport &&
      !_suspended &&
      state.bookId != null &&
      state.error == null;
  final _layoutVisibilityResults =
      <int, ({int revision, bool visible, Completer<void> result})>{};
  int _layoutVisibilityRequest = 0;
  String? _pausedPdfSession;

  void _invalidateLayoutVisibility() {
    _visibilityRevision++;
    _pausedPdfSession = null;
    for (final pending in _layoutVisibilityResults.values) {
      if (!pending.result.isCompleted) pending.result.complete();
    }
    _layoutVisibilityResults.clear();
  }

  Future<void> _setPdfLayoutVisible(
    bool visible,
    int revision,
    bool Function() current,
  ) async {
    if (book?.format != 'pdf' || !state.ready || state.error != null) return;
    final session = _session;
    final request = ++_layoutVisibilityRequest, result = Completer<void>();
    _layoutVisibilityResults[request] = (
      revision: revision,
      visible: visible,
      result: result,
    );
    try {
      Future<void> deliver() async {
        await _send('layoutVisibility', {
          'visible': visible,
          'revision': revision,
          'request': request,
        }, isCurrent: current);
        if (!current() && !result.isCompleted) result.complete();
      }

      await Future.wait<void>([
        result.future.timeout(const Duration(seconds: 5)),
        deliver(),
      ], eagerError: true);
      if (current()) _pausedPdfSession = visible ? null : session;
    } catch (_) {
      if (current()) rethrow;
    } finally {
      _layoutVisibilityResults.remove(request);
    }
  }

  bool get _canRenderAppearance =>
      state.ready &&
      !_suspended &&
      _routeVisible &&
      (book?.format != 'pdf' ||
          (_surfaceVisible &&
              state.surfaceVisible &&
              _pausedPdfSession != _session));

  Future<bool> _reconcileVisibleAppearance(bool Function() current) async {
    if (!_appearanceNeedsReconcile || !state.ready || _suspended) return true;
    final session = _session, id = state.bookId;
    await _appearanceTail;
    if (!current() || !state.ready || _suspended) return false;
    final revision = _appearanceRevision;
    try {
      await _renderAppearance(appearance, revision, session);
    } catch (error) {
      if (current() && revision == _appearanceRevision) {
        state = state.copy(warning: _labels.fontApplyFailed);
        events.add({'type': 'feedback', 'message': _labels.fontApplyFailed});
      }
      return false;
    }
    if (current() && id == state.bookId && revision == _appearanceRevision) {
      _appearanceNeedsReconcile = false;
    }
    return current();
  }

  Future<void> _applyVisibility() async {
    final revision = ++_visibilityRevision, session = _session;
    final visible = _surfaceVisible;
    bool current() =>
        ref.mounted &&
        revision == _visibilityRevision &&
        session == _session &&
        visible == _surfaceVisible;
    if (state.bookId == null) return;
    if (!visible) {
      // PDF display tasks use the engine's normal animation-frame scheduler.
      // Drain while native frames are available, then prevent automatic layout
      // from restarting in a hidden retained Split pane.
      await _setPdfLayoutVisible(false, revision, current);
      if (!current()) return;
    }
    await readerChannel.invokeMethod<void>('visible', visible);
    if (!current()) return;
    if (state.surfaceVisible != visible) {
      state = state.copy(surfaceVisible: visible);
    }
    if (visible) {
      // The physical surface must produce frames before deferred PDF layout or
      // renderer-dependent appearance reconciliation can resume.
      await _setPdfLayoutVisible(true, revision, current);
      if (!current()) return;
      if (book?.format == 'pdf') await _reconcileVisibleAppearance(current);
    }
    if (current() && interactive && state.bookId != null) {
      await _consumePendingJump(state.bookId!, _openRevision);
    }
  }

  Future<void> reloadOutline({String? bookId}) async {
    if ((bookId != null && bookId != state.bookId) || !state.ready) return;
    final session = _session;
    state = state.copy(outlineStatus: 'loading');
    try {
      await send('outline');
    } catch (error) {
      if (session == _session) state = state.copy(outlineStatus: 'error');
    }
  }

  Future<void> focusChrome() async {
    _focusRevision++;
    if (state.bookId == null ||
        _panelActive ||
        (_appearanceMenuOwner != null || _selectionMenuOwner != null)) {
      return;
    }
    await readerChannel.invokeMethod<void>('focusChrome', {
      'session': _session,
    });
  }

  Future<bool> _dismissForSidebar() async {
    _focusRevision++;
    final session = _session;
    try {
      await dismissReaderControls(restoreFocus: false);
      if (session != _session) return false;
      await focusChrome();
      return session == _session;
    } catch (error) {
      if (session == _session) {
        state = state.copy(warning: error.toString());
        events.add({'type': 'feedback', 'message': error.toString()});
      }
      return false;
    }
  }

  Future<bool> prepareChromeChange() => _dismissForSidebar();

  int _focusRevision = 0;
  int get focusRevision => _focusRevision;

  bool ownsContentFocus(Map<String, dynamic> event) =>
      ref.mounted &&
      event['session'] == _session &&
      event['focusRevision'] == _focusRevision &&
      interactive &&
      !_panelActive &&
      _appearanceMenuOwner == null &&
      _selectionMenuOwner == null;

  /// Null means ownership could not be established; it is never permission to
  /// reclaim focus. Both native hosts validate the captured renderer session.
  Future<bool?> nativeContentHasFocus() async {
    final session = _session;
    try {
      final focused = await readerChannel.invokeMethod<bool>('hasFocus', {
        'session': session,
      });
      return ref.mounted && session == _session ? focused : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> _acceptNativeContentFocus() async {
    if (_panelActive && interactive) {
      final session = _session, revision = _focusRevision;
      final focused = await nativeContentHasFocus();
      if (focused == true &&
          ref.mounted &&
          session == _session &&
          revision == _focusRevision) {
        await dismissReaderControls(restoreFocus: false);
      }
    }

    if (!interactive ||
        _panelActive ||
        _appearanceMenuOwner != null ||
        _selectionMenuOwner != null ||
        state.bookId == null) {
      return false;
    }
    final session = _session, revision = _focusRevision, id = state.bookId!;
    bool current() =>
        ref.mounted &&
        session == _session &&
        id == state.bookId &&
        revision == _focusRevision &&
        interactive &&
        !_panelActive &&
        _appearanceMenuOwner == null &&
        _selectionMenuOwner == null;
    final focused = await nativeContentHasFocus();
    if (focused != true || !current()) return false;
    ref.read(bookPresentationProvider.notifier).focusPane(id, BookPane.reading);
    return true;
  }

  Future<void> navigateFromSidebar(
    Map<String, dynamic> anchor, {
    required String bookId,
    Future<bool> Function()? validateNavigation,
  }) async {
    if (state.bookId != bookId || !interactive) return;
    final session = _session;
    if (!await _dismissForSidebar() || !ref.mounted) return;
    if (ref.read(narrationControllerProvider).active) {
      await ref.read(narrationControllerProvider.notifier).stop();
    }
    if (session != _session || state.bookId != bookId) return;
    if (validateNavigation != null && !await validateNavigation()) return;
    if (!ref.mounted ||
        session != _session ||
        state.bookId != bookId ||
        !interactive) {
      return;
    }
    if (!state.ready) {
      events.add({
        'type': 'feedback',
        'message': state.error == null
            ? _labels.loadingBook
            : _labels.bookError,
      });
      return;
    }
    await _send(
      'goto',
      {'anchor': anchor},
      isCurrent: () =>
          ref.mounted &&
          session == _session &&
          state.bookId == bookId &&
          interactive,
      validateNavigation: validateNavigation,
    );
  }

  void search(String query, {int offset = 0, int limit = 200}) {
    if (regionNotes || !canSearch) return;
    _finishSearchWaiters(false);
    final revision = ++_searchRevision;
    offset = max(0, offset);
    limit = limit.clamp(1, 500);
    if (state.ready) unawaited(send('cancelSearch', {'queryId': revision}));
    state = state.copy(
      query: query,
      matches: [],
      currentMatch: -1,
      searchProgress: 0,
      searchTotal: 0,
      searchOffset: offset,
      searchLimit: limit,
      searching: state.ready && query.isNotEmpty,
      searchStatus: !state.ready || query.isEmpty ? 'idle' : 'searching',
    );
    if (!state.ready || query.isEmpty) return;
    unawaited(
      send('search', {
        'query': query,
        'queryId': revision,
        'offset': offset,
        'limit': limit,
      }),
    );
  }

  /// Resolves only for this query revision and renderer session. A cancelled
  /// search must never be mistaken for a completed empty result set.
  Future<bool> waitForSearch() async {
    final session = _session, revision = _searchRevision;
    bool current() =>
        ref.mounted && session == _session && revision == _searchRevision;
    if (!current() || state.searchStatus != 'searching') {
      return current() && state.searchStatus == 'done';
    }
    final waiter = Completer<bool>();
    _searchWaiters.add(waiter);
    try {
      if (!await waiter.future.timeout(const Duration(seconds: 60))) {
        return false;
      }
    } on TimeoutException {
      return false;
    } finally {
      _searchWaiters.remove(waiter);
    }
    return current() && state.searchStatus == 'done';
  }

  /// Navigation can request an occurrence beyond the displayed window. The
  /// bounded rescan counts the publication again without retaining every CFI.
  Future<bool> loadSearchWindow(int absoluteIndex) async {
    if (!canSearch || absoluteIndex < 0 || state.query.isEmpty) return false;
    if (absoluteIndex >= state.searchOffset &&
        absoluteIndex < state.searchOffset + state.matches.length) {
      return true;
    }
    final query = state.query;
    final limit = state.searchLimit;
    search(query, offset: absoluteIndex ~/ limit * limit, limit: limit);
    return await waitForSearch() &&
        state.query == query &&
        absoluteIndex < state.searchOffset + state.matches.length;
  }

  Future<void> cancelSearch() async {
    if (!ref.mounted) return;
    _finishSearchWaiters(false);
    final session = _session, revision = ++_searchRevision;
    if (state.ready) await send('cancelSearch', {'queryId': revision});
    if (!ref.mounted || session != _session || revision != _searchRevision) {
      return;
    }
    state = state.copy(
      searching: false,
      searchStatus: state.query.isEmpty ? 'idle' : 'cancelled',
    );
  }

  Future<void> selectMatch(int index) async {
    if (!interactive || index < 0 || index >= state.matches.length) return;
    final session = _session, revision = _searchRevision;
    final match = state.matches[index];
    if (!await _dismissForSidebar() || !ref.mounted) return;
    if (ref.read(narrationControllerProvider).active) {
      await ref.read(narrationControllerProvider.notifier).stop();
    }
    if (!ref.mounted ||
        !interactive ||
        session != _session ||
        revision != _searchRevision ||
        index >= state.matches.length ||
        !identical(match, state.matches[index])) {
      return;
    }
    state = state.copy(currentMatch: index);
    await send('goto', {'anchor': match['anchor']});
  }

  int _thumbnailRevision = 0;
  Set<int> _thumbnailWindow = {};
  void requestThumbnailWindow(Iterable<int> pages) {
    final next = pages.where((p) => p >= 0 && p < state.pages).take(12).toSet();
    if (next.isNotEmpty && (!interactive || !pageNavigation)) return;
    if (next.length == _thumbnailWindow.length &&
        next.containsAll(_thumbnailWindow)) {
      return;
    }
    _thumbnailWindow = next;
    final revision = ++_thumbnailRevision;

    final needed = next
        .where(
          (p) =>
              !state.thumbnails.containsKey(p) &&
              !state.thumbnailErrors.containsKey(p),
        )
        .toSet();

    state = state.copy(thumbnailPending: needed);
    if (!state.ready || !pageNavigation || next.isNotEmpty && !interactive) {
      return;
    }
    unawaited(
      send('thumbnailWindow', {
        'pages': needed.toList(),
        'request': revision,
      }).catchError((Object error) {
        if (revision != _thumbnailRevision) return;

        state = state.copy(
          thumbnailPending: {},
          thumbnailErrors: {
            ...state.thumbnailErrors,
            for (final p in needed) p: _labels.thumbnailFailed,
          },
        );
      }),
    );
  }

  void retryThumbnail(int page, {String? bookId}) {
    if (bookId != null && bookId != state.bookId) return;
    if (!_thumbnailWindow.contains(page) ||
        state.thumbnailPending.contains(page)) {
      return;
    }
    final session = _session, revision = _thumbnailRevision;
    state = state.copy(
      thumbnails: {...state.thumbnails}..remove(page),
      thumbnailErrors: {...state.thumbnailErrors}..remove(page),
      thumbnailPending: {...state.thumbnailPending, page},
    );
    unawaited(
      send('thumbnail', {
        'page': page,
        'request': _thumbnailRevision,
      }).catchError((Object error) {
        if (session != _session ||
            revision != _thumbnailRevision ||
            !_thumbnailWindow.contains(page)) {
          return;
        }
        state = state.copy(
          thumbnailErrors: {
            ...state.thumbnailErrors,
            page: _labels.thumbnailFailed,
          },
          thumbnailPending: {...state.thumbnailPending}..remove(page),
        );
      }),
    );
  }

  Future<void> configureChrome(Map<String, dynamic> value) async {
    final session = _session;
    if (jsonEncode(value) == jsonEncode(_chrome)) return;
    _chrome = value;
    await readerChannel.invokeMethod<void>('surface', value);
    if (state.ready) {
      await send('chrome', {'value': value});
      await _appearanceTail;
      if (session != _session || !state.ready) return;
      if (!_canRenderAppearance) {
        _appearanceNeedsReconcile = true;
        return;
      }
      final effective = await _resolveAppearance(
        appearance,
        capabilities: typographyCapabilities,
      );
      if (session != _session || !state.ready) return;
      if (!_canRenderAppearance) {
        _appearanceNeedsReconcile = true;
        return;
      }
      await send('appearance', {'value': effective});
    }
  }

  Future<void> dismissReaderControls({bool restoreFocus = true}) {
    _panelRequest++;
    return _dismissReaderControls(restoreFocus: restoreFocus);
  }

  Future<void> _dismissReaderControls({bool restoreFocus = true}) async {
    final panel = state.panel;
    final session = _session, presentation = _presentation;
    final focusRevision = _focusRevision;
    await _dismissSelectionMenu();
    await _dismissAppearanceMenu();
    if (!ref.mounted || session != _session || presentation != _presentation) {
      return;
    }
    _presentation++;
    _invalidateLookup();
    if (panel != null) state = state.copy(clearPanel: true);
    if (restoreFocus && panel != null) {
      final dismissed = _presentation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ref.mounted ||
            session != _session ||
            dismissed != _presentation ||
            focusRevision != _focusRevision ||
            !_routeVisible ||
            _suspended) {
          return;
        }
        _restoreLookupFocus(session, dismissed);
      });
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  Map<String, dynamic> _publicationFocusEvent() => {
    'type': 'focusBook',
    'session': _session,
    'presentation': _presentation,
    'focusRevision': _focusRevision,
  };

  void _restoreLookupFocus(String session, int presentation) => events.add({
    ..._publicationFocusEvent(),
    'restorePublicationFocus': true,
    'session': session,
    'presentation': presentation,
  });

  bool ownsFocusRequest(Map<String, dynamic> event) =>
      ref.mounted &&
      _routeVisible &&
      !_suspended &&
      state.ready &&
      !_panelActive &&
      _appearanceMenuOwner == null &&
      _selectionMenuOwner == null &&
      event['session'] == _session &&
      event['focusRevision'] == _focusRevision &&
      event['presentation'] == _presentation;

  void requestSelectionMenu({ReadingAnnotation? annotation, Object? rect}) {
    if (!interactive || state.bookId == null) return;
    if (annotation != null) _selectionRevision++;
    final passage = annotation == null
        ? state.selection
        : <String, dynamic>{
            'anchor': annotation.anchor,
            'text': annotation.text,
            'reference': annotation.reference,
          };
    if (passage?['anchor'] is! Map) return;
    _selectionIntent = passage;
    validateAnchor(passage!['anchor'], book!.format);
    final snapshot = Map<String, dynamic>.unmodifiable(
      (jsonDecode(jsonEncode(passage)) as Map).cast<String, dynamic>(),
    );
    final notebook = ref.read(notebookControllerProvider);
    final pending = notebook.sources.values
        .where(
          (a) =>
              a.bookId == state.bookId &&
              notebook.drafts.containsKey(a.id) &&
              _sameAnchor(a.anchor, snapshot['anchor']),
        )
        .firstOrNull;
    final target = ReaderSelectionTarget(
      state.bookId!,
      _session,
      _presentation,
      snapshot['text'] as String? ?? '',
      _selectionRect(rect ?? snapshot['rect']),
      passage: snapshot,
      selectionRevision: _selectionRevision,
      annotationId: annotation?.id ?? pending?.id,
    );
    if (_selectionMenuOwner?.target.selectionRevision == _selectionRevision) {
      return;
    }
    events.add({'type': 'selectionMenu', 'target': target});
  }

  Future<void> _dismissSelectionMenu() async {
    final dismiss = _selectionMenuDismiss;
    _selectionMenuOwner = null;
    _selectionMenuDismiss = null;
    await dismiss?.call();
  }

  ReadingAnnotation? selectionAnnotation(ReaderSelectionTarget target) =>
      target.annotationId == null
      ? null
      : ref
            .read(notebookControllerProvider)
            .findAnnotation(target.bookId, target.annotationId!, annotations);

  Future<ReaderSelectionMenuOwner?> prepareSelectionMenu(
    ReaderSelectionTarget target, {
    required Future<void> Function() dismiss,
  }) async {
    if (!_ownsSelection(target) || !interactive) return null;
    await dismissReaderControls(restoreFocus: false);
    while (_viewportSettled != null) {
      await _viewportSettled!.future;
    }
    if (!ref.mounted ||
        !interactive ||
        target.bookId != state.bookId ||
        target.session != _session ||
        target.selectionRevision != _selectionRevision ||
        target.presentation + 1 != _presentation) {
      return null;
    }
    await focusChrome();
    if (!ref.mounted ||
        !interactive ||
        target.bookId != state.bookId ||
        target.session != _session ||
        target.selectionRevision != _selectionRevision ||
        target.presentation + 1 != _presentation) {
      return null;
    }
    final ownedTarget = ReaderSelectionTarget(
      target.bookId,
      target.session,
      _presentation,
      target.text,
      target.rect,
      passage: target.passage,
      selectionRevision: target.selectionRevision,
      annotationId: target.annotationId,
    );
    final owner = ReaderSelectionMenuOwner._(ownedTarget, _focusRevision);
    _selectionMenuOwner = owner;
    _selectionMenuDismiss = dismiss;
    return owner;
  }

  bool ownsSelectionMenu(ReaderSelectionMenuOwner owner) =>
      ref.mounted &&
      identical(owner, _selectionMenuOwner) &&
      owner.target.bookId == state.bookId &&
      owner.target.session == _session &&
      owner.target.presentation == _presentation &&
      owner.target.selectionRevision == _selectionRevision &&
      (owner.target.annotationId == null ||
          selectionAnnotation(owner.target) != null) &&
      interactive;

  void finishSelectionMenu(
    ReaderSelectionMenuOwner owner, {
    bool restoreFocus = false,
  }) {
    if (!identical(owner, _selectionMenuOwner)) return;
    final current = ownsSelectionMenu(owner);
    _selectionMenuOwner = null;
    _selectionMenuDismiss = null;
    if (restoreFocus && current) _restoreSelectionFocus(owner);
  }

  void _restoreSelectionFocus(ReaderSelectionMenuOwner owner) {
    if (ref.mounted &&
        _ownsSelection(owner.target) &&
        owner._focusRevision == _focusRevision &&
        ref.read(bookPresentationProvider).lastPane == BookPane.reading) {
      _restoreLookupFocus(owner.target.session, owner.target.presentation);
    }
  }

  Future<void> selectionMenuAction(
    ReaderSelectionMenuOwner owner,
    ReaderSelectionAction action, {
    String? color,
  }) {
    if (!ownsSelectionMenu(owner)) return Future.value();
    finishSelectionMenu(owner);
    final operation = _eventTail.then(
      (_) => _selectionMenuAction(owner, action, color: color),
    );
    _eventTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _selectionMenuAction(
    ReaderSelectionMenuOwner owner,
    ReaderSelectionAction action, {
    String? color,
  }) async {
    final target = owner.target;
    if (!_ownsSelection(target)) return;
    final passage = target.passage!;
    final existing = selectionAnnotation(target);
    if (target.annotationId != null && existing == null) return;
    switch (action) {
      case ReaderSelectionAction.highlight:
        if (color != null && !annotationColors.contains(color)) {
          throw ArgumentError.value(color, 'color');
        }
        color ??= existing?.color ?? highlightColor;
        final notes = ref.read(notebookControllerProvider.notifier);
        final workspace = ref.read(workspaceControllerProvider.notifier);
        if (existing != null) {
          await notes.save(existing.id);
          await workspace.updateAnnotation(existing.id, {
            'color': color,
          }, bookId: existing.bookId);
        } else {
          final time = DateTime.now().microsecondsSinceEpoch;
          final a = ReadingAnnotation({
            'id': 'annotation-$time',
            'kind': 'annotation',
            'bookId': target.bookId,
            'annotationKind': passage['anchor']['region'] != null
                ? 'region'
                : 'highlight',
            'anchor': passage['anchor'],
            'text': target.text,
            'reference': passage['reference'] ?? '',
            'note': '',
            'color': color,
            'created': time,
          });
          notes.create(a, '');
          await notes.save(a.id);
        }
        await ref.read(appSettingsControllerProvider.notifier).update({
          'highlightColor': color,
        });
      case ReaderSelectionAction.copy:
        await Clipboard.setData(ClipboardData(text: target.text));
      case ReaderSelectionAction.search:
        await searchSelection(selection: target);
      case ReaderSelectionAction.lookUp:
        final lookup = await prepareLookup(selection: target);
        if (lookup != null) events.add({'type': 'lookup', 'target': lookup});
      case ReaderSelectionAction.readAloud:
        await ref
            .read(narrationControllerProvider.notifier)
            .start(passage: passage);
      case ReaderSelectionAction.addNote:
        await _editSelectionNote(target);
    }
    if ({
      ReaderSelectionAction.highlight,
      ReaderSelectionAction.copy,
      ReaderSelectionAction.readAloud,
    }.contains(action)) {
      _restoreSelectionFocus(owner);
    }
  }

  Rect? Function()? appearanceAnchor;
  ReaderAppearanceMenuOwner? _appearanceMenuOwner;
  Future<void> Function()? _appearanceMenuDismiss;

  Future<void> _dismissAppearanceMenu() async {
    final dismiss = _appearanceMenuDismiss;
    _appearanceMenuOwner = null;
    _appearanceMenuDismiss = null;
    await dismiss?.call();
  }

  /// Retires the previous reader control and waits for its measured viewport
  /// before granting a menu ownership of the current session/presentation.
  Future<ReaderAppearanceMenuOwner?> prepareAppearanceMenu({
    required Future<void> Function() dismiss,
  }) async {
    if (!interactive) return null;
    final bookId = state.bookId!, session = _session, previous = _presentation;
    await dismissReaderControls(restoreFocus: false);
    while (_viewportSettled != null) {
      await _viewportSettled!.future;
    }
    if (!ref.mounted ||
        !interactive ||
        bookId != state.bookId ||
        session != _session ||
        _presentation != previous + 1) {
      return null;
    }
    final owner = ReaderAppearanceMenuOwner._(bookId, session, _presentation);
    _appearanceMenuOwner = owner;
    _appearanceMenuDismiss = dismiss;
    return owner;
  }

  bool ownsAppearanceMenu(ReaderAppearanceMenuOwner owner) =>
      ref.mounted &&
      identical(owner, _appearanceMenuOwner) &&
      owner.bookId == state.bookId &&
      owner.session == _session &&
      owner.presentation == _presentation &&
      interactive;

  void finishAppearanceMenu(ReaderAppearanceMenuOwner owner) {
    if (!identical(owner, _appearanceMenuOwner)) return;
    _appearanceMenuOwner = null;
    _appearanceMenuDismiss = null;
  }

  bool get currentPageHasNoText =>
      book?.format == 'pdf' && state.location['noText'] == true;

  void openAppearanceSettings(ReaderAppearanceMenuOwner owner) {
    if (ownsAppearanceMenu(owner)) {
      events.add({'type': 'readingSettings', 'bookId': owner.bookId});
    }
  }

  bool ownsReaderPanel(ReaderPanel panel) =>
      ref.mounted &&
      state.panel?.presentation == panel.presentation &&
      panel.presentation == _presentation &&
      panel.session == _session &&
      panel.bookId == state.bookId &&
      state.ready &&
      _routeVisible &&
      !_suspended;

  Future<void> _showLookupPanel(String term) async {
    if (!state.ready || !_routeVisible || _suspended) return;
    final layout = ref.read(bookPresentationProvider);
    if (!_workspaceVisible &&
        layout.lastPane == BookPane.notebook &&
        !layout.splitAvailable) {
      return;
    }
    final session = _session, request = ++_panelRequest;
    bool current() =>
        ref.mounted &&
        request == _panelRequest &&
        session == _session &&
        _routeVisible &&
        !_suspended &&
        state.ready;
    if (!current()) return;
    await _dismissReaderControls(restoreFocus: false);
    if (!current()) return;
    final presentation = _presentation;
    await focusChrome();
    if (!current() || presentation != _presentation) return;
    state = state.copy(
      panel: ReaderPanel(
        bookId: state.bookId!,
        session: session,
        presentation: presentation,
        term: term,
      ),
    );
    ref
        .read(bookPresentationProvider.notifier)
        .focusPane(state.bookId!, BookPane.reading);
  }

  Future<void> retryLookup(ReaderPanel panel) async {
    if (ownsReaderPanel(panel)) {
      await _runLookup();
    }
  }

  void openLookupEntry(ReaderPanel panel) {
    final entry = _lookupResult?.entry;
    if (ownsReaderPanel(panel) &&
        entry != null &&
        entry.scheme == 'https' &&
        entry.host == 'en.wiktionary.org' &&
        entry.path.startsWith('/wiki/')) {
      events.add({'type': 'dictionaryEntry', 'url': entry.toString()});
    }
  }

  Rect? _selectionRect(Object? value) {
    if (value is! Map) return null;
    double n(String k) => (value[k] as num? ?? 0).toDouble();
    return Rect.fromLTWH(
      viewport.left + n('x'),
      viewport.top + n('y'),
      n('width'),
      n('height'),
    );
  }

  Future<void> _editSelectionNote(ReaderSelectionTarget target) async {
    if (!_ownsSelection(target) || target.passage?['anchor'] is! Map) return;
    var annotation = selectionAnnotation(target);
    if (annotation == null && target.annotationId != null) return;
    if (annotation == null) {
      final time = DateTime.now().microsecondsSinceEpoch;
      annotation = ReadingAnnotation({
        'id': 'annotation-$time',
        'kind': 'annotation',
        'bookId': target.bookId,
        'annotationKind': target.passage!['anchor']['region'] != null
            ? 'region'
            : 'highlight',
        'anchor': target.passage!['anchor'],
        'text': target.text,
        'reference': target.passage!['reference'] ?? '',
        'note': '',
        'color': highlightColor,
        'created': time,
      });
      // Notebook owns the full creation before any fallible save or navigation.
      ref.read(notebookControllerProvider.notifier).create(annotation, '');
    }
    await editAnnotation(annotation);
  }

  bool ownsNoteEditRequest(Map<String, dynamic> event) =>
      ref.mounted &&
      event['bookId'] == state.bookId &&
      event['session'] == _session &&
      event['selectionRevision'] == _selectionRevision &&
      ref
              .read(notebookControllerProvider)
              .findAnnotation(
                event['bookId'] as String,
                event['annotationId'] as String,
                annotations,
              ) !=
          null;

  Future<void> editAnnotation(ReadingAnnotation annotation) async {
    if (annotation.bookId != state.bookId) return;
    final session = _session, selection = _selectionRevision;
    await dismissReaderControls(restoreFocus: false);
    if (!ref.mounted ||
        session != _session ||
        annotation.bookId != state.bookId ||
        selection != _selectionRevision) {
      return;
    }
    final current = ref
        .read(notebookControllerProvider)
        .findAnnotation(annotation.bookId, annotation.id, annotations);
    if (current == null) return;
    await focusChrome();
    if (!ref.mounted ||
        session != _session ||
        annotation.bookId != state.bookId ||
        selection != _selectionRevision) {
      return;
    }
    _selectionRevision++;
    events.add({
      'type': 'editAnnotationNote',
      'bookId': annotation.bookId,
      'annotationId': annotation.id,
      'session': session,
      'selectionRevision': _selectionRevision,
    });
  }

  bool _sameAnchor(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _sameAnchor(a[k], b[k]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameAnchor(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  Future<void> _save() async {
    for (final pending in _pendingLocations.entries.toList()) {
      final id = pending.key, value = pending.value;
      if (identical(_pendingLocations[id], value)) _pendingLocations.remove(id);
      try {
        final current = ref.read(workspaceControllerProvider).bookById(id);
        await ref.read(workspaceControllerProvider.notifier).updateBook(id, {
          'anchor': value['anchor'],
          'progress': value['progress'] ?? 0,
          'reference': value['reference'],
          'read': DateTime.now().millisecondsSinceEpoch,
          'state': (value['progress'] as num? ?? 0) >= .999
              ? 'finished'
              : current?.state == 'unread'
              ? 'reading'
              : current?.state,
        });
      } catch (error) {
        _pendingLocations.putIfAbsent(id, () => value);
        state = state.copy(warning: error.toString());
        rethrow;
      }
    }
    state = state.copy(clearWarning: true);
  }

  Future<void> flush() {
    if (_flushOperation != null) return _flushOperation!;
    final operation = _flush();
    _flushOperation = operation.whenComplete(() => _flushOperation = null);
    return _flushOperation!;
  }

  Future<void>? _rendererFlushOperation;
  Future<void> _flushRenderer() {
    final pending = _rendererFlushOperation;
    if (pending != null) return pending;
    return _rendererFlushOperation = _drainRenderer().whenComplete(
      () => _rendererFlushOperation = null,
    );
  }

  Future<void> _drainRenderer() async {
    await _appearanceTail;
    if (state.ready && !_suspended) {
      _flushing = Completer<void>();
      try {
        await send('flush', {'request': ++_flushRequest});
        await _flushing!.future.timeout(const Duration(seconds: 5));
      } finally {
        _flushing = null;
      }
    }
  }

  Future<void> _flush() async {
    await _flushRenderer();
    _saveTimer?.cancel();
    do {
      await _save();
    } while (_pendingLocations.isNotEmpty);
    await ref.read(workspaceControllerProvider.notifier).flush();
  }

  Future<void> close() async {
    await _dismissSelectionMenu();
    await _dismissAppearanceMenu();
    _focusRevision++;
    _pendingJump?.cancel();
    final revision = ++_openRevision;
    final session = _session;
    bool ownsClosing() =>
        ref.mounted && revision == _openRevision && session == _session;
    if (_preparationOwner != null) {
      await ref.read(readingDataStoreProvider).call('cancelPrepare');
      if (!ownsClosing()) return;
    }
    requestThumbnailWindow(const []);
    _startupTimer?.cancel();
    await ref.read(narrationControllerProvider.notifier).stop();
    if (!ownsClosing()) return;
    try {
      if (!ownsClosing()) return;
      _invalidateAppearanceWork();
      if (state.ready) await send('cancelAppearance');
      if (!ownsClosing()) return;
      await flush();
      if (!ownsClosing()) return;
      await _eventTail;
      if (!ownsClosing()) return;
      await ref.read(notebookControllerProvider.notifier).flush();
      if (!ownsClosing()) return;
      do {
        await _save();
        if (!ownsClosing()) return;
      } while (_pendingLocations.isNotEmpty);
      await readerChannel.invokeMethod<void>('visible', false);
    } catch (error) {
      if (!ownsClosing()) return;
      await _applyVisibility();
      rethrow;
    }
    if (!ownsClosing()) return;
    _finishSearchWaiters(false);
    _searchRevision++;
    if (revision != _openRevision) return;
    _fileCheck?.cancel();
    _filePoll?.cancel();
    _filePoll = null;
    await _fileWatch?.cancel();
    if (revision != _openRevision) return;
    _fileWatch = null;
    _sourcePath = null;
    await _eventTail;
    if (revision != _openRevision) return;
    _presentation++;
    _invalidateLookup();
    state = state.copy(clearPanel: true);
    _invalidateLayoutVisibility();
    _session = 'closed:${++_generation}';
    await readerChannel.invokeMethod<void>('close');
    if (revision != _openRevision) return;
    _selectionIntent = null;
    state = const ReaderState();
  }

  TypographyCapabilities get typographyCapabilities =>
      state.ready && state.error == null && !_suspended
      ? state.typography
      : TypographyCapabilities.none;
  Future<void> _appearanceTail = Future.value();
  final _appearanceResults = <int, Completer<void>>{};
  int _appearanceRevision = 0, _appearanceRequest = 0;
  bool _appearanceNeedsReconcile = false;
  ({String session, String id, Map<String, dynamic> value})? _appearanceIntent;

  void _invalidateAppearanceWork() {
    _appearanceRevision++;
    _appearanceIntent = null;
    for (final pending in _appearanceResults.values) {
      if (!pending.isCompleted) pending.complete();
    }
    _appearanceResults.clear();
  }

  Future<Map<String, dynamic>> _resolveAppearance(
    Map<String, dynamic> value, {
    TypographyCapabilities? capabilities,
  }) async {
    final diagnose =
        const bool.fromEnvironment('BUSYBOOKS_READER_DIAGNOSTICS') ||
        Platform.environment['BUSYBOOKS_READER_DIAGNOSTICS'] == '1';
    final mode = diagnose
        ? ref.read(appSettingsControllerProvider).themeMode.name
        : null;
    final choice = FontChoice.parse(value['font']) ?? FontChoice.serif;
    final resolved = value['publisher'] == true
        ? null
        : await ref.read(readingFontServiceProvider).resolve(choice);
    final effective = {
      ...value,
      'systemDark': _chrome['dark'] == true,
      if (resolved != null) 'resolvedFont': resolved.toJson(),
    };
    if (capabilities != null) {
      if (!capabilities.fontFamily) {
        effective.remove('font');
        effective.remove('resolvedFont');
      }
      if (!capabilities.fontFamily && !capabilities.textMetrics) {
        effective.remove('publisher');
      }
      if (!capabilities.textMetrics) {
        for (final key in TypographyCapabilities.metricFields) {
          effective.remove(key);
        }
      }
    }
    if (diagnose) {
      debugPrint(
        'reader-theme applicationTheme=$mode '
        'resolvedBrightness=${_chrome['dark'] == true ? 'dark' : 'light'} '
        'chromeDark=${_chrome['dark']} color=${effective['color']} '
        'systemDark=${effective['systemDark']}',
      );
    }
    return effective;
  }

  Future<void> setAppearance(
    Map<String, dynamic> changes, {
    bool defaults = false,
  }) {
    if (state.bookId == null ||
        !state.ready ||
        state.error != null ||
        _suspended) {
      return Future.error(StateError(_labels.fontApplyFailed));
    }
    if (!typographyCapabilities.permits(changes.keys)) {
      return Future.error(StateError(_labels.fontApplyFailed));
    }
    if (changes.containsKey('font') &&
        FontChoice.parse(changes['font']) == null) {
      return Future.error(const FormatException('Invalid font family'));
    }
    final session = _session, id = state.bookId!;
    final pending = _appearanceIntent;
    final base = pending?.session == session && pending?.id == id
        ? pending!.value
        : appearance;
    final next = normalizeReadingAppearance({...base, ...changes});
    return _queueAppearance(session, id, next, defaults: defaults);
  }

  Future<void> resetAppearance() {
    if (state.bookId == null ||
        !state.ready ||
        state.error != null ||
        _suspended) {
      return Future.error(StateError(_labels.fontApplyFailed));
    }
    final key = appearanceDefaultsKey;
    final value = (ref.read(appSettingsControllerProvider).data[key] as Map)
        .cast<String, dynamic>();
    return _queueAppearance(_session, state.bookId!, value, reset: true);
  }

  Future<void> _queueAppearance(
    String session,
    String id,
    Map<String, dynamic> next, {
    bool defaults = false,
    bool reset = false,
  }) {
    final revision = defaults ? _appearanceRevision : ++_appearanceRevision;
    final defaultsKey = appearanceDefaultsKey;
    if (!defaults) {
      _appearanceIntent = (session: session, id: id, value: next);
      // Release superseded renderer waiters. The adapter independently cancels
      // their restoration, and late replies no longer own a preference write.
      for (final pending in _appearanceResults.values) {
        if (!pending.isCompleted) pending.complete();
      }
      if (state.ready) {
        unawaited(
          send('cancelAppearance').catchError((Object error) {
            if (ref.mounted && session == _session) {
              state = state.copy(warning: error.toString());
            }
          }),
        );
      }
    }
    final operation = _appearanceTail.then((_) async {
      bool owned() => ref.mounted && session == _session && id == state.bookId;
      if (!owned() || (!defaults && revision != _appearanceRevision)) return;
      if (defaults) {
        await ref
            .read(appSettingsControllerProvider.notifier)
            .updateReadingDefaults(defaultsKey, next);
        return;
      }
      final previous = appearance;
      final render = _canRenderAppearance;
      if (!render) _appearanceNeedsReconcile = true;
      if (render) {
        try {
          await _renderAppearance(next, revision, session);
        } catch (error, trace) {
          if (owned() &&
              revision == _appearanceRevision &&
              state.ready &&
              !_suspended &&
              _canRenderAppearance) {
            try {
              await _renderAppearance(previous, revision, session);
            } catch (restoreError) {
              state = state.copy(
                warning: '${_labels.fontApplyFailed} $restoreError',
              );
            }
          }
          Error.throwWithStackTrace(error, trace);
        }
        if (!owned() || revision != _appearanceRevision) return;
      }
      try {
        await ref.read(workspaceControllerProvider.notifier).updateBook(id, {
          'appearance': reset ? null : next,
        });
      } catch (error, trace) {
        if (render &&
            owned() &&
            revision == _appearanceRevision &&
            state.ready &&
            !_suspended &&
            _canRenderAppearance) {
          try {
            await _renderAppearance(previous, revision, session);
          } catch (restoreError) {
            state = state.copy(
              warning: '${_labels.fontApplyFailed} $restoreError',
            );
          }
        }
        Error.throwWithStackTrace(error, trace);
      }
    });
    _appearanceTail = operation
        .then<void>((_) {
          if (revision == _appearanceRevision) _appearanceIntent = null;
        })
        .catchError((Object error) {
          if (revision == _appearanceRevision) _appearanceIntent = null;
          if (ref.mounted && session == _session && id == state.bookId) {
            state = state.copy(warning: _labels.fontApplyFailed);
            events.add({
              'type': 'feedback',
              'message': _labels.fontApplyFailed,
            });
          }
        });
    return operation;
  }

  Future<void> _renderAppearance(
    Map<String, dynamic> value,
    int revision,
    String session,
  ) async {
    final resolved = await _resolveAppearance(
      value,
      capabilities: typographyCapabilities,
    );
    if (!ref.mounted ||
        session != _session ||
        revision != _appearanceRevision ||
        _suspended ||
        !_canRenderAppearance) {
      _appearanceNeedsReconcile = true;
      return;
    }
    final request = ++_appearanceRequest, result = Completer<void>();
    _appearanceResults[request] = result;
    try {
      await Future.wait<void>([
        result.future.timeout(const Duration(seconds: 15)),
        send('appearance', {'value': resolved, 'request': request}),
      ], eagerError: true);
    } finally {
      _appearanceResults.remove(request);
    }
  }

  Future<void> annotation(
    String kind, {
    String? color,
    String note = '',
    Map<String, dynamic>? passage,
  }) async {
    if (kind != 'bookmark') {
      await _annotation(kind, color: color, note: note, passage: passage);
      return;
    }
    if (!canBookmark) return;
    final pending = (
      bookId: state.bookId!,
      anchor: Map<String, dynamic>.unmodifiable(
        (state.location['anchor'] as Map).cast<String, dynamic>(),
      ),
    );
    _pendingBookmarks.add(pending);
    state = state.copy();
    try {
      // _annotation captures identity/location before its first await.
      await _annotation(kind, color: color, note: note, passage: passage);
    } finally {
      _pendingBookmarks.remove(pending);
      if (ref.mounted) state = state.copy();
    }
  }

  Future<void> _annotation(
    String kind, {
    String? color,
    String note = '',
    Map<String, dynamic>? passage,
  }) async {
    final selected = kind == 'highlight' || kind == 'region'
        ? (passage ?? state.selection)
        : null;
    if ((kind == 'highlight' || kind == 'region') && selected == null) return;
    final id = state.bookId,
        anchor = selected?['anchor'] ?? state.location['anchor'];
    final reference =
        selected?['reference'] ?? state.location['reference'] ?? '';
    if (anchor is! Map || id == null) return;
    color ??= highlightColor;
    if (kind == 'bookmark') {
      final existing = annotations
          .where(
            (a) =>
                a.kind == 'bookmark' &&
                sameBookmarkLocation(a.anchor, anchor.cast<String, dynamic>()),
          )
          .firstOrNull;
      if (existing != null) {
        await ref
            .read(workspaceControllerProvider.notifier)
            .deleteAnnotation(existing.id);
        return;
      }
    } else {
      await ref.read(appSettingsControllerProvider.notifier).update({
        'highlightColor': color,
      });
    }
    final time = DateTime.now().microsecondsSinceEpoch;
    await ref
        .read(workspaceControllerProvider.notifier)
        .saveAnnotation(
          ReadingAnnotation({
            'id': 'annotation-$time',
            'kind': 'annotation',
            'annotationKind': kind,
            'bookId': id,
            'anchor': anchor,
            'text': selected?['text'] ?? '',
            'reference': reference,
            'note': note,
            'color': color,
            'created': time,
          }),
        );
  }

  Future<bool> _sendAnnotationSnapshot(
    List<Map<String, dynamic>> values,
  ) async {
    final session = _session, revision = ++_annotationRevision;
    for (final batch in annotationTransfer(values, revision)) {
      if (session != _session || revision != _annotationRevision) return false;
      await send('annotations', batch);
    }
    return session == _session && revision == _annotationRevision;
  }

  Future<void> syncAnnotations() async {
    await _sendAnnotationSnapshot(_rendererAnnotations);
  }
}

final readerControllerProvider =
    NotifierProvider<ReaderController, ReaderState>(ReaderController.new);
