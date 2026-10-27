import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/busybooks_toast.dart';
import '../../app/command_focus.dart';
import '../../app/localization.dart';
import '../../app/product_actions.dart';
import '../../notebook/application/notebook_controller.dart';
import '../../notebook/presentation/book_view_selector.dart';
import '../../search/book_search_session.dart';
import '../../workspace/workspace_controller.dart';
import '../application/narration_controller.dart';
import '../application/reader_controller.dart';

class ReadingContent extends ConsumerStatefulWidget {
  const ReadingContent({
    super.key,
    required this.id,
    required this.active,
    required this.visible,
  });
  final String id;
  final bool active, visible;
  @override
  ConsumerState<ReadingContent> createState() => _ReadingContentState();
}

class _ReadingContentState extends ConsumerState<ReadingContent> {
  late final ReaderController _reader;
  final _surface = GlobalKey<_NativeReaderSurfaceState>();
  StreamSubscription<Map<String, dynamic>>? _events;
  @override
  void initState() {
    super.initState();
    _reader = ref.read(readerControllerProvider.notifier);
    if (widget.active) {
      Future.microtask(() {
        if (mounted && widget.active) unawaited(_reader.open(widget.id));
      });
    }
    _events = _reader.events.stream.listen((event) {
      if (!mounted || !widget.visible) return;
      if (event['type'] == 'feedback') {
        BusyBooksToastOverlay.show(
          context,
          message: event['message'] as String,
        );
      }
      if (event['type'] == 'external') {
        unawaited(externalLink(context, event['url'] as String));
      }
      if (event['type'] == 'lookup') {
        unawaited(
          runAppAction(
            context,
            () => dictionary(
              context,
              ref,
              target: event['target'] as ReaderSelectionTarget,
            ),
          ),
        );
      }
      if (event['type'] == 'dictionaryEntry') {
        unawaited(
          runAppAction(
            context,
            () => openDictionaryEntry(event['url'] as String),
          ),
        );
      }
      if (event['type'] == 'opened' || event['type'] == 'focusBook') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              ref.read(readerControllerProvider).ready &&
              ref.read(readerControllerProvider).bookId == widget.id &&
              ModalRoute.of(context)?.isCurrent == true &&
              (event['restorePublicationFocus'] == true
                  ? _reader.ownsFocusRequest(event)
                  : !ref.read(bookSearchProvider(widget.id)).active)) {
            _surface.currentState?.focusBook();
          }
        });
        if (event['restorePublicationFocus'] == true) {
          WidgetsBinding.instance.scheduleFrame();
        }
      }
      if (event['type'] == 'focusChrome') {
        _surface.currentState?.leaveFocus(event['backwards'] == true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ReadingContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && (!oldWidget.active || oldWidget.id != widget.id)) {
      Future.microtask(() {
        if (mounted && widget.active) unawaited(_reader.open(widget.id));
      });
    }
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerControllerProvider),
        workspace = ref.watch(workspaceControllerProvider);
    final book = workspace.bookById(widget.id), l = context.l10n;
    final notebook = ref.watch(notebookControllerProvider);
    final noteFailure = notebook.drafts.entries.any(
      (e) =>
          e.value.error != null && notebook.sources[e.key]?.bookId == widget.id,
    );
    return Column(
      children: [
        if (noteFailure)
          BusyBooksBanner(
            title: l.noteSaveFailed,
            actionLabel: l.notebook,
            onAction: () => openNotebook(context, ref, widget.id),
          ),
        if (state.popoverError != null)
          BusyBooksBanner(
            title: state.popoverError!,
            actionLabel: l.retry,
            onAction: _reader.retryPopover,
          ),
        if (state.warning != null)
          BusyBooksBanner(
            title: '${l.saveWarning}\n${state.warning}',
            actionLabel: l.retry,
            onAction: () async {
              try {
                await _reader.flush();
              } catch (_) {
                /* The warning retains the pending save. */
              }
            },
          ),
        if (state.error != null)
          BusyBooksBanner(
            title: '${l.bookError}\n${state.error}',
            actionLabel: l.retry,
            onAction: () async {
              try {
                await _reader.retry(widget.id);
              } catch (e) {
                if (context.mounted) {
                  BusyBooksToastOverlay.show(
                    context,
                    message: '${l.bookError}: $e',
                  );
                }
              }
            },
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: _NativeReaderSurface(
                  key: _surface,
                  active:
                      widget.visible &&
                      state.bookId == widget.id &&
                      state.error == null,
                ),
              ),
              if (state.error != null)
                Positioned.fill(
                  child: Center(
                    child: book == null
                        ? Text(l.bookError)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              BusyBooksPushButton.standard(
                                onPressed: () =>
                                    openNotebook(context, ref, book.id),
                                child: Text(l.notebook),
                              ),
                              if ([
                                'missing',
                                'changed',
                                'denied',
                              ].contains(state.errorCode))
                                BusyBooksPushButton.standard(
                                  onPressed: () =>
                                      locateBook(context, ref, book.id),
                                  child: Text(l.locateBook),
                                ),
                            ],
                          ),
                  ),
                ),
              if (state.error == null &&
                  (!state.ready || state.bookId != widget.id))
                Positioned.fill(
                  child: ColoredBox(
                    color: BusyBooksSurfaceColors.of(context).view,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: BusyBooksSpacing.lg),
                          if (workspace.loading)
                            SizedBox(
                              width: 300,
                              child: LinearProgressIndicator(
                                value:
                                    (workspace.progress['total'] as int? ?? 0) >
                                        0
                                    ? (workspace.progress['done'] as int) /
                                          (workspace.progress['total'] as int)
                                    : null,
                              ),
                            ),
                          Text(
                            state.phase == 'initializing'
                                ? l.initializingReader
                                : state.phase == 'opening'
                                ? l.openingPassage
                                : l.loadingBook,
                          ),
                          BusyBooksPushButton.standard(
                            child: Text(l.cancel),
                            onPressed: () async {
                              ref.read(readingDataStoreProvider).cancel();
                              await _reader.suspend();
                              if (context.mounted) {
                                await returnToWorkspace(context, ref);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const _PlaybackBar(),
      ],
    );
  }
}

