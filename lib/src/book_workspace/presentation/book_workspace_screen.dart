import 'package:yaru/yaru.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/busybooks_design.dart';
import '../../app/app_router.dart';
import '../../app/command_focus.dart';
import '../../app/busybooks_search_field.dart';
import '../../app/linux/linux_page_frame.dart';
import '../../app/localization.dart';
import '../../notebook/presentation/notebook_screen.dart';
import '../../reading/application/reader_controller.dart';
import '../../reading/presentation/reader_screen.dart';
import '../../reading/presentation/reader_sidebar.dart';
import '../../search/book_search_session.dart';
import '../../search/book_search_widgets.dart';
import '../../workspace/workspace_controller.dart';
import '../application/book_sidebar_controller.dart';
import '../application/book_presentation.dart';
import 'book_header.dart';
import 'book_pane_layout.dart';

/// All three public book URLs update this same page and element. The shell, header,
/// sidebar, content scroll positions and search session survive view changes.
class BookWorkspaceScreen extends ConsumerStatefulWidget {
  const BookWorkspaceScreen({super.key, required this.id, required this.view});
  final String id;
  final BookView view;
  @override
  ConsumerState<BookWorkspaceScreen> createState() =>
      _BookWorkspaceScreenState();
}

class _BookWorkspaceScreenState extends ConsumerState<BookWorkspaceScreen> {
  String? _error;
  bool _loading = true;
  int _loadRevision = 0;
  bool? _readerVisible;
  int _readingFocusRequest = 0;
  Future<bool>? _notebookHandoff;
  String? _handoffBook;
  (String, double, double)? _layoutReport;
  int _resizeRevision = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(covariant BookWorkspaceScreen old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      unawaited(
        ref.read(readerControllerProvider.notifier).setWorkspaceVisible(false),
      );
      _readerVisible = null;
      _loading = true;
      Future.microtask(() {
        if (mounted) unawaited(_load());
      });
    }
    final retainedPublicationFocus =
        old.id == widget.id &&
        old.view.hasReader &&
        widget.view == BookView.split &&
        ref.read(bookPresentationProvider).lastPane == BookPane.reading &&
        FocusManager.instance.primaryFocus is BusyBooksPublicationFocusNode;
    if (old.view != widget.view &&
        (widget.view == BookView.reading || retainedPublicationFocus)) {
      _readingFocusRequest++;
    }
    final id = widget.id, view = widget.view;
    Future.microtask(() async {
      if (!mounted || widget.id != id || widget.view != view) return;
      ref.read(bookPresentationProvider.notifier).enterBook(id, view);
      final reader = ref.read(readerControllerProvider.notifier);
      if (!view.hasReader) {
        await reader.setWorkspaceVisible(false);
        if (!reader.suspended) {
          try {
            await reader.suspend();
          } catch (error) {
            if (mounted && widget.id == id) {
              setState(() => _error = error.toString());
            }
          }
        }
      } else if (old.view != view) {
        _readerVisible = null;
        if (ModalRoute.of(context)?.isCurrent != false) await reader.show(true);
      }
    });
  }

  Future<void> _load() async {
    final revision = ++_loadRevision, id = widget.id;
    _loading = true;
    _error = null;
    ref.read(bookPresentationProvider.notifier).enterBook(id, widget.view);
    try {
      final workspace = ref.read(workspaceControllerProvider.notifier);
      if (ref.read(workspaceControllerProvider).openedBook?.id != id) {
        await workspace.loadBook(
          id,
          activate: true,
          isCurrent: () =>
              mounted && revision == _loadRevision && widget.id == id,
        );
      }
      if (!mounted || revision != _loadRevision) return;
      final reader = ref.read(readerControllerProvider.notifier);
      if (!widget.view.hasReader && !reader.suspended) {
        await reader.suspend();
      }
    } catch (error) {
      if (mounted && revision == _loadRevision) _error = error.toString();
    }
    if (mounted && revision == _loadRevision) setState(() => _loading = false);
  }

  void _setReaderVisible(bool visible) {
    if (_readerVisible == visible) return;
    _readerVisible = visible;
    if (visible) return; // Measured bounds own every positive native reveal.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _readerVisible != false) return;
      await ref
          .read(readerControllerProvider.notifier)
          .setWorkspaceVisible(false);
    });
  }

  void _notebookFocused() {
    if (!mounted || !widget.view.hasNotebook) return;
    ref
        .read(bookPresentationProvider.notifier)
        .focusPane(widget.id, BookPane.notebook);
    if (_notebookHandoff != null && _handoffBook == widget.id) return;
    final operation = ref
        .read(readerControllerProvider.notifier)
        .prepareChromeChange();
    _notebookHandoff = operation;
    _handoffBook = widget.id;
    unawaited(
      operation.whenComplete(() {
        if (identical(_notebookHandoff, operation)) _notebookHandoff = null;
      }),
    );
  }

  Future<void> _showCollapsedPane(BookPane pane) async {
    final id = widget.id;
    final router = ref.read(appRouterProvider);
    final origin = router.routeInformationProvider.value.uri;
    final route = ModalRoute.of(context);
    bool current() =>
        mounted &&
        widget.id == id &&
        widget.view == BookView.split &&
        bookIdForRoute(origin.path) == id &&
        router.routeInformationProvider.value.uri == origin &&
        route?.isCurrent != false;
    if (!current()) return;
    final reader = ref.read(readerControllerProvider.notifier);
    if (!await reader.prepareChromeChange() || !current()) {
      return;
    }
    if (pane == BookPane.notebook) {
      await reader.setWorkspaceVisible(false);
      if (!current()) return;
    }
    if (pane == BookPane.reading) setState(() => _readingFocusRequest++);
    ref.read(bookPresentationProvider.notifier).focusPane(id, pane);
  }

  void _reportLayout(double width, double scale) {
    final report = (widget.id, width, scale);
    if (_layoutReport == report) return;
    _layoutReport = report;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _layoutReport != report || widget.id != report.$1) return;
      ref
          .read(bookPresentationProvider.notifier)
          .updateLayout(
            report.$1,
            availableWidth: report.$2,
            textScale: report.$3,
          );
    });
  }

  Future<void> _resizePanes(double ratio) async {
    final revision = ++_resizeRevision, id = widget.id;
    final router = ref.read(appRouterProvider);
    final origin = router.routeInformationProvider.value.uri;
    final route = ModalRoute.of(context);
    bool current() =>
        mounted &&
        revision == _resizeRevision &&
        widget.id == id &&
        widget.view == BookView.split &&
        bookIdForRoute(origin.path) == id &&
        router.routeInformationProvider.value.uri == origin &&
        route?.isCurrent != false;
    if (!current()) return;
    final reader = ref.read(readerControllerProvider.notifier);
    await reader.invalidateViewport();
    if (!current()) return;
    ref.read(bookPresentationProvider.notifier).setDividerRatio(id, ratio);
    // A clamped/no-op movement still needs to restore its validated allocation.
    reader.requestViewportLayout();
  }

  Future<bool> _prepareResize() async {
    final id = widget.id;
    final router = ref.read(appRouterProvider);
    final origin = router.routeInformationProvider.value.uri;
    final route = ModalRoute.of(context);
    bool current() =>
        mounted &&
        widget.id == id &&
        widget.view == BookView.split &&
        bookIdForRoute(origin.path) == id &&
        router.routeInformationProvider.value.uri == origin &&
        route?.isCurrent != false;
    if (!current()) return false;
    final prepared = await ref
        .read(readerControllerProvider.notifier)
        .prepareChromeChange();
    return prepared && current();
  }

  @override
  Widget build(BuildContext context) {
    final sidebar = ref.watch(bookSidebarProvider(widget.id)),
        search = ref.watch(bookSearchSessionProvider),
        presentation = ref.watch(bookPresentationProvider),
        l = context.l10n;
    final narrow =
        MediaQuery.sizeOf(context).width <
        BusyBooksSizes.workspaceSidebarBreakpoint;
    final open = search.active || sidebar.open;
    Widget content;
    if (_loading) {
      _setReaderVisible(false);
      content = const Center(child: YaruCircularProgressIndicator());
    } else if (_error != null) {
      _setReaderVisible(false);
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BusyBooksStatusBox(
              message: '${l.bookError}\n$_error',
              kind: BusyBooksStatusKind.error,
            ),
            TextButton(
              onPressed: () => setState(() => unawaited(_load())),
              child: Text(l.retry),
            ),
          ],
        ),
      );
    } else {
      content = LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
          final metrics = BookSplitMetrics(scale);
          _reportLayout(constraints.maxWidth, metrics.textScale);
          final collapsed =
              widget.view == BookView.split &&
              constraints.maxWidth < metrics.minimumWidth;
          final effectiveView = collapsed
              ? (presentation.lastPane == BookPane.notebook
                    ? BookView.notebook
                    : BookView.reading)
              : widget.view;
          final visible = effectiveView.hasReader && !(narrow && open);
          _setReaderVisible(visible);
          final panes = BookPaneLayout(
            key: ValueKey('book-panes-${widget.id}'),
            view: effectiveView,
            ratio: presentation.dividerRatio,
            readingMinWidth: metrics.minimumReadingWidth,
            notebookMinWidth: metrics.minimumNotebookWidth,
            dividerLabel: l.resizeSplitPanes,
            dividerHint: l.resizeSplitPanesHelp,
            ratioLabel: l.splitPaneRatio,
            onRatioChanged: (ratio) => unawaited(_resizePanes(ratio)),
            prepareResize: _prepareResize,
            reading: ReadingContent(
              key: ValueKey('reading-${widget.id}'),
              id: widget.id,
              active: widget.view.hasReader,
              visible: visible,
              focusRequest: _readingFocusRequest,
              focusOnOpen:
                  effectiveView.hasReader &&
                  (widget.view == BookView.reading ||
                      presentation.lastPane == BookPane.reading),
            ),
            notebook: Listener(
              onPointerDown: (_) => _notebookFocused(),
              child: Focus(
                onFocusChange: (focused) {
                  if (focused) _notebookFocused();
                },
                child: NotebookContent(
                  key: ValueKey('notebook-${widget.id}'),
                  id: widget.id,
                  active: effectiveView.hasNotebook,
                  focusOnActivate:
                      widget.view == BookView.notebook ||
                      presentation.lastPane == BookPane.notebook,
                  onFocus: _notebookFocused,
                ),
              ),
            ),
          );
          return Column(
            children: [
              ExcludeFocus(
                excluding: !collapsed,
                child: Offstage(
                  offstage: !collapsed,
                  child: BusyBooksBanner(
                    title: l.splitCollapsed(
                      presentation.lastPane == BookPane.notebook
                          ? l.notebook
                          : l.reading,
                    ),
                    actionLabel: l.showSplitPane(
                      presentation.lastPane == BookPane.notebook
                          ? l.reading
                          : l.notebook,
                    ),
                    onAction: () => _showCollapsedPane(
                      presentation.lastPane == BookPane.notebook
                          ? BookPane.reading
                          : BookPane.notebook,
                    ),
                  ),
                ),
              ),
              Expanded(child: panes),
            ],
          );
        },
      );
    }
    return Scaffold(
      body: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              !busyBooksTextInputComposing() &&
              ref.read(bookSearchSessionProvider).active) {
            ref.read(bookSearchSessionProvider.notifier).close();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: LinuxPageFrame(
          sidebarOverlay: narrow,
          sidebarAvailable: true,
          sidebarExpanded: open,
          sidebarTransitionGeneration: open ? 1 : 0,
          onSidebarDismiss: () => search.active
              ? ref.read(bookSearchSessionProvider.notifier).close()
              : unawaited(
                  ref
                      .read(bookSidebarProvider(widget.id).notifier)
                      .setOpen(false),
                ),
          sidebarHeader: const BusyBooksLinuxBrandHeader(),
          sidebarBody: BookSearchSidebarHost(
            child: Column(
              children: [
                ReadingSidebarHeader(bookId: widget.id),
                Expanded(child: ReadingSidebarBody(bookId: widget.id)),
              ],
            ),
          ),
          header: BookHeader(bookId: widget.id, view: widget.view),
          body: ColoredBox(
            color: BusyBooksSurfaceColors.of(context).view,
            child: content,
          ),
        ),
      ),
    );
  }
}
