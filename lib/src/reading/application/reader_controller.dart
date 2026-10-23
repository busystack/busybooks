import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_settings.dart';
import '../../core/reading_preferences.dart';
import '../../core/typography.dart';
import '../fonts/reading_font_service.dart';
import '../../workspace/workspace_controller.dart';
import '../../workspace/workspace_model.dart';
import '../../library/domain/book.dart';
import '../../library/domain/annotation_limits.dart';
import '../domain/reading_navigation.dart';
import '../domain/publication_outline.dart';
import '../domain/page_preview.dart';
import 'reader_sidebar_state.dart';
import '../domain/reader_action.dart';
import 'narration_controller.dart';
import 'dictionary_service.dart';
import '../../notebook/application/notebook_controller.dart';

const readerChannel = MethodChannel('io.busystack.busybooks/reader');
final readerStartupTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 45),
);

class _NoteDeliveryFailure implements Exception {
  const _NoteDeliveryFailure(this.cause);
  final Object cause;
  @override
  String toString() => cause.toString();
}

/// Captured before a native selection can collapse or its popover can close.
class ReaderSelectionTarget {
  const ReaderSelectionTarget(
    this.bookId,
    this.session,
    this.presentation,
    this.text,
    this.rect,
  );
  final String bookId, session, text;
  final int presentation;
  final Rect? rect;
}

class ReaderState {
  const ReaderState({
    this.bookId,
    this.ready = false,
    this.error,
    this.warning,
    this.popoverError,
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
    this.searchVisible = false,
    this.currentMatch = -1,
    this.searchFocus = 0,
    this.panel = 'outline',
    this.panelOpen = false,
    this.fixed = false,
    this.typography = TypographyCapabilities.none,
    this.pages = 0,
    this.labels = const [],
    this.thumbnails = const {},
    this.thumbnailErrors = const {},
    this.thumbnailPending = const {},
  });
  final String? bookId, error, warning, errorCode, popoverError;
  final String phase;
  final bool ready, searching, panelOpen, fixed;
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
  final String panel, query, searchStatus;
  final bool searchVisible;
  final int currentMatch, searchFocus;
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
    String? error,
    String? warning,
    String? errorCode,
    String? phase,
    bool clearWarning = false,
    String? popoverError,
    bool clearPopoverError = false,
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
    bool? searchVisible,
    int? currentMatch,
    int? searchFocus,
    String? panel,
    bool? panelOpen,
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
    error: error ?? this.error,
    warning: clearWarning ? null : warning ?? this.warning,
    popoverError: clearPopoverError ? null : popoverError ?? this.popoverError,
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
    searchVisible: searchVisible ?? this.searchVisible,
    currentMatch: currentMatch ?? this.currentMatch,
    searchFocus: searchFocus ?? this.searchFocus,
    panel: panel ?? this.panel,
    panelOpen: panelOpen ?? this.panelOpen,
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
  Timer? _saveTimer, _searchTimer, _startupTimer;
  int _searchRevision = 0, _presentation = 0;
  Rect viewport = Rect.zero;
  Map<String, dynamic> _chrome = {};
  Map<String, dynamic>? _popoverSelection;
  String? _annotationId;
  bool _popoverActive = false;
  String? _popoverKind;
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