class _PlaybackBar extends ConsumerWidget {
  const _PlaybackBar();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(narrationControllerProvider),
        controller = ref.read(narrationControllerProvider.notifier),
        l = context.l10n;
    if (state.error != null) {
      return BusyBooksBanner(
        title: state.error == 'no-text'
            ? l.noSpeechText
            : '${l.speechUnavailable}\n${state.error}',
        actionLabel: l.retry,
        onAction: controller.start,
      );
    }
    if (!state.active) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BusyBooksSpacing.sm),
      child: Semantics(
        container: true,
        label: l.playback,
        liveRegion: true,
        child: Row(
          children: [
            BusyBooksHeaderIconButton(
              tooltip: state.status == 'paused' ? l.resume : l.pause,
              icon: state.status == 'paused'
                  ? BusyBooksGlyphs.play
                  : BusyBooksGlyphs.pause,
              onPressed: state.status == 'loading'
                  ? null
                  : controller.pauseResume,
            ),
            Expanded(
              child: Tooltip(
                message: state.text,
                child: Text(
                  state.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            BusyBooksHeaderIconButton(
              tooltip: l.speechOptions,
              icon: BusyBooksGlyphs.settings,
              onPressed: controller.options,
            ),
            BusyBooksHeaderIconButton(
              tooltip: l.stop,
              icon: BusyBooksGlyphs.stop,
              onPressed: controller.stop,
            ),
          ],
        ),
      ),
    );
  }
}

class _NativeReaderSurface extends ConsumerStatefulWidget {
  const _NativeReaderSurface({super.key, required this.active});
  final bool active;
  @override
  ConsumerState<_NativeReaderSurface> createState() =>
      _NativeReaderSurfaceState();
}

class _NativeReaderSurfaceState extends ConsumerState<_NativeReaderSurface>
    with WidgetsBindingObserver {
  late final ReaderController _reader;
  final _focus = BusyBooksPublicationFocusNode();
  Rect? _last;
  bool _queued = false;
  @override
  void initState() {
    super.initState();
    _reader = ref.read(readerControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => _schedule();
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  void focusBook() {
    _focus.requestFocus();
    unawaited(_reader.send('focus'));
  }

  void leaveFocus(bool backwards) {
    unawaited(_reader.focusChrome());
    if (backwards) {
      _focus.previousFocus();
    } else {
      _focus.nextFocus();
    }
  }

  void _schedule() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || !widget.active) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      _acceptBounds(rect);
    });
  }

  void _acceptBounds(Rect rect) {
    if (!mounted || !widget.active) return;
    _reader.viewport = rect;
    if (_last == rect) return;
    _last = rect;
    unawaited(
      readerChannel.invokeMethod<void>('bounds', {
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BusyBooksSurfaceColors.of(context),
        theme = Theme.of(context);
    final chrome = <String, dynamic>{
      'dark': theme.brightness == Brightness.dark,
      'accent': theme.colorScheme.primary.toARGB32(),
      'canvas': colors.view.toARGB32(),
      'foreground': colors.foreground.toARGB32(),
      'selection': theme.colorScheme.primary.withValues(alpha: .35).toARGB32(),
      'locale': Localizations.localeOf(context).languageCode,
      'reducedMotion': MediaQuery.disableAnimationsOf(context),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) unawaited(_reader.configureChrome(chrome));
    });
    _schedule();
    return Focus(
      focusNode: _focus,
      onFocusChange: (value) {
        if (value && widget.active) {
          unawaited(_reader.send('focus'));
        }
      },
      child: _ReaderSurfaceBounds(
        onBounds: _acceptBounds,
        child: ColoredBox(
          color: BusyBooksSurfaceColors.of(context).view,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// Layout/paint, rather than widget rebuild frequency, owns native geometry.
// This observes intermediate sidebar animation frames and inline banner changes.
class _ReaderSurfaceBounds extends SingleChildRenderObjectWidget {
  const _ReaderSurfaceBounds({required this.onBounds, required super.child});
  final ValueChanged<Rect> onBounds;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ReaderSurfaceBoundsRender(onBounds);
  @override
  void updateRenderObject(
    BuildContext context,
    _ReaderSurfaceBoundsRender renderObject,
  ) => renderObject.onBounds = onBounds;
}

class _ReaderSurfaceBoundsRender extends RenderProxyBox {
  _ReaderSurfaceBoundsRender(this.onBounds);
  ValueChanged<Rect> onBounds;
  bool _queued = false;
  void _report() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (attached && hasSize) onBounds(localToGlobal(Offset.zero) & size);
    });
  }

  @override
  void performLayout() {
    super.performLayout();
    _report();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _report();
  }
}
