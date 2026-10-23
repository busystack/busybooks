import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/busybooks_design.dart';
import '../../app/busybooks_glyphs.dart';
import '../../app/busybooks_main_menu.dart';
import '../../app/busybooks_toast.dart';
import '../../app/busybooks_search_field.dart';
import '../../app/busybooks_motion_widgets.dart';
import '../../app/command_registry.dart';
import '../../app/command_focus.dart';
import '../../app/localization.dart';
import '../../app/linux/linux_page_frame.dart';
import '../../app/linux/linux_header_style.dart';
import '../../platform/gtk_header_icon_service.dart';
import '../../app/product_actions.dart';
import '../../workspace/workspace_controller.dart';
import '../application/reader_controller.dart';
import '../application/reader_sidebar_state.dart';
import '../domain/publication_outline.dart';
import 'publication_location.dart';
import 'reader_sidebar.dart';
import '../../notebook/presentation/book_view_selector.dart';
import '../../notebook/application/notebook_controller.dart';
import '../application/narration_controller.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  late final ReaderController _reader;
  final _surface = GlobalKey<_NativeReaderSurfaceState>();
  late final TextEditingController _query;
  final _location = GlobalKey();
  final _previous = GlobalKey();
  final _appearance = GlobalKey();
  late final Rect? Function() _appearanceBounds;
  late final Rect? Function() _locationBounds;
  StreamSubscription<Map<String, dynamic>>? _events;
  @override
  void initState() {
    super.initState();
    _reader = ref.read(readerControllerProvider.notifier);
    _locationBounds = () =>
        _bounds(_location.currentContext ?? _previous.currentContext);
    _reader.goToAnchor = _locationBounds;
    _appearanceBounds = () => _bounds(_appearance.currentContext);
    _reader.appearanceAnchor = _appearanceBounds;
    _query = TextEditingController(
      text: ref.read(readerControllerProvider).bookId == widget.id
          ? ref.read(readerControllerProvider).query
          : ref.read(readerSidebarProvider(widget.id)).query,
    );
    Future.microtask(() async {
      if (mounted) await _reader.open(widget.id);
    });
    _events = _reader.events.stream.listen((event) {
      if (!mounted) return;
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
                  : !ref.read(readerControllerProvider).searchVisible)) {
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
  void didUpdateWidget(covariant ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _query.text = ref.read(readerSidebarProvider(widget.id)).query;
      Future.microtask(() async {
        if (mounted) {
          await _reader.open(widget.id);
        }
      });
    }
  }

  @override
  void dispose() {
    if (identical(_reader.goToAnchor, _locationBounds)) {
      _reader.goToAnchor = null;
    }
    if (identical(_reader.appearanceAnchor, _appearanceBounds)) {
      _reader.appearanceAnchor = null;
    }
    _query.dispose();
    unawaited(_events?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(readerControllerProvider.select((s) => (s.bookId, s.query)), (
      _,
      next,
    ) {
      if (next.$1 == widget.id && _query.text != next.$2) {
        // Only an external query change replaces the editing value. Typing,
        // caret movement and IME composition keep their existing value.
        _query.value = TextEditingValue(
          text: next.$2,
          selection: TextSelection.collapsed(offset: next.$2.length),
        );
      }
    });
    final state = ref.watch(readerControllerProvider),
        workspace = ref.watch(workspaceControllerProvider);
    final book = _reader.book, l = context.l10n;
    final notebook = ref.watch(notebookControllerProvider);
    final noteFailure = notebook.drafts.entries.any(
      (e) =>
          e.value.error != null && notebook.sources[e.key]?.bookId == widget.id,
    );
    final registry =
        BusyBooksCommandRegistryScope.maybeOf(context) ??
        BusyBooksCommandCatalog.metadata;
    String? binding(String id) => registry[id]?.shortcut?.label;
    _reader.popoverTextScale = MediaQuery.textScalerOf(context).scale(1);
    final narrow =
        MediaQuery.sizeOf(context).width <
        BusyBooksSizes.workspaceSidebarBreakpoint;
    return Scaffold(
      body: LinuxPageFrame(
        sidebarOverlay: narrow,
        sidebarAvailable: true,
        sidebarExpanded: state.panelOpen,
        sidebarTransitionGeneration: state.panelOpen ? 1 : 0,
        sidebarHeader: const BusyBooksLinuxBrandHeader(),
        sidebarBody: Column(
          children: [
            ReadingSidebarHeader(bookId: widget.id),
            Expanded(child: ReadingSidebarBody(bookId: widget.id)),
          ],
        ),
        header: LayoutBuilder(
          builder: (context, constraints) {
            final insets = LinuxPageHeaderInsetsScope.of(context);
            final available =
                constraints.maxWidth -
                insets.leftObstruction -
                insets.rightObstruction -
                BusyBooksSpacing.headerInset * 2;
            final button = BusyBooksSizes.iconButton + BusyBooksSpacing.xs;
            final compact =
                available <
                button * 10 +
                    MediaQuery.textScalerOf(
                      context,
                    ).scale(BusyBooksSizes.iconButton * 4);
            final paging = !state.searchVisible && available >= button * 6;
            final showViewSelector =
                book != null && !state.searchVisible && !compact;
            return BusyBooksLinuxHeaderLayout(
              centerAllocation: state.searchVisible
                  ? BusyBooksLinuxHeaderCenterAllocation.fillBetweenControls
                  : BusyBooksLinuxHeaderCenterAllocation
                        .centeredBetweenControls,
              leading: BusyBooksLinuxHeaderControlGroup(
                children: [
                  BusyBooksHeaderIconButton(
                    key: const ValueKey('reader-sidebar-toggle'),
                    tooltip: l.sidebar,
                    shortcut: binding(BusyBooksCommandIds.sidebar),
                    icon: BusyBooksGlyphs.sidebar,
                    selected: state.panelOpen,
                    onPressed: _reader.toggleSidebar,
                  ),
                  BusyBooksHeaderIconButton(
                    key: const ValueKey('reader-home'),
                    tooltip: l.welcome,
                    icon: BusyBooksGlyphs.home,
                    onPressed: () =>
                        registry[BusyBooksCommandIds.welcome]?.execute != null
                        ? registry.execute(BusyBooksCommandIds.welcome)
                        : closeWorkspace(context, ref),
                  ),
                  if (paging) ...[
                    KeyedSubtree(
                      key: _previous,
                      child: BusyBooksLinuxHeaderIconButton(
                        key: const ValueKey('reader-previous'),
                        tooltip: l.previousPage,
                        shortcut: binding(BusyBooksCommandIds.previous),
                        icon: BusyBooksGlyphs.headerBackFor(
                          Directionality.of(context),
                        ),
                        nativeIcon: BusyBooksLinuxHeaderIcon.previous,
                        onPressed:
                            state.canPrevious &&
                                registry[BusyBooksCommandIds.previous]!
                                    .canExecute
                            ? () =>
                                  registry.execute(BusyBooksCommandIds.previous)
                            : null,
                      ),
                    ),
                    if (!compact)
                      KeyedSubtree(key: _location, child: _ReadingLocation()),
                    BusyBooksLinuxHeaderIconButton(
                      key: const ValueKey('reader-next'),
                      tooltip: l.nextPage,
                      shortcut: binding(BusyBooksCommandIds.next),
                      icon: BusyBooksGlyphs.forwardFor(
                        Directionality.of(context),
                      ),
                      nativeIcon: BusyBooksLinuxHeaderIcon.next,
                      onPressed:
                          state.canNext &&
                              registry[BusyBooksCommandIds.next]!.canExecute
                          ? () => registry.execute(BusyBooksCommandIds.next)
                          : null,
                    ),
                  ],
                ],
              ),
              title: BusyBooksRetainedCrossfade(
                index: state.searchVisible ? 1 : 0,
                duration: BusyBooksMotion.search,
                children: [
                  BusyBooksLinuxHeaderTitle(book?.title ?? l.reader),
                  BusyBooksSearchField(
                    key: const ValueKey('book-header-search'),
                    controller: _query,
                    hintText: l.searchBook,
                    autofocus: false,
                    focusRequest: state.searchFocus,
                    clearOnEscape: false,
                    onChanged: _reader.search,
                    onSubmitted: (v) => _reader.submitSearch(v ?? _query.text),
                    onMoveSelection: (direction) =>
                        unawaited(_reader.stepMatch(direction)),
                    onEscape: () => unawaited(
                      runAppAction(context, () async {
                        await _reader.toggleSearch(visible: false);
                        await _reader.send('focus');
                      }),
                    ),
                  ),
                ],
              ),
              trailing: BusyBooksLinuxHeaderControlGroup(
                children: [
                  if (showViewSelector) ...[
                    BookViewSelector(id: widget.id, view: BookView.reading),
                    Semantics(
                      value: _reader.bookmarkPending ? l.busy : null,
                      child: BusyBooksHeaderIconButton(
                        key: const ValueKey('reader-bookmark'),
                        tooltip: _reader.bookmarked
                            ? l.removeBookmark
                            : l.bookmark,
                        shortcut: binding(BusyBooksCommandIds.bookmark),
                        icon: BusyBooksGlyphs.bookmark,
                        selected: _reader.bookmarked,
                        onPressed: _reader.canBookmark
                            ? () =>
                                  registry[BusyBooksCommandIds.bookmark]
                                          ?.execute !=
                                      null
                                  ? registry.execute(
                                      BusyBooksCommandIds.bookmark,
                                    )
                                  : runAppAction(
                                      context,
                                      () => _reader.annotation('bookmark'),
                                    )
                            : null,
                      ),
                    ),
                    Builder(
                      key: _appearance,
                      builder: (c) => BusyBooksHeaderIconButton(
                        tooltip: state.fixed ? l.viewOptions : l.appearance,
                        shortcut: binding(BusyBooksCommandIds.appearance),
                        icon: state.fixed
                            ? BusyBooksGlyphs.fitWidth
                            : BusyBooksGlyphs.font,
                        onPressed: state.ready
                            ? () =>
                                  registry[BusyBooksCommandIds.appearance]
                                          ?.execute !=
                                      null
                                  ? registry.execute(
                                      BusyBooksCommandIds.appearance,
                                    )
                                  : runAppAction(
                                      c,
                                      () => _reader.showPopover(
                                        'appearance',
                                        anchor: _bounds(c),
                                      ),
                                    )
                            : null,
                      ),
                    ),
                  ],
                  BusyBooksHeaderIconButton(
                    tooltip: l.searchBook,
                    shortcut: binding(BusyBooksCommandIds.search),
                    icon: BusyBooksGlyphs.search,
                    selected: state.searchVisible,
                    onPressed: state.ready
                        ? () =>
                              registry[BusyBooksCommandIds.search]?.execute !=
                                  null
                              ? registry.execute(BusyBooksCommandIds.search)
                              : runAppAction(context, _reader.toggleSearch)
                        : null,
                  ),
                  BusyBooksMainMenuButton(
                    bookViewSelectorVisible: showViewSelector,
                  ),
                ],
              ),
            );
          },
        ),
        body: Padding(
          padding: EdgeInsetsDirectional.only(
            start: narrow && state.panelOpen ? BusyBooksSizes.sidebarWidth : 0,
          ),
          child: Column(
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
                      await _reader.close();
                      await _reader.open(widget.id);
                    } catch (e) {
                      if (context.mounted) await showError(context, e);
                    }
                  },
                ),
              Expanded(
                child: state.error != null
                    ? Center(
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
                      )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: _NativeReaderSurface(key: _surface),
                          ),
                          if (!state.ready)
                            Positioned.fill(
                              child: ColoredBox(
                                color: BusyBooksSurfaceColors.of(context).view,
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(),
                                      const SizedBox(
                                        height: BusyBooksSpacing.lg,
                                      ),
                                      if (workspace.loading)
                                        SizedBox(
                                          width: 300,
                                          child: LinearProgressIndicator(
                                            value:
                                                (workspace.progress['total']
                                                            as int? ??
                                                        0) >
                                                    0
                                                ? (workspace.progress['done']
                                                          as int) /
                                                      (workspace
                                                              .progress['total']
                                                          as int)
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
                                      BusyBooksDialogButton(
                                        label: l.cancel,
                                        onPressed: () async {
                                          ref
                                              .read(readingDataStoreProvider)
                                              .cancel();
                                          await _reader.suspend();
                                          if (context.mounted) {
                                            await returnToWorkspace(
                                              context,
                                              ref,
                                            );
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
          ),
        ),
      ),
    );
  }
}

Rect? _bounds(BuildContext? context) {
  final box = context?.findRenderObject();
  return box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
}

class _ReadingLocation extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(readerControllerProvider),
        reader = ref.read(readerControllerProvider.notifier),
        l = context.l10n;
    final page = (state.location['anchor'] as Map?)?['page'] as int?;
    final pdf = reader.book?.format == 'pdf';
    final pageReference = pdf && page != null
        ? PublicationPageReference.pdf(page, state.pages, state.labels)
        : null;
    final progress =
        '${((state.location['progress'] as num? ?? reader.book?.progress ?? 0) * 100).round()}%';
    final anchor = state.location['anchor'] as Map?;
    final available =
        state.ready &&
        state.error == null &&
        (pdf
            ? page != null && page >= 0 && page < state.pages
            : anchor?['cfi'] is String || anchor?['index'] is int);
    final title = !available
        ? l.loadingBook
        : pageReference != null
        ? pageReference.display
        : state.location['printPage'] != null
        ? '${state.location['printPage']}'
        : progress;
    final reference = pageReference != null
        ? describePublicationPage(l, pageReference)
        : [
            state.location['chapter']?.toString() ?? l.goTo,
            progress,
          ].where((v) => v.isNotEmpty).join(' · ');
    return Tooltip(
      message: '${l.goTo} · $reference',
      child: Semantics(
        button: true,
        label: '${l.goTo} · $reference',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 132),
          child: TextButton(
            key: const ValueKey('reader-location'),
            style:
                busyBooksHeaderIconButtonStyle(
                  foregroundColor: busyBooksLinuxHeaderForeground(context),
                  disabledForegroundColor: busyBooksLinuxHeaderForeground(
                    context,
                    disabled: true,
                  ),
                  backgroundColor: busyBooksLinuxHeaderControlBackground(
                    context,
                  ),
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ).copyWith(
                  minimumSize: const WidgetStatePropertyAll(
                    Size(0, BusyBooksSizes.iconButton),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: BusyBooksSpacing.sm),
                  ),
                ),
            onPressed: available
                ? () => runAppAction(
                    context,
                    () => reader.showPopover('goto', anchor: _bounds(context)),
                  )
                : null,
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
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
  const _NativeReaderSurface({super.key});
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
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
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
    });
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
      if (mounted) unawaited(_reader.configureChrome(chrome));
    });
    _schedule();
    return Focus(
      focusNode: _focus,
      onFocusChange: (value) {
        if (value) {
          unawaited(_reader.send('focus'));
        }
      },
      child: ColoredBox(
        color: BusyBooksSurfaceColors.of(context).view,
        child: const SizedBox.expand(),
      ),
    );
  }
}