  ReaderSelectionTarget? captureSelection() {
    if (!state.ready || !_routeVisible || _suspended || state.bookId == null) {
      return null;
    }
    final passage = _popoverActive && _popoverKind == 'selection'
        ? _popoverSelection
        : state.selection;
    final text = (passage?['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    return ReaderSelectionTarget(
      state.bookId!,
      _session,
      _presentation,
      text,
      _selectionRect(passage?['rect']),
    );
  }

  bool _ownsSelection(ReaderSelectionTarget target) =>
      ref.mounted &&
      state.ready &&
      _routeVisible &&
      !_suspended &&
      target.bookId == state.bookId &&
      target.session == _session &&
      target.presentation == _presentation;

  Future<void> searchSelection() async {
    final target = captureSelection();
    if (target == null) {
      events.add({'type': 'feedback', 'message': _labels.selectText});
      return;
    }
    await dismissPopover(restoreFocus: false);
    if (target.session != _session ||
        target.bookId != state.bookId ||
        target.presentation + 1 != _presentation ||
        !_routeVisible ||
        !state.ready) {
      return;
    }
    await toggleSearch(visible: true);
    if (target.session != _session ||
        target.bookId != state.bookId ||
        target.presentation + 1 != _presentation ||
        !_routeVisible ||
        !state.ready) {
      return;
    }
    // Submission intentionally advances an unchanged completed query. A
    // selection action starts a fresh revision without navigating the passage.
    search(target.text, immediate: true);
    _rememberSidebar();
  }

  Future<ReaderSelectionTarget?> prepareLookup() async {
    final target = captureSelection();
    if (target == null) return null;
    await dismissPopover(restoreFocus: false);
    if (target.session != _session ||
        target.bookId != state.bookId ||
        target.presentation + 1 != _presentation ||
        !_routeVisible ||
        !state.ready) {
      return null;
    }
    return ReaderSelectionTarget(
      target.bookId,
      target.session,
      _presentation,
      target.text,
      target.rect,
    );
  }

  Future<void> lookup(ReaderSelectionTarget target) async {
    if (!_ownsSelection(target)) return;
    await showPopover(
      'lookup',
      anchor: target.rect,
      extra: {
        'lookupTerm': target.text,
        'lookup': {'status': 'loading'},
      },
    );
    if (target.session != _session ||
        target.bookId != state.bookId ||
        target.presentation + 1 != _presentation ||
        !_popoverActive ||
        _popoverKind != 'lookup' ||
        !_routeVisible ||
        !state.ready) {
      return;
    }
    _lookupTerm = target.text;
    unawaited(_runLookup());
  }

  Future<void> _runLookup() async {
    final term = _lookupTerm;
    if (term == null || !_popoverActive || _popoverKind != 'lookup') return;
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
        _popoverActive &&
        _popoverKind == 'lookup' &&
        _routeVisible &&
        !_suspended &&
        state.ready;
    Future<void> update(Map<String, dynamic> value) async {
      if (!current()) return;
      await readerChannel.invokeMethod<void>('popoverResult', {
        'session': session,
        'presentation': presentation,
        'lookupTerm': term,
        'lookup': value,
      });
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
  Map<String, dynamic>? pendingJump;
  bool _suspended = false;
  Future<void> suspend() async {
    final session = _session, visible = _routeVisible;
    await ref.read(narrationControllerProvider.notifier).stop();
    _invalidateAppearanceWork();
    if (state.ready) await send('cancelAppearance');
    await _eventTail;
    await dismissPopover();
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
    _startupTimer?.cancel();
    if (!state.ready) {
      _session = 'suspended:${++_generation}';
      _failedPopover = null;
      await readerChannel.invokeMethod<void>('close');
    }
    try {
      await flush();
    } catch (_) {
      /* pending positions stay protected in this controller */
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
  Completer<void>? _flushing;
  Future<void>? _flushOperation;
  StreamSubscription<FileSystemEvent>? _fileWatch;
  Timer? _fileCheck, _filePoll;
  String? _sourcePath;
  int _generation = 0;
  int _openRevision = 0;
  bool _routeVisible = false;
  final _sessionPrefix =
      '${DateTime.now().microsecondsSinceEpoch}${Random.secure().nextInt(0x100000000)}';
  String _session = 'closed';
  final _pendingLocations = <String, Map<String, dynamic>>{};
  @override
  ReaderState build() {
    listenSelf((previous, next) {
      if (previous?.error != next.error) unawaited(_applyVisibility());
    });
    readerChannel.setMethodCallHandler((call) async {
      if (call.method == 'event' && call.arguments is String) {
        final text = call.arguments as String;
        if (text.length > maxReaderPopoverActionBytes) {
          throw PlatformException(code: 'reader-action-size');
        }
        final msg = (jsonDecode(text) as Map).cast<String, dynamic>();
        if (msg['session'] != _session) return;
        if (msg['type'] == 'popoverAction') {
          if (!validReaderPopoverAction(text)) {
            await readerChannel.invokeMethod<void>('popoverResult', {
              'request': msg['request'],
              'error': 'Reader action exceeds its UTF-8 byte limit',
            });
            return;
          }
        } else if (text.length > 1048576) {
          return; // Preserve the publication renderer's existing event bound.
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
        if (msg['type'] == 'navigationResult' &&
            msg['request'] == _navigationRequest) {
          final pending = _navigationPending;
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
        // Go To settles through popoverResult. Acknowledge its delivery now so
        // the same inbound channel can deliver the correlated renderer result;
        // the existing action tail still serializes all mutations/dismissals.
        if (msg['type'] == 'popoverAction' &&
            [
              'goto',
              'appearance',
              'resetAppearance',
              'saveDefaults',
            ].contains(msg['action'])) {
          return;
        }
        await operation;
      }
    });
    ref.onDispose(() {
      _invalidateLookup();
      for (final pending in _appearanceResults.values) {
        if (!pending.isCompleted) pending.complete();
      }
      _appearanceResults.clear();
      _session = 'disposed:${++_generation}';
      _presentation++;
      _openRevision++;
      _saveTimer?.cancel();
      _searchTimer?.cancel();
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
    ref.listen(notebookControllerProvider, (before, after) {
      final id = _annotationId;
      if (id == null || !_routeVisible || _suspended) return;
      final draft = after.drafts[id];
      if (identical(before?.drafts[id], draft)) return;
      // Status travels through the existing native result bridge. It neither
      // reopens the popover nor resets its actively edited text field.
      unawaited(
        readerChannel
            .invokeMethod<void>('popoverResult', {
              'session': _session,
              'presentation': _presentation,
              'notePending': draft != null,
              'noteError': draft?.error,
              'noteRevision':
                  draft?.revision ?? before?.drafts[id]?.revision ?? 0,
            })
            .catchError((Object _) {}),
      );
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
      (ref.read(appSettingsControllerProvider).data[book?.format == 'pdf'
                  ? 'pdfReading'
                  : 'reading']
              as Map)
          .cast<String, dynamic>();
  AppLocalizations get _labels {
    final tag =
        ref.read(appSettingsControllerProvider).data['locale'] as String? ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return lookupAppLocalizations(Locale(tag == 'de' ? 'de' : 'en'));
  }

  Future<void> open(String id) async {
    _suspended = false;
    final current = ref.read(workspaceControllerProvider).bookById(id);
    if (current == null) return;
    final revision = ++_openRevision;
    final replacing = state.bookId != id || !state.ready;
    try {
      // Capture while the old session still owns the book and passage. The
      // preparing phase below intentionally invalidates old native callbacks.
      await _capturePopoverDraft(seal: replacing);
      if (revision != _openRevision) return;
      if (replacing) _popoverActive = false;
    } catch (error) {
      if (revision == _openRevision) {
        state = state.copy(warning: error.toString());
        events.add({'type': 'feedback', 'message': error.toString()});
      }
      return;
    }
    if (state.bookId != id || !state.ready) {
      _invalidateLookup();
      _rememberSidebar();
      _invalidateAppearanceWork();
      if (state.ready) await send('cancelAppearance');
      _session = 'preparing:${++_generation}';
      _failedPopover = null;
      state = ReaderState(bookId: id, phase: 'verifying');
    }
    final path = current.path.isNotEmpty
        ? current.path
        : (current.data['paths'] as List?)?.firstOrNull as String?;
    try {
      // Revalidate the original even when reusing a live renderer after routing.
      final descriptor = await ref.read(readingDataStoreProvider).call(
        'prepare',
        {
          'id': id,
          'path': path,
          'validationToken': current.data['validationToken'],
        },
      );
      if (revision != _openRevision) return;
      if (state.bookId == id && state.ready && _sourcePath == path) {
        await _appearanceTail;
        final value = await _resolveAppearance(
          appearance,
          capabilities: typographyCapabilities,
        );
        if (revision != _openRevision) return;
        await send('appearance', {'value': value});
        await syncAnnotations();
        await _applyVisibility();
        if (pendingJump != null) {
          final jump = pendingJump;
          pendingJump = null;
          await send('goto', {'anchor': jump});
        }
        if (revision == _openRevision && _routeVisible && state.ready) {
          events.add({'type': 'focusBook'});
        }
        return;
      }
      await flush();
      if (revision != _openRevision) return;
      await _fileWatch?.cancel();
      if (revision != _openRevision) return;
      _fileCheck?.cancel();
      _filePoll?.cancel();
      _filePoll = null;
      await ref.read(narrationControllerProvider.notifier).stop();
      _searchTimer?.cancel();
      _searchRevision++;
      _revealOnLocation = false;
      _outlineRevision = null;
      _outlineIncoming.clear();
      _outlineIndices = {};

      _thumbnailWindow = {};
      _thumbnailRevision++;
      _popoverSelection = null;
      _annotationId = null;
      _popoverActive = false;
      _presentation++;
      final settings = ref.read(appSettingsControllerProvider).data;
      final remembered = ref.read(readerSidebarProvider(id));
      var panel = remembered.panel ?? settings['readerPanel'] as String;
      if (panel == 'books' &&
              ref.read(workspaceControllerProvider).workspace?.isBook !=
                  false ||
          panel == 'thumbnails' && current.format != 'pdf') {
        panel = 'outline';
      }
      state = ReaderState(
        bookId: id,
        phase: 'initializing',
        panelOpen: remembered.open ?? settings['readerSidebar'] == true,
        panel: panel,
        query: remembered.query,
        matches: remembered.matches,
        currentMatch: remembered.currentMatch,
        searchVisible: remembered.searchVisible,
      );
      _sourcePath = path;
      _session = '$_sessionPrefix${++_generation}';
      final session = _session;
      _startupTimer?.cancel();
      _startupTimer = Timer(ref.read(readerStartupTimeoutProvider), () {
        if (session == _session) {
          state = state.copy(error: _labels.readerStartupTimedOut);
        }
      });
      await readerChannel.invokeMethod<void>('open', {
        ...(descriptor as Map),
        'session': _session,
        'loadingQuery': Uri.encodeQueryComponent(_labels.loadingBook),
      });
      if (revision != _openRevision) return;
      await _applyVisibility();
      if (revision != _openRevision) return;
      await _watchOriginal(path!, id, revision);
    } catch (error) {
      // A native initialization result can arrive after another open/close.
      // Its error belongs to the superseded surface, not the current book.
      if (revision != _openRevision) return;
      if (error is _NoteDeliveryFailure) {
        // Opening another book must not tear down the only owner of input
        // whose handoff failed. Keep the old session/passage and show recovery.
        state = state.copy(warning: error.toString());
        events.add({'type': 'feedback', 'message': error.toString()});
        return;
      }
      _startupTimer?.cancel();
      _fileCheck?.cancel();
      _filePoll?.cancel();
      await _fileWatch?.cancel();
      if (revision != _openRevision) return;
      _sourcePath = null;
      _session = 'closed:${++_generation}';
      _failedPopover = null;
      await readerChannel.invokeMethod<void>('close');
      if (revision != _openRevision) return;
      final remembered = ref.read(readerSidebarProvider(id));
      state = ReaderState(
        bookId: id,
        panel: panelAvailable(remembered.panel ?? 'outline')
            ? remembered.panel ?? 'outline'
            : 'outline',
        panelOpen: remembered.open ?? true,
        query: remembered.query,
        matches: remembered.matches,
        currentMatch: remembered.currentMatch,
        searchVisible: remembered.searchVisible,
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

  Future<void> _watchOriginal(String path, String id, int revision) async {
    final original = File(path);
    var observed = await original.stat();
    if (revision != _openRevision) return;
    void changed() {
      _fileCheck?.cancel();
      _fileCheck = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(_verifyOriginal(path, id)),
      );
    }

    // Some network/removable filesystems do not provide native watch events.
    // Poll metadata there, then fingerprint any changed original in the worker.
    void poll() {
      if (_filePoll != null) return;
      _filePoll = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (_sourcePath != path || state.bookId != id) return;
        final stat = await original.stat();
        if (stat.type != observed.type ||
            stat.size != observed.size ||
            stat.modified != observed.modified) {
          observed = stat;
          changed();
        }
      });
    }

    if (observed.type != FileSystemEntityType.file) changed();
    try {
      _fileWatch = original.watch().listen(
        (_) => changed(),
        onError: (Object _) => poll(),
      );
    } catch (_) {
      poll();
    }
  }

  Future<void> _verifyOriginal(String path, String id) async {
    if (_sourcePath != path || state.bookId != id) return;
    final revision = _openRevision;
    try {
      await ref.read(readingDataStoreProvider).call('prepare', {
        'id': id,
        'path': path,
      });
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
      _session = 'closed:${++_generation}';
      _failedPopover = null;
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
      case 'popoverHidden':
        if (event['presentation'] == _presentation &&
            _popoverKind == 'lookup') {
          final presenting = _lookupTerm == null;
          _invalidateLookup();
          _popoverActive = false;
          _popoverKind = null;
          // A native failure can hide the frame before its presentation reply.
          // Keep that reply's owner valid for the existing Retry feedback.
          if (!presenting) _presentation++;
          if (event['keyboard'] == true && _routeVisible && !_suspended) {
            _restoreLookupFocus(_session, _presentation);
          }
        }
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
            },
            'anchor': b.anchor,
            'appearance': initialAppearance,
            'chrome': _chrome,
            'annotations': _rendererAnnotations,
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
        if (pendingJump != null) {
          final jump = pendingJump;
          pendingJump = null;
          await send('goto', {'anchor': jump});
        }
        await ref
            .read(workspaceControllerProvider.notifier)
            .updateBook(state.bookId!, {
              'read': DateTime.now().millisecondsSinceEpoch,
              'state': book?.state == 'unread' ? 'reading' : book?.state,
            });
      case 'location':
        if (_suspended || state.error != null) return;
        if (event['anchor'] is Map) {
          state = state.copy(location: event);
          if (_revealOnLocation && state.bookId != null) {
            _revealOnLocation = false;
            ref.read(readerSidebarProvider(state.bookId!).notifier).reveal();
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
      case 'popoverAction':
        var noteReceived = false;
        try {
          if (event['presentation'] == _presentation) {
            if ([
                  'noteDraft',
                  'annotationNote',
                  'highlight',
                ].contains(event['action']) &&
                event['note'] is String) {
              noteReceived = _receiveNoteDraft(event);
              if (!noteReceived &&
                  _annotationId != null &&
                  event['presentation'] == _presentation &&
                  ['annotationNote', 'highlight'].contains(event['action'])) {
                throw StateError(_labels.noteItemUnavailable);
              }
            }
            if (event['presentation'] == _presentation) {
              await _popoverAction(event);
            }
          }
          // Acknowledge ignored presentations too, so a queued Close/Escape
          // can settle without changing the current book or editor.
          if (event['request'] is int) {
            await readerChannel.invokeMethod<void>('popoverResult', {
              'request': event['request'],
              'ok': true,
              'noteReceived': noteReceived,
            });
          }
        } catch (error) {
          if (event['request'] is int) {
            await readerChannel.invokeMethod<void>('popoverResult', {
              'request': event['request'],
              'error': error.toString(),
              'noteReceived': noteReceived,
            });
          }
        }
      case 'annotation':
        final a = annotations
            .where(
              (a) =>
                  a.id == event['id'] ||
                  a.anchor['cfi'] == event['cfi'] && event['cfi'] != null,
            )
            .firstOrNull;
        if (a != null) await editAnnotation(a, rect: event['rect']);
      case 'selection':
        state = state.copy(
          selection: event['anchor'] is Map ? event : null,
          clearSelection: event['anchor'] is! Map,
        );
        if (event['anchor'] is Map && event['settled'] == true) {
          await showPopover('selection');
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
              .read(readerSidebarProvider(state.bookId!).notifier)
              .reconcile(outline);
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
        );
      case 'searchError':
        state = state.copy(searching: false, searchStatus: 'error');
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
      case 'flushed':
        if (_flushing?.isCompleted == false) _flushing!.complete();
      case 'error':
        _invalidateAppearanceWork();
        _startupTimer?.cancel();
        debugPrint('BusyBooks reader error: ${event['message']}');
        state = state.copy(ready: false, error: event['message']?.toString());
    }
    events.add(event);
  }

  Future<void> send(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    final session = _session;
    if (['goto', 'back', 'forward', 'next', 'previous'].contains(action) &&
        ref.read(narrationControllerProvider).active) {
      await ref.read(narrationControllerProvider.notifier).stop();
    }
    if (session != _session) return;
    if (action == 'focus') {
      if (!_routeVisible || !state.ready) return;
      await readerChannel.invokeMethod<void>('focus');
      if (session != _session) return;
    }
    if (['goto', 'back', 'forward', 'next', 'previous'].contains(action)) {
      _revealOnLocation = true;
    }
    await readerChannel.invokeMethod<void>(
      'dispatch',
      jsonEncode({'action': action, ...args, 'session': session}),
    );
  }

  // Route visibility survives a native close/open on a retained reader route.
  // Geometry and widget rebuilding do not own this state; dialogs do.
  Future<void> show(bool value) async {
    _routeVisible = value;
    if (!value) {
      _invalidateLookup();
      _appearanceNeedsReconcile |=
          _appearanceIntent != null || _appearanceResults.isNotEmpty;
      _invalidateAppearanceWork();
      if (state.ready) await send('cancelAppearance');
    } else if (_appearanceNeedsReconcile &&
        state.ready &&
        state.error == null &&
        !_suspended) {
      final session = _session, id = state.bookId;
      await _appearanceTail;
      if (session != _session ||
          id != state.bookId ||
          !_routeVisible ||
          !state.ready ||
          _suspended) {
        return;
      }
      final revision = _appearanceRevision;
      // A renderer acknowledgement precedes book persistence. Reconcile from
      // the committed record before revealing a retained surface, including
      // cancellation during that acknowledgement/write interval.
      try {
        await _renderAppearance(appearance, revision, session);
      } catch (error) {
        if (session == _session &&
            id == state.bookId &&
            revision == _appearanceRevision) {
          state = state.copy(warning: _labels.fontApplyFailed);
          events.add({'type': 'feedback', 'message': _labels.fontApplyFailed});
        }
        return;
      }
      if (session != _session || id != state.bookId) return;
      if (revision == _appearanceRevision) _appearanceNeedsReconcile = false;
    }
    if (!value) requestThumbnailWindow(const []);
    return _applyVisibility();
  }

  Future<void> _applyVisibility() => readerChannel.invokeMethod<void>(
    'visible',
    _routeVisible && !_suspended && state.bookId != null && state.error == null,
  );
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

  Future<bool> _dismissForSidebar() async {
    final session = _session;
    try {
      await dismissPopover();
      return session == _session;
    } catch (error) {
      if (session == _session) {
        state = state.copy(warning: error.toString());
        events.add({'type': 'feedback', 'message': error.toString()});
      }
      return false;
    }
  }

  void _rememberSidebar() {
    final id = state.bookId;
    if (id == null) return;
    ref
        .read(readerSidebarProvider(id).notifier)
        .remember(
          panel: state.panel,
          open: state.panelOpen,
          query: state.query,
          matches: state.matches,
          currentMatch: state.currentMatch,
          searchVisible: state.searchVisible,
        );
  }

  bool panelAvailable(String value) => switch (value) {
    'books' => ref.read(workspaceControllerProvider).workspace?.isBook == false,
    'thumbnails' => book?.format == 'pdf',
    'outline' || 'annotations' || 'search' => true,
    _ => false,
  };
  Future<void> panel(String value) async {
    if (!panelAvailable(value)) return;
    final session = _session;
    if (_popoverActive && !await _dismissForSidebar()) return;
    if (session != _session) return;
    if (value != 'thumbnails') requestThumbnailWindow(const []);
    state = state.copy(panel: value, panelOpen: true);
    _rememberSidebar();
    unawaited(_savePanel());
  }

  Future<void> toggleSidebar() async {
    final session = _session;
    if (_popoverActive && !await _dismissForSidebar()) return;
    if (session != _session) return;
    state = state.copy(panelOpen: !state.panelOpen);
    if (!state.panelOpen) requestThumbnailWindow(const []);
    _rememberSidebar();
    unawaited(_savePanel());
  }

  Future<void> navigateFromSidebar(
    Map<String, dynamic> anchor, {
    required String bookId,
  }) async {
    if (state.bookId != bookId) return;
    final session = _session;
    if (!await _dismissForSidebar()) return;
    if (session != _session || state.bookId != bookId) return;
    if (!state.ready) {
      events.add({
        'type': 'feedback',
        'message': state.error == null
            ? _labels.loadingBook
            : _labels.bookError,
      });
      return;
    }
    await send('goto', {'anchor': anchor});
  }

  Future<void> _savePanel() async {
    try {
      await ref.read(appSettingsControllerProvider.notifier).update({
        'readerSidebar': state.panelOpen,
        'readerPanel': state.panel,
      });
    } catch (error) {
      if (ref.mounted) {
        events.add({'type': 'feedback', 'message': error.toString()});
      }
    }
  }

  Future<void> toggleSearch({bool? visible}) async {
    final session = _session;
    if (_popoverActive && !await _dismissForSidebar()) return;
    if (session != _session) return;
    requestThumbnailWindow(const []);
    final show = visible ?? !state.searchVisible;
    state = state.copy(
      searchVisible: show,
      searchFocus: state.searchFocus + (show ? 1 : 0),
      panel: show ? 'search' : state.panel,
      panelOpen: show || state.panelOpen,
    );
    _rememberSidebar();
  }

  void search(String query, {bool immediate = false}) {
    _searchTimer?.cancel();
    final revision = ++_searchRevision;
    if (state.ready) unawaited(send('cancelSearch', {'queryId': revision}));
    state = state.copy(
      query: query,
      matches: [],
      currentMatch: -1,
      searchProgress: 0,
      searching: state.ready && query.trim().isNotEmpty,
      searchStatus: !state.ready || query.trim().isEmpty ? 'idle' : 'searching',
    );
    if (!state.ready || query.trim().isEmpty) return;
    void run() =>
        unawaited(send('search', {'query': query.trim(), 'queryId': revision}));
    if (immediate) {
      run();
    } else {
      _searchTimer = Timer(const Duration(milliseconds: 300), run);
    }
  }

  Future<void> cancelSearch() async {
    _searchTimer?.cancel();
    ++_searchRevision;
    if (state.ready) await send('cancelSearch', {'queryId': _searchRevision});
    state = state.copy(
      searching: false,
      searchStatus: state.query.isEmpty ? 'idle' : 'cancelled',
    );
  }

  Future<void> selectMatch(int index) async {
    if (!state.ready || index < 0 || index >= state.matches.length) return;
    state = state.copy(currentMatch: index);
    await send('goto', {'anchor': state.matches[index]['anchor']});
  }

  void submitSearch(String query) {
    if (query.trim() == state.query.trim() &&
        state.matches.isNotEmpty &&
        !state.searching) {
      unawaited(stepMatch(1));
    } else {
      search(query, immediate: true);
    }
  }

  Future<void> stepMatch(int delta) => state.matches.isEmpty
      ? Future.value()
      : selectMatch(
          state.currentMatch < 0
              ? (delta > 0 ? 0 : state.matches.length - 1)
              : (state.currentMatch + delta) % state.matches.length,
        );
  int _thumbnailRevision = 0;
  Set<int> _thumbnailWindow = {};
  void requestThumbnailWindow(Iterable<int> pages) {
    final next = pages.where((p) => p >= 0 && p < state.pages).take(12).toSet();
    if (next.isNotEmpty && (!state.ready || book?.format != 'pdf')) return;
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
    if (!state.ready || book?.format != 'pdf') return;
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
      final effective = await _resolveAppearance(
        appearance,
        capabilities: typographyCapabilities,
      );
      if (session != _session || !state.ready) return;
      await send('appearance', {'value': effective});
    }
  }

  Future<void> dismissPopover({bool restoreFocus = true}) async {
    final session = _session, presentation = _presentation;
    final lookupFocus = _popoverKind == 'lookup';
    await _capturePopoverDraft(seal: true);
    if (session != _session || presentation != _presentation) return;
    final dismissedPresentation = ++_presentation;
    _invalidateLookup();
    _popoverActive = false;
    _popoverKind = null;
    _popoverSelection = null;
    _annotationId = null;
    await readerChannel.invokeMethod<void>('dismissPopover', {
      'restoreFocus': restoreFocus,
    });
    if (_routeVisible && restoreFocus) {
      if (lookupFocus) {
        _restoreLookupFocus(session, dismissedPresentation);
      } else {
        events.add({'type': 'focusBook'});
      }
    }
  }

  void _restoreLookupFocus(String session, int presentation) => events.add({
    'type': 'focusBook',
    'restorePublicationFocus': true,
    'session': session,
    'presentation': presentation,
  });

  bool ownsFocusRequest(Map<String, dynamic> event) =>
      ref.mounted &&
      _routeVisible &&
      !_suspended &&
      state.ready &&
      !_popoverActive &&
      event['session'] == _session &&
      event['presentation'] == _presentation;

  Rect? Function()? goToAnchor;
  Rect? Function()? appearanceAnchor;
  double popoverTextScale = 1;
  Future<void>? _popoverLayoutPending;
  ({String kind, Rect? anchor, Map<String, dynamic> extra})? _failedPopover;
  int _navigationRequest = 0;
  Completer<void>? _navigationPending;

  Future<void> retryPopover() async {
    final failed = _failedPopover;
    if (failed != null) {
      if (failed.kind == 'lookup' &&
          failed.extra['lookupTerm'] is String &&
          state.bookId != null) {
        await lookup(
          ReaderSelectionTarget(
            state.bookId!,
            _session,
            _presentation,
            failed.extra['lookupTerm'] as String,
            failed.anchor,
          ),
        );
        return;
      }
      await showPopover(
        failed.kind,
        anchor: ['goto', 'appearance'].contains(failed.kind)
            ? null
            : failed.anchor,
        extra: failed.extra,
      );
    }
  }

  Future<void> showPopover(
    String kind, {
    Rect? anchor,
    Map<String, dynamic> extra = const {},
  }) async {
    if (!state.ready || !_routeVisible) return;
    final previous = _presentation, session = _session;
    await _capturePopoverDraft(seal: true);
    if (session != _session || previous != _presentation) return;
    // The handoff can change this very annotation's effective note. Resolve
    // its payload afterwards, rather than reopening a pre-capture snapshot.
    final targetId = extra['annotationId'];
    if (kind == 'selection' && targetId is String) {
      final target =
          annotations.where((a) => a.id == targetId).firstOrNull ??
          ref.read(notebookControllerProvider).sources[targetId];
      if (target != null && target.bookId == state.bookId) {
        extra = {...extra, ..._notePayload(target)};
      }
    }
    _presentation++;
    _invalidateLookup();
    _popoverKind = kind;
    if (kind == 'selection') {
      _popoverSelection = state.selection;
      _annotationId = extra['annotationId'] as String?;
      if (_annotationId == null && _popoverSelection?['anchor'] is Map) {
        final notebook = ref.read(notebookControllerProvider);
        final pending = notebook.sources.values
            .where(
              (a) =>
                  a.bookId == state.bookId &&
                  notebook.drafts.containsKey(a.id) &&
                  _sameAnchor(a.anchor, _popoverSelection!['anchor']),
            )
            .firstOrNull;
        if (pending != null) {
          _annotationId = pending.id;
          extra = {...extra, ..._notePayload(pending)};
        }
      }
    }
    final presentation = _presentation;
    _popoverActive = true;
    try {
      if (state.popoverError != null) {
        state = state.copy(clearPopoverError: true);
        // Removing primary feedback changes the publication bounds. Both hosts
        // dismiss controls on a bounds update, so settle that frame first. All
        // rapid replacements share this barrier; none can overtake its layout.
        _popoverLayoutPending ??= WidgetsBinding.instance.endOfFrame.timeout(
          const Duration(seconds: 15),
        );
      }
      final layout = _popoverLayoutPending;
      if (layout != null) {
        try {
          await layout;
        } finally {
          if (identical(_popoverLayoutPending, layout)) {
            _popoverLayoutPending = null;
          }
        }
      }
      if (session != _session ||
          presentation != _presentation ||
          !_routeVisible) {
        return;
      }
      final rect =
          anchor ??
          (kind == 'goto'
              ? goToAnchor?.call()
              : kind == 'appearance'
              ? appearanceAnchor?.call()
              : _selectionRect(state.selection?['rect'])) ??
          (kind == 'goto'
              ? Rect.fromLTWH(viewport.left + 24, viewport.top - 1, 1, 1)
              : Rect.fromLTWH(viewport.right - 48, viewport.top, 1, 1));
      await readerChannel
          .invokeMethod<void>('popover', {
            ..._chrome,
            'kind': kind,
            'session': _session,
            'presentation': _presentation,
            'x': rect.left,
            'y': rect.top,
            'anchorWidth': rect.width,
            'anchorHeight': rect.height,
            'width': kind == 'goto' ? 360.0 : 460.0,
            'height': kind == 'goto'
                ? (viewport.height > 0 ? viewport.height : 420.0)
                : kind == 'selection'
                ? 340.0
                : 480.0,
            'textScale': popoverTextScale,
            'appearance': appearance,
            'typography': typographyCapabilities.toJson(),
            'pdf': book?.format == 'pdf',
            'pages': state.pages,
            'labels': state.labels,
            'toc': state.toc,
            'location': state.location,
            'color': highlightColor,
            ...extra,
          })
          .timeout(const Duration(seconds: 18));
      if (session == _session && presentation == _presentation) {
        _failedPopover = null;
      }
    } catch (error) {
      if (session != _session || presentation != _presentation) return;
      if (error is PlatformException && error.code == 'popover-cancelled') {
        _popoverActive = false;
        _popoverKind = null;
        _invalidateLookup();
        return;
      }
      _failedPopover = (kind: kind, anchor: anchor, extra: extra);
      state = state.copy(popoverError: _labels.readerControlsFailed);
      // A lost presentation reply may coexist with an interactive child. Protect
      // accepted input before hiding it, just as on every normal handoff.
      try {
        await _capturePopoverDraft(seal: true);
      } on _NoteDeliveryFailure {
        return;
      }
      if (session != _session || presentation != _presentation) return;
      await readerChannel.invokeMethod<void>('dismissPopover');
      _popoverActive = false;
    }
  }

  // This bounded request reads UI input only; it never waits behind the reader
  // event queue or asks the transient Flutter view to access the database.
  // Sealing the old field closes the capture-to-replacement input gap.
  Future<void> _capturePopoverDraft({bool seal = false}) async {
    if (!_popoverActive) return;
    final session = _session, presentation = _presentation;
    try {
      final captured = await readerChannel
          .invokeMethod<dynamic>('capturePopover', {
            'seal': seal,
            'session': session,
            'presentation': presentation,
          })
          .timeout(const Duration(seconds: 15));
      if (session != _session || presentation != _presentation) return;
      if (captured is Map &&
          captured['note'] is String &&
          captured['session'] == session &&
          captured['presentation'] == presentation) {
        _receiveNoteDraft(captured.cast<String, dynamic>());
      }
      if (session != _session || presentation != _presentation) return;
      await readerChannel.invokeMethod<void>('popoverResult', {
        'session': session,
        'presentation': presentation,
        'capturedRevision': captured is Map ? captured['revision'] : null,
        'captureComplete': true,
        'sealed': seal,
      });
    } catch (error) {
      await readerChannel.invokeMethod<void>('popoverResult', {
        'session': session,
        'presentation': presentation,
        'captureError': error.toString(),
      });
      if (session == _session && presentation == _presentation) {
        state = state.copy(warning: error.toString());
      }
      throw _NoteDeliveryFailure(error);
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

  Future<void> editAnnotation(
    ReadingAnnotation annotation, {
    Object? rect,
  }) async {
    if (annotation.bookId != state.bookId) return;
    final current =
        annotations.where((a) => a.id == annotation.id).firstOrNull ??
        ref.read(notebookControllerProvider).sources[annotation.id];
    if (current == null) return;
    await showPopover(
      'selection',
      anchor: _selectionRect(rect),
      extra: _notePayload(current),
    );
  }

  Map<String, dynamic> _notePayload(ReadingAnnotation annotation) {
    final notebook = ref.read(notebookControllerProvider),
        draft = notebook.drafts[annotation.id];
    return {
      'annotationId': annotation.id,
      'annotationKind': annotation.kind,
      'note': notebook.effectiveNote(annotation),
      'color': annotation.color,
      'notePending': draft != null,
      'noteError': draft?.error,
      'noteRevision': draft?.revision ?? 0,
    };
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

  bool _receiveNoteDraft(Map<String, dynamic> event) {
    final text = event['note'];
    if (text is! String || !validAnnotationText(text)) {
      throw FormatException(_labels.noteInputLimit);
    }
    final drafts = ref.read(notebookControllerProvider.notifier);
    var a =
        annotations.where((a) => a.id == _annotationId).firstOrNull ??
        ref.read(notebookControllerProvider).sources[_annotationId];
    if (a == null &&
        _annotationId == null &&
        _popoverSelection?['anchor'] is Map &&
        state.bookId != null) {
      final time = DateTime.now().microsecondsSinceEpoch;
      a = ReadingAnnotation({
        'id': 'annotation-$time',
        'kind': 'annotation',
        'bookId': state.bookId,
        'annotationKind': 'highlight',
        'anchor': _popoverSelection!['anchor'],
        'text': _popoverSelection!['text'] ?? '',
        'note': '',
        'reference': _popoverSelection!['reference'] ?? '',
        'color': event['color'] ?? highlightColor,
        'created': time,
      });
      _annotationId = a.id;
      drafts.create(a, event['note'] as String);
      // Capture later input while insertion is slow. The primary draft
      // owns the full creation before any repository call can fail.
      unawaited(drafts.save(a.id).catchError((Object _) {}));
      return true;
    }
    if (a != null && event['note'] is String) {
      if (ref.read(notebookControllerProvider).effectiveNote(a) == text) {
        return true;
      }
      drafts.edit(a, event['note'] as String);
      return true;
    }
    return false; // A deliberately deleted annotation cannot become a creation.
  }

  Future<void> _popoverAction(Map<String, dynamic> event) async {
    final session = _session, presentation = _presentation;
    bool current() => session == _session && presentation == _presentation;
    Future<void> finish() async {
      if (current()) await dismissPopover();
    }

    switch (event['action']) {
      case 'dismiss':
        await finish();
      case 'appearance':
        await setAppearance((event['value'] as Map).cast<String, dynamic>());
      case 'resetAppearance':
        await resetAppearance();
        if (current()) await showPopover('appearance');
      case 'saveDefaults':
        await setAppearance({}, defaults: true);
        await finish();
      case 'goto':
        final pending = Completer<void>();
        _navigationPending = pending;
        final request = ++_navigationRequest;
        try {
          await Future.wait<void>([
            pending.future.timeout(const Duration(seconds: 15)),
            send('goto', {'anchor': event['anchor'], 'request': request}),
          ], eagerError: true);
          await finish();
        } finally {
          if (!pending.isCompleted) {
            pending.completeError(StateError('Navigation cancelled'));
          }
          if (identical(_navigationPending, pending)) _navigationPending = null;
        }
      case 'highlightColor':
        final active =
            annotations.where((a) => a.id == _annotationId).firstOrNull ??
            ref.read(notebookControllerProvider).sources[_annotationId];
        await ref.read(appSettingsControllerProvider.notifier).update({
          'highlightColor': event['color'],
        });
        if (!current()) return;
        if (active != null) {
          await ref.read(notebookControllerProvider.notifier).save(active.id);
          await ref.read(workspaceControllerProvider.notifier).updateAnnotation(
            active.id,
            {'color': event['color']},
            bookId: active.bookId,
          );
        }
      case 'highlight':
        if (event['color'] is String) {
          await ref.read(appSettingsControllerProvider.notifier).update({
            'highlightColor': event['color'],
          });
        }
        final draft =
            annotations.where((a) => a.id == _annotationId).firstOrNull ??
            ref.read(notebookControllerProvider).sources[_annotationId];
        if (draft != null) {
          ref
              .read(notebookControllerProvider.notifier)
              .edit(draft, event['note'] as String? ?? '');
          await ref.read(notebookControllerProvider.notifier).save(draft.id);
          await finish();
          return;
        }
        if (_annotationId != null) {
          return; // A deleted editor cannot become a creation.
        }
        await annotation(
          'highlight',
          color: event['color'] as String?,
          note: event['note'] as String? ?? '',
          passage: _popoverSelection,
        );
        await finish();
      case 'copy':
        await Clipboard.setData(
          ClipboardData(
            text:
                (_popoverSelection ?? state.selection)?['text'] as String? ??
                '',
          ),
        );
        await finish();
      case 'dictionary':
        final target = await prepareLookup();
        if (target != null) events.add({'type': 'lookup', 'target': target});
      case 'searchSelection':
        await searchSelection();
      case 'lookupRetry':
        unawaited(_runLookup());
      case 'lookupFullEntry':
        final entry = _lookupResult?.entry;
        if (_popoverKind == 'lookup' &&
            entry != null &&
            entry.scheme == 'https' &&
            entry.host == 'en.wiktionary.org' &&
            entry.path.startsWith('/wiki/')) {
          events.add({'type': 'dictionaryEntry', 'url': entry.toString()});
        }
      case 'speak':
        await ref
            .read(narrationControllerProvider.notifier)
            .start(passage: _popoverSelection);
        await finish();
      case 'voice':
        await ref
            .read(narrationControllerProvider.notifier)
            .configure(voice: event['voice'] as String);
      case 'speed':
        await ref
            .read(narrationControllerProvider.notifier)
            .configure(speed: event['speed'] as num);
      case 'noteDraft':
        break; // Captured before any fallible work in the event handler.
      case 'annotationNote':
      case 'annotationColor':
      case 'deleteAnnotation':
        final a =
            annotations.where((a) => a.id == _annotationId).firstOrNull ??
            ref.read(notebookControllerProvider).sources[_annotationId];
        if (a == null) return;
        final workspace = ref.read(workspaceControllerProvider.notifier);
        if (event['action'] == 'deleteAnnotation') {
          await workspace.deleteAnnotation(a.id);
        } else {
          if (event['note'] is String) {
            final notes = ref.read(notebookControllerProvider.notifier);
            notes.edit(a, event['note'] as String);
            await notes.save(a.id);
          }
          if (event['color'] is String) {
            await workspace.updateAnnotation(a.id, {
              'color': event['color'],
            }, bookId: a.bookId);
          }
        }
        if (event['action'] != 'annotationColor') await finish();
    }
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

  Future<void> _flush() async {
    await _capturePopoverDraft();
    await _appearanceTail;
    if (state.ready) {
      _flushing = Completer<void>();
      try {
        await send('flush');
        await _flushing!.future.timeout(const Duration(seconds: 5));
      } finally {
        _flushing = null;
      }
    }
    _saveTimer?.cancel();
    do {
      await _save();
    } while (_pendingLocations.isNotEmpty);
    await ref.read(workspaceControllerProvider.notifier).flush();
  }

  Future<void> close() async {
    final revision = ++_openRevision;
    _rememberSidebar();
    requestThumbnailWindow(const []);
    final session = _session, presentation = _presentation;
    _startupTimer?.cancel();
    await ref.read(narrationControllerProvider.notifier).stop();
    try {
      await _capturePopoverDraft(seal: true);
      _invalidateAppearanceWork();
      if (state.ready) await send('cancelAppearance');
      await readerChannel.invokeMethod<void>('visible', false);
      await flush();
      await _eventTail;
      await ref.read(notebookControllerProvider.notifier).flush();
      do {
        await _save();
      } while (_pendingLocations.isNotEmpty);
    } catch (error) {
      await readerChannel.invokeMethod<void>('popoverResult', {
        'session': session,
        'presentation': presentation,
        'captureError': error.toString(),
      });
      await _applyVisibility();
      rethrow;
    }
    _searchTimer?.cancel();
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
    _popoverActive = false;
    _popoverSelection = null;
    _annotationId = null;
    _session = 'closed:${++_generation}';
    _failedPopover = null;
    await readerChannel.invokeMethod<void>('close');
    if (revision != _openRevision) return;
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
    final key = book?.format == 'pdf' ? 'pdfReading' : 'reading';
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
    final defaultsKey = book?.format == 'pdf' ? 'pdfReading' : 'reading';
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
      final render = state.ready && !_suspended && _routeVisible;
      if (render) {
        try {
          await _renderAppearance(next, revision, session);
        } catch (error, trace) {
          if (owned() &&
              revision == _appearanceRevision &&
              state.ready &&
              !_suspended &&
              _routeVisible) {
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
            _routeVisible) {
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
        !_routeVisible) {
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
    final selected = kind == 'highlight' ? (passage ?? state.selection) : null;
    if (kind == 'highlight' && selected == null) return;
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

  Future<void> syncAnnotations() =>
      send('annotations', {'value': _rendererAnnotations});
}

final readerControllerProvider =
    NotifierProvider<ReaderController, ReaderState>(ReaderController.new);
